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
                        Label("Layout", systemImage: "square.grid.3x3")
                    }

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
                        Label("Add Sources", systemImage: "plus.rectangle.on.rectangle")
                    }
                }
            }
        }
        .sheet(isPresented: $appState.isSourcePickerPresented) {
            SourcePickerView(appState: appState)
        }
    }
}
