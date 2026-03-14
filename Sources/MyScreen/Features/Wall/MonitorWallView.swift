import SwiftUI
import UniformTypeIdentifiers

struct MonitorWallView: View {
    @Bindable var appState: AppState
    @State private var draggedSourceID: String?
    @State private var dropTargetSourceID: String?
    @State private var tileFrames: [String: CGRect] = [:]

    private let wallAnimation = Animation.spring(response: 0.3, dampingFraction: 0.84)
    private let wallCoordinateSpace = "monitor-wall-grid"

    var body: some View {
        GeometryReader { proxy in
            content(in: proxy.size)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(6)
                .animation(wallAnimation, value: appState.selectedSources.map(\.id))
                .animation(wallAnimation, value: draggedSourceID)
                .onAppear {
                    appState.updateWindowSize(proxy.size)
                }
                .onChange(of: proxy.size) { _, newValue in
                    appState.updateWindowSize(newValue)
                }
        }
        .background(Color.black)
    }

    @ViewBuilder
    private func content(in size: CGSize) -> some View {
        if appState.selectedSources.isEmpty {
            ZStack {
                Rectangle()
                    .fill(Color.black)

                VStack(spacing: 12) {
                    Image(systemName: "rectangle.grid.2x2")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                    Text("No Monitoring Sources Yet")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.92))
                    Text("Use Add in the floating controls to build the wall.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
        } else {
            wallContent(in: size)
        }
    }

    @ViewBuilder
    private func wallContent(in size: CGSize) -> some View {
        if let focusSourceID = appState.wallLayout.focusedSourceID,
           let focusSource = appState.selectedSources.first(where: { $0.id == focusSourceID }) {
            let remainingSources = appState.selectedSources.filter { $0.id != focusSourceID }
            let remainingGrid = WallGridCalculator.calculate(
                for: remainingSources.count,
                in: CGSize(width: size.width, height: max(size.height * 0.38, 240)),
                preferredColumnCount: appState.wallLayout.preferredColumnCount
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    interactiveTileView(for: focusSource)

                    if !remainingSources.isEmpty {
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: max(remainingGrid.columns, 1)),
                            spacing: 6
                        ) {
                            ForEach(remainingSources) { source in
                                interactiveTileView(for: source)
                            }
                        }
                    }
                }
                .padding(.bottom, 82)
            }
            .coordinateSpace(name: wallCoordinateSpace)
            .onPreferenceChange(MonitorWallTileFramePreferenceKey.self) { newValue in
                tileFrames = newValue
            }
            .onDrop(
                of: [UTType.text],
                delegate: MonitorWallReorderDropDelegate(
                    appState: appState,
                    tileFrames: tileFrames,
                    draggedSourceID: $draggedSourceID,
                    dropTargetSourceID: $dropTargetSourceID,
                    animation: wallAnimation
                )
            )
        } else {
            let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: max(appState.wallLayout.grid.columns, 1))
            ScrollView {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(appState.selectedSources) { source in
                        interactiveTileView(for: source)
                    }
                }
                .padding(.bottom, 82)
            }
            .coordinateSpace(name: wallCoordinateSpace)
            .onPreferenceChange(MonitorWallTileFramePreferenceKey.self) { newValue in
                tileFrames = newValue
            }
            .onDrop(
                of: [UTType.text],
                delegate: MonitorWallReorderDropDelegate(
                    appState: appState,
                    tileFrames: tileFrames,
                    draggedSourceID: $draggedSourceID,
                    dropTargetSourceID: $dropTargetSourceID,
                    animation: wallAnimation
                )
            )
        }
    }

    @ViewBuilder
    private func interactiveTileView(for source: MonitorSource) -> some View {
        if appState.selectedSources.count > 1 {
            tileView(for: source)
                .zIndex(draggedSourceID == source.id ? 1 : 0)
                .onDrag {
                    draggedSourceID = source.id
                    dropTargetSourceID = nil
                    return NSItemProvider(object: source.id as NSString)
                }
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: MonitorWallTileFramePreferenceKey.self,
                            value: [source.id: proxy.frame(in: .named(wallCoordinateSpace))]
                        )
                    }
                )
        } else {
            tileView(for: source)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: MonitorWallTileFramePreferenceKey.self,
                            value: [source.id: proxy.frame(in: .named(wallCoordinateSpace))]
                        )
                    }
                )
        }
    }

    private func tileView(for source: MonitorSource) -> MonitorTileView {
        MonitorTileView(
            source: source,
            tile: appState.tiles[source.id] ?? TileState.placeholder(
                sourceID: source.id,
                fpsTier: .balanced,
                freshness: .stale,
                lastFrameAt: source.lastSeenAt
            ),
            isFocused: appState.wallLayout.focusedSourceID == source.id,
            isBeingDragged: draggedSourceID == source.id,
            isDropTarget: dropTargetSourceID == source.id && draggedSourceID != source.id,
            onActivate: {
                appState.activate(sourceID: source.id)
            },
            onToggleFocus: {
                appState.setFocusedSourceID(appState.wallLayout.focusedSourceID == source.id ? nil : source.id)
            },
            onRemove: {
                appState.removeSource(id: source.id)
            }
        )
    }
}

@MainActor
private struct MonitorWallReorderDropDelegate: DropDelegate {
    let appState: AppState
    let tileFrames: [String: CGRect]
    @Binding var draggedSourceID: String?
    @Binding var dropTargetSourceID: String?
    let animation: Animation

    func dropEntered(info: DropInfo) {
        reorderIfNeeded(at: info.location)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        reorderIfNeeded(at: info.location)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        finalizeDrag()
    }

    func performDrop(info: DropInfo) -> Bool {
        reorderIfNeeded(at: info.location)
        finalizeDrag()
        return true
    }

    private func reorderIfNeeded(at location: CGPoint) {
        guard let draggedSourceID else { return }
        guard let targetSourceID = targetSourceID(for: location, excluding: draggedSourceID) else { return }

        if dropTargetSourceID != targetSourceID {
            dropTargetSourceID = targetSourceID
        }

        withAnimation(animation) {
            _ = appState.previewSelectedSourceMove(id: draggedSourceID, to: targetSourceID)
        }
    }

    private func targetSourceID(for location: CGPoint, excluding draggedSourceID: String) -> String? {
        let hitTarget = tileFrames.first { sourceID, frame in
            sourceID != draggedSourceID && frame.contains(location)
        }
        if let hitTarget {
            return hitTarget.key
        }

        return tileFrames
            .filter { $0.key != draggedSourceID }
            .min { lhs, rhs in
                distance(from: location, to: lhs.value.center) < distance(from: location, to: rhs.value.center)
            }?
            .key
    }

    private func distance(from point: CGPoint, to target: CGPoint) -> CGFloat {
        let deltaX = point.x - target.x
        let deltaY = point.y - target.y
        return sqrt((deltaX * deltaX) + (deltaY * deltaY))
    }

    private func finalizeDrag() {
        guard draggedSourceID != nil else { return }
        appState.commitSelectedSourceOrder()
        draggedSourceID = nil
        dropTargetSourceID = nil
    }
}

private struct MonitorWallTileFramePreferenceKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}
