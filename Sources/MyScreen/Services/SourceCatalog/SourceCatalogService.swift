import AppKit
import CoreGraphics
import Foundation
@preconcurrency import ScreenCaptureKit

enum SourceCatalogServiceError: LocalizedError {
    case unavailableContent

    var errorDescription: String? {
        switch self {
        case .unavailableContent:
            "Unable to enumerate shareable displays and windows."
        }
    }
}

actor SourceCatalogService {
    func fetchCatalog() async throws -> SourceCatalog {
        let content = try await SCShareableContent.current
        let now = Date()
        let currentBundleID = Bundle.main.bundleIdentifier
        let appMap = NSWorkspace.shared.runningApplications.reduce(into: [Int32: NSRunningApplication]()) { partialResult, application in
            partialResult[application.processIdentifier] = application
        }
        let windowSnapshots = currentWindowSnapshots()

        let displays = content.displays
            .map { display in
                MonitorSource.display(
                    displayID: display.displayID,
                    title: displayTitle(for: display),
                    isAvailable: true,
                    lastSeenAt: now
                )
            }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

        let windows = content.windows
            .compactMap { window -> MonitorSource? in
                let application = window.owningApplication
                if application?.bundleIdentifier == currentBundleID {
                    return nil
                }

                let snapshot = windowSnapshots[window.windowID]
                let processID = application?.processID ?? snapshot?.ownerPID
                let workspaceApplication = processID.flatMap { appMap[$0] }
                let appName = application?.applicationName ?? workspaceApplication?.localizedName ?? "Unknown App"
                let bundleID = application?.bundleIdentifier ?? workspaceApplication?.bundleIdentifier
                let windowTitle = (window.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let title = windowTitle.isEmpty || windowTitle == appName ? appName : "\(appName) — \(windowTitle)"
                let isAvailable = snapshot?.isOnScreen ?? window.isOnScreen

                return MonitorSource.window(
                    windowID: window.windowID,
                    title: title,
                    bundleIdentifier: bundleID,
                    processID: processID,
                    isAvailable: isAvailable,
                    lastSeenAt: isAvailable ? now : nil
                )
            }
            .sorted { lhs, rhs in
                lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }

        return SourceCatalog(displays: displays, windows: windows)
    }

    private func displayTitle(for display: SCDisplay) -> String {
        "Display \(display.displayID) · \(display.width)×\(display.height)"
    }

    private func currentWindowSnapshots() -> [UInt32: WindowSnapshot] {
        guard let windowInfoList = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else {
            return [:]
        }

        return windowInfoList.reduce(into: [UInt32: WindowSnapshot]()) { partialResult, info in
            guard let rawWindowID = info[kCGWindowNumber as String] as? NSNumber else {
                return
            }

            let windowID = rawWindowID.uint32Value
            let ownerPID = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
            let isOnScreen = (info[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false

            partialResult[windowID] = WindowSnapshot(
                ownerPID: ownerPID,
                isOnScreen: isOnScreen
            )
        }
    }
}

private struct WindowSnapshot {
    var ownerPID: Int32?
    var isOnScreen: Bool
}
