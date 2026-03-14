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
            VStack(alignment: .leading, spacing: 16) {
                WallStatusSummaryView(
                    sourceCount: appState.selectedSources.count,
                    liveCount: appState.tiles.values.filter { $0.freshness == .live }.count,
                    staleCount: appState.tiles.values.filter { $0.freshness == .stale }.count,
                    offlineCount: appState.tiles.values.filter { $0.freshness == .offline }.count,
                    grid: appState.wallLayout.grid
                )

                wallContent(in: size)
            }
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

private struct WallStatusSummaryView: View {
    let sourceCount: Int
    let liveCount: Int
    let staleCount: Int
    let offlineCount: Int
    let grid: WallGrid

    var body: some View {
        HStack(spacing: 12) {
            summaryBadge(title: "Sources", value: "\(sourceCount)", color: .accentColor)
            summaryBadge(title: "Live", value: "\(liveCount)", color: .green)
            summaryBadge(title: "Waiting", value: "\(staleCount)", color: .yellow)
            summaryBadge(title: "Offline", value: "\(offlineCount)", color: .red)
            Spacer()
            summaryBadge(title: "Grid", value: "\(grid.columns) × \(grid.rows)", color: .secondary)
        }
    }

    private func summaryBadge(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(nsColor: .underPageBackgroundColor))
        )
    }
}
