import CoreGraphics
import Foundation

enum MonitorSourceKind: String, Codable, CaseIterable, Sendable {
    case display
    case window

    var displayName: String {
        switch self {
        case .display:
            "Display"
        case .window:
            "Window"
        }
    }
}

struct MonitorSource: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var title: String
    var kind: MonitorSourceKind
    var bundleIdentifier: String?
    var processID: Int32?
    var windowID: UInt32?
    var displayID: UInt32?
    var windowTitle: String?
    var isAvailable: Bool
    var lastSeenAt: Date?

    static func display(
        displayID: UInt32,
        title: String,
        bundleIdentifier: String? = nil,
        processID: Int32? = nil,
        isAvailable: Bool = true,
        lastSeenAt: Date? = nil
    ) -> MonitorSource {
        MonitorSource(
            id: displayIdentity(displayID),
            title: title,
            kind: .display,
            bundleIdentifier: bundleIdentifier,
            processID: processID,
            windowID: nil,
            displayID: displayID,
            windowTitle: nil,
            isAvailable: isAvailable,
            lastSeenAt: lastSeenAt
        )
    }

    static func window(
        windowID: UInt32,
        title: String,
        bundleIdentifier: String? = nil,
        processID: Int32? = nil,
        windowTitle: String? = nil,
        isAvailable: Bool = true,
        lastSeenAt: Date? = nil
    ) -> MonitorSource {
        MonitorSource(
            id: windowIdentity(windowID),
            title: title,
            kind: .window,
            bundleIdentifier: bundleIdentifier,
            processID: processID,
            windowID: windowID,
            displayID: nil,
            windowTitle: windowTitle,
            isAvailable: isAvailable,
            lastSeenAt: lastSeenAt
        )
    }

    static func displayIdentity(_ displayID: UInt32) -> String {
        "display:\(displayID)"
    }

    static func windowIdentity(_ windowID: UInt32) -> String {
        "window:\(windowID)"
    }
}
