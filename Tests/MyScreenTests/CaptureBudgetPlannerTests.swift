import Testing
@testable import MyScreen

@Test
func highDensityPlanMovesOverflowSourcesToPolling() {
        let sources = (1 ... 14).map { index in
            MonitorSource.window(windowID: UInt32(index), title: "Window \(index)")
        }

        let plan = CaptureBudgetPlanner.plan(for: sources, focusSourceID: sources.last?.id)

        #expect(plan.previewMaxDimension == 480)
        #expect(plan.deliveryModes[sources.last!.id] == .live(framesPerSecond: 8))

        let pollingCount = plan.deliveryModes.values.filter {
            if case .polling = $0 {
                true
            } else {
                false
            }
        }.count

        #expect(pollingCount == 2)
}

@Test
func smallWallKeepsAllSourcesLive() {
        let sources = (1 ... 3).map { index in
            MonitorSource.display(displayID: UInt32(index), title: "Display \(index)")
        }

        let plan = CaptureBudgetPlanner.plan(for: sources, focusSourceID: sources.first?.id)

        #expect(plan.previewMaxDimension == 640)
        #expect(plan.deliveryModes[sources[0].id] == .live(framesPerSecond: 15))
        #expect(plan.deliveryModes[sources[1].id] == .live(framesPerSecond: 12))
        #expect(plan.deliveryModes[sources[2].id] == .live(framesPerSecond: 12))
}
