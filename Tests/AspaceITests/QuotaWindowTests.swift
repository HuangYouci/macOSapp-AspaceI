import Foundation
import Testing
@testable import AspaceI

struct QuotaWindowTests {
    @Test
    func clampsPercentageIntoValidRange() {
        let belowRange = QuotaWindow(
            id: "below",
            title: "Below",
            remainingPercentage: -1,
            resetsAt: nil
        )
        let aboveRange = QuotaWindow(
            id: "above",
            title: "Above",
            remainingPercentage: 101,
            resetsAt: nil
        )

        #expect(belowRange.remainingPercentage == 0)
        #expect(aboveRange.remainingPercentage == 100)
    }
}
