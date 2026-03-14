import SwiftUI

struct SourcePickerView: View {
    @Bindable var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let error = appState.sourceCatalogError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }

                Section("Displays") {
                    if appState.sourceCatalog.displays.isEmpty {
                        emptyRow("No displays available")
                    } else {
                        ForEach(appState.sourceCatalog.displays) { source in
                            SourcePickerRow(
                                source: source,
                                isSelected: appState.isSelected(sourceID: source.id),
                                onToggleSelection: {
                                    appState.toggleSelection(for: source)
                                }
                            )
                        }
                    }
                }

                Section("App Windows") {
                    if appState.sourceCatalog.windows.isEmpty {
                        emptyRow("No windows available")
                    } else {
                        ForEach(appState.sourceCatalog.windows) { source in
                            SourcePickerRow(
                                source: source,
                                isSelected: appState.isSelected(sourceID: source.id),
                                onToggleSelection: {
                                    appState.toggleSelection(for: source)
                                }
                            )
                        }
                    }
                }
            }
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
        .frame(minWidth: 760, minHeight: 520)
    }

    @ViewBuilder
    private func emptyRow(_ title: String) -> some View {
        Text(title)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
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

private struct SourcePickerRow: View {
    let source: MonitorSource
    let isSelected: Bool
    let onToggleSelection: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: source.kind == .display ? "display" : "macwindow")
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(source.title)
                    .font(.body)
                    .lineLimit(1)
                Text(metadataText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if !source.isAvailable {
                Text("Offline")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.red)
            }

            Button(isSelected ? "Remove" : "Add", action: onToggleSelection)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(.vertical, 2)
    }

    private var metadataText: String {
        let pidText = source.processID.map { "pid \($0)" } ?? "pid -"
        let bundleText = source.bundleIdentifier ?? "unknown bundle"
        return "\(source.kind.displayName) · \(pidText) · \(bundleText)"
    }
}
