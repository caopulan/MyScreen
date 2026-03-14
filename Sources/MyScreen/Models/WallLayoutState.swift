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

        let maxColumns = min(sourceCount, 4)
        let targetAspect = 16.0 / 10.0
        var bestGrid = WallGrid(columns: 1, rows: sourceCount)
        var bestScore = Double.greatestFiniteMagnitude

        for columns in 1 ... maxColumns {
            let rows = Int(ceil(Double(sourceCount) / Double(columns)))
            let tileWidth = max(size.width, 1) / CGFloat(columns)
            let tileHeight = max(size.height, 1) / CGFloat(rows)
            let aspect = Double(tileWidth / max(tileHeight, 1))
            let emptySlots = (rows * columns) - sourceCount
            let score = abs(aspect - targetAspect) + (Double(emptySlots) * 0.2)

            if score < bestScore {
                bestScore = score
                bestGrid = WallGrid(columns: columns, rows: rows)
            }
        }

        return bestGrid
    }
}
