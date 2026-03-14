import SwiftUI
import UniformTypeIdentifiers

struct MonitorWallView: View {
    @Bindable var appState: AppState
    @State private var draggedSourceID: String?
    @State private var dropTargetSourceID: String?

    private let wallAnimation = Animation.spring(response: 0.3, dampingFraction: 0.84)

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
                    Text("Use Add Sources in the toolbar to build the wall.")
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
            }
            .onDrop(
                of: [UTType.text],
                delegate: MonitorWallDropResetDelegate(
                    draggedSourceID: $draggedSourceID,
                    dropTargetSourceID: $dropTargetSourceID
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
            }
            .onDrop(
                of: [UTType.text],
                delegate: MonitorWallDropResetDelegate(
                    draggedSourceID: $draggedSourceID,
                    dropTargetSourceID: $dropTargetSourceID
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
                    dropTargetSourceID = source.id
                    return NSItemProvider(object: source.id as NSString)
                }
                .onDrop(
                    of: [UTType.text],
                    delegate: MonitorWallReorderDropDelegate(
                        targetSourceID: source.id,
                        appState: appState,
                        draggedSourceID: $draggedSourceID,
                        dropTargetSourceID: $dropTargetSourceID,
                        animation: wallAnimation
                    )
                )
        } else {
            tileView(for: source)
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
    let targetSourceID: String
    let appState: AppState
    @Binding var draggedSourceID: String?
    @Binding var dropTargetSourceID: String?
    let animation: Animation

    func dropEntered(info: DropInfo) {
        guard let draggedSourceID, draggedSourceID != targetSourceID else { return }
        dropTargetSourceID = targetSourceID
        withAnimation(animation) {
            appState.moveSelectedSource(id: draggedSourceID, to: targetSourceID)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        guard dropTargetSourceID == targetSourceID else { return }
        dropTargetSourceID = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedSourceID = nil
        dropTargetSourceID = nil
        return true
    }
}

@MainActor
private struct MonitorWallDropResetDelegate: DropDelegate {
    @Binding var draggedSourceID: String?
    @Binding var dropTargetSourceID: String?

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        draggedSourceID = nil
        dropTargetSourceID = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedSourceID = nil
        dropTargetSourceID = nil
        return true
    }
}
