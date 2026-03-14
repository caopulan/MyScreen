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
    var preferredColumnCount: Int?
}

enum WallGridCalculator {
    static func calculate(for sourceCount: Int, in size: CGSize, preferredColumnCount: Int? = nil) -> WallGrid {
        guard sourceCount > 0 else {
            return WallGrid(columns: 1, rows: 1)
        }

        if let preferredColumnCount {
            let columns = max(1, min(sourceCount, preferredColumnCount))
            let rows = Int(ceil(Double(sourceCount) / Double(columns)))
            return WallGrid(columns: columns, rows: rows)
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
