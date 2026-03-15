import AppKit
import CoreImage
import CoreMedia
import CoreVideo
import Foundation
import ObjectiveC.runtime
@preconcurrency import ScreenCaptureKit

@MainActor
final class CaptureCoordinator {
    var onFrame: (@MainActor (_ sourceID: String, _ frame: PreviewFrame, _ tier: TileFrameRateTier) -> Void)?
    var onError: (@MainActor (_ sourceID: String, _ message: String) -> Void)?
    var onOffline: (@MainActor (_ sourceID: String) -> Void)?

    private var sessions: [String: CaptureSession] = [:]
    private let streamResolver = ScreenCaptureResolver()

    func sync(sources: [MonitorSource], focusSourceID: String?) async {
        let plan = CaptureBudgetPlanner.plan(for: sources, focusSourceID: focusSourceID)
        let validIDs = Set(sources.map(\.id))

        for (sourceID, session) in sessions where !validIDs.contains(sourceID) {
            await session.stop()
            sessions.removeValue(forKey: sourceID)
        }

        let liveSources = sources.filter {
            guard let mode = plan.deliveryModes[$0.id] else { return false }
            return mode.prefersStreamCapture
        }
        let streamTargets = await streamResolver.resolveTargets(for: liveSources)

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
            let streamTarget = streamTargets[source.id]

            if let session = sessions[source.id] {
                await session.update(
                    target: target,
                    streamTarget: streamTarget,
                    mode: mode,
                    previewMaxDimension: plan.previewMaxDimension
                )
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
                await session.start(
                    target: target,
                    streamTarget: streamTarget,
                    mode: mode,
                    previewMaxDimension: plan.previewMaxDimension
                )
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

private enum CaptureTarget: Equatable, Sendable {
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

    var identity: String {
        switch self {
        case .display(let displayID):
            MonitorSource.displayIdentity(displayID)
        case .window(let windowID):
            MonitorSource.windowIdentity(windowID)
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

private enum StreamCaptureTarget: @unchecked Sendable {
    case display(SCDisplay)
    case window(SCWindow)

    var identity: String {
        switch self {
        case .display(let display):
            MonitorSource.displayIdentity(display.displayID)
        case .window(let window):
            MonitorSource.windowIdentity(window.windowID)
        }
    }

    func makeFilter() -> SCContentFilter {
        switch self {
        case .display(let display):
            let filter = SCContentFilter(display: display, excludingWindows: [])
            if #available(macOS 14.2, *) {
                filter.includeMenuBar = true
            }
            return filter
        case .window(let window):
            return SCContentFilter(desktopIndependentWindow: window)
        }
    }

    func makeStreamConfiguration(mode: CaptureDeliveryMode, previewMaxDimension: Int) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        let targetSize = scaledPixelSize(maxDimension: previewMaxDimension)

        configuration.width = max(1, targetSize.width)
        configuration.height = max(1, targetSize.height)
        configuration.minimumFrameInterval = mode.minimumFrameInterval
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.queueDepth = 3
        configuration.showsCursor = true
        configuration.scalesToFit = true
        if #available(macOS 14.0, *) {
            configuration.preservesAspectRatio = true
        }

        return configuration
    }

    private func scaledPixelSize(maxDimension: Int) -> (width: Int, height: Int) {
        let sourceSize: CGSize
        switch self {
        case .display(let display):
            sourceSize = CGSize(width: display.width, height: display.height)
        case .window(let window):
            sourceSize = window.frame.size
        }

        let width = max(sourceSize.width, 1)
        let height = max(sourceSize.height, 1)
        let longestSide = max(width, height)
        let scale = min(CGFloat(maxDimension) / longestSide, 1)
        let scaledWidth = max(Int((width * scale).rounded(.toNearestOrEven)), 1)
        let scaledHeight = max(Int((height * scale).rounded(.toNearestOrEven)), 1)
        return (scaledWidth, scaledHeight)
    }
}

private struct DesiredCaptureState: Sendable {
    var target: CaptureTarget
    var streamTarget: StreamCaptureTarget?
    var mode: CaptureDeliveryMode
    var previewMaxDimension: Int

    var signature: CaptureSessionSignature {
        CaptureSessionSignature(
            targetIdentity: target.identity,
            streamTargetIdentity: streamTarget?.identity,
            mode: mode,
            previewMaxDimension: previewMaxDimension,
            prefersStream: mode.prefersStreamCapture && streamTarget != nil
        )
    }
}

private struct CaptureSessionSignature: Equatable, Sendable {
    var targetIdentity: String
    var streamTargetIdentity: String?
    var mode: CaptureDeliveryMode
    var previewMaxDimension: Int
    var prefersStream: Bool
}

private actor CaptureSession {
    private let sourceID: String
    private let onFrame: @MainActor (String, PreviewFrame, TileFrameRateTier) -> Void
    private let onError: @MainActor (String, String) -> Void
    private let onOffline: @MainActor (String) -> Void

    private var desiredState: DesiredCaptureState?
    private var activeSignature: CaptureSessionSignature?
    private var pollingTask: Task<Void, Never>?
    private var streamDriver: StreamCaptureDriver?

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

    func start(target: CaptureTarget, streamTarget: StreamCaptureTarget?, mode: CaptureDeliveryMode, previewMaxDimension: Int) async {
        await update(target: target, streamTarget: streamTarget, mode: mode, previewMaxDimension: previewMaxDimension)
    }

    func update(target: CaptureTarget, streamTarget: StreamCaptureTarget?, mode: CaptureDeliveryMode, previewMaxDimension: Int) async {
        desiredState = DesiredCaptureState(
            target: target,
            streamTarget: streamTarget,
            mode: mode,
            previewMaxDimension: previewMaxDimension
        )
        await reconcile()
    }

    func stop() async {
        desiredState = nil
        activeSignature = nil
        pollingTask?.cancel()
        pollingTask = nil
        if let streamDriver {
            await streamDriver.stop()
            self.streamDriver = nil
        }
    }

    private func reconcile() async {
        guard let desiredState else {
            await stop()
            return
        }

        let signature = desiredState.signature
        guard signature != activeSignature else { return }

        pollingTask?.cancel()
        pollingTask = nil
        if let streamDriver {
            await streamDriver.stop()
            self.streamDriver = nil
        }

        if signature.prefersStream, let streamTarget = desiredState.streamTarget {
            do {
                let tier = desiredState.mode.tileFrameRateTier
                let streamDriver = StreamCaptureDriver(
                    sourceID: sourceID,
                    tier: tier,
                    onFrame: { [weak self] frame, tier in
                        Task { [weak self] in
                            await self?.deliverFrame(frame, tier: tier)
                        }
                    },
                    onError: { [weak self] message in
                        Task { [weak self] in
                            await self?.deliverError(message)
                        }
                    },
                    onOffline: { [weak self] in
                        Task { [weak self] in
                            await self?.deliverOffline()
                        }
                    }
                )
                try await streamDriver.start(
                    target: streamTarget,
                    mode: desiredState.mode,
                    previewMaxDimension: desiredState.previewMaxDimension
                )
                self.streamDriver = streamDriver
                activeSignature = signature
                return
            } catch {
                await MainActor.run {
                    self.onError(self.sourceID, error.localizedDescription)
                }
            }
        }

        startPolling(for: desiredState)
        activeSignature = DesiredCaptureState(
            target: desiredState.target,
            streamTarget: nil,
            mode: desiredState.mode,
            previewMaxDimension: desiredState.previewMaxDimension
        ).signature
    }

    private func startPolling(for desiredState: DesiredCaptureState) {
        let sourceID = self.sourceID
        let onFrame = self.onFrame
        let onOffline = self.onOffline

        pollingTask = Task.detached(priority: .userInitiated) { [weak self] in
            let ciContext = CIContext()

            while !Task.isCancelled {
                guard let self else { return }
                guard let state = await self.currentPollingState() else { return }

                let frameDate = Date()
                let image = autoreleasepool {
                    state.target.snapshotImage(previewMaxDimension: state.previewMaxDimension, ciContext: ciContext)
                }

                if let image {
                    let frame = PreviewFrame(image: image, createdAt: frameDate)
                    await MainActor.run {
                        onFrame(sourceID, frame, state.mode.tileFrameRateTier)
                    }
                } else {
                    await MainActor.run {
                        onOffline(sourceID)
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

    private func currentPollingState() -> DesiredCaptureState? {
        guard let desiredState else { return nil }
        guard !desiredState.signature.prefersStream else { return nil }
        return desiredState
    }

    private func deliverFrame(_ frame: PreviewFrame, tier: TileFrameRateTier) async {
        await MainActor.run {
            onFrame(sourceID, frame, tier)
        }
    }

    private func deliverError(_ message: String) async {
        await MainActor.run {
            onError(sourceID, message)
        }
    }

    private func deliverOffline() async {
        await MainActor.run {
            onOffline(sourceID)
        }
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

private final class StreamCaptureDriver: NSObject, @unchecked Sendable, SCStreamOutput, SCStreamDelegate {
    private let sourceID: String
    private let tier: TileFrameRateTier
    private let onFrame: @Sendable (PreviewFrame, TileFrameRateTier) -> Void
    private let onError: @Sendable (String) -> Void
    private let onOffline: @Sendable () -> Void
    private let sampleHandlerQueue: DispatchQueue
    private let ciContext = CIContext()

    private var stream: SCStream?
    private var isStopped = false
    private let stateLock = NSLock()

    init(
        sourceID: String,
        tier: TileFrameRateTier,
        onFrame: @escaping @Sendable (PreviewFrame, TileFrameRateTier) -> Void,
        onError: @escaping @Sendable (String) -> Void,
        onOffline: @escaping @Sendable () -> Void
    ) {
        self.sourceID = sourceID
        self.tier = tier
        self.onFrame = onFrame
        self.onError = onError
        self.onOffline = onOffline
        self.sampleHandlerQueue = DispatchQueue(label: "MyScreen.Capture.\(sourceID)", qos: .userInitiated)
        super.init()
    }

    func start(target: StreamCaptureTarget, mode: CaptureDeliveryMode, previewMaxDimension: Int) async throws {
        let filter = target.makeFilter()
        let configuration = target.makeStreamConfiguration(mode: mode, previewMaxDimension: previewMaxDimension)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        self.stream = stream

        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleHandlerQueue)

        do {
            try await performStreamOperation(named: "start capture") { completion in
                stream.startCapture(completionHandler: completion)
            }
        } catch {
            self.stream = nil
            throw error
        }
    }

    func stop() async {
        guard let stream else { return }
        markStopped()
        self.stream = nil

        try? stream.removeStreamOutput(self, type: .screen)
        try? await performStreamOperation(named: "stop capture", timeout: 2.0) { completion in
            stream.stopCapture(completionHandler: completion)
        }
    }

    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        guard !isMarkedStopped else { return }

        autoreleasepool {
            guard let status = frameStatus(for: sampleBuffer) else { return }
            switch status {
            case .complete, .started:
                break
            case .blank, .stopped, .suspended:
                onOffline()
                return
            case .idle:
                return
            @unknown default:
                return
            }

            guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            let ciImage = CIImage(cvImageBuffer: imageBuffer)
            guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }

            let size = NSSize(width: cgImage.width, height: cgImage.height)
            let frame = PreviewFrame(
                image: NSImage(cgImage: cgImage, size: size),
                createdAt: Date()
            )
            onFrame(frame, tier)
        }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        guard !isMarkedStopped else { return }
        onError(error.localizedDescription)
    }

    private var isMarkedStopped: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return isStopped
    }

    private func markStopped() {
        stateLock.lock()
        isStopped = true
        stateLock.unlock()
    }

    private func performStreamOperation(
        named operationName: String,
        timeout: TimeInterval = 5.0,
        _ operation: (@escaping @Sendable (Error?) -> Void) -> Void
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let gate = ContinuationGate(continuation)

            operation { error in
                if let error {
                    gate.resume(throwing: error)
                } else {
                    gate.resume(returning: ())
                }
            }

            Task.detached {
                try? await Task.sleep(for: .seconds(timeout))
                gate.resume(throwing: ScreenCaptureOperationError.timedOut(operationName))
            }
        }
    }

    private func frameStatus(for sampleBuffer: CMSampleBuffer) -> SCFrameStatus? {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let firstAttachment = attachments.first,
              let rawStatus = firstAttachment[.status] as? Int else {
            return nil
        }

        return SCFrameStatus(rawValue: rawStatus)
    }
}

private actor ScreenCaptureResolver {
    func resolveTargets(for sources: [MonitorSource]) async -> [String: StreamCaptureTarget] {
        guard !sources.isEmpty else { return [:] }

        let shareableContent: SCShareableContent
        do {
            shareableContent = try await ScreenCaptureShareableContentProvider.current()
        } catch {
            return [:]
        }

        let displaysByID = Dictionary(uniqueKeysWithValues: shareableContent.displays.map { ($0.displayID, $0) })
        let windowsByID = Dictionary(uniqueKeysWithValues: shareableContent.windows.map { ($0.windowID, $0) })

        var resolvedTargets: [String: StreamCaptureTarget] = [:]

        for source in sources {
            switch source.kind {
            case .display:
                guard let displayID = source.displayID, let display = displaysByID[displayID] else { continue }
                resolvedTargets[source.id] = .display(display)
            case .window:
                guard let windowID = source.windowID, let window = windowsByID[windowID] else { continue }
                resolvedTargets[source.id] = .window(window)
            }
        }

        return resolvedTargets
    }
}

private enum ScreenCaptureShareableContentProvider {
    static func current(timeout: TimeInterval = 5.0) async throws -> SCShareableContent {
        let boxedContent = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ShareableContentBox, Error>) in
            let gate = ContinuationGate(continuation)
            let selector = NSSelectorFromString("getShareableContentWithCompletionHandler:")

            guard let method = class_getClassMethod(SCShareableContent.self, selector) else {
                gate.resume(throwing: ScreenCaptureOperationError.failed("ScreenCaptureKit content API is unavailable."))
                return
            }

            typealias Completion = @convention(block) (SCShareableContent?, NSError?) -> Void
            typealias Method = @convention(c) (AnyClass, Selector, Completion) -> Void

            let implementation = method_getImplementation(method)
            let function = unsafeBitCast(implementation, to: Method.self)
            let completion: Completion = { content, error in
                if let error {
                    gate.resume(throwing: error)
                } else if let content {
                    gate.resume(returning: ShareableContentBox(content: content))
                } else {
                    gate.resume(throwing: ScreenCaptureOperationError.failed("ScreenCaptureKit returned no shareable content."))
                }
            }

            function(SCShareableContent.self, selector, completion)

            Task.detached {
                try? await Task.sleep(for: .seconds(timeout))
                gate.resume(throwing: ScreenCaptureOperationError.timedOut("load shareable content"))
            }
        }
        return boxedContent.content
    }
}

private struct ShareableContentBox: @unchecked Sendable {
    let content: SCShareableContent
}

private final class ContinuationGate<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?

    init(_ continuation: CheckedContinuation<Value, Error>) {
        self.continuation = continuation
    }

    func resume(returning value: Value) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: value)
    }

    func resume(throwing error: Error) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(throwing: error)
    }
}

private enum ScreenCaptureOperationError: LocalizedError {
    case timedOut(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .timedOut(let operation):
            "ScreenCaptureKit \(operation) timed out."
        case .failed(let message):
            message
        }
    }
}

private extension CaptureDeliveryMode {
    var prefersStreamCapture: Bool {
        if case .live = self {
            return true
        }
        return false
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
