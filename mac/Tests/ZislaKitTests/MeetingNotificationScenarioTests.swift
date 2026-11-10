import Foundation
import Testing
import ZislaCore
@testable import ZislaKit

@MainActor
struct MeetingNotificationScenarioTests {
    @Test
    func automaticAndManualControlsAreIndependentAndDefaultToTheOldBehavior() {
        let fixture = Fixture()
        defer { fixture.scene.stop(); fixture.queue.removeAll() }
        let current = fixture.event(start: -60, end: 600)
        fixture.scene.configure(settings: .init(), manual: false, events: [current])
        #expect(fixture.queue.activeNotificationScenarios.isEmpty && !fixture.calendarActive)
        var settings = NotificationScenarioSettings(enabled: true)
        fixture.scene.configure(settings: settings, manual: false, events: [current])
        #expect(fixture.queue.activeNotificationScenarios.isEmpty && fixture.scheduled.isEmpty)
        settings.automaticallyDetectsMeetings = true
        fixture.scene.configure(settings: settings, manual: false, events: [current])
        #expect(fixture.queue.activeNotificationScenarios == [.meeting] && fixture.calendarActive)
        fixture.scene.configure(settings: settings, manual: true, events: [])
        #expect(fixture.queue.activeNotificationScenarios == [.meeting] && !fixture.calendarActive)
        settings.automaticallyDetectsMeetings = false
        fixture.scene.configure(settings: settings, manual: true, events: [current])
        #expect(fixture.queue.activeNotificationScenarios == [.meeting] && !fixture.calendarActive)
        fixture.scene.configure(settings: settings, manual: false, events: [current])
        #expect(fixture.queue.activeNotificationScenarios.isEmpty)
    }

    @Test
    func exactTimeBoundariesStartAndEndTheAutomaticSceneAndPublishOnlyOneReview() throws {
        let fixture = Fixture()
        defer { fixture.scene.stop(); fixture.queue.removeAll() }
        let settings = NotificationScenarioSettings(enabled: true, automaticallyDetectsMeetings: true)
        fixture.queue.configureNotificationScenarios(settings, displayIdentifiers: ["display"])
        let event = fixture.event(start: 60, end: 120)
        fixture.scene.configure(settings: settings, manual: false, events: [event])
        #expect(fixture.queue.activeNotificationScenarios.isEmpty)
        #expect(try #require(fixture.scheduled.last).delay == 60)
        fixture.date = event.startDate
        try #require(fixture.scheduled.last).action()
        #expect(fixture.queue.activeNotificationScenarios == [.meeting])
        fixture.queue.enqueue(.init(id: "deferred", title: "Deferred"), expiresAfter: nil)
        fixture.date = event.endDate
        try #require(fixture.scheduled.last).action()
        #expect(fixture.queue.activeNotificationScenarios.isEmpty && !fixture.calendarActive)
        #expect(fixture.queue.scenarioReview(displayIdentifier: "display").map(\.id) == ["deferred"])
        #expect(fixture.cancelled == 2)
    }

    @Test
    func cancelledRevokedAndRescheduledCalendarDataEndsOnlyTheAutomaticSource() {
        let fixture = Fixture()
        defer { fixture.scene.stop(); fixture.queue.removeAll() }
        let settings = NotificationScenarioSettings(enabled: true, automaticallyDetectsMeetings: true)
        var event = fixture.event(start: -60, end: 600)
        fixture.scene.configure(settings: settings, manual: false, events: [event])
        #expect(fixture.calendarActive)
        event.isCancelled = true
        fixture.scene.configure(settings: settings, manual: false, events: [event])
        #expect(!fixture.calendarActive && fixture.queue.activeNotificationScenarios.isEmpty)
        event.isCancelled = false
        event.startDate = fixture.date.addingTimeInterval(300)
        event.endDate = fixture.date.addingTimeInterval(900)
        fixture.scene.configure(settings: settings, manual: false, events: [event])
        #expect(!fixture.calendarActive && fixture.scheduled.last?.delay == 300)
        fixture.scene.configure(settings: settings, manual: true, events: [])
        #expect(!fixture.calendarActive && fixture.queue.activeNotificationScenarios == [.meeting])
        fixture.scene.configure(settings: settings, manual: false, events: [])
        #expect(fixture.queue.activeNotificationScenarios.isEmpty)
    }

    @Test
    func overlappingCalendarMeetingsRemainQuietUntilTheLastEndsAndStopInvalidatesQueuedTimers() throws {
        let fixture = Fixture()
        defer { fixture.scene.stop(); fixture.queue.removeAll() }
        let settings = NotificationScenarioSettings(enabled: true, automaticallyDetectsMeetings: true)
        let first = fixture.event(id: "one", start: -60, end: 60)
        let second = fixture.event(id: "two", start: 30, end: 120)
        fixture.scene.configure(settings: settings, manual: false, events: [second, first])
        fixture.date += 30
        try #require(fixture.scheduled.last).action()
        fixture.date += 30
        try #require(fixture.scheduled.last).action()
        #expect(fixture.queue.activeNotificationScenarios == [.meeting])
        let queued = try #require(fixture.scheduled.last).action
        fixture.scene.stop()
        fixture.date += 60
        queued()
        #expect(fixture.queue.activeNotificationScenarios.isEmpty && !fixture.calendarActive)
    }

    @Test
    func midnightSleepAndClockChangesRecomputeAbsoluteTimesWithoutReplayingEvents() throws {
        let fixture = Fixture()
        defer { fixture.scene.stop(); fixture.queue.removeAll() }
        let settings = NotificationScenarioSettings(enabled: true, automaticallyDetectsMeetings: true)
        fixture.date = try #require(ISO8601DateFormatter().date(from: "2026-11-10T23:55:00+08:00"))
        let event = fixture.event(start: 0, end: 1_800)
        fixture.scene.configure(settings: settings, manual: false, events: [event])
        fixture.date += 900
        fixture.scene.configure(settings: settings, manual: false, events: [event])
        #expect(fixture.calendarActive)
        fixture.date += 7_200
        fixture.scene.configure(settings: settings, manual: false, events: [])
        #expect(!fixture.calendarActive && fixture.queue.activeNotificationScenarios.isEmpty)
        fixture.date = event.startDate.addingTimeInterval(-60)
        fixture.scene.configure(settings: settings, manual: false, events: [event])
        #expect(!fixture.calendarActive && fixture.scheduled.last?.delay == 60)
    }

    @Test
    func aQueuedBoundaryFromOldCalendarDataCannotRestartTheSceneAfterDisablingDetection() throws {
        let fixture = Fixture()
        defer { fixture.scene.stop(); fixture.queue.removeAll() }
        var settings = NotificationScenarioSettings(enabled: true, automaticallyDetectsMeetings: true)
        let future = fixture.event(start: 60, end: 120)
        fixture.scene.configure(settings: settings, manual: false, events: [future])
        let queued = try #require(fixture.scheduled.last).action
        settings.automaticallyDetectsMeetings = false
        fixture.scene.configure(settings: settings, manual: false, events: [future])
        fixture.date = future.startDate
        let scheduledCount = fixture.scheduled.count
        queued()
        #expect(fixture.scheduled.count == scheduledCount)
        #expect(fixture.queue.activeNotificationScenarios.isEmpty && !fixture.calendarActive)
    }

    @Test
    func aCallbackFromBeforeStopCannotReplaceTheRestartedMeetingTimerOrPublishADuplicateReview() throws {
        let fixture = Fixture()
        defer { fixture.scene.stop(); fixture.queue.removeAll() }
        let settings = NotificationScenarioSettings(enabled: true, automaticallyDetectsMeetings: true)
        fixture.queue.configureNotificationScenarios(settings, displayIdentifiers: ["display"])
        fixture.scene.configure(settings: settings, manual: false, events: [fixture.event(start: 60, end: 120)])
        let queued = try #require(fixture.scheduled.last).action
        fixture.scene.stop()
        let restarted = fixture.event(start: 0, end: 300)
        fixture.scene.configure(settings: settings, manual: false, events: [restarted])
        fixture.queue.enqueue(.init(id: "new-meeting", title: "New meeting"), expiresAfter: nil)
        let scheduledCount = fixture.scheduled.count
        let cancelledCount = fixture.cancelled
        let calendarUpdates = fixture.calendarUpdates
        fixture.date += 120
        queued()
        #expect(fixture.queue.activeNotificationScenarios == [.meeting] && fixture.calendarActive)
        #expect(fixture.queue.scenarioReview(displayIdentifier: "display").isEmpty)
        #expect(fixture.scheduled.count == scheduledCount && fixture.cancelled == cancelledCount)
        #expect(fixture.activeTimers.count == 1 && fixture.calendarUpdates == calendarUpdates)
        fixture.date = restarted.endDate
        try #require(fixture.scheduled.last).action()
        #expect(fixture.activeTimers.isEmpty && !fixture.calendarActive)
        #expect(fixture.queue.scenarioReview(displayIdentifier: "display").map(\.id) == ["new-meeting"])
    }

    @MainActor
    private final class Fixture {
        let queue = SideNoticeQueue()
        var date = Date(timeIntervalSince1970: 10_000)
        var calendarActive = false
        var calendarUpdates = 0
        var scheduled: [(delay: TimeInterval, action: @MainActor () -> Void)] = []
        var activeTimers: Set<Int> = []
        var cancelled = 0
        lazy var scene = MeetingNotificationScenario(queue: queue, now: { [unowned self] in date },
            schedule: { [unowned self] delay, action in
                scheduled.append((delay, action))
                let timer = scheduled.count
                activeTimers.insert(timer)
                return { [unowned self] in cancelled += 1; activeTimers.remove(timer) }
            }, onCalendarStateChanged: { [unowned self] in calendarActive = $0; calendarUpdates += 1 })

        func event(id: String = "meeting", start: Double, end: Double) -> CalendarEventSnapshot {
            .init(id: id, title: id, startDate: date.addingTimeInterval(start), endDate: date.addingTimeInterval(end),
                isAllDay: false, calendarTitle: "Fixture", eventURL: URL(string: "https://meet.google.com/abc-defg-hij"))
        }
    }
}
