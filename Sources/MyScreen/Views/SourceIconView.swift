import AppKit
import SwiftUI

struct SourceIconView: View {
    let source: MonitorSource
    var size: CGFloat = 18
    var padding: CGFloat = 6
    var backgroundOpacity: Double = 0.16

    var body: some View {
        Group {
            if let image = applicationIcon {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: source.kind == .display ? "display" : "macwindow")
                    .font(.system(size: size * 0.62, weight: .medium))
                    .foregroundStyle(.white.opacity(0.88))
            }
        }
        .frame(width: size, height: size)
        .padding(padding)
        .background(
            RoundedRectangle(cornerRadius: max(8, size * 0.35))
                .fill(.white.opacity(backgroundOpacity))
        )
    }

    private var applicationIcon: NSImage? {
        guard source.kind == .window,
              let bundleIdentifier = source.bundleIdentifier,
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return nil
        }

        return NSWorkspace.shared.icon(forFile: appURL.path)
    }
}
