import SwiftUI

struct MonitorWallView: View {
    @Bindable var appState: AppState
    @State private var dragSession: WallDragSession?
    @State private var dropTargetSourceID: String?
    @State private var previewSourceIDs: [String]?
    @State private var tileFrames: [String: CGRect] = [:]

    private let wallAnimation = Animation.spring(response: 0.3, dampingFraction: 0.84)
    private let wallCoordinateSpace = "monitor-wall-grid"

    private var isReorderingEnabled: Bool {
        appState.wallLayout.focusedSourceID == nil && appState.selectedSources.count > 1
    }

    private var displayedSourceIDs: [String] {
        previewSourceIDs ?? appState.selectedSources.map(\.id)
    }

    var body: some View {
        GeometryReader { proxy in
            content(in: proxy.size)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(6)
                .animation(wallAnimation, value: displayedSourceIDs)
                .onAppear {
                    appState.updateWindowSize(proxy.size)
                }
                .onChange(of: proxy.size) { _, newValue in
                    appState.updateWindowSize(newValue)
                }
                .onChange(of: appState.wallLayout.focusedSourceID) { _, _ in
                    resetDragState()
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
        } else {
            let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: max(appState.wallLayout.grid.columns, 1))
            let sources = orderedSources(for: displayedSourceIDs)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(sources) { source in
                        interactiveTileView(for: source)
                    }
                }
                .padding(.bottom, 82)
            }
            .coordinateSpace(name: wallCoordinateSpace)
            .onPreferenceChange(MonitorWallTileFramePreferenceKey.self) { newValue in
                tileFrames = newValue
            }
        }
    }

    @ViewBuilder
    private func interactiveTileView(for source: MonitorSource) -> some View {
        let baseTile = tileView(for: source)
            .zIndex(dragSession?.sourceID == source.id ? 1 : 0)
            .offset(dragOffset(for: source.id))
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: MonitorWallTileFramePreferenceKey.self,
                        value: [source.id: proxy.frame(in: .named(wallCoordinateSpace))]
                    )
                }
            )

        if isReorderingEnabled {
            baseTile
                .simultaneousGesture(reorderGesture(for: source.id))
        } else {
            baseTile
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
            isBeingDragged: dragSession?.sourceID == source.id,
            isDropTarget: dropTargetSourceID == source.id && dragSession?.sourceID != source.id,
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

    private func reorderGesture(for sourceID: String) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named(wallCoordinateSpace))
            .onChanged { value in
                handleDragChanged(for: sourceID, value: value)
            }
            .onEnded { value in
                handleDragEnded(for: sourceID, value: value)
            }
    }

    private func handleDragChanged(for sourceID: String, value: DragGesture.Value) {
        if dragSession?.sourceID != sourceID {
            beginDragIfPossible(for: sourceID)
        }

        guard var dragSession, dragSession.sourceID == sourceID else { return }
        dragSession.translation = value.translation
        self.dragSession = dragSession
        updatePreviewOrder(for: dragSession, at: value.location)
    }

    private func handleDragEnded(for sourceID: String, value: DragGesture.Value) {
        guard var dragSession, dragSession.sourceID == sourceID else { return }
        dragSession.translation = value.translation
        self.dragSession = dragSession
        updatePreviewOrder(for: dragSession, at: value.location)

        let finalOrder = previewSourceIDs ?? dragSession.originalOrder
        appState.commitSelectedSourceOrder(finalOrder)

        withAnimation(wallAnimation) {
            resetDragState()
        }
    }

    private func beginDragIfPossible(for sourceID: String) {
        let originalOrder = appState.selectedSources.map(\.id)
        guard let initialFrame = tileFrames[sourceID] else { return }

        let slotFrames = originalOrder.compactMap { sourceID -> WallDragSlot? in
            guard let frame = tileFrames[sourceID] else { return nil }
            return WallDragSlot(sourceID: sourceID, frame: frame)
        }
        guard slotFrames.count == originalOrder.count else { return }

        dragSession = WallDragSession(
            sourceID: sourceID,
            originalOrder: originalOrder,
            initialFrame: initialFrame,
            slotFrames: slotFrames,
            translation: .zero
        )
        previewSourceIDs = nil
        dropTargetSourceID = nil
    }

    private func updatePreviewOrder(for dragSession: WallDragSession, at location: CGPoint) {
        guard let destinationIndex = destinationIndex(for: location, in: dragSession.slotFrames) else { return }

        let nextPreviewOrder = SelectedSourceReorderer.reordered(
            sourceIDs: dragSession.originalOrder,
            moving: dragSession.sourceID,
            toIndex: destinationIndex
        )

        let targetSourceID = dragSession.slotFrames[destinationIndex].sourceID
        let nextDropTargetSourceID = targetSourceID == dragSession.sourceID ? nil : targetSourceID

        if dropTargetSourceID != nextDropTargetSourceID {
            dropTargetSourceID = nextDropTargetSourceID
        }

        let normalizedPreviewOrder = nextPreviewOrder == dragSession.originalOrder ? nil : nextPreviewOrder
        guard normalizedPreviewOrder != previewSourceIDs else { return }

        withAnimation(wallAnimation) {
            previewSourceIDs = normalizedPreviewOrder
        }
    }

    private func destinationIndex(for location: CGPoint, in slotFrames: [WallDragSlot]) -> Int? {
        if let hitIndex = slotFrames.firstIndex(where: { $0.frame.contains(location) }) {
            return hitIndex
        }

        return slotFrames.enumerated().min { lhs, rhs in
            distance(from: location, to: lhs.element.frame.center) < distance(from: location, to: rhs.element.frame.center)
        }?.offset
    }

    private func orderedSources(for sourceIDs: [String]) -> [MonitorSource] {
        let sourcesByID = Dictionary(uniqueKeysWithValues: appState.selectedSources.map { ($0.id, $0) })
        return sourceIDs.compactMap { sourcesByID[$0] }
    }

    private func dragOffset(for sourceID: String) -> CGSize {
        guard let dragSession, dragSession.sourceID == sourceID else { return .zero }
        let currentFrame = tileFrames[sourceID] ?? dragSession.initialFrame
        let targetOrigin = CGPoint(
            x: dragSession.initialFrame.minX + dragSession.translation.width,
            y: dragSession.initialFrame.minY + dragSession.translation.height
        )

        return CGSize(
            width: targetOrigin.x - currentFrame.minX,
            height: targetOrigin.y - currentFrame.minY
        )
    }

    private func distance(from point: CGPoint, to target: CGPoint) -> CGFloat {
        let deltaX = point.x - target.x
        let deltaY = point.y - target.y
        return sqrt((deltaX * deltaX) + (deltaY * deltaY))
    }

    private func resetDragState() {
        dragSession = nil
        dropTargetSourceID = nil
        previewSourceIDs = nil
    }
}

private struct WallDragSession {
    let sourceID: String
    let originalOrder: [String]
    let initialFrame: CGRect
    let slotFrames: [WallDragSlot]
    var translation: CGSize
}

private struct WallDragSlot {
    let sourceID: String
    let frame: CGRect
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
