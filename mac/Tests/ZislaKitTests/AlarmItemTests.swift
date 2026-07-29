import Foundation
import Testing

@testable import ZislaKit

@MainActor
struct AlarmItemTests {
    @Test
    func initClampsOutOfRangeTimeAndWeekdays() {
        let alarm = AlarmItem(hour: 30, minute: -5, weekdays: [0, 3, 8])
        #expect(alarm.hour == 23)
        #expect(alarm.minute == 0)
        #expect(alarm.weekdays == [3])
    }

    @Test
    func timeTextPadsToTwoDigits() {
        #expect(AlarmItem(hour: 7, minute: 5).timeText == "07:05")
        #expect(AlarmItem(hour: 23, minute: 59).timeText == "23:59")
    }

    @Test
    func repeatTextNamesCommonWeekdaySets() {
        #expect(AlarmItem(hour: 8, minute: 0, weekdays: []).repeatText == "仅一次")
        #expect(AlarmItem(hour: 8, minute: 0, weekdays: Set(1...7)).repeatText == "每天")
        #expect(AlarmItem(hour: 8, minute: 0, weekdays: Set(2...6)).repeatText == "工作日")
        #expect(AlarmItem(hour: 8, minute: 0, weekdays: [1, 7]).repeatText == "周末")
        #expect(AlarmItem(hour: 8, minute: 0, weekdays: [2, 4]).repeatText == "周一 周三")
    }

    @Test
    func oneShotAlarmRollsToTomorrowOnceTimeHasPassed() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let now = try #require(calendar.date(
            from: DateComponents(year: 2026, month: 7, day: 26, hour: 12, minute: 0)
        ))

        let later = try #require(
            AlarmItem(hour: 18, minute: 30).nextTriggerDate(after: now, calendar: calendar)
        )
        #expect(calendar.dateComponents([.day, .hour, .minute], from: later)
            == DateComponents(day: 26, hour: 18, minute: 30))

        let passed = try #require(
            AlarmItem(hour: 9, minute: 15).nextTriggerDate(after: now, calendar: calendar)
        )
        #expect(calendar.dateComponents([.day, .hour, .minute], from: passed)
            == DateComponents(day: 27, hour: 9, minute: 15))
    }

    @Test
    func repeatingAlarmPicksTheNearestSelectedWeekday() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        // 2026-07-26 is a Sunday (weekday == 1).
        let now = try #require(calendar.date(
            from: DateComponents(year: 2026, month: 7, day: 26, hour: 12, minute: 0)
        ))
        #expect(calendar.component(.weekday, from: now) == 1)

        let wednesday = try #require(
            AlarmItem(hour: 7, minute: 0, weekdays: [4]).nextTriggerDate(after: now, calendar: calendar)
        )
        #expect(calendar.dateComponents([.day, .hour, .minute], from: wednesday)
            == DateComponents(day: 29, hour: 7, minute: 0))

        // Today is still selected, but 07:00 has passed, so advance to the next selected day (Monday).
        let nextSunday = try #require(
            AlarmItem(hour: 7, minute: 0, weekdays: [1, 2]).nextTriggerDate(after: now, calendar: calendar)
        )
        #expect(calendar.dateComponents([.day, .hour, .minute], from: nextSunday)
            == DateComponents(day: 27, hour: 7, minute: 0))
    }

    @Test
    func notificationIdentifiersCoverEachSelectedWeekday() {
        let oneShot = AlarmItem(hour: 8, minute: 0)
        #expect(AlarmService.notificationIdentifiers(for: oneShot)
            == ["zisla.alarm.\(oneShot.id.uuidString)"])

        let repeating = AlarmItem(hour: 8, minute: 0, weekdays: [5, 2])
        #expect(AlarmService.notificationIdentifiers(for: repeating) == [
            "zisla.alarm.\(repeating.id.uuidString).2",
            "zisla.alarm.\(repeating.id.uuidString).5",
        ])
    }
}
