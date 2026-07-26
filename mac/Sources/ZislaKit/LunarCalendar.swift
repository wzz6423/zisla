import Foundation

/// Lunar calendar conversion based on Foundation's Chinese Calendar; pure logic with an injectable calendar for unit testing.
public enum LunarCalendar {
    private static let heavenlyStems = ["甲", "乙", "丙", "丁", "戊", "己", "庚", "辛", "壬", "癸"]
    private static let earthlyBranches = ["子", "丑", "寅", "卯", "辰", "巳", "午", "未", "申", "酉", "戌", "亥"]
    private static let zodiacs = ["鼠", "牛", "虎", "兔", "龙", "蛇", "马", "羊", "猴", "鸡", "狗", "猪"]
    private static let monthNames = [
        "正月", "二月", "三月", "四月", "五月", "六月",
        "七月", "八月", "九月", "十月", "冬月", "腊月",
    ]
    private static let dayTens = ["初", "十", "廿", "三"]
    private static let dayDigits = ["十", "一", "二", "三", "四", "五", "六", "七", "八", "九"]

    /// Components of a lunar date. `isLeapMonth` indicates a leap month.
    public struct Components: Equatable, Sendable {
        public var yearGanZhi: String
        public var zodiac: String
        public var month: String
        public var day: String
        public var isLeapMonth: Bool

        public init(
            yearGanZhi: String,
            zodiac: String,
            month: String,
            day: String,
            isLeapMonth: Bool
        ) {
            self.yearGanZhi = yearGanZhi
            self.zodiac = zodiac
            self.month = month
            self.day = day
            self.isLeapMonth = isLeapMonth
        }

        /// Example: a full lunar date containing the sexagenary year, zodiac, month, and day.
        public var fullText: String {
            "\(yearGanZhi)\(zodiac)年 \(monthText)\(day)"
        }

        /// Example: a lunar month and day; leap months carry a dedicated prefix.
        public var monthDayText: String {
            "\(monthText)\(day)"
        }

        /// Example: a compact lunar date for the space-constrained lock screen.
        public var yearMonthDayText: String {
            "\(yearGanZhi)年\(monthText)\(day)"
        }

        private var monthText: String {
            isLeapMonth ? "闰\(month)" : month
        }
    }

    public static func components(
        from date: Date,
        timeZone: TimeZone = .current
    ) -> Components? {
        var calendar = Calendar(identifier: .chinese)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day, .isLeapMonth], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day,
              (1...12).contains(month), (1...30).contains(day) else { return nil }

        // Chinese calendar year is a ganzhi sequence number in 1...60.
        let stemIndex = (year - 1) % 10
        let branchIndex = (year - 1) % 12
        return Components(
            yearGanZhi: heavenlyStems[stemIndex] + earthlyBranches[branchIndex],
            zodiac: zodiacs[branchIndex],
            month: monthNames[month - 1],
            day: dayText(day),
            isLeapMonth: parts.isLeapMonth ?? false
        )
    }

    /// Returns the Chinese written form for a lunar day.
    static func dayText(_ day: Int) -> String {
        switch day {
        case 10: return "初十"
        case 20: return "二十"
        case 30: return "三十"
        default:
            let tens = day / 10
            let digit = day % 10
            return dayTens[tens] + dayDigits[digit]
        }
    }
}
