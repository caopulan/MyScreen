import AppKit
import SwiftUI

@main
struct MyScreenApp: App {
    @State private var appState = AppState()

    init() {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    var body: some Scene {
        WindowGroup("MyScreen") {
            RootView(appState: appState)
                .frame(minWidth: 900, minHeight: 620)
                .task {
                    await appState.bootstrap()
                }
        }
        .defaultSize(width: 1440, height: 900)
        .windowStyle(.hiddenTitleBar)
    }
}

private struct RootView: View {
    @Bindable var appState: AppState

    var body: some View {
        Group {
            if appState.permissionStatus == .granted {
                MonitorWallView(appState: appState)
            } else {
                PermissionGateView(
                    status: appState.permissionStatus,
                    isRequestInFlight: appState.isPermissionRequestInFlight,
                    onRequest: {
                        Task {
                            await appState.requestScreenCapturePermission()
                        }
                    }
                )
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if appState.permissionStatus == .granted {
                FloatingWallControls(appState: appState)
                    .padding(.trailing, 18)
                    .padding(.bottom, 18)
            }
        }
        .sheet(isPresented: $appState.isSourcePickerPresented) {
            SourcePickerView(appState: appState)
        }
    }
}

private struct FloatingWallControls: View {
    @Bindable var appState: AppState

    var body: some View {
        HStack(spacing: 10) {
            Menu {
                Button("Auto") {
                    appState.setPreferredColumnCount(nil)
                }

                Divider()

                ForEach(1 ... 6, id: \.self) { count in
                    Button("\(count) Columns") {
                        appState.setPreferredColumnCount(count)
                    }
                }
            } label: {
                FloatingControlButtonLabel(
                    title: "Layout",
                    systemImage: "square.grid.3x3"
                )
            }
            .menuStyle(.borderlessButton)

            Button {
                Task {
                    await appState.refreshSourceCatalog()
                }
            } label: {
                FloatingControlButtonLabel(
                    title: appState.isRefreshingSourceCatalog ? "Refreshing" : "Refresh",
                    systemImage: appState.isRefreshingSourceCatalog ? "arrow.trianglehead.2.clockwise.rotate.90" : "arrow.clockwise"
                )
            }
            .disabled(appState.isRefreshingSourceCatalog)

            Button {
                appState.isSourcePickerPresented = true
            } label: {
                FloatingControlButtonLabel(
                    title: "Add",
                    systemImage: "plus.rectangle.on.rectangle"
                )
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
    }
}

private struct FloatingControlButtonLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
            Text(title)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(.white.opacity(0.94))
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
