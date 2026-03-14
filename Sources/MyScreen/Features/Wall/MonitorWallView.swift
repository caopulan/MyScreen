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
                WallControlBar(
                    selectedColumnCount: appState.wallLayout.preferredColumnCount,
                    sourceCount: appState.selectedSources.count,
                    liveCount: appState.tiles.values.filter { $0.freshness == .live }.count,
                    onSelectColumnCount: { columnCount in
                        appState.setPreferredColumnCount(columnCount)
                    }
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
                in: CGSize(width: size.width, height: max(size.height * 0.38, 240)),
                preferredColumnCount: appState.wallLayout.preferredColumnCount
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    tileView(for: focusSource)

                    if !remainingSources.isEmpty {
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: max(remainingGrid.columns, 1)),
                            spacing: 10
                        ) {
                            ForEach(remainingSources) { source in
                                tileView(for: source)
                            }
                        }
                    }
                }
            }
        } else {
            let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: max(appState.wallLayout.grid.columns, 1))
            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
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

private struct WallControlBar: View {
    let selectedColumnCount: Int?
    let sourceCount: Int
    let liveCount: Int
    let onSelectColumnCount: (Int?) -> Void

    var body: some View {
        HStack(spacing: 14) {
            Text("\(sourceCount) sources")
                .font(.headline)

            Text("\(liveCount) live")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            HStack(spacing: 8) {
                Text("Columns")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                Picker("Columns", selection: Binding(
                    get: { selectedColumnCount ?? 0 },
                    set: { value in
                        onSelectColumnCount(value == 0 ? nil : value)
                    }
                )) {
                    Text("Auto").tag(0)
                    ForEach(1 ... 6, id: \.self) { count in
                        Text("\(count)").tag(count)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 250)
            }
        }
        .padding(.horizontal, 4)
    }
}
