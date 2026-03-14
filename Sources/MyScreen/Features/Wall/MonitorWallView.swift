import SwiftUI

struct MonitorWallView: View {
    @Bindable var appState: AppState

    var body: some View {
        GeometryReader { proxy in
            content(in: proxy.size)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(20)
                .onAppear {
                    appState.updateWindowSize(proxy.size)
                }
                .onChange(of: proxy.size) { _, newValue in
                    appState.updateWindowSize(newValue)
                }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private func content(in size: CGSize) -> some View {
        if appState.selectedSources.isEmpty {
            ContentUnavailableView(
                "No Monitoring Sources Yet",
                systemImage: "square.grid.3x3",
                description: Text("Add displays and app windows to build the monitoring wall.")
            )
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
                in: CGSize(width: size.width, height: max(size.height * 0.38, 240))
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Focused Monitor")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    tileView(for: focusSource)

                    if !remainingSources.isEmpty {
                        Divider()
                            .padding(.vertical, 4)

                        Text("Other Sources")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: max(remainingGrid.columns, 1)),
                            spacing: 16
                        ) {
                            ForEach(remainingSources) { source in
                                tileView(for: source)
                            }
                        }
                    }
                }
            }
        } else {
            let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: max(appState.wallLayout.grid.columns, 1))
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(appState.selectedSources) { source in
                        tileView(for: source)
                    }
                }
            }
        }
    }

    private func tileView(for source: MonitorSource) -> some View {
        MonitorTileView(
            source: source,
            tile: appState.tiles[source.id] ?? TileState.placeholder(
                sourceID: source.id,
                fpsTier: .balanced,
                freshness: .stale,
                lastFrameAt: source.lastSeenAt
            ),
            isFocused: appState.wallLayout.focusedSourceID == source.id,
            onToggleFocus: {
                appState.setFocusedSourceID(appState.wallLayout.focusedSourceID == source.id ? nil : source.id)
            },
            onRemove: {
                appState.removeSource(id: source.id)
            }
        )
    }
}
