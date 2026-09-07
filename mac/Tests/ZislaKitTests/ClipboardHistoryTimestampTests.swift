import Foundation
import Testing

@testable import ZislaKit

struct ClipboardHistoryTimestampTests {
    private static let shanghai: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }()

    @Test
    func todayShowsOnlyTime() {
        let now = Self.date(2026, 9, 6, 23, 5, 1)

        #expect(Self.text(copiedAt: Self.date(2026, 9, 6, 10, 59, 23), now: now) == "10:59:23")
        #expect(Self.text(copiedAt: Self.date(2026, 9, 6, 0, 0, 0), now: now) == "00:00:00")
    }

    @Test
    func anotherDayInTheSameYearAddsMonthAndDay() {
        let now = Self.date(2026, 9, 6, 0, 30, 0)

        #expect(Self.text(copiedAt: Self.date(2026, 9, 5, 23, 59, 59), now: now) == "09-05 23:59:59")
        #expect(Self.text(copiedAt: Self.date(2026, 1, 2, 8, 7, 6), now: now) == "01-02 08:07:06")
    }

    @Test
    func anotherYearAddsYear() {
        let now = Self.date(2026, 1, 1, 0, 0, 30)

        #expect(
            Self.text(copiedAt: Self.date(2025, 12, 31, 23, 59, 59), now: now)
                == "2025-12-31 23:59:59"
        )
    }

    @Test
    func calendarTimeZoneControlsTheDayBoundaryAndClock() {
        let copiedAt = Self.date(2026, 9, 6, 0, 15, 0)
        let now = Self.date(2026, 9, 6, 20, 0, 0)
        var losAngeles = Calendar(identifier: .gregorian)
        losAngeles.timeZone = TimeZone(identifier: "America/Los_Angeles")!

        #expect(Self.text(copiedAt: copiedAt, now: now) == "00:15:00")
        #expect(Self.text(copiedAt: copiedAt, now: now, calendar: losAngeles) == "09-05 09:15:00")
    }

    private static func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int,
        _ second: Int
    ) -> Date {
        shanghai.date(from: DateComponents(
            timeZone: shanghai.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute,
            second: second
        ))!
    }

    private static func text(copiedAt: Date, now: Date, calendar: Calendar = shanghai) -> String {
        ClipboardHistoryItem(content: .text("剪贴板内容"), lastCopiedAt: copiedAt)
            .lastCopiedAtText(now: now, calendar: calendar)
    }
}
