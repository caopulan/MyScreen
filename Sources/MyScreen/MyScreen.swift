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
                FloatingIconControlButton(
                    systemImage: "square.grid.3x3.fill"
                )
            }
            .menuStyle(.borderlessButton)
            .help("Layout")

            Button {
                Task {
                    await appState.refreshSourceCatalog()
                }
            } label: {
                FloatingIconControlButton(
                    systemImage: appState.isRefreshingSourceCatalog ? "arrow.trianglehead.2.clockwise.rotate.90" : "arrow.clockwise"
                )
            }
            .buttonStyle(.plain)
            .disabled(appState.isRefreshingSourceCatalog)
            .help("Refresh")

            Button {
                appState.isSourcePickerPresented = true
            } label: {
                FloatingIconControlButton(systemImage: "plus")
            }
            .buttonStyle(.plain)
            .help("Add")
        }
    }
}

private struct FloatingIconControlButton: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Color.black.opacity(0.72))
            .frame(width: 42, height: 36)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.22))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.55), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.2), radius: 14, y: 8)
    }
}
