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
            let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: max(appState.wallLayout.grid.columns, 1))
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(appState.selectedSources) { source in
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
            }
        }
    }
}
