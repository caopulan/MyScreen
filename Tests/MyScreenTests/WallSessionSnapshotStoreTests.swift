import Foundation
import Testing
@testable import MyScreen

@Test
func snapshotStoreRoundTripsSelectionAndWindowState() throws {
    let suiteName = "MyScreenTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        Issue.record("Unable to create isolated UserDefaults suite")
        return
    }
    defer {
        defaults.removePersistentDomain(forName: suiteName)
    }

    let store = WallSessionSnapshotStore(userDefaults: defaults)
    let snapshot = WallSessionSnapshot(
        selectedSources: [
            MonitorSource.display(displayID: 1, title: "Display 1"),
            MonitorSource.window(windowID: 2, title: "Safari"),
        ],
        focusedSourceID: "window:2",
        windowSize: CodableSize(width: 1440, height: 900),
        preferredColumnCount: 3
    )

    store.save(snapshot)

    #expect(store.load() == snapshot)
}
