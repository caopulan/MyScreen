import Testing
@testable import MyScreen

@Test
func displayAndWindowSourcesUseStableIDs() {
        let display = MonitorSource.display(displayID: 42, title: "Display")
        let window = MonitorSource.window(windowID: 84, title: "Window")

        #expect(display.id == "display:42")
        #expect(window.id == "window:84")
        #expect(display.kind == .display)
        #expect(window.kind == .window)
}
