import Foundation
import Testing

@testable import ZislaCore

struct UserCareIntervalTests {
    @Test(arguments: [
        (0.0, 1.0), (-1, 1), (0.5, 1), (1.9, 1), (1, 1), (5, 5), (30, 30), (2_700, 2_700),
        (360_000, 359_999), (Double(Int.max), 359_999), (Double.greatestFiniteMagnitude, 359_999),
        (Double.infinity, 359_999), (-Double.infinity, 1), (Double.nan, 1),
    ] as [(Double, Double)])
    func settingsAndScheduleNormalizeToTheSameWholeSecondRange(raw: Double, expected: Double) {
        #expect(UserCareInterval.normalized(raw) == expected)
        #expect(FeatureSettings(userCareReminderInterval: raw).userCareReminderInterval == expected)
        var settings = FeatureSettings.default
        settings.userCareReminderInterval = raw
        #expect(settings.userCareReminderInterval == expected)
        var schedule = UserCareSchedule(interval: raw)
        #expect(schedule.interval == expected)
        schedule.setInterval(raw)
        #expect(schedule.interval == expected)
    }

    @Test
    func durationComponentsRespectTheirBoundsWithoutOverflow() {
        #expect(UserCareInterval.seconds(hours: 0, minutes: 0, seconds: 1) == 1)
        #expect(UserCareInterval.seconds(hours: 1, minutes: 2, seconds: 3) == 3_723)
        #expect(UserCareInterval.seconds(hours: 99, minutes: 59, seconds: 59) == 359_999)
        #expect(UserCareInterval.seconds(hours: 0, minutes: 0, seconds: 0) == nil)
        for value in [-1, Int.min, Int.max] {
            #expect(UserCareInterval.seconds(hours: value, minutes: 0, seconds: 1) == nil)
            #expect(UserCareInterval.seconds(hours: 0, minutes: value, seconds: 1) == nil)
            #expect(UserCareInterval.seconds(hours: 0, minutes: 0, seconds: value) == nil)
        }
        #expect(UserCareInterval.seconds(hours: 100, minutes: 0, seconds: 0) == nil)
        #expect(UserCareInterval.seconds(hours: 0, minutes: 60, seconds: 0) == nil)
        #expect(UserCareInterval.seconds(hours: 0, minutes: 0, seconds: 60) == nil)
    }

    @Test
    func schedulingDeadlineTracksResetAndDeliveryWithoutAnotherFullPeriod() {
        var schedule = UserCareSchedule(interval: 5)
        #expect(schedule.timeUntilReminder(at: 100) == 5)
        _ = schedule.update(at: 100, isActive: true, idleSeconds: 0, localHour: 10)
        #expect(abs(schedule.timeUntilReminder(at: 104.995) - 0.005) < 0.000_001)
        #expect(schedule.update(at: 105, isActive: true, idleSeconds: 0, localHour: 10) == .rest)
        #expect(schedule.timeUntilReminder(at: 105) == 5)
        schedule.reset()
        #expect(schedule.timeUntilReminder(at: 500) == 5)
    }

    @Test(arguments: [0.005, 8_191.995, 1_048_575.005])
    func fractionalUptimeFiresAtTheSameAbsoluteDeadlineUsedForScheduling(start: TimeInterval) {
        var schedule = UserCareSchedule(interval: 1)
        _ = schedule.update(at: start, isActive: true, idleSeconds: 0, localHour: 10)
        let deadline = start + 1
        #expect(schedule.timeUntilReminder(at: deadline) == 0)
        #expect(schedule.update(at: deadline, isActive: true, idleSeconds: 0, localHour: 10) == .rest)
    }
}
