import AppKit
import CoreImage
import Foundation

@MainActor
final class CaptureCoordinator {
    var onFrame: (@MainActor (_ sourceID: String, _ frame: PreviewFrame, _ tier: TileFrameRateTier) -> Void)?
    var onError: (@MainActor (_ sourceID: String, _ message: String) -> Void)?
    var onOffline: (@MainActor (_ sourceID: String) -> Void)?

    private var sessions: [String: CaptureSession] = [:]

    func sync(sources: [MonitorSource], focusSourceID: String?) async {
        let plan = CaptureBudgetPlanner.plan(for: sources, focusSourceID: focusSourceID)
        let validIDs = Set(sources.map(\.id))

        for (sourceID, session) in sessions where !validIDs.contains(sourceID) {
            await session.stop()
            sessions.removeValue(forKey: sourceID)
        }

        for source in sources {
            guard let target = CaptureTarget(source: source), source.isAvailable else {
                if let session = sessions[source.id] {
                    await session.stop()
                    sessions.removeValue(forKey: source.id)
                }
                onOffline?(source.id)
                continue
            }

            let mode = plan.deliveryModes[source.id] ?? .polling(interval: 2.0)

            if let session = sessions[source.id] {
                session.update(target: target, mode: mode, previewMaxDimension: plan.previewMaxDimension)
            } else {
                let session = CaptureSession(
                    sourceID: source.id,
                    onFrame: { [weak self] sourceID, frame, tier in
                        self?.onFrame?(sourceID, frame, tier)
                    },
                    onError: { [weak self] sourceID, message in
                        self?.onError?(sourceID, message)
                    },
                    onOffline: { [weak self] sourceID in
                        self?.onOffline?(sourceID)
                    }
                )
                session.start(target: target, mode: mode, previewMaxDimension: plan.previewMaxDimension)
                sessions[source.id] = session
            }
        }
    }

    func stopAll() async {
        for session in sessions.values {
            await session.stop()
        }
        sessions.removeAll()
    }
}

private enum CaptureTarget {
    case display(CGDirectDisplayID)
    case window(CGWindowID)

    init?(source: MonitorSource) {
        switch source.kind {
        case .display:
            guard let displayID = source.displayID else { return nil }
            self = .display(displayID)
        case .window:
            guard let windowID = source.windowID else { return nil }
            self = .window(windowID)
        }
    }

    func snapshotImage(previewMaxDimension: Int, ciContext: CIContext) -> NSImage? {
        let baseImage: CGImage?

        switch self {
        case .display(let displayID):
            baseImage = CGDisplayCreateImage(displayID)
        case .window(let windowID):
            baseImage = CGWindowListCreateImage(
                .null,
                .optionIncludingWindow,
                windowID,
                [.bestResolution, .boundsIgnoreFraming]
            )
        }

        guard let baseImage else { return nil }
        let scaledImage = scaleIfNeeded(baseImage, maxDimension: previewMaxDimension, ciContext: ciContext)
        return NSImage(cgImage: scaledImage, size: NSSize(width: scaledImage.width, height: scaledImage.height))
    }

    private func scaleIfNeeded(_ image: CGImage, maxDimension: Int, ciContext: CIContext) -> CGImage {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let longestSide = max(width, height)
        guard longestSide > CGFloat(maxDimension), longestSide > 0 else {
            return image
        }

        let scale = CGFloat(maxDimension) / longestSide
        let ciImage = CIImage(cgImage: image).transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return ciContext.createCGImage(ciImage, from: ciImage.extent) ?? image
    }
}

private final class CaptureSession: @unchecked Sendable {
    private let sourceID: String
    private let onFrame: @MainActor (String, PreviewFrame, TileFrameRateTier) -> Void
    private let onError: @MainActor (String, String) -> Void
    private let onOffline: @MainActor (String) -> Void
    private let ciContext = CIContext()
    private let stateLock = NSLock()

    private var currentTarget: CaptureTarget?
    private var currentMode: CaptureDeliveryMode = .polling(interval: 2.0)
    private var currentPreviewMaxDimension = 640
    private var captureTask: Task<Void, Never>?

    init(
        sourceID: String,
        onFrame: @escaping @MainActor (String, PreviewFrame, TileFrameRateTier) -> Void,
        onError: @escaping @MainActor (String, String) -> Void,
        onOffline: @escaping @MainActor (String) -> Void
    ) {
        self.sourceID = sourceID
        self.onFrame = onFrame
        self.onError = onError
        self.onOffline = onOffline
    }

    func start(target: CaptureTarget, mode: CaptureDeliveryMode, previewMaxDimension: Int) {
        update(target: target, mode: mode, previewMaxDimension: previewMaxDimension)
        ensureCaptureTask()
    }

    func update(target: CaptureTarget, mode: CaptureDeliveryMode, previewMaxDimension: Int) {
        stateLock.lock()
        currentTarget = target
        currentMode = mode
        currentPreviewMaxDimension = previewMaxDimension
        stateLock.unlock()
        ensureCaptureTask()
    }

    func stop() async {
        captureTask?.cancel()
        captureTask = nil
    }

    private func ensureCaptureTask() {
        guard captureTask == nil else { return }

        captureTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                guard let state = self.snapshotState() else { return }

                if let image = state.target.snapshotImage(previewMaxDimension: state.previewMaxDimension, ciContext: self.ciContext) {
                    let frame = PreviewFrame(image: image, createdAt: Date())
                    await MainActor.run {
                        self.onFrame(self.sourceID, frame, state.mode.tileFrameRateTier)
                    }
                } else {
                    await MainActor.run {
                        self.onOffline(self.sourceID)
                    }
                }

                do {
                    try await Task.sleep(for: .seconds(self.interval(for: state.mode)))
                } catch {
                    return
                }
            }
        }
    }

    private func snapshotState() -> (target: CaptureTarget, mode: CaptureDeliveryMode, previewMaxDimension: Int)? {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard let currentTarget else { return nil }
        return (currentTarget, currentMode, currentPreviewMaxDimension)
    }

    private func interval(for mode: CaptureDeliveryMode) -> TimeInterval {
        switch mode {
        case .live(let framesPerSecond):
            return max(0.18, 1.0 / Double(max(framesPerSecond, 1)))
        case .polling(let interval):
            return max(interval, 1.0)
        }
    }
}

final class PreviewFrame: @unchecked Sendable {
    let image: NSImage
    let createdAt: Date

    init(image: NSImage, createdAt: Date) {
        self.image = image
        self.createdAt = createdAt
    }
}
