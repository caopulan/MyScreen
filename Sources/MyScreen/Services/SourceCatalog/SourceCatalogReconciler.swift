import Foundation

enum SourceCatalogReconciler {
    static func reconcileSelections(_ selected: [MonitorSource], with catalog: SourceCatalog) -> [MonitorSource] {
        let catalogByID = Dictionary(uniqueKeysWithValues: (catalog.displays + catalog.windows).map { ($0.id, $0) })

        return selected.map { current in
            if let latest = catalogByID[current.id] {
                return latest
            }

            var offline = current
            offline.isAvailable = false
            return offline
        }
    }
}
