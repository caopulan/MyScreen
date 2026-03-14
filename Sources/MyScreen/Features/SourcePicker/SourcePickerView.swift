import SwiftUI

struct SourcePickerView: View {
    @Bindable var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var showsOfflineWindows = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let error = appState.sourceCatalogError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    SourcePickerSection(
                        title: "Displays",
                        subtitle: "Choose physical screens and fullscreen spaces."
                    ) {
                        if filteredDisplays.isEmpty {
                            emptyState("No displays available")
                        } else {
                            cardGrid(for: filteredDisplays)
                        }
                    }

                    SourcePickerSection(
                        title: "Windows",
                        subtitle: "Visible app windows on the current desktop."
                    ) {
                        if filteredOnlineWindows.isEmpty {
                            emptyState("No visible windows match the current filter")
                        } else {
                            cardGrid(for: filteredOnlineWindows)
                        }
                    }

                    if !filteredOfflineWindows.isEmpty {
                        DisclosureGroup(isExpanded: $showsOfflineWindows) {
                            cardGrid(for: filteredOfflineWindows)
                                .padding(.top, 12)
                        } label: {
                            HStack {
                                Text("Hidden or Other-Space Windows")
                                    .font(.headline)
                                Spacer()
                                Text("\(filteredOfflineWindows.count)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(18)
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(Color(nsColor: .underPageBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                    }
                }
                .padding(20)
            }
            .searchable(text: $searchText, prompt: "Search displays or windows")
            .navigationTitle("Monitoring Sources")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    refreshButton
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                if appState.sourceCatalog.isEmpty {
                    await appState.refreshSourceCatalog()
                }
            }
        }
        .frame(minWidth: 960, minHeight: 620)
    }

    private var filteredDisplays: [MonitorSource] {
        filter(appState.sourceCatalog.displays)
    }

    private var filteredOnlineWindows: [MonitorSource] {
        filter(appState.sourceCatalog.onlineWindows)
    }

    private var filteredOfflineWindows: [MonitorSource] {
        filter(appState.sourceCatalog.offlineWindows)
    }

    private func filter(_ sources: [MonitorSource]) -> [MonitorSource] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return sources }

        return sources.filter { source in
            source.title.localizedCaseInsensitiveContains(keyword) ||
            (source.bundleIdentifier?.localizedCaseInsensitiveContains(keyword) ?? false)
        }
    }

    @ViewBuilder
    private func emptyState(_ title: String) -> some View {
        Text(title)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(nsColor: .underPageBackgroundColor))
            )
    }

    private func cardGrid(for sources: [MonitorSource]) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 250, maximum: 320), spacing: 16)],
            spacing: 16
        ) {
            ForEach(sources) { source in
                SourcePickerCard(
                    source: source,
                    isSelected: appState.isSelected(sourceID: source.id),
                    onToggleSelection: {
                        appState.toggleSelection(for: source)
                    }
                )
            }
        }
    }

    @ViewBuilder
    private var refreshButton: some View {
        if appState.isRefreshingSourceCatalog {
            ProgressView()
                .controlSize(.small)
        } else {
            Button {
                Task {
                    await appState.refreshSourceCatalog()
                }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
    }
}

private struct SourcePickerSection<Content: View>: View {
    let title: String
    let subtitle: String
    let content: () -> Content

    init(title: String, subtitle: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            content()
        }
    }
}

private struct SourcePickerCard: View {
    let source: MonitorSource
    let isSelected: Bool
    let onToggleSelection: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                SourceIconView(source: source, size: 34, padding: 8, backgroundOpacity: 0.12)

                VStack(alignment: .leading, spacing: 4) {
                    Text(source.title)
                        .font(.headline)
                        .lineLimit(2)
                    Text(metadataText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(nsColor: .controlBackgroundColor))

                VStack(spacing: 10) {
                    Image(systemName: source.kind == .display ? "display.2" : "macwindow.on.rectangle")
                        .font(.system(size: 30, weight: .medium))
                    Text(source.kind == .display ? "Display feed" : "Window feed")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 128)

            HStack {
                Text(source.isAvailable ? "Visible" : "Hidden")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(source.isAvailable ? .green : .red)

                Spacer()

                Button(isSelected ? "Remove" : "Add", action: onToggleSelection)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(nsColor: .underPageBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: isSelected ? 2 : 1)
        )
    }

    private var metadataText: String {
        let pidText = source.processID.map { "pid \($0)" } ?? "pid -"
        let bundleText = source.bundleIdentifier ?? "display source"
        return "\(source.kind.displayName) · \(pidText) · \(bundleText)"
    }
}
