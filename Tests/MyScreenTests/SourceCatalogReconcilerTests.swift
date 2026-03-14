import Foundation
import Testing
@testable import MyScreen

@Test
func missingCatalogEntryMarksSelectionOffline() {
        let selected = [
            MonitorSource.window(
                windowID: 88,
                title: "Notes",
                bundleIdentifier: "com.apple.Notes",
                processID: 900,
                isAvailable: true,
                lastSeenAt: Date()
            ),
        ]

        let reconciled = SourceCatalogReconciler.reconcileSelections(selected, with: .empty)

        #expect(reconciled.count == 1)
        #expect(reconciled[0].id == selected[0].id)
        #expect(reconciled[0].title == selected[0].title)
        #expect(reconciled[0].isAvailable == false)
}
