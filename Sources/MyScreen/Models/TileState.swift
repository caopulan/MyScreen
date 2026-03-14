import AppKit
import SwiftUI

enum TileFreshness: String {
    case live
    case stale
    case offline
}

enum TileFrameRateTier: String {
    case high
    case balanced
    case low
    case polling
}

struct TileState {
    var sourceID: String
    var previewImage: NSImage?
    var freshness: TileFreshness
    var fpsTier: TileFrameRateTier
    var lastFrameAt: Date?
    var errorMessage: String?

    var isOffline: Bool {
        freshness == .offline
    }

    var statusLabel: String {
        if errorMessage != nil {
            return "Error"
        }

        switch freshness {
        case .live:
            return "Live"
        case .stale:
            return "Waiting"
        case .offline:
            return "Offline"
        }
    }

    var statusColor: Color {
        if errorMessage != nil {
            return .orange
        }

        switch freshness {
        case .live:
            return Color.green
        case .stale:
            return Color.yellow
        case .offline:
            return Color.red
        }
    }

    static func placeholder(
        sourceID: String,
        fpsTier: TileFrameRateTier,
        freshness: TileFreshness,
        lastFrameAt: Date?
    ) -> TileState {
        TileState(
            sourceID: sourceID,
            previewImage: nil,
            freshness: freshness,
            fpsTier: fpsTier,
            lastFrameAt: lastFrameAt,
            errorMessage: nil
        )
    }
}
