import CoreMedia
import Foundation

enum CaptureDeliveryMode: Equatable, Sendable {
    case live(framesPerSecond: Int)
    case polling(interval: TimeInterval)

    var tileFrameRateTier: TileFrameRateTier {
        switch self {
        case .live(let framesPerSecond) where framesPerSecond >= 12:
            .high
        case .live(let framesPerSecond) where framesPerSecond >= 8:
            .balanced
        case .live:
            .low
        case .polling:
            .polling
        }
    }

    var minimumFrameInterval: CMTime {
        switch self {
        case .live(let framesPerSecond):
            CMTime(value: 1, timescale: CMTimeScale(max(framesPerSecond, 1)))
        case .polling(let interval):
            CMTime(seconds: max(interval, 0.5), preferredTimescale: 600)
        }
    }
}

struct CaptureBudgetPlan: Equatable, Sendable {
    var previewMaxDimension: Int
    var deliveryModes: [String: CaptureDeliveryMode]
}

enum CaptureBudgetPlanner {
    static func plan(for sources: [MonitorSource], focusSourceID: String?) -> CaptureBudgetPlan {
        let count = sources.count
        guard count > 0 else {
            return CaptureBudgetPlan(previewMaxDimension: 640, deliveryModes: [:])
        }

        let previewMaxDimension: Int
        switch count {
        case 1 ... 4:
            previewMaxDimension = 640
        case 5 ... 8:
            previewMaxDimension = 560
        default:
            previewMaxDimension = 480
        }

        var orderedIDs = sources.map(\.id)
        if let focusSourceID, let index = orderedIDs.firstIndex(of: focusSourceID) {
            orderedIDs.remove(at: index)
            orderedIDs.insert(focusSourceID, at: 0)
        }

        var deliveryModes: [String: CaptureDeliveryMode] = [:]

        switch count {
        case 1 ... 4:
            for source in sources {
                deliveryModes[source.id] = source.id == focusSourceID ? .live(framesPerSecond: 15) : .live(framesPerSecond: 12)
            }
        case 5 ... 8:
            for source in sources {
                deliveryModes[source.id] = source.id == focusSourceID ? .live(framesPerSecond: 12) : .live(framesPerSecond: 10)
            }
        case 9 ... 12:
            for source in sources {
                deliveryModes[source.id] = source.id == focusSourceID ? .live(framesPerSecond: 8) : .live(framesPerSecond: 6)
            }
        default:
            let liveIDs = Set(orderedIDs.prefix(12))
            for source in sources {
                if liveIDs.contains(source.id) {
                    deliveryModes[source.id] = source.id == focusSourceID ? .live(framesPerSecond: 8) : .live(framesPerSecond: 5)
                } else {
                    deliveryModes[source.id] = .polling(interval: 2.0)
                }
            }
        }

        return CaptureBudgetPlan(
            previewMaxDimension: previewMaxDimension,
            deliveryModes: deliveryModes
        )
    }
}
