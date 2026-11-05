import Foundation
import Testing

@testable import ZislaCore

struct UserCareScheduleTests {
    @Test(arguments: [1.0, 5, 30, 2_700])
    func configuredIntervalsHonorTheirExactSecondBoundary(interval: TimeInterval) {
        var schedule = UserCareSchedule(interval: interval)
        #expect(schedule.update(at: 100, isActive: true, idleSeconds: 0, localHour: 10) == nil)
        #expect(schedule.update(at: 100 + interval - 0.001, isActive: true, idleSeconds: 0, localHour: 10) == nil)
        #expect(schedule.update(at: 100 + interval, isActive: true, idleSeconds: 0, localHour: 10) == .rest)
        #expect(schedule.update(at: 100 + interval * 2, isActive: true, idleSeconds: 0, localHour: 10) == .water)
    }

    @Test
    func changingTheIntervalResetsWorkButReapplyingTheSameIntervalDoesNot() {
        var schedule = UserCareSchedule(interval: 5)
        _ = schedule.update(at: 0, isActive: true, idleSeconds: 0, localHour: 10)
        #expect(schedule.update(at: 4, isActive: true, idleSeconds: 0, localHour: 10) == nil)
        schedule.setInterval(10)
        #expect(!schedule.isWorking)
        #expect(schedule.update(at: 4, isActive: true, idleSeconds: 0, localHour: 10) == nil)
        schedule.setInterval(10)
        #expect(schedule.isWorking)
        #expect(schedule.update(at: 13.999, isActive: true, idleSeconds: 0, localHour: 10) == nil)
        #expect(schedule.update(at: 14, isActive: true, idleSeconds: 0, localHour: 10) == .rest)
    }

    @Test
    func requiresFortyFiveMinutesOfContinuousWork() {
        var schedule = UserCareSchedule()
        #expect(schedule.update(at: 100, isActive: true, idleSeconds: 0, localHour: 10) == nil)
        #expect(schedule.update(at: 2_799.999, isActive: true, idleSeconds: 0, localHour: 10) == nil)
        #expect(schedule.update(at: 2_800, isActive: true, idleSeconds: 0, localHour: 10) == .rest)
        #expect(schedule.update(at: 5_499.999, isActive: true, idleSeconds: 0, localHour: 10) == nil)
        #expect(schedule.update(at: 5_500, isActive: true, idleSeconds: 0, localHour: 10) == .water)
    }

    @Test
    func naturalBreakBeginsAtFiveMinutesAndDoesNotCatchUpOnReturn() {
        var schedule = UserCareSchedule()
        _ = schedule.update(at: 0, isActive: true, idleSeconds: 0, localHour: 10)
        #expect(schedule.update(at: 2_699, isActive: true, idleSeconds: 299.999, localHour: 10) == nil)
        #expect(schedule.update(at: 2_700, isActive: true, idleSeconds: 300, localHour: 10) == nil)
        #expect(schedule.update(at: 30_000, isActive: true, idleSeconds: 0, localHour: 10) == nil)
        #expect(schedule.update(at: 32_699.999, isActive: true, idleSeconds: 0, localHour: 10) == nil)
        #expect(schedule.update(at: 32_700, isActive: true, idleSeconds: 0, localHour: 10) == .rest)
    }

    @Test
    func inactivityAndExplicitResetDiscardPartialIntervals() {
        var schedule = UserCareSchedule()
        _ = schedule.update(at: 0, isActive: true, idleSeconds: 0, localHour: 10)
        _ = schedule.update(at: 2_699, isActive: false, idleSeconds: 0, localHour: 10)
        #expect(schedule.update(at: 10_000, isActive: true, idleSeconds: 0, localHour: 10) == nil)
        schedule.reset()
        #expect(schedule.update(at: 20_000, isActive: true, idleSeconds: 0, localHour: 10) == nil)
        #expect(schedule.update(at: 22_699, isActive: true, idleSeconds: 0, localHour: 10) == nil)
        #expect(schedule.update(at: 22_700, isActive: true, idleSeconds: 0, localHour: 10) == .rest)
    }

    @Test(arguments: [nil, Double.nan, Double.infinity, -Double.infinity, -1] as [Double?])
    func unavailableOrInvalidIdleReadingsResetWork(idle: Double?) {
        var schedule = UserCareSchedule()
        _ = schedule.update(at: 0, isActive: true, idleSeconds: 0, localHour: 10)
        #expect(schedule.update(at: 2_700, isActive: true, idleSeconds: idle, localHour: 10) == nil)
        #expect(schedule.update(at: 5_400, isActive: true, idleSeconds: 0, localHour: 10) == nil)
        #expect(schedule.update(at: 8_100, isActive: true, idleSeconds: 0, localHour: 10) == .rest)
    }

    @Test
    func delayedTicksIssueOnlyOneReminderAndRestartTheThrottleFromNow() {
        var schedule = UserCareSchedule()
        _ = schedule.update(at: 0, isActive: true, idleSeconds: 0, localHour: 10)
        #expect(schedule.update(at: 27_000, isActive: true, idleSeconds: 0, localHour: 10) == .rest)
        for _ in 0..<10 {
            #expect(schedule.update(at: 27_000, isActive: true, idleSeconds: 0, localHour: 10) == nil)
        }
        #expect(schedule.update(at: 29_699, isActive: true, idleSeconds: 0, localHour: 10) == nil)
        #expect(schedule.update(at: 29_700, isActive: true, idleSeconds: 0, localHour: 10) == .water)
    }

    @Test(arguments: Array(0..<24))
    func selectsLocalMiddayNightAndDaytimeMessages(hour: Int) {
        var schedule = UserCareSchedule()
        _ = schedule.update(at: 0, isActive: true, idleSeconds: 0, localHour: hour)
        let first = schedule.update(at: 2_700, isActive: true, idleSeconds: 0, localHour: hour)
        let second = schedule.update(at: 5_400, isActive: true, idleSeconds: 0, localHour: hour)
        if (12..<14).contains(hour) {
            #expect(first == .lunch)
            #expect(second == .nap)
        } else if hour >= 23 || hour < 6 {
            #expect(first == .bedtime)
            #expect(second == .tomorrow)
        } else {
            #expect(first == .rest)
            #expect(second == .water)
        }
        #expect(first != second)
    }

    @Test
    func rotatesAllGeneralRemindersAcrossNaturalBreaks() {
        var schedule = UserCareSchedule()
        var reminders: [UserCareReminder] = []
        for index in 0..<14 {
            let start = Double(index * 10_000)
            _ = schedule.update(at: start, isActive: true, idleSeconds: 0, localHour: 10)
            if let reminder = schedule.update(at: start + 2_700, isActive: true, idleSeconds: 0, localHour: 10) {
                reminders.append(reminder)
            }
            schedule.reset()
        }
        let cycle: [UserCareReminder] = [.rest, .water, .walk, .eyes, .posture, .stretch, .breathe]
        #expect(reminders == cycle + cycle)
    }

    @Test
    func periodChangesUseTheHourAtDeliveryTime() {
        var schedule = UserCareSchedule()
        _ = schedule.update(at: 0, isActive: true, idleSeconds: 0, localHour: 11)
        #expect(schedule.update(at: 2_700, isActive: true, idleSeconds: 0, localHour: 12) == .lunch)
        #expect(schedule.update(at: 5_400, isActive: true, idleSeconds: 0, localHour: 23) == .tomorrow)
    }
}
