import Foundation

enum SelectedSourceReorderer {
    static func reordered(
        sources: [MonitorSource],
        moving movingSourceID: String,
        to targetSourceID: String
    ) -> [MonitorSource] {
        guard movingSourceID != targetSourceID,
              let movingIndex = sources.firstIndex(where: { $0.id == movingSourceID }),
              let targetIndex = sources.firstIndex(where: { $0.id == targetSourceID }) else {
            return sources
        }

        var reorderedSources = sources
        let movingSource = reorderedSources.remove(at: movingIndex)
        reorderedSources.insert(movingSource, at: targetIndex)
        return reorderedSources
    }
}
