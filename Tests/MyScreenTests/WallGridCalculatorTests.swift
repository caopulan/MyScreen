import CoreGraphics
import Testing
@testable import MyScreen

@Test
func wallGridPrefersBalancedTwoByTwoForFourSources() {
        let grid = WallGridCalculator.calculate(for: 4, in: CGSize(width: 1200, height: 800))

        #expect(grid == WallGrid(columns: 2, rows: 2))
}

@Test
func wallGridPrefersThreeByThreeForNineSources() {
        let grid = WallGridCalculator.calculate(for: 9, in: CGSize(width: 1600, height: 900))

        #expect(grid == WallGrid(columns: 3, rows: 3))
}
