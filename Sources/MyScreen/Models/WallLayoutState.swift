import CoreGraphics
import Foundation

struct WallGrid: Codable, Equatable, Sendable {
    var columns: Int
    var rows: Int
}

struct WallLayoutState: Codable, Equatable, Sendable {
    var activeSourceIDs: [String]
    var focusedSourceID: String?
    var grid: WallGrid
    var windowSize: CodableSize
}

enum WallGridCalculator {
    static func calculate(for sourceCount: Int, in size: CGSize) -> WallGrid {
        guard sourceCount > 0 else {
            return WallGrid(columns: 1, rows: 1)
        }

        let aspectRatio = max(size.width, 1) / max(size.height, 1)
        let estimatedColumns = Int((sqrt(Double(sourceCount) * aspectRatio)).rounded(.up))
        let columns = max(1, min(sourceCount, estimatedColumns))
        let rows = Int(ceil(Double(sourceCount) / Double(columns)))
        return WallGrid(columns: columns, rows: rows)
    }
}
