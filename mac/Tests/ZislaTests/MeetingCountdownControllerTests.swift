import AppKit
import EventKit
import Foundation
import Testing
import ZislaCore
@testable import ZislaKit
@testable import Zisla

@MainActor
struct MeetingCountdownControllerTests {
    @Test
    func noMeetingCreatesNoTimerAndLeavesOtherNoticesAlone() throws {
        let fixture = try CountdownFixture()
        defer { fixture.close() }
        let ordinary = IslandNotice(id: "ordinary", title: "Other", side: .left)
        fixture.queue.enqueue(ordinary, expiresAfter: nil)
        fixture.controller.configure()
        #expect(fixture.timers.isEmpty)
        #expect(fixture.queue.left == [ordinary])
    }

    @Test
    func timerWaitsForTheLeadWindowTicksOnlyBeforeStartAndThenWaitsForEnd() throws {
        let fixture = try CountdownFixture()
        defer { fixture.close() }
        let event = try fixture.event(start: fixture.date.addingTimeInterval(3_600))
        fixture.store.fixtures = [event]
        fixture.calendar.refreshMeetings()
        fixture.controller.configure()
        #expect(fixture.intervals.last == 3_000)
        #expect(fixture.queue.left.isEmpty)
        fixture.date = event.startDate.addingTimeInterval(-600)
        fixture.fireLatest()
        #expect(fixture.queue.left.first?.detail == "10:00")
        #expect(fixture.queue.right.count == 1)
        #expect(fixture.intervals.last == 1)
        fixture.date = event.startDate.addingTimeInterval(-0.2)
        fixture.fireLatest()
        #expect(fixture.queue.left.first?.detail == "00:01")
        #expect(abs((fixture.intervals.last ?? 0) - 0.2) < 0.0001)
        fixture.date = event.startDate
        fixture.fireLatest()
        #expect(fixture.queue.left.first?.detail == "会议进行中")
        #expect(fixture.intervals.last == 3_600)
        #expect(fixture.timers.last?.tolerance == 1)
        let count = fixture.timers.count
        fixture.date = event.endDate
        fixture.fireLatest()
        #expect(fixture.queue.left.isEmpty && fixture.queue.right.isEmpty)
        #expect(fixture.timers.count == count)
    }

    @Test
    func calendarUpdatesReplaceTheCountdownAndRemoveCancelledOrDeletedMeetings() throws {
        let fixture = try CountdownFixture()
        defer { fixture.close() }
        let later = try fixture.event(id: "later", start: fixture.date.addingTimeInterval(300))
        fixture.store.fixtures = [later]
        fixture.calendar.refreshMeetings()
        fixture.controller.configure()
        #expect(fixture.queue.left.first?.detail == "05:00")
        let earlier = try fixture.event(id: "earlier", start: fixture.date.addingTimeInterval(60))
        fixture.store.fixtures = [later, earlier]
        fixture.calendar.refreshMeetings()
        #expect(fixture.queue.left.count == 1 && fixture.queue.right.count == 1)
        #expect(fixture.queue.left.first?.title == "earlier")
        #expect(fixture.queue.left.first?.detail == "01:00")
        earlier.fixtureStatus = .canceled
        fixture.calendar.refreshMeetings()
        #expect(fixture.queue.left.first?.title == "later")
        fixture.store.fixtures = []
        fixture.calendar.refreshMeetings()
        #expect(fixture.queue.left.isEmpty && fixture.queue.right.isEmpty)
        #expect(fixture.timers.last?.isValid == false)
    }

    @Test
    func languageChangesRefreshOngoingTextAndCalendarPermissionRevocationRemovesIt() throws {
        let fixture = try CountdownFixture()
        defer { fixture.close() }
        fixture.store.fixtures = [try fixture.event(start: fixture.date.addingTimeInterval(-60))]
        fixture.calendar.refreshMeetings()
        fixture.controller.configure()
        #expect(fixture.queue.left.first?.detail == "会议进行中")
        fixture.language.language = .english
        #expect(fixture.queue.left.first?.detail == "Meeting in progress")
        fixture.language.language = .arabic
        #expect(fixture.queue.left.first?.detail == "الاجتماع جارٍ")
        fixture.access = .denied
        fixture.calendar.refreshMeetings()
        #expect(fixture.queue.left.isEmpty && fixture.queue.right.isEmpty)
        #expect(fixture.timers.last?.isValid == false)
    }

    @Test(arguments: ["calendar", "notices", "stop", "restart"])
    func disablingOrRestartingInvalidatesLateTimersWithoutRestoringOldNotices(change: String) throws {
        let fixture = try CountdownFixture()
        defer { fixture.close() }
        fixture.store.fixtures = [try fixture.event(start: fixture.date.addingTimeInterval(60))]
        fixture.calendar.refreshMeetings()
        fixture.controller.configure()
        let old = try #require(fixture.actions.last)
        if change == "calendar" { fixture.settings.settings.calendarEnabled = false; fixture.controller.configure() }
        if change == "notices" { fixture.settings.settings.sideNoticesEnabled = false; fixture.controller.configure() }
        if change == "stop" || change == "restart" { fixture.controller.stop() }
        if change == "restart" {
            fixture.store.fixtures = []
            fixture.calendar.refreshMeetings()
            fixture.controller.configure()
        }
        let count = fixture.timers.count
        old()
        #expect(fixture.queue.left.isEmpty && fixture.queue.right.isEmpty)
        #expect(fixture.timers.count == count)
        #expect(fixture.timers.first?.isValid == false)
    }

    @Test
    func aChangedMeetingInvalidatesItsPreviousTimerCallback() throws {
        let fixture = try CountdownFixture()
        defer { fixture.close() }
        let event = try fixture.event(start: fixture.date.addingTimeInterval(60))
        fixture.store.fixtures = [event]
        fixture.calendar.refreshMeetings()
        fixture.controller.configure()
        let old = try #require(fixture.actions.last)
        event.startDate = fixture.date.addingTimeInterval(3_600)
        event.endDate = event.startDate.addingTimeInterval(3_600)
        fixture.calendar.refreshMeetings()
        let count = fixture.timers.count
        old()
        #expect(fixture.queue.left.isEmpty && fixture.queue.right.isEmpty)
        #expect(fixture.timers.count == count)
        #expect(fixture.intervals.last == 3_000)
    }

    @Test(arguments: ["calendar", "language"])
    func stoppedCountdownIgnoresCalendarAndLanguagePublishers(source: String) throws {
        let fixture = try CountdownFixture()
        defer { fixture.close() }
        let event = try fixture.event(start: fixture.date.addingTimeInterval(60))
        fixture.store.fixtures = [event]
        fixture.calendar.refreshMeetings()
        fixture.controller.configure()
        fixture.controller.stop()
        let count = fixture.timers.count
        if source == "calendar" {
            event.title = "Renamed"
            fixture.calendar.refreshMeetings()
        } else {
            fixture.language.language = .english
        }
        #expect(fixture.queue.left.isEmpty && fixture.queue.right.isEmpty)
        #expect(fixture.timers.count == count)
        #expect(fixture.timers.last?.isValid == false)
    }
}

@MainActor
private final class CountdownFixture {
    let defaults: UserDefaults
    let suite = "meeting-countdown-\(UUID())"
    let store = CountdownEventStore()
    let queue = SideNoticeQueue()
    let settings: FeatureSettingsStore
    let language: AppLanguageStore
    var date = Date(timeIntervalSince1970: 1_000_000)
    var access = EKAuthorizationStatus.fullAccess
    var timers: [Timer] = []
    var intervals: [TimeInterval] = []
    var actions: [@Sendable () -> Void] = []
    lazy var calendar = CalendarService(store: store, mutations: .live(store: store),
        environment: CalendarServiceEnvironment(authorizationStatus: { [self] _ in access }, now: { [self] in date },
            notificationCenter: NotificationCenter(), workspaceNotificationCenter: NotificationCenter()))
    lazy var controller = MeetingCountdownController(calendar: calendar, queue: queue, settings: settings,
        language: language, now: { [self] in date }, makeTimer: { [self] interval, action in
            let timer = Timer(timeInterval: interval, repeats: false) { _ in action() }
            timers.append(timer); intervals.append(interval); actions.append(action)
            return timer
        })

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suite))
        settings = FeatureSettingsStore(defaults: defaults)
        language = AppLanguageStore(defaults: defaults)
        settings.settings.calendarEnabled = true
        settings.settings.sideNoticesEnabled = true
    }

    func close() {
        controller.stop(); calendar.stop(); queue.removeAll()
        settings.flushPendingChanges()
        defaults.removePersistentDomain(forName: suite)
    }

    func fireLatest() { actions.last?() }

    func event(id: String = "meeting", start: Date) throws -> CountdownEvent {
        let event = try #require(CountdownEvent.perform(NSSelectorFromString("eventWithEventStore:"),
            with: store)?.takeUnretainedValue() as? CountdownEvent)
        let calendar = try #require(CountdownCalendar.perform(NSSelectorFromString("calendarWithEventStore:"),
            with: store)?.takeUnretainedValue() as? CountdownCalendar)
        calendar.title = "Fixture"
        event.fixtureID = id; event.title = id; event.calendar = calendar
        event.startDate = start; event.endDate = start.addingTimeInterval(3_600)
        event.url = URL(string: "https://meet.google.com/abc-defg-hij")
        return event
    }
}

private final class CountdownEvent: EKEvent {
    var fixtureID = "meeting"
    var fixtureStatus = EKEventStatus.confirmed
    override var eventIdentifier: String! { fixtureID }
    override var calendarItemExternalIdentifier: String! { fixtureID }
    override var status: EKEventStatus { fixtureStatus }
}

private final class CountdownCalendar: EKCalendar {
    override var calendarIdentifier: String { "fixture" }
}

private final class CountdownEventStore: EKEventStore {
    var fixtures: [EKEvent] = []
    override func predicateForEvents(withStart start: Date, end: Date, calendars: [EKCalendar]?) -> NSPredicate {
        NSPredicate { value, _ in
            guard let event = value as? EKEvent else { return false }
            return event.startDate < end && event.endDate > start
        }
    }
    override func events(matching predicate: NSPredicate) -> [EKEvent] { fixtures.filter { predicate.evaluate(with: $0) } }
}
