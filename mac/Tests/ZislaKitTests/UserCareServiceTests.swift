import AppKit
import Foundation
import Testing
import ZislaCore

@testable import ZislaKit

@MainActor
struct UserCareServiceTests {
    @Test(arguments: [1.0, 5, 30, 2_700])
    func customIntervalsDriveBothTheTimerAndExactReminderBoundary(interval: TimeInterval) throws {
        let fixture = UserCareFixture()
        let service = fixture.makeService()
        defer { service.stop() }
        service.apply(settings: FeatureSettings(userCareEnabled: true, userCareReminderInterval: interval))
        let timer = try #require(fixture.timers.first)
        #expect(timer.timeInterval == min(30, interval))
        #expect(timer.tolerance == (interval <= 30 ? 0 : 5))
        fixture.uptime = interval - 0.001
        service.refresh()
        #expect(fixture.presentedReminder == nil)
        fixture.uptime = interval
        service.refresh()
        #expect(fixture.presentedReminder != nil)
        fixture.presentedReminder = nil
        fixture.uptime = interval * 2 - 0.001
        service.refresh()
        #expect(fixture.presentedReminder == nil)
        fixture.uptime = interval * 2
        service.refresh()
        #expect(fixture.presentedReminder != nil)
    }

    @Test(arguments: [1.0, 5])
    func timerSetupLatencyAndEarlyTicksDoNotDelayByAnotherWholeInterval(interval: TimeInterval) throws {
        let fixture = UserCareFixture()
        fixture.timerSetupDelay = 0.005
        let service = fixture.makeService()
        defer { service.stop() }
        let beforeStart = Date()
        service.apply(settings: FeatureSettings(userCareEnabled: true, userCareReminderInterval: interval))
        let afterStart = Date()
        let timer = try #require(fixture.timers.first)
        assertDeadline(timer, delay: interval - 0.005, before: beforeStart, after: afterStart)
        fixture.uptime = interval + 0.005
        fixture.callbacks[0](timer)
        #expect(fixture.presentedReminder != nil, "The first tick must use the work baseline established before timer creation")
        fixture.presentedReminder = nil
        fixture.uptime = interval * 2
        let beforeEarlyTick = Date()
        fixture.callbacks[0](timer)
        let afterEarlyTick = Date()
        #expect(fixture.presentedReminder == nil)
        assertDeadline(timer, delay: 0.005, before: beforeEarlyTick, after: afterEarlyTick)
        fixture.uptime += 0.005
        fixture.callbacks[0](timer)
        #expect(fixture.presentedReminder != nil)
    }

    @Test
    func longerIntervalsScheduleTheRemainingSecondsInsteadOfRoundingUpToTheNextPoll() throws {
        let fixture = UserCareFixture()
        let service = fixture.makeService()
        defer { service.stop() }
        service.apply(settings: FeatureSettings(userCareEnabled: true, userCareReminderInterval: 31))
        let timer = try #require(fixture.timers.first)
        #expect(timer.tolerance == 1)
        fixture.uptime = 30
        let before = Date()
        fixture.callbacks[0](timer)
        let after = Date()
        #expect(fixture.presentedReminder == nil)
        assertDeadline(timer, delay: 1, before: before, after: after)
        #expect(timer.tolerance == 0)
        fixture.uptime = 31
        fixture.callbacks[0](timer)
        #expect(fixture.presentedReminder != nil)
    }

    @Test
    func changingTheIntervalClearsTheNoticeCancelsOldCallbacksAndStartsFromNow() {
        let fixture = UserCareFixture()
        let service = fixture.makeService()
        defer { service.stop() }
        service.apply(settings: FeatureSettings(userCareEnabled: true, userCareReminderInterval: 5))
        fixture.uptime = 5
        service.refresh()
        #expect(fixture.presentedReminder != nil)
        fixture.uptime = 6
        service.apply(settings: FeatureSettings(userCareEnabled: true, userCareReminderInterval: 10))
        #expect(fixture.presentedReminder == nil)
        #expect(fixture.timers.count == 2)
        #expect(!fixture.timers[0].isValid)
        #expect(fixture.workspace.handlers.count == 6)
        #expect(fixture.workspace.removedObservers == 0)
        let reads = fixture.reads
        fixture.callbacks[0](fixture.timers[0])
        #expect(fixture.reads == reads)
        fixture.uptime = 15.999
        service.refresh()
        #expect(fixture.presentedReminder == nil)
        fixture.uptime = 16
        fixture.callbacks[1](fixture.timers[1])
        #expect(fixture.presentedReminder == .water)
    }

    @Test
    func unrelatedSettingsDoNotResetCustomIntervalProgress() {
        let fixture = UserCareFixture()
        let service = fixture.makeService()
        defer { service.stop() }
        service.apply(settings: FeatureSettings(userCareEnabled: true, userCareReminderInterval: 5))
        fixture.uptime = 4
        service.apply(settings: FeatureSettings(
            userCareEnabled: true, userCareReminderInterval: 5, notificationsMuted: true, petEnabled: false
        ))
        #expect(fixture.timers.count == 1)
        fixture.uptime = 5
        fixture.callbacks[0](fixture.timers[0])
        #expect(fixture.presentedReminder == .rest)
    }

    @Test
    func changingIntervalsDuringLockPreservesTheInterruptionAndRearmsOnUnlock() throws {
        let fixture = UserCareFixture()
        let service = fixture.makeService()
        defer { service.stop() }
        service.apply(settings: FeatureSettings(userCareEnabled: true, userCareReminderInterval: 5))
        fixture.uptime = 4
        fixture.distributed.post(name: .init("com.apple.screenIsLocked"), object: nil)
        fixture.uptime = 100
        service.apply(settings: FeatureSettings(userCareEnabled: true, userCareReminderInterval: 1))
        fixture.uptime = 101
        service.refresh()
        #expect(fixture.presentedReminder == nil)
        fixture.uptime = 200.005
        let before = Date()
        fixture.distributed.post(name: .init("com.apple.screenIsUnlocked"), object: nil)
        let after = Date()
        let timer = try #require(fixture.timers.last)
        assertDeadline(timer, delay: 1, before: before, after: after)
        fixture.uptime = 201
        let beforeEarlyTick = Date()
        fixture.callbacks[1](timer)
        let afterEarlyTick = Date()
        #expect(fixture.presentedReminder == nil)
        assertDeadline(timer, delay: 0.005, before: beforeEarlyTick, after: afterEarlyTick)
        fixture.uptime = 201.005
        fixture.callbacks[1](timer)
        #expect(fixture.presentedReminder != nil)
    }

    @Test
    func disabledSettingsDoNotAcquireResourcesAndEnablingStartsFromNow() throws {
        let fixture = UserCareFixture()
        let service = fixture.makeService()
        defer { service.stop() }
        service.apply(settings: FeatureSettings(userCareEnabled: false))
        #expect(fixture.timers.isEmpty)
        #expect(fixture.workspace.handlers.isEmpty)
        #expect(fixture.distributed.handlers.isEmpty)
        #expect(fixture.reads == 0)

        fixture.uptime = 50_000
        service.apply(settings: FeatureSettings(userCareEnabled: true, petEnabled: false))
        #expect(fixture.presentedReminder == nil)
        #expect(fixture.timers.count == 1)
        #expect(fixture.timers[0].timeInterval == 30)
        #expect(fixture.workspace.handlers.count == 6)
        #expect(fixture.distributed.handlers.count == 2)
        fixture.uptime += 2_699
        service.refresh()
        #expect(fixture.presentedReminder == nil)
        fixture.uptime += 1
        service.refresh()
        #expect(fixture.presentedReminder == .rest)
    }

    @Test
    func repeatedSettingsAndPetVoiceChangesDoNotRestartWork() {
        let fixture = UserCareFixture()
        let service = fixture.makeService()
        defer { service.stop() }
        service.apply(settings: FeatureSettings(userCareEnabled: true, petEnabled: false))
        fixture.uptime = 2_000
        service.apply(settings: FeatureSettings(userCareEnabled: true, petEnabled: true))
        #expect(fixture.timers.count == 1)
        fixture.uptime = 2_700
        service.refresh()
        #expect(fixture.presentedReminder == .rest)
    }

    @Test
    func optOutCancelsResourcesClearsTheReminderAndRejectsStaleCallbacks() {
        let fixture = UserCareFixture()
        let service = fixture.makeService()
        defer { service.stop() }
        service.apply(settings: FeatureSettings(userCareEnabled: true))
        fixture.uptime = 2_700
        service.refresh()
        #expect(fixture.presentedReminder != nil)
        service.apply(settings: FeatureSettings(userCareEnabled: false))
        #expect(fixture.presentedReminder == nil)
        #expect(fixture.timers.first?.isValid == false)
        #expect(fixture.workspace.removedObservers == 6)
        #expect(fixture.distributed.removedObservers == 2)
        let reads = fixture.reads
        fixture.uptime = 80_000
        fixture.callbacks[0](fixture.timers[0])
        service.refresh()
        #expect(fixture.reads == reads)
        #expect(fixture.presentedReminder == nil)

        service.apply(settings: FeatureSettings(userCareEnabled: true))
        #expect(fixture.presentedReminder == nil)
        #expect(fixture.timers.count == 2)
        let restartedReads = fixture.reads
        fixture.callbacks[0](fixture.timers[0])
        let oldSleepCallback = fixture.workspace.handlers.first { $0.0 == NSWorkspace.willSleepNotification }?.1
        oldSleepCallback?(Notification(name: NSWorkspace.willSleepNotification))
        #expect(fixture.reads == restartedReads, "Callbacks from the stopped generation must not read or mutate the restarted service")
        fixture.uptime += 2_700
        service.refresh()
        #expect(fixture.presentedReminder != nil)
    }

    @Test
    func sideNoticeSettingsDoNotControlInIslandCareOrResetItsProgress() {
        let fixture = UserCareFixture()
        let service = fixture.makeService()
        defer { service.stop() }
        service.apply(settings: FeatureSettings(sideNoticesEnabled: false, userCareEnabled: true))
        fixture.uptime = 2_699
        service.apply(settings: FeatureSettings(sideNoticesEnabled: true, userCareEnabled: true))
        #expect(fixture.timers.count == 1)
        fixture.uptime = 2_700
        service.refresh()
        #expect(fixture.presentedReminder == .rest)
    }

    @Test
    func periodicIdleCleanupKeepsEventFeedbackButSystemInterruptionClearsAllCare() {
        let fixture = UserCareFixture()
        let service = fixture.makeService()
        defer { service.stop() }
        service.apply(settings: FeatureSettings(userCareEnabled: true))
        fixture.activity?.idleSeconds = 300
        service.refresh()
        #expect(fixture.clearScopes.last == true)
        fixture.workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
        #expect(fixture.clearScopes.last == false)
        fixture.workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        fixture.activity = UserCareFixture.active
        fixture.canPresent = false
        service.refresh()
        #expect(fixture.clearScopes.last == false)
        service.stop()
        #expect(fixture.clearScopes.last == false)
    }

    @Test(arguments: ["sleep", "screen", "session", "lock"], [false, true])
    func systemInterruptionsClearEventCareWhenTheActivityReadIsUnavailable(reason: String, ended: Bool) {
        let fixture = UserCareFixture()
        fixture.activity = nil
        let service = fixture.makeService()
        defer { service.stop() }
        service.apply(settings: FeatureSettings(userCareEnabled: true))
        fixture.clearScopes.removeAll()
        let (center, began, resumed) = fixture.events(for: reason)
        center.post(name: ended ? resumed : began, object: nil)
        #expect(fixture.clearScopes.contains(false),
            "A system interruption must clear event care even when the activity sampler cannot read the session")
    }

    @Test
    func notificationMuteKeepsSilentVisualRemindersEnabled() {
        let fixture = UserCareFixture()
        let service = fixture.makeService()
        defer { service.stop() }
        service.apply(settings: FeatureSettings(userCareEnabled: true, notificationsMuted: true))
        fixture.uptime = 2_700
        service.refresh()
        #expect(fixture.presentedReminder != nil)
    }

    @Test(arguments: ["screen", "session", "lock", "unavailable", "idle"])
    func initiallyUnavailableComputersDoNotCountWorkOrCatchUpAfterReturning(reason: String) {
        let fixture = UserCareFixture()
        switch reason {
        case "screen": fixture.activity?.isScreenAwake = false
        case "session": fixture.activity?.isSessionActive = false
        case "lock": fixture.activity?.isScreenLocked = true
        case "unavailable": fixture.activity = nil
        default: fixture.activity?.idleSeconds = 300
        }
        let service = fixture.makeService()
        defer { service.stop() }
        service.apply(settings: FeatureSettings(userCareEnabled: true))
        fixture.uptime = 20_000
        service.refresh()
        #expect(fixture.presentedReminder == nil)
        fixture.activity = UserCareFixture.active
        service.refresh()
        #expect(fixture.presentedReminder == nil)
        fixture.uptime += 2_699
        service.refresh()
        #expect(fixture.presentedReminder == nil)
        fixture.uptime += 1
        service.refresh()
        #expect(fixture.presentedReminder != nil)
    }

    @Test(arguments: ["sleep", "screen", "session", "lock"])
    func interruptionsClearAnExistingReminderAndRequireANewFullInterval(reason: String) {
        let fixture = UserCareFixture()
        let service = fixture.makeService()
        defer { service.stop() }
        service.apply(settings: FeatureSettings(userCareEnabled: true))
        fixture.uptime = 2_700
        service.refresh()
        #expect(fixture.presentedReminder != nil)
        let (center, began, ended) = fixture.events(for: reason)
        center.post(name: began, object: nil)
        #expect(fixture.presentedReminder == nil)
        fixture.uptime = 20_000
        service.refresh()
        #expect(fixture.presentedReminder == nil)
        center.post(name: ended, object: nil)
        #expect(fixture.presentedReminder == nil)
        fixture.uptime += 2_699
        service.refresh()
        #expect(fixture.presentedReminder == nil)
        fixture.uptime += 1
        service.refresh()
        #expect(fixture.presentedReminder != nil)
    }

    @Test
    func overlappingSystemInterruptionsOnlyResumeAfterEveryReasonClears() {
        let fixture = UserCareFixture()
        let service = fixture.makeService()
        defer { service.stop() }
        service.apply(settings: FeatureSettings(userCareEnabled: true))
        fixture.uptime = 2_699
        fixture.distributed.post(name: .init("com.apple.screenIsLocked"), object: nil)
        fixture.workspace.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        fixture.workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
        fixture.workspace.post(name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        fixture.uptime = 30_000
        fixture.workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        fixture.workspace.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        fixture.workspace.post(name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        fixture.uptime += 2_700
        service.refresh()
        #expect(fixture.presentedReminder == nil, "Display and session wake must not clear the lock interruption")
        fixture.distributed.post(name: .init("com.apple.screenIsUnlocked"), object: nil)
        #expect(fixture.presentedReminder == nil)
        fixture.uptime += 2_700
        service.refresh()
        #expect(fixture.presentedReminder != nil)
    }

    @Test
    func idleBreakClearsTheReminderAndReturnDoesNotReplayIt() {
        let fixture = UserCareFixture()
        let service = fixture.makeService()
        defer { service.stop() }
        service.apply(settings: FeatureSettings(userCareEnabled: true))
        fixture.uptime = 2_700
        service.refresh()
        fixture.activity?.idleSeconds = 300
        service.refresh()
        #expect(fixture.presentedReminder == nil)
        fixture.uptime = 40_000
        fixture.activity?.idleSeconds = 0
        service.refresh()
        #expect(fixture.presentedReminder == nil)
        fixture.uptime += 2_700
        service.refresh()
        #expect(fixture.presentedReminder != nil)
    }

    @Test
    func failedSystemStateReadClearsTheNoticeAndRestartsTheWorkInterval() {
        let fixture = UserCareFixture()
        let service = fixture.makeService()
        defer { service.stop() }
        service.apply(settings: FeatureSettings(userCareEnabled: true))
        fixture.uptime = 2_700
        service.refresh()
        #expect(fixture.presentedReminder != nil)
        fixture.activity = nil
        service.refresh()
        #expect(fixture.presentedReminder == nil)
        fixture.uptime += 2_700
        fixture.activity = UserCareFixture.active
        service.refresh()
        #expect(fixture.presentedReminder == nil)
        fixture.uptime += 2_700
        service.refresh()
        #expect(fixture.presentedReminder != nil)
    }

    @Test
    func suppressedDueRemindersAreDroppedWithoutCatchUpOrQueueAccumulation() {
        let fixture = UserCareFixture()
        let service = fixture.makeService()
        defer { service.stop() }
        service.apply(settings: FeatureSettings(userCareEnabled: true))
        fixture.canPresent = false
        fixture.uptime = 2_700
        service.refresh()
        #expect(fixture.presentedReminder == nil)
        fixture.canPresent = true
        for _ in 0..<10 { service.refresh() }
        #expect(fixture.presentedReminder == nil)
        fixture.uptime += 2_700
        service.refresh()
        #expect(fixture.presentedReminder != nil)
        fixture.uptime += 27_000
        service.refresh()
        #expect(fixture.presentedReminder != nil)
        #expect(fixture.deliveredReminders.count == 2)
    }

    @Test
    func localTimeSelectsTheMessageWhileWallClockChangesDoNotAdvanceWork() {
        let fixture = UserCareFixture()
        fixture.hour = 12
        fixture.chooseIndex = { $0.upperBound - 1 }
        let service = fixture.makeService()
        defer { service.stop() }
        service.apply(settings: FeatureSettings(userCareEnabled: true, petEnabled: false))
        fixture.hour = 23
        service.refresh()
        #expect(fixture.presentedReminder == nil)
        fixture.hour = 12
        fixture.uptime = 2_700
        service.refresh()
        #expect(fixture.presentedReminder == .nap)
        fixture.hour = 23
        fixture.uptime += 2_700
        service.refresh()
        #expect(fixture.presentedReminder == .tomorrow)
    }

    @Test
    func timeZoneChangesUseTheCurrentLocalHourAtDelivery() {
        let fixture = UserCareFixture()
        fixture.chooseIndex = { $0.upperBound - 1 }
        let service = fixture.makeService()
        defer { service.stop() }
        service.apply(settings: FeatureSettings(userCareEnabled: true, petEnabled: false))
        fixture.timeZone = TimeZone(secondsFromGMT: 14 * 3_600)!
        fixture.uptime = 2_700
        service.refresh()
        #expect(fixture.presentedReminder == .tomorrow)
    }

    @Test
    func deinitializationCancelsTheTimerObserversAndStaleCallbacks() {
        let fixture = UserCareFixture()
        var service: UserCareService? = fixture.makeService()
        service?.apply(settings: FeatureSettings(userCareEnabled: true))
        weak var retained = service
        service = nil
        #expect(retained == nil)
        #expect(fixture.timers[0].isValid == false)
        #expect(fixture.workspace.removedObservers == 6)
        #expect(fixture.distributed.removedObservers == 2)
        let reads = fixture.reads
        fixture.uptime = 20_000
        fixture.callbacks[0](fixture.timers[0])
        for (_, callback) in fixture.workspace.handlers {
            callback(Notification(name: NSWorkspace.didWakeNotification))
        }
        #expect(fixture.reads == reads)
        #expect(fixture.presentedReminder == nil)
    }

    private func assertDeadline(_ timer: Timer, delay: TimeInterval, before: Date, after: Date) {
        #expect(timer.fireDate.timeIntervalSince(before) >= delay - 0.000_01)
        #expect(timer.fireDate.timeIntervalSince(after) <= delay + 0.000_01)
    }
}

@MainActor
private final class UserCareFixture {
    static var active: UserCareActivity {
        UserCareActivity(isScreenAwake: true, isSessionActive: true, isScreenLocked: false, idleSeconds: 0)
    }

    var presentedReminder: UserCareReminder?
    var deliveredReminders: [UserCareReminder] = []
    var clearScopes: [Bool] = []
    var chooseIndex: (Range<Int>) -> Int = { $0.lowerBound }
    let workspace = UserCareNotificationCenter()
    let distributed = UserCareNotificationCenter()
    var uptime: TimeInterval = 0
    var activity: UserCareActivity? = active
    var canPresent = true
    var hour = 10
    var reads = 0
    var timers: [Timer] = []
    var callbacks: [@Sendable (Timer) -> Void] = []
    var timerSetupDelay: TimeInterval = 0
    var timeZone = TimeZone(secondsFromGMT: 0)!
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
    var date: Date {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        return utc.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: hour))!
    }

    func makeService() -> UserCareService {
        UserCareService(
            onReminder: {
                self.presentedReminder = $0
                self.deliveredReminders.append($0)
            },
            onClear: {
                self.clearScopes.append($0)
                self.presentedReminder = nil
            },
            uptime: { self.uptime },
            now: { self.date },
            calendar: { self.calendar },
            activity: { self.reads += 1; return self.activity },
            presentationAllowed: { self.canPresent },
            workspaceCenter: workspace,
            distributedCenter: distributed,
            chooseIndex: { self.chooseIndex($0) },
            timerFactory: { interval, callback in
                let timer = Timer(timeInterval: interval, repeats: true, block: callback)
                self.timers.append(timer)
                self.callbacks.append(callback)
                self.uptime += self.timerSetupDelay
                return timer
            }
        )
    }

    func events(for reason: String) -> (NotificationCenter, Notification.Name, Notification.Name) {
        switch reason {
        case "sleep": (workspace, NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification)
        case "screen": (workspace, NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification)
        case "session": (workspace, NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification)
        default: (distributed, .init("com.apple.screenIsLocked"), .init("com.apple.screenIsUnlocked"))
        }
    }
}

private final class UserCareNotificationCenter: NotificationCenter, @unchecked Sendable {
    private(set) var handlers: [(Notification.Name?, @Sendable (Notification) -> Void)] = []
    private(set) var removedObservers = 0

    override func addObserver(
        forName name: Notification.Name?,
        object: Any?,
        queue: OperationQueue?,
        using block: @escaping @Sendable (Notification) -> Void
    ) -> NSObjectProtocol {
        handlers.append((name, block))
        return super.addObserver(forName: name, object: object, queue: queue, using: block)
    }

    override func removeObserver(_ observer: Any) {
        removedObservers += 1
        super.removeObserver(observer)
    }
}
