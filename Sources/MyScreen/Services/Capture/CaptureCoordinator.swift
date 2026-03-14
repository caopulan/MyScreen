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
        setCurrentMode(mode)
        self.stream = stream
        try await stream.startCapture()
    }

    func update(target: CaptureTarget, mode: CaptureDeliveryMode, previewMaxDimension: Int) async throws {
        guard let stream else {
            try await start(target: target, mode: mode, previewMaxDimension: previewMaxDimension)
            return
        }

        setCurrentMode(mode)
        try await stream.updateContentFilter(target.contentFilter())
        try await stream.updateConfiguration(
            target.streamConfiguration(mode: mode, previewMaxDimension: previewMaxDimension)
        )
    }

    func stop() async {
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
        DispatchQueue.main.async {
            self.onError(self.sourceID, error.localizedDescription)
            self.onOffline(self.sourceID)
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

        DispatchQueue.main.async {
            self.onFrame(self.sourceID, frame, tier)
        }
    }

    private func setCurrentMode(_ mode: CaptureDeliveryMode) {
        stateLock.lock()
        defer { stateLock.unlock() }
        currentMode = mode
    }

    private func currentModeTier() -> TileFrameRateTier {
        stateLock.lock()
        defer { stateLock.unlock() }
        return currentMode.tileFrameRateTier
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
