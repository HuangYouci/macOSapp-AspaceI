import Foundation

/// 額度時窗的重置倒數：最多兩個時間單位，第二個單位為零時省略。
enum QuotaCountdown {
    struct Units {
        let day: String
        let hour: String
        let minute: String
        let second: String
        let separator: String

        static let localized = Units(
            day: String(localized: "CountdownDay", defaultValue: "天", bundle: .module),
            hour: String(localized: "CountdownHour", defaultValue: "時", bundle: .module),
            minute: String(localized: "CountdownMinute", defaultValue: "分", bundle: .module),
            second: String(localized: "CountdownSecond", defaultValue: "秒", bundle: .module),
            separator: String(localized: "CountdownSeparator", defaultValue: "", bundle: .module)
        )
    }

    static func text(until resetsAt: Date, now: Date = .now, units: Units = .localized) -> String? {
        let remaining = Int(resetsAt.timeIntervalSince(now).rounded(.down))
        guard remaining > 0 else { return nil }
        let day = remaining / 86_400
        let hour = remaining % 86_400 / 3_600
        let minute = remaining % 3_600 / 60
        let second = remaining % 60
        if day > 0 { return join(day, units.day, hour, units.hour, units) }
        if hour > 0 { return join(hour, units.hour, minute, units.minute, units) }
        if minute > 0 { return join(minute, units.minute, second, units.second, units) }
        return "\(second)\(units.second)"
    }

    private static func join(_ value: Int, _ unit: String, _ trailingValue: Int, _ trailingUnit: String, _ units: Units) -> String {
        guard trailingValue > 0 else { return "\(value)\(unit)" }
        return "\(value)\(unit)\(units.separator)\(trailingValue)\(trailingUnit)"
    }
}
