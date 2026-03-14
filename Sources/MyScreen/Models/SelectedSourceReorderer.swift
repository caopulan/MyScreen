import Foundation

enum SelectedSourceReorderer {
    static func reordered(
        sourceIDs: [String],
        moving movingSourceID: String,
        toIndex destinationIndex: Int
    ) -> [String] {
        guard let movingIndex = sourceIDs.firstIndex(of: movingSourceID), !sourceIDs.isEmpty else {
            return sourceIDs
        }

        let clampedDestinationIndex = max(0, min(destinationIndex, sourceIDs.count - 1))
        guard movingIndex != clampedDestinationIndex else {
            return sourceIDs
        }

        var reorderedSourceIDs = sourceIDs
        let movingSourceID = reorderedSourceIDs.remove(at: movingIndex)
        reorderedSourceIDs.insert(movingSourceID, at: clampedDestinationIndex)
        return reorderedSourceIDs
    }

    static func reordered(
        sources: [MonitorSource],
        moving movingSourceID: String,
        to targetSourceID: String
    ) -> [MonitorSource] {
        guard movingSourceID != targetSourceID,
              let targetIndex = sources.firstIndex(where: { $0.id == targetSourceID }) else {
            return sources
        }
        let reorderedIDs = reordered(
            sourceIDs: sources.map(\.id),
            moving: movingSourceID,
            toIndex: targetIndex
        )
        let sourcesByID = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0) })
        return reorderedIDs.compactMap { sourcesByID[$0] }
    }
}
