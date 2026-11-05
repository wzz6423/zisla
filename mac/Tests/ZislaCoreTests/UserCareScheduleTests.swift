import Foundation
import Testing

@testable import ZislaCore

struct UserCareScheduleTests {
    @Test(arguments: [1.0, 5, 30, 2_700])
    func configuredIntervalsHonorTheirExactSecondBoundary(interval: TimeInterval) {
        var schedule = UserCareSchedule(interval: interval)
        #expect(schedule.update(at: 100, isActive: true, idleSeconds: 0, localHour: 10, chooseIndex: { $0.lowerBound }) == nil)
        #expect(schedule.update(at: 100 + interval - 0.001, isActive: true, idleSeconds: 0, localHour: 10, chooseIndex: { $0.lowerBound }) == nil)
        #expect(schedule.update(at: 100 + interval, isActive: true, idleSeconds: 0, localHour: 10, chooseIndex: { $0.lowerBound }) == .rest)
        #expect(schedule.update(at: 100 + interval * 2, isActive: true, idleSeconds: 0, localHour: 10, chooseIndex: { $0.lowerBound }) == .water)
    }

    @Test
    func changingTheIntervalResetsWorkButReapplyingTheSameIntervalDoesNot() {
        var schedule = UserCareSchedule(interval: 5)
        _ = schedule.update(at: 0, isActive: true, idleSeconds: 0, localHour: 10, chooseIndex: { $0.lowerBound })
        #expect(schedule.update(at: 4, isActive: true, idleSeconds: 0, localHour: 10, chooseIndex: { $0.lowerBound }) == nil)
        schedule.setInterval(10)
        #expect(!schedule.isWorking)
        #expect(schedule.update(at: 4, isActive: true, idleSeconds: 0, localHour: 10, chooseIndex: { $0.lowerBound }) == nil)
        schedule.setInterval(10)
        #expect(schedule.isWorking)
        #expect(schedule.update(at: 13.999, isActive: true, idleSeconds: 0, localHour: 10, chooseIndex: { $0.lowerBound }) == nil)
        #expect(schedule.update(at: 14, isActive: true, idleSeconds: 0, localHour: 10, chooseIndex: { $0.lowerBound }) == .rest)
    }

    @Test
    func requiresFortyFiveMinutesOfContinuousWork() {
        var schedule = UserCareSchedule()
        #expect(schedule.update(at: 100, isActive: true, idleSeconds: 0, localHour: 10, chooseIndex: { $0.lowerBound }) == nil)
        #expect(schedule.update(at: 2_799.999, isActive: true, idleSeconds: 0, localHour: 10, chooseIndex: { $0.lowerBound }) == nil)
        #expect(schedule.update(at: 2_800, isActive: true, idleSeconds: 0, localHour: 10, chooseIndex: { $0.lowerBound }) == .rest)
        #expect(schedule.update(at: 5_499.999, isActive: true, idleSeconds: 0, localHour: 10, chooseIndex: { $0.lowerBound }) == nil)
        #expect(schedule.update(at: 5_500, isActive: true, idleSeconds: 0, localHour: 10, chooseIndex: { $0.lowerBound }) == .water)
    }

    @Test
    func naturalBreakBeginsAtFiveMinutesAndDoesNotCatchUpOnReturn() {
        var schedule = UserCareSchedule()
        _ = schedule.update(at: 0, isActive: true, idleSeconds: 0, localHour: 10, chooseIndex: { $0.lowerBound })
        #expect(schedule.update(at: 2_699, isActive: true, idleSeconds: 299.999, localHour: 10, chooseIndex: { $0.lowerBound }) == nil)
        #expect(schedule.update(at: 2_700, isActive: true, idleSeconds: 300, localHour: 10, chooseIndex: { $0.lowerBound }) == nil)
        #expect(schedule.update(at: 30_000, isActive: true, idleSeconds: 0, localHour: 10, chooseIndex: { $0.lowerBound }) == nil)
        #expect(schedule.update(at: 32_699.999, isActive: true, idleSeconds: 0, localHour: 10, chooseIndex: { $0.lowerBound }) == nil)
        #expect(schedule.update(at: 32_700, isActive: true, idleSeconds: 0, localHour: 10, chooseIndex: { $0.lowerBound }) == .rest)
    }

    @Test
    func inactivityAndExplicitResetDiscardPartialIntervals() {
        var schedule = UserCareSchedule()
        _ = schedule.update(at: 0, isActive: true, idleSeconds: 0, localHour: 10, chooseIndex: { $0.lowerBound })
        _ = schedule.update(at: 2_699, isActive: false, idleSeconds: 0, localHour: 10, chooseIndex: { $0.lowerBound })
        #expect(schedule.update(at: 10_000, isActive: true, idleSeconds: 0, localHour: 10, chooseIndex: { $0.lowerBound }) == nil)
        schedule.reset()
        #expect(schedule.update(at: 20_000, isActive: true, idleSeconds: 0, localHour: 10, chooseIndex: { $0.lowerBound }) == nil)
        #expect(schedule.update(at: 22_699, isActive: true, idleSeconds: 0, localHour: 10, chooseIndex: { $0.lowerBound }) == nil)
        #expect(schedule.update(at: 22_700, isActive: true, idleSeconds: 0, localHour: 10, chooseIndex: { $0.lowerBound }) == .rest)
    }

    @Test(arguments: [nil, Double.nan, Double.infinity, -Double.infinity, -1] as [Double?])
    func unavailableOrInvalidIdleReadingsResetWork(idle: Double?) {
        var schedule = UserCareSchedule()
        _ = schedule.update(at: 0, isActive: true, idleSeconds: 0, localHour: 10, chooseIndex: { $0.lowerBound })
        #expect(schedule.update(at: 2_700, isActive: true, idleSeconds: idle, localHour: 10, chooseIndex: { $0.lowerBound }) == nil)
        #expect(schedule.update(at: 5_400, isActive: true, idleSeconds: 0, localHour: 10, chooseIndex: { $0.lowerBound }) == nil)
        #expect(schedule.update(at: 8_100, isActive: true, idleSeconds: 0, localHour: 10, chooseIndex: { $0.lowerBound }) == .rest)
    }

    @Test
    func delayedTicksIssueOnlyOneReminderAndRestartTheThrottleFromNow() {
        var schedule = UserCareSchedule()
        _ = schedule.update(at: 0, isActive: true, idleSeconds: 0, localHour: 10, chooseIndex: { $0.lowerBound })
        #expect(schedule.update(at: 27_000, isActive: true, idleSeconds: 0, localHour: 10, chooseIndex: { $0.lowerBound }) == .rest)
        for _ in 0..<10 {
            #expect(schedule.update(at: 27_000, isActive: true, idleSeconds: 0, localHour: 10, chooseIndex: { $0.lowerBound }) == nil)
        }
        #expect(schedule.update(at: 29_699, isActive: true, idleSeconds: 0, localHour: 10, chooseIndex: { $0.lowerBound }) == nil)
        #expect(schedule.update(at: 29_700, isActive: true, idleSeconds: 0, localHour: 10, chooseIndex: { $0.lowerBound }) == .water)
    }

    @Test(arguments: Array(0..<24))
    func selectsLocalMiddayNightAndDaytimeMessages(hour: Int) {
        var schedule = UserCareSchedule()
        _ = schedule.update(at: 0, isActive: true, idleSeconds: 0, localHour: hour, chooseIndex: { $0.lowerBound })
        let first = schedule.update(at: 2_700, isActive: true, idleSeconds: 0, localHour: hour, chooseIndex: { $0.lowerBound })
        let second = schedule.update(at: 5_400, isActive: true, idleSeconds: 0, localHour: hour, chooseIndex: { $0.upperBound - 1 })
        #expect(first == .rest, "General health reminders remain available at every local hour")
        if (12..<14).contains(hour) {
            #expect(second == .nap)
        } else if hour >= 23 || hour < 6 {
            #expect(second == .tomorrow)
        } else {
            #expect(second == .eyeDrops)
        }
        #expect(first != second)
    }

    @Test(arguments: Array(0..<24))
    func everyAllowedIndexSelectsItsHealthOrLocalTimeTopicAndExcludesEventMessages(hour: Int) {
        var expected: [UserCareReminder] = [.rest, .water, .walk, .eyes, .posture, .stretch, .breathe, .blink, .eyeDrops]
        if (12..<14).contains(hour) {
            expected += [.lunch, .nap]
        } else if hour >= 23 || hour < 6 {
            expected += [.bedtime, .tomorrow]
        }
        for index in expected.indices {
            var schedule = UserCareSchedule(interval: 1)
            _ = schedule.update(at: 0, isActive: true, idleSeconds: 0, localHour: hour)
            let selected = schedule.update(at: 1, isActive: true, idleSeconds: 0, localHour: hour) { range in
                #expect(range == expected.indices)
                return index
            }
            #expect(selected == expected[index])
        }
    }

    @Test(arguments: [false, true])
    func repeatedExtremeChoicesNeverRepeatThePreviousTopic(chooseLast: Bool) {
        var schedule = UserCareSchedule(interval: 1)
        _ = schedule.update(at: 0, isActive: true, idleSeconds: 0, localHour: 10)
        var previous: UserCareReminder?
        for tick in 1...100 {
            let reminder = schedule.update(at: Double(tick), isActive: true, idleSeconds: 0, localHour: 10) { range in
                #expect(range.count == (previous == nil ? 9 : 8))
                return chooseLast ? range.upperBound - 1 : range.lowerBound
            }
            #expect(reminder != nil)
            #expect(reminder != previous)
            previous = reminder
        }
    }

    @Test(arguments: ["reset", "idle", "inactive", "interval"])
    func resettingWorkPreservesThePreviousTopicForAdjacentDeduplication(reason: String) {
        var schedule = UserCareSchedule(interval: 1)
        _ = schedule.update(at: 0, isActive: true, idleSeconds: 0, localHour: 10)
        #expect(schedule.update(at: 1, isActive: true, idleSeconds: 0, localHour: 10, chooseIndex: { $0.lowerBound }) == .rest)
        switch reason {
        case "idle": _ = schedule.update(at: 2, isActive: true, idleSeconds: 300, localHour: 10)
        case "inactive": _ = schedule.update(at: 2, isActive: false, idleSeconds: 0, localHour: 10)
        case "interval": schedule.setInterval(2)
        default: schedule.reset()
        }
        _ = schedule.update(at: 100, isActive: true, idleSeconds: 0, localHour: 10)
        #expect(schedule.update(at: 100 + schedule.interval, isActive: true, idleSeconds: 0, localHour: 10,
            chooseIndex: { $0.lowerBound }) == .water)
    }

    @Test
    func randomSelectionIsSampledOnlyOncePerActualDeadline() {
        var schedule = UserCareSchedule(interval: 1)
        var samples = 0
        let choose: (Range<Int>) -> Int = { range in
            samples += 1
            return range.lowerBound
        }
        _ = schedule.update(at: 0, isActive: true, idleSeconds: 0, localHour: 10, chooseIndex: choose)
        _ = schedule.update(at: 0.999, isActive: true, idleSeconds: 0, localHour: 10, chooseIndex: choose)
        _ = schedule.update(at: 10, isActive: false, idleSeconds: 0, localHour: 10, chooseIndex: choose)
        _ = schedule.update(at: 20, isActive: true, idleSeconds: 300, localHour: 10, chooseIndex: choose)
        _ = schedule.update(at: 30, isActive: true, idleSeconds: 0, localHour: 10, chooseIndex: choose)
        #expect(samples == 0)
        #expect(schedule.update(at: 31, isActive: true, idleSeconds: 0, localHour: 10, chooseIndex: choose) == .rest)
        for _ in 0..<10 {
            #expect(schedule.update(at: 31, isActive: true, idleSeconds: 0, localHour: 10, chooseIndex: choose) == nil)
        }
        #expect(samples == 1)
        #expect(schedule.update(at: 100, isActive: true, idleSeconds: 0, localHour: 10, chooseIndex: choose) == .water)
        #expect(samples == 2, "A delayed tick must consume one selection instead of catching up")
    }

    @Test
    func periodChangesUseTheHourAtDeliveryTime() {
        var schedule = UserCareSchedule()
        _ = schedule.update(at: 0, isActive: true, idleSeconds: 0, localHour: 11)
        #expect(schedule.update(at: 2_700, isActive: true, idleSeconds: 0, localHour: 12,
            chooseIndex: { $0.upperBound - 2 }) == .lunch)
        #expect(schedule.update(at: 5_400, isActive: true, idleSeconds: 0, localHour: 23,
            chooseIndex: { $0.upperBound - 1 }) == .tomorrow)
    }
}
