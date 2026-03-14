import Testing
@testable import MyScreen

@Test
func reordererMovesSourceForwardToHoveredTargetSlot() {
    let sources = [
        MonitorSource.display(displayID: 1, title: "Display 1"),
        MonitorSource.window(windowID: 2, title: "Safari"),
        MonitorSource.window(windowID: 3, title: "Xcode"),
        MonitorSource.window(windowID: 4, title: "Terminal"),
    ]

    let reordered = SelectedSourceReorderer.reordered(
        sources: sources,
        moving: "window:2",
        to: "window:4"
    )

    #expect(reordered.map(\.id) == ["display:1", "window:3", "window:4", "window:2"])
}

@Test
func reordererMovesSourceBackwardToHoveredTargetSlot() {
    let sources = [
        MonitorSource.display(displayID: 1, title: "Display 1"),
        MonitorSource.window(windowID: 2, title: "Safari"),
        MonitorSource.window(windowID: 3, title: "Xcode"),
        MonitorSource.window(windowID: 4, title: "Terminal"),
    ]

    let reordered = SelectedSourceReorderer.reordered(
        sources: sources,
        moving: "window:4",
        to: "window:2"
    )

    #expect(reordered.map(\.id) == ["display:1", "window:4", "window:2", "window:3"])
}

@Test
func reordererKeepsOrderWhenSourceOrTargetIsMissing() {
    let sources = [
        MonitorSource.display(displayID: 1, title: "Display 1"),
        MonitorSource.window(windowID: 2, title: "Safari"),
    ]

    let reordered = SelectedSourceReorderer.reordered(
        sources: sources,
        moving: "window:999",
        to: "window:2"
    )

    #expect(reordered.map(\.id) == sources.map(\.id))
}
