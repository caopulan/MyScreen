import AppKit
import ApplicationServices
import Foundation

@MainActor
final class WindowActivationService {
    func activate(source: MonitorSource) {
        guard source.kind == .window, let processID = source.processID else { return }
        let pid = pid_t(processID)

        if let application = NSRunningApplication(processIdentifier: pid) {
            application.unhide()
            application.activate(options: [.activateAllWindows])
        }

        guard let windowTitle = source.windowTitle, !windowTitle.isEmpty else { return }
        guard requestAccessibilityIfNeeded() else { return }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            raiseWindow(processID: pid, title: windowTitle)
        }
    }

    private func requestAccessibilityIfNeeded() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private func raiseWindow(processID: pid_t, title: String) {
        let applicationElement = AXUIElementCreateApplication(processID)
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(applicationElement, kAXWindowsAttribute as CFString, &value)
        guard status == .success, let windows = value as? [AXUIElement], !windows.isEmpty else { return }

        let target = windows.first { window in
            var titleValue: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue)
            return result == .success && (titleValue as? String) == title
        } ?? windows.first

        guard let target else { return }

        AXUIElementPerformAction(target, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(target, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(target, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    }
}
