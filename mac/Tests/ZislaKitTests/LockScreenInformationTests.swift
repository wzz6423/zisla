import Foundation
import IOKit.ps
import Testing
@testable import ZislaKit

struct LockScreenInformationTests {
    @Test
    func batterySnapshotReadsInternalBatteryState() {
        let description: [String: Any] = [
            kIOPSTypeKey as String: kIOPSInternalBatteryType,
            kIOPSCurrentCapacityKey as String: NSNumber(value: 76),
            kIOPSMaxCapacityKey as String: NSNumber(value: 100),
            kIOPSIsChargingKey as String: true,
            kIOPSIsChargedKey as String: false,
            kIOPSPowerSourceStateKey as String: kIOPSACPowerValue,
            kIOPSTimeToFullChargeKey as String: NSNumber(value: 42),
        ]

        let snapshot = BatteryMonitor.snapshot(from: description)

        #expect(snapshot?.percentInt == 76)
        #expect(snapshot?.isCharging == true)
        #expect(snapshot?.isPluggedIn == true)
        #expect(snapshot?.timeRemainingMinutes == 42)
    }

    @Test
    func lunarCalendarFormatsChineseNewYear() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(from: DateComponents(year: 2024, month: 2, day: 10, hour: 12))!

        let lunar = LunarCalendar.components(from: date, timeZone: calendar.timeZone)

        #expect(lunar?.monthDayText == "正月初一")
    }

    @Test
    func lunarCalendarYearMonthDayTextOmitsZodiac() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(from: DateComponents(year: 2026, month: 7, day: 25, hour: 12))!

        let lunar = LunarCalendar.components(from: date, timeZone: calendar.timeZone)

        #expect(lunar?.yearMonthDayText == "丙午年六月十二")
    }

    @Test
    func dailyQuoteIsStableWithinOneDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(from: DateComponents(year: 2026, month: 7, day: 23, hour: 12))!

        let first = DailyQuote.quote(for: date, calendar: calendar)
        let second = DailyQuote.quote(for: date, calendar: calendar)

        #expect(first == second)
        #expect(DailyQuote.library.contains(first))
    }
}
