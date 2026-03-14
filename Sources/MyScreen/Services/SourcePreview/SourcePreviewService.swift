import AppKit
import CoreGraphics
import CoreImage
import Foundation

enum SourcePreviewService {
    static func snapshotImage(for source: MonitorSource, maxDimension: Int) -> NSImage? {
        let baseImage: CGImage?

        switch source.kind {
        case .display:
            guard let displayID = source.displayID else { return nil }
            baseImage = CGDisplayCreateImage(displayID)
        case .window:
            guard let windowID = source.windowID else { return nil }
            baseImage = CGWindowListCreateImage(
                .null,
                .optionIncludingWindow,
                windowID,
                [.bestResolution, .boundsIgnoreFraming]
            )
        }

        guard let baseImage else { return nil }
        let scaledImage = scaleIfNeeded(baseImage, maxDimension: maxDimension)
        return NSImage(cgImage: scaledImage, size: NSSize(width: scaledImage.width, height: scaledImage.height))
    }

    private static func scaleIfNeeded(_ image: CGImage, maxDimension: Int) -> CGImage {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let longestSide = max(width, height)
        guard longestSide > CGFloat(maxDimension), longestSide > 0 else {
            return image
        }

        let scale = CGFloat(maxDimension) / longestSide
        let ciImage = CIImage(cgImage: image).transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext()
        return context.createCGImage(ciImage, from: ciImage.extent) ?? image
    }
}
