import AppKit
import CoreImage
import CoreMedia
import Foundation
@preconcurrency import ScreenCaptureKit

@MainActor
final class CaptureCoordinator {
    var onFrame: (@MainActor (_ sourceID: String, _ frame: PreviewFrame, _ tier: TileFrameRateTier) -> Void)?
    var onError: (@MainActor (_ sourceID: String, _ message: String) -> Void)?
    var onOffline: (@MainActor (_ sourceID: String) -> Void)?

    private var sessions: [String: CaptureSession] = [:]

    func sync(sources: [MonitorSource], focusSourceID: String?) async {
        guard !sources.isEmpty else {
            await stopAll()
            return
        }

        let targetMap: [String: CaptureTarget]
        do {
            targetMap = try await currentTargetMap()
        } catch {
            for source in sources {
                onError?(source.id, error.localizedDescription)
            }
            return
        }

        let plan = CaptureBudgetPlanner.plan(for: sources, focusSourceID: focusSourceID)
        let validIDs = Set(sources.map(\.id))

        for (sourceID, session) in sessions where !validIDs.contains(sourceID) {
            await session.stop()
            sessions.removeValue(forKey: sourceID)
        }

        for source in sources {
            guard source.isAvailable, let target = targetMap[source.id] else {
                if let session = sessions[source.id] {
                    await session.stop()
                    sessions.removeValue(forKey: source.id)
                }
                onOffline?(source.id)
                continue
            }

            let mode = plan.deliveryModes[source.id] ?? .polling(interval: 2.0)

            do {
                if let session = sessions[source.id] {
                    try await session.update(target: target, mode: mode, previewMaxDimension: plan.previewMaxDimension)
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
                    sessions[source.id] = session
                    try await session.start(target: target, mode: mode, previewMaxDimension: plan.previewMaxDimension)
                }
            } catch {
                onError?(source.id, error.localizedDescription)
            }
        }
    }

    func stopAll() async {
        for session in sessions.values {
            await session.stop()
        }
        sessions.removeAll()
    }

    private func currentTargetMap() async throws -> [String: CaptureTarget] {
        let content = try await SCShareableContent.current
        var targetMap: [String: CaptureTarget] = [:]

        for display in content.displays {
            targetMap[MonitorSource.displayIdentity(display.displayID)] = .display(display)
        }

        for window in content.windows {
            targetMap[MonitorSource.windowIdentity(window.windowID)] = .window(window)
        }

        return targetMap
    }
}

private enum CaptureTarget {
    case display(SCDisplay)
    case window(SCWindow)

    func contentFilter() -> SCContentFilter {
        switch self {
        case .display(let display):
            SCContentFilter(display: display, excludingWindows: [])
        case .window(let window):
            SCContentFilter(desktopIndependentWindow: window)
        }
    }

    func streamConfiguration(mode: CaptureDeliveryMode, previewMaxDimension: Int) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.minimumFrameInterval = mode.minimumFrameInterval
        configuration.queueDepth = 2
        configuration.showsCursor = true
        configuration.capturesAudio = false

        switch self {
        case .display(let display):
            let scale = CGFloat(previewMaxDimension) / CGFloat(max(display.width, display.height))
            configuration.width = Int(CGFloat(display.width) * min(scale, 1))
            configuration.height = Int(CGFloat(display.height) * min(scale, 1))
        case .window(let window):
            let frame = window.frame
            let maxDimension = max(frame.width, frame.height)
            let scale = maxDimension > 0 ? CGFloat(previewMaxDimension) / maxDimension : 1
            configuration.width = Int(frame.width * min(scale, 1))
            configuration.height = Int(frame.height * min(scale, 1))
        }

        configuration.width = max(configuration.width, 320)
        configuration.height = max(configuration.height, 200)
        return configuration
    }

    func snapshotImage(previewMaxDimension: Int, ciContext: CIContext) -> NSImage? {
        let baseImage: CGImage?

        switch self {
        case .display(let display):
            baseImage = CGDisplayCreateImage(display.displayID)
        case .window(let window):
            baseImage = CGWindowListCreateImage(
                .null,
                .optionIncludingWindow,
                window.windowID,
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

private final class CaptureSession: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let sourceID: String
    private let onFrame: @MainActor (String, PreviewFrame, TileFrameRateTier) -> Void
    private let onError: @MainActor (String, String) -> Void
    private let onOffline: @MainActor (String) -> Void
    private let sampleQueue: DispatchQueue
    private let ciContext = CIContext()
    private let stateLock = NSLock()

    private var stream: SCStream?
    private var currentMode: CaptureDeliveryMode = .polling(interval: 2.0)
    private var currentTarget: CaptureTarget?
    private var currentPreviewMaxDimension = 640
    private var snapshotTask: Task<Void, Never>?
    private var lastDeliveredFrameAt: Date?

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
        self.sampleQueue = DispatchQueue(label: "myscreen.capture.\(sourceID)", qos: .userInitiated)
    }

    func start(target: CaptureTarget, mode: CaptureDeliveryMode, previewMaxDimension: Int) async throws {
        let filter = target.contentFilter()
        let configuration = target.streamConfiguration(mode: mode, previewMaxDimension: previewMaxDimension)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        updateSnapshotState(target: target, mode: mode, previewMaxDimension: previewMaxDimension)
        ensureSnapshotTask()
        self.stream = stream
        try await stream.startCapture()
    }

    func update(target: CaptureTarget, mode: CaptureDeliveryMode, previewMaxDimension: Int) async throws {
        guard let stream else {
            try await start(target: target, mode: mode, previewMaxDimension: previewMaxDimension)
            return
        }

        updateSnapshotState(target: target, mode: mode, previewMaxDimension: previewMaxDimension)
        ensureSnapshotTask()
        try await stream.updateContentFilter(target.contentFilter())
        try await stream.updateConfiguration(
            target.streamConfiguration(mode: mode, previewMaxDimension: previewMaxDimension)
        )
    }

    func stop() async {
        snapshotTask?.cancel()
        snapshotTask = nil
        guard let stream else { return }
        self.stream = nil
        do {
            try await stream.stopCapture()
        } catch {
            await MainActor.run {
                onError(sourceID, error.localizedDescription)
            }
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        self.stream = nil
        DispatchQueue.main.async {
            self.onError(self.sourceID, error.localizedDescription)
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .screen else { return }
        guard CMSampleBufferIsValid(sampleBuffer), let imageBuffer = sampleBuffer.imageBuffer else { return }

        let ciImage = CIImage(cvImageBuffer: imageBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        let tier = currentModeTier()
        let frame = PreviewFrame(image: image, createdAt: Date())
        recordDeliveredFrame(at: frame.createdAt)

        DispatchQueue.main.async {
            self.onFrame(self.sourceID, frame, tier)
        }
    }

    private func updateSnapshotState(target: CaptureTarget, mode: CaptureDeliveryMode, previewMaxDimension: Int) {
        stateLock.lock()
        defer { stateLock.unlock() }
        currentTarget = target
        currentMode = mode
        currentPreviewMaxDimension = previewMaxDimension
    }

    private func currentModeTier() -> TileFrameRateTier {
        stateLock.lock()
        defer { stateLock.unlock() }
        return currentMode.tileFrameRateTier
    }

    private func recordDeliveredFrame(at date: Date) {
        stateLock.lock()
        defer { stateLock.unlock() }
        lastDeliveredFrameAt = date
    }

    private func snapshotState() -> (target: CaptureTarget, mode: CaptureDeliveryMode, previewMaxDimension: Int, lastDeliveredFrameAt: Date?)? {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard let currentTarget else { return nil }
        return (currentTarget, currentMode, currentPreviewMaxDimension, lastDeliveredFrameAt)
    }

    private func ensureSnapshotTask() {
        guard snapshotTask == nil else { return }

        snapshotTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                guard let state = self.snapshotState() else { return }
                let interval = self.snapshotInterval(for: state.mode)

                if let lastDeliveredFrameAt = state.lastDeliveredFrameAt,
                   Date().timeIntervalSince(lastDeliveredFrameAt) < interval * 1.2 {
                    do {
                        try await Task.sleep(for: .seconds(interval))
                    } catch {
                        return
                    }
                    continue
                }

                if let image = state.target.snapshotImage(previewMaxDimension: state.previewMaxDimension, ciContext: self.ciContext) {
                    let frame = PreviewFrame(image: image, createdAt: Date())
                    self.recordDeliveredFrame(at: frame.createdAt)
                    let tier = state.mode.tileFrameRateTier
                    await MainActor.run {
                        self.onFrame(self.sourceID, frame, tier)
                    }
                } else if state.lastDeliveredFrameAt == nil || Date().timeIntervalSince(state.lastDeliveredFrameAt!) > 3 {
                    await MainActor.run {
                        self.onOffline(self.sourceID)
                    }
                }

                do {
                    try await Task.sleep(for: .seconds(interval))
                } catch {
                    return
                }
            }
        }
    }

    private func snapshotInterval(for mode: CaptureDeliveryMode) -> TimeInterval {
        switch mode {
        case .live(let framesPerSecond):
            return max(0.5, 1.0 / Double(max(framesPerSecond / 2, 1)))
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
