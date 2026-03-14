import Foundation

struct SourceCatalog: Equatable {
    var displays: [MonitorSource]
    var windows: [MonitorSource]

    static let empty = SourceCatalog(displays: [], windows: [])

    var isEmpty: Bool {
        displays.isEmpty && windows.isEmpty
    }

    var onlineWindows: [MonitorSource] {
        windows.filter(\.isAvailable)
    }

    var offlineWindows: [MonitorSource] {
        windows.filter { !$0.isAvailable }
    }
}
