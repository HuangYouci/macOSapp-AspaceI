import Foundation
import Testing
@testable import AspaceI

struct QuotaCountdownTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    /// 語系不影響組法，測試固定用繁中單位。
    private let units = QuotaCountdown.Units(day: "天", hour: "時", minute: "分", second: "秒", separator: "")

    @Test("倒數最多兩個時間單位")
    func formatsTwoUnits() {
        #expect(countdown(seconds: 5 * 86_400 + 3 * 3_600 + 42 * 60) == "5天3時")
        #expect(countdown(seconds: 3_600 + 3 * 60 + 9) == "1時3分")
        #expect(countdown(seconds: 3 * 60 + 5) == "3分5秒")
        #expect(countdown(seconds: 5) == "5秒")
    }

    @Test("第二個單位為零時只顯示一個")
    func omitsZeroTrailingUnit() {
        #expect(countdown(seconds: 2 * 86_400) == "2天")
        #expect(countdown(seconds: 3_600) == "1時")
        #expect(countdown(seconds: 60) == "1分")
    }

    @Test("已經重置就不顯示倒數")
    func hidesAfterReset() {
        #expect(countdown(seconds: 0) == nil)
        #expect(countdown(seconds: -30) == nil)
    }

    private func countdown(seconds: Int) -> String? {
        QuotaCountdown.text(until: now.addingTimeInterval(TimeInterval(seconds)), now: now, units: units)
    }
}
