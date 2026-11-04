import AppKit
import Combine
import Foundation
import Testing
import ZislaCore

@testable import ZislaKit

@MainActor
struct UserCareServiceTests {
    @Test
    func disabledSettingsDoNotAcquireResourcesAndEnablingStartsFromNow() throws {
        let fixture = UserCareFixture()
        let service = fixture.makeService()
        defer { service.stop() }
        service.apply(settings: FeatureSettings())
        #expect(fixture.timers.isEmpty)
        #expect(fixture.workspace.handlers.isEmpty)
        #expect(fixture.distributed.handlers.isEmpty)
        #expect(fixture.reads == 0)

        fixture.uptime = 50_000
        service.apply(settings: FeatureSettings(userCareEnabled: true, petEnabled: false))
        #expect(fixture.queue.right.isEmpty)
        #expect(fixture.timers.count == 1)
        #expect(fixture.timers[0].timeInterval == 30)
        #expect(fixture.workspace.handlers.count == 6)
        #expect(fixture.distributed.handlers.count == 2)
        fixture.uptime += 2_699
        service.refresh()
        #expect(fixture.queue.right.isEmpty)
        fixture.uptime += 1
        service.refresh()
        #expect(fixture.queue.right.first?.title == "忙了一阵了，歇一会儿吧。")
        #expect(fixture.queue.right.first?.style == .message)
        #expect(fixture.queue.right.first?.side == .right)
    }

    @Test
    func repeatedSettingsDoNotRestartWorkAndPetToneUsesTheCurrentSetting() {
        let fixture = UserCareFixture()
        let service = fixture.makeService()
        defer { service.stop() }
        service.apply(settings: FeatureSettings(userCareEnabled: true, petEnabled: false))
        fixture.uptime = 2_000
        service.apply(settings: FeatureSettings(userCareEnabled: true, petEnabled: true))
        #expect(fixture.timers.count == 1)
        fixture.uptime = 2_700
        service.refresh()
        #expect(fixture.queue.right.first?.title == "人，忙了一阵了，陪我歇一会儿吧。")
        #expect(fixture.queue.right.first?.style == .message)
        #expect(fixture.queue.right.first?.id == UserCareService.noticeID)
    }

    @Test(arguments: [false, true])
    func optOutAndDisabledSideNoticesCancelResourcesAndRemoveQueuedReminders(disableSideNotices: Bool) {
        let fixture = UserCareFixture()
        let service = fixture.makeService()
        defer { service.stop() }
        service.apply(settings: FeatureSettings(userCareEnabled: true))
        fixture.uptime = 2_700
        service.refresh()
        #expect(fixture.queue.right.count == 1)
        service.apply(settings: FeatureSettings(
            sideNoticesEnabled: !disableSideNotices,
            userCareEnabled: disableSideNotices
        ))
        #expect(fixture.queue.right.isEmpty)
        #expect(fixture.timers.first?.isValid == false)
        #expect(fixture.workspace.removedObservers == 6)
        #expect(fixture.distributed.removedObservers == 2)
        let reads = fixture.reads
        fixture.uptime = 80_000
        fixture.callbacks[0](fixture.timers[0])
        service.refresh()
        #expect(fixture.reads == reads)
        #expect(fixture.queue.right.isEmpty)

        service.apply(settings: FeatureSettings(userCareEnabled: true))
        #expect(fixture.queue.right.isEmpty)
        #expect(fixture.timers.count == 2)
        let restartedReads = fixture.reads
        fixture.callbacks[0](fixture.timers[0])
        let oldSleepCallback = fixture.workspace.handlers.first { $0.0 == NSWorkspace.willSleepNotification }?.1
        oldSleepCallback?(Notification(name: NSWorkspace.willSleepNotification))
        #expect(fixture.reads == restartedReads, "Callbacks from the stopped generation must not read or mutate the restarted service")
        fixture.uptime += 2_700
        service.refresh()
        #expect(fixture.queue.right.count == 1)
    }

    @Test
    func notificationMuteKeepsSilentVisualRemindersEnabled() {
        let fixture = UserCareFixture()
        let service = fixture.makeService()
        defer { service.stop() }
        service.apply(settings: FeatureSettings(userCareEnabled: true, notificationsMuted: true))
        fixture.uptime = 2_700
        service.refresh()
        #expect(fixture.queue.right.count == 1)
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
        #expect(fixture.queue.right.isEmpty)
        fixture.activity = UserCareFixture.active
        service.refresh()
        #expect(fixture.queue.right.isEmpty)
        fixture.uptime += 2_699
        service.refresh()
        #expect(fixture.queue.right.isEmpty)
        fixture.uptime += 1
        service.refresh()
        #expect(fixture.queue.right.count == 1)
    }

    @Test(arguments: ["sleep", "screen", "session", "lock"])
    func interruptionsClearAnExistingReminderAndRequireANewFullInterval(reason: String) {
        let fixture = UserCareFixture()
        let service = fixture.makeService()
        defer { service.stop() }
        service.apply(settings: FeatureSettings(userCareEnabled: true))
        fixture.uptime = 2_700
        service.refresh()
        #expect(fixture.queue.right.count == 1)
        let (center, began, ended) = fixture.events(for: reason)
        center.post(name: began, object: nil)
        #expect(fixture.queue.right.isEmpty)
        fixture.uptime = 20_000
        service.refresh()
        #expect(fixture.queue.right.isEmpty)
        center.post(name: ended, object: nil)
        #expect(fixture.queue.right.isEmpty)
        fixture.uptime += 2_699
        service.refresh()
        #expect(fixture.queue.right.isEmpty)
        fixture.uptime += 1
        service.refresh()
        #expect(fixture.queue.right.count == 1)
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
        #expect(fixture.queue.right.isEmpty, "Display and session wake must not clear the lock interruption")
        fixture.distributed.post(name: .init("com.apple.screenIsUnlocked"), object: nil)
        #expect(fixture.queue.right.isEmpty)
        fixture.uptime += 2_700
        service.refresh()
        #expect(fixture.queue.right.count == 1)
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
        #expect(fixture.queue.right.isEmpty)
        fixture.uptime = 40_000
        fixture.activity?.idleSeconds = 0
        service.refresh()
        #expect(fixture.queue.right.isEmpty)
        fixture.uptime += 2_700
        service.refresh()
        #expect(fixture.queue.right.count == 1)
    }

    @Test
    func failedSystemStateReadClearsTheNoticeAndRestartsTheWorkInterval() {
        let fixture = UserCareFixture()
        let service = fixture.makeService()
        defer { service.stop() }
        service.apply(settings: FeatureSettings(userCareEnabled: true))
        fixture.uptime = 2_700
        service.refresh()
        #expect(fixture.queue.right.count == 1)
        fixture.activity = nil
        service.refresh()
        #expect(fixture.queue.right.isEmpty)
        fixture.uptime += 2_700
        fixture.activity = UserCareFixture.active
        service.refresh()
        #expect(fixture.queue.right.isEmpty)
        fixture.uptime += 2_700
        service.refresh()
        #expect(fixture.queue.right.count == 1)
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
        #expect(fixture.queue.right.isEmpty)
        fixture.canPresent = true
        for _ in 0..<10 { service.refresh() }
        #expect(fixture.queue.right.isEmpty)
        fixture.uptime += 2_700
        service.refresh()
        #expect(fixture.queue.right.count == 1)
        fixture.uptime += 27_000
        service.refresh()
        #expect(fixture.queue.right.count == 1)
        #expect(fixture.queue.right.first?.createdAt == fixture.date)
    }

    @Test
    func localTimeSelectsTheMessageWhileWallClockChangesDoNotAdvanceWork() {
        let fixture = UserCareFixture()
        fixture.hour = 12
        let service = fixture.makeService()
        defer { service.stop() }
        service.apply(settings: FeatureSettings(userCareEnabled: true, petEnabled: false))
        fixture.hour = 23
        service.refresh()
        #expect(fixture.queue.right.isEmpty)
        fixture.hour = 12
        fixture.uptime = 2_700
        service.refresh()
        #expect(fixture.queue.right.first?.title == "到午间了，记得吃饭，也休息一会儿。")
        fixture.hour = 23
        fixture.uptime += 2_700
        service.refresh()
        #expect(fixture.queue.right.first?.title == "今天辛苦了，余下的事留给明天吧。")
    }

    @Test
    func timeZoneChangesUseTheCurrentLocalHourAtDelivery() {
        let fixture = UserCareFixture()
        let service = fixture.makeService()
        defer { service.stop() }
        service.apply(settings: FeatureSettings(userCareEnabled: true, petEnabled: false))
        fixture.timeZone = TimeZone(secondsFromGMT: 14 * 3_600)!
        fixture.uptime = 2_700
        service.refresh()
        #expect(fixture.queue.right.first?.title == "已经很晚了，早点休息吧。")
    }

    @Test(arguments: AppLanguage.allCases, [false, true])
    func queuedLongTextUsesTheRequestedLanguageAndScrollableMessageStyle(language: AppLanguage, petEnabled: Bool) {
        let fixture = UserCareFixture()
        fixture.language = language
        let service = fixture.makeService()
        defer { service.stop() }
        service.apply(settings: FeatureSettings(userCareEnabled: true, petEnabled: petEnabled))
        fixture.uptime = 2_700
        service.refresh()
        #expect(fixture.queue.right.first?.title == AppLocalization.string(
            UserCareReminder.rest.localizationKey(petEnabled: petEnabled), language: language
        ))
        #expect(fixture.queue.right.first?.style == .message)
        #expect(fixture.queue.right.first?.side == .right)
        #expect(fixture.queue.right.first?.detail == nil)
    }

    @Test
    func reminderExpiresAfterSixSecondsAndDoesNotReappearOnTheNextTick() async throws {
        let (scheduled, scheduledContinuation) = AsyncStream<Duration>.makeStream()
        let (expiry, expiryContinuation) = AsyncStream<Void>.makeStream()
        let queue = SideNoticeQueue(capacityPerSide: 3, expirySleeper: { duration in
            scheduledContinuation.yield(duration)
            var iterator = expiry.makeAsyncIterator()
            _ = await iterator.next()
        })
        let fixture = UserCareFixture(queue: queue)
        let service = fixture.makeService()
        defer {
            service.stop()
            scheduledContinuation.finish()
            expiryContinuation.finish()
        }
        service.apply(settings: FeatureSettings(userCareEnabled: true))
        fixture.uptime = 2_700
        service.refresh()
        #expect(queue.right.count == 1)
        var scheduledIterator = scheduled.makeAsyncIterator()
        #expect(await scheduledIterator.next() == .seconds(6))
        expiryContinuation.yield(())
        for await notices in queue.$right.values {
            if notices.isEmpty { break }
        }
        fixture.uptime += 30
        service.refresh()
        #expect(queue.right.isEmpty)
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
        #expect(fixture.queue.right.isEmpty)
    }
}

@MainActor
private final class UserCareFixture {
    static var active: UserCareActivity {
        UserCareActivity(isScreenAwake: true, isSessionActive: true, isScreenLocked: false, idleSeconds: 0)
    }

    let queue: SideNoticeQueue
    let workspace = UserCareNotificationCenter()
    let distributed = UserCareNotificationCenter()
    var uptime: TimeInterval = 0
    var activity: UserCareActivity? = active
    var language = AppLanguage.simplifiedChinese
    var canPresent = true
    var hour = 10
    var reads = 0
    var timers: [Timer] = []
    var callbacks: [@Sendable (Timer) -> Void] = []
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

    init(queue: SideNoticeQueue? = nil) {
        self.queue = queue ?? SideNoticeQueue()
    }

    func makeService() -> UserCareService {
        UserCareService(
            queue: queue,
            uptime: { self.uptime },
            now: { self.date },
            calendar: { self.calendar },
            language: { self.language },
            activity: { self.reads += 1; return self.activity },
            presentationAllowed: { self.canPresent },
            workspaceCenter: workspace,
            distributedCenter: distributed,
            timerFactory: { interval, callback in
                let timer = Timer(timeInterval: interval, repeats: true, block: callback)
                self.timers.append(timer)
                self.callbacks.append(callback)
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
