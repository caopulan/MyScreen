import AppKit
import CoreGraphics
import Foundation

actor SourceCatalogService {
    func fetchCatalog() async throws -> SourceCatalog {
        let now = Date()
        let currentBundleID = Bundle.main.bundleIdentifier
        let currentProcessID = ProcessInfo.processInfo.processIdentifier
        let appMap = NSWorkspace.shared.runningApplications.reduce(into: [Int32: NSRunningApplication]()) { partialResult, application in
            partialResult[application.processIdentifier] = application
        }

        let displays = NSScreen.screens.compactMap { screen -> MonitorSource? in
            guard let displayID = displayID(for: screen) else {
                return nil
            }

            let width = CGDisplayPixelsWide(displayID)
            let height = CGDisplayPixelsHigh(displayID)
            let title = "\(screen.localizedName) · \(width)×\(height)"

            return MonitorSource.display(
                displayID: displayID,
                title: title,
                isAvailable: true,
                lastSeenAt: now
            )
        }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

        let windows = currentWindowSnapshots()
            .compactMap { snapshot -> MonitorSource? in
                guard snapshot.ownerPID != currentProcessID else { return nil }
                guard let app = appMap[snapshot.ownerPID] else { return nil }
                guard app.bundleIdentifier != currentBundleID else { return nil }
                guard shouldIncludeWindow(snapshot: snapshot, app: app) else { return nil }

                let appName = app.localizedName ?? snapshot.ownerName ?? "Unknown App"
                let windowTitle = snapshot.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let title = windowTitle.isEmpty || windowTitle == appName ? appName : "\(appName) — \(windowTitle)"

                return MonitorSource.window(
                    windowID: snapshot.windowID,
                    title: title,
                    bundleIdentifier: app.bundleIdentifier,
                    processID: snapshot.ownerPID,
                    windowTitle: windowTitle.isEmpty ? nil : windowTitle,
                    isAvailable: snapshot.isOnScreen,
                    lastSeenAt: snapshot.isOnScreen ? now : nil
                )
            }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

        return SourceCatalog(displays: displays, windows: windows)
    }

    private func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let screenNumber = screen.deviceDescription[key] as? NSNumber else {
            return nil
        }

        return CGDirectDisplayID(screenNumber.uint32Value)
    }

    private func shouldIncludeWindow(snapshot: WindowSnapshot, app: NSRunningApplication) -> Bool {
        guard snapshot.layer == 0 else { return false }
        guard snapshot.alpha > 0.03 else { return false }
        guard snapshot.bounds.width >= 160, snapshot.bounds.height >= 100 else { return false }
        guard app.activationPolicy != .prohibited else { return false }
        return true
    }

    private func currentWindowSnapshots() -> [WindowSnapshot] {
        guard let windowInfoList = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        return windowInfoList.compactMap { info in
            guard let rawWindowID = info[kCGWindowNumber as String] as? NSNumber,
                  let ownerPID = info[kCGWindowOwnerPID as String] as? NSNumber else {
                return nil
            }

            let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            let isOnScreen = (info[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false
            let boundsPayload = info[kCGWindowBounds as String] as? [String: Any]
            let bounds = boundsPayload.flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) } ?? .zero
            let ownerName = info[kCGWindowOwnerName as String] as? String
            let title = (info[kCGWindowName as String] as? String) ?? ""

            return WindowSnapshot(
                windowID: rawWindowID.uint32Value,
                ownerPID: ownerPID.int32Value,
                ownerName: ownerName,
                title: title,
                isOnScreen: isOnScreen,
                layer: layer,
                alpha: alpha,
                bounds: bounds
            )
        }
    }
}

private struct WindowSnapshot {
    var windowID: UInt32
    var ownerPID: Int32
    var ownerName: String?
    var title: String
    var isOnScreen: Bool
    var layer: Int
    var alpha: Double
    var bounds: CGRect
}
