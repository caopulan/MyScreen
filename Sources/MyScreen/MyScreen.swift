import SwiftUI

@main
struct MyScreenApp: App {
    @State private var appState = AppState()

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
        .toolbar {
            if appState.permissionStatus == .granted {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        Task {
                            await appState.refreshSourceCatalog()
                        }
                    } label: {
                        Label("Refresh Sources", systemImage: "arrow.clockwise")
                    }
                    .disabled(appState.isRefreshingSourceCatalog)

                    Button {
                        appState.isSourcePickerPresented = true
                    } label: {
                        Label("Sources", systemImage: "slider.horizontal.3")
                    }
                }
            }
        }
        .sheet(isPresented: $appState.isSourcePickerPresented) {
            SourcePickerView(appState: appState)
        }
    }
}
