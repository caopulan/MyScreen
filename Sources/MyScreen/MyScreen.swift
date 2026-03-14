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
    @State private var isLayoutPopoverPresented = false

    var body: some View {
        HStack(spacing: 10) {
            Button {
                isLayoutPopoverPresented.toggle()
            } label: {
                FloatingGlassControlChrome(
                    systemImage: "square.grid.3x3.fill",
                    isActive: isLayoutPopoverPresented
                )
            }
            .buttonStyle(.plain)
            .help("Layout")
            .popover(isPresented: $isLayoutPopoverPresented, arrowEdge: .bottom) {
                LayoutOptionsPopover(
                    appState: appState,
                    isPresented: $isLayoutPopoverPresented
                )
            }

            Button {
                Task {
                    await appState.refreshSourceCatalog()
                }
            } label: {
                FloatingGlassControlChrome(
                    systemImage: appState.isRefreshingSourceCatalog ? "arrow.trianglehead.2.clockwise.rotate.90" : "arrow.clockwise",
                    isDisabled: appState.isRefreshingSourceCatalog
                )
            }
            .buttonStyle(.plain)
            .disabled(appState.isRefreshingSourceCatalog)
            .help("Refresh")

            Button {
                appState.isSourcePickerPresented = true
            } label: {
                FloatingGlassControlChrome(systemImage: "plus")
            }
            .buttonStyle(.plain)
            .help("Add")
        }
    }
}

private struct FloatingGlassControlChrome: View {
    let systemImage: String
    var isActive = false
    var isDisabled = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(.ultraThinMaterial)

            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(isActive ? 0.36 : 0.28),
                            Color.white.opacity(isActive ? 0.22 : 0.16),
                            Color.white.opacity(0.08),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(isActive ? 0.92 : 0.82),
                            Color.white.opacity(0.36),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )

            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
                .blur(radius: 1.2)
                .mask(
                    VStack(spacing: 0) {
                        Rectangle().frame(height: 14)
                        Spacer(minLength: 0)
                    }
                )

            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.black.opacity(isDisabled ? 0.34 : 0.7))
        }
        .frame(width: 44, height: 38)
        .shadow(color: .black.opacity(isActive ? 0.16 : 0.12), radius: 16, y: 10)
        .opacity(isDisabled ? 0.78 : 1)
    }
}

private struct LayoutOptionsPopover: View {
    @Bindable var appState: AppState
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            layoutOptionButton(title: "Auto", preferredColumnCount: nil)

            Divider()

            ForEach(1 ... 6, id: \.self) { count in
                layoutOptionButton(title: "\(count) Columns", preferredColumnCount: count)
            }
        }
        .padding(12)
        .frame(width: 140)
    }

    private func layoutOptionButton(title: String, preferredColumnCount: Int?) -> some View {
        Button(title) {
            appState.setPreferredColumnCount(preferredColumnCount)
            isPresented = false
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(appState.wallLayout.preferredColumnCount == preferredColumnCount ? 0.08 : 0.0001))
        )
    }
}
