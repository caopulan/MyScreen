import SwiftUI

@main
struct MyScreenApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup("MyScreen") {
            RootView(appState: appState)
                .frame(minWidth: 900, minHeight: 620)
                .task {
                    appState.bootstrap()
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
    }
}
