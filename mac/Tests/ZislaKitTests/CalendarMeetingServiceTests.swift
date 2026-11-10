import AppKit
import Combine
import EventKit
import Foundation
import Testing
import ZislaCore
@testable import ZislaKit

@MainActor
struct CalendarMeetingServiceTests {
    @Test(arguments: [EKAuthorizationStatus.notDetermined, .denied, .restricted, .writeOnly])
    func passiveMeetingMonitoringNeverRequestsOrReadsUnauthorizedEvents(status: EKAuthorizationStatus) {
        let fixture = MeetingCalendarFixture()
        fixture.eventAccess = status
        let service = fixture.service()
        defer { service.stop() }
        service.start()
        service.refreshMeetings()
        #expect(service.meetingEvents.isEmpty)
        #expect(fixture.store.queries.isEmpty)
        #expect(fixture.store.eventPermissionRequests == 0)
        #expect(fixture.store.reminderPermissionRequests == 0)
    }

    @Test
    func permissionRevocationClearsMeetingsAndGrantRestoresWithoutPrompt() throws {
        let fixture = MeetingCalendarFixture()
        fixture.store.fixtures = [try fixture.event()]
        let service = fixture.service()
        defer { service.stop() }
        service.start()
        #expect(service.meetingEvents.count == 1)
        fixture.eventAccess = .denied
        service.refreshMeetings()
        #expect(service.meetingEvents.isEmpty)
        let readsBeforeGrant = fixture.store.queries.count
        fixture.eventAccess = .fullAccess
        service.refreshMeetings()
        #expect(service.meetingEvents.count == 1)
        #expect(fixture.store.queries.count == readsBeforeGrant + 1)
        #expect(fixture.store.eventPermissionRequests == 0)
    }

    @Test
    func browsingAnotherWeekDoesNotReplaceCurrentMeetingEvents() async throws {
        let fixture = MeetingCalendarFixture()
        let current = try fixture.event()
        let future = try fixture.event(id: "next-week", start: fixture.date.addingTimeInterval(21 * 86_400))
        fixture.store.fixtures = [future, current]
        let service = fixture.service()
        defer { service.stop() }
        await service.refresh(referenceDate: future.startDate)
        #expect(service.events.map(\.sourceIdentifier) == ["next-week"])
        #expect(service.meetingEvents.map(\.sourceIdentifier) == ["meeting"])
        #expect(fixture.store.queries.first?.start == fixture.date)
        #expect(fixture.store.queries.first?.end == fixture.date.addingTimeInterval(86_400))
    }

    @Test
    func rejectedAgendaRefreshClearsOldMeetingData() async throws {
        let fixture = MeetingCalendarFixture()
        fixture.store.fixtures = [try fixture.event()]
        let service = fixture.service()
        defer { service.stop() }
        service.refreshMeetings()
        #expect(service.meetingEvents.count == 1)
        fixture.eventAccess = .denied
        await service.refresh(referenceDate: fixture.date)
        #expect(service.events.isEmpty)
        #expect(service.meetingEvents.isEmpty)
        #expect(service.errorDescription != nil)
    }

    @Test
    func cancelledAndAllDayEventsAreExcludedAtTheEventKitBoundary() throws {
        let fixture = MeetingCalendarFixture()
        let normal = try fixture.event(id: "normal")
        let cancelled = try fixture.event(id: "cancelled"); cancelled.fixtureStatus = .canceled
        let allDay = try fixture.event(id: "all-day"); allDay.isAllDay = true
        fixture.store.fixtures = [allDay, cancelled, normal]
        let service = fixture.service()
        defer { service.stop() }
        service.refreshMeetings()
        #expect(service.meetingEvents.map(\.sourceIdentifier) == ["normal"])
        #expect(CalendarService.makeEventSnapshot(cancelled).isCancelled)
    }

    @Test
    func onlyTheCurrentUsersDeclineSuppressesTheMeeting() {
        #expect(CalendarService.isDeclined(participants: [(true, .declined), (false, .accepted)]))
        #expect(!CalendarService.isDeclined(participants: [(false, .declined), (true, .accepted)]))
        #expect(!CalendarService.isDeclined(participants: [(true, .pending)]))
        #expect(!CalendarService.isDeclined(participants: []))
    }

    @Test
    func snapshotPreservesLinksAndIdentityThroughRenamingAndRescheduling() throws {
        let fixture = MeetingCalendarFixture()
        let event = try fixture.event()
        event.location = "Room A"; event.notes = "Private invite https://zoom.us/j/123456789"
        let original = CalendarService.makeEventSnapshot(event)
        #expect(original.eventURL == event.url)
        #expect(original.notes == event.notes)
        #expect(original.location == event.location)
        event.fixtureID = "new-local-id"
        event.title = "Renamed"; event.startDate = event.startDate.addingTimeInterval(3_600)
        event.endDate = event.endDate.addingTimeInterval(3_600)
        let changed = CalendarService.makeEventSnapshot(event)
        #expect(changed.id != original.id)
        #expect(changed.eventIdentity == original.eventIdentity)
        #expect(changed.eventIdentity?.occurrenceDate == nil)
        event.fixtureExternalID = nil
        #expect(CalendarService.makeEventSnapshot(event).eventIdentity?.eventIdentifier == event.calendarItemIdentifier)
    }

    @Test
    func detachedOccurrenceKeepsItsOriginalIdentityAndOtherCalendarsStaySeparate() throws {
        let fixture = MeetingCalendarFixture()
        let event = try fixture.event()
        event.fixtureRecurring = true
        let originalDate = event.startDate!
        event.fixtureOccurrence = originalDate
        let original = CalendarService.makeEventSnapshot(event)
        event.fixtureDetached = true; event.fixtureRecurring = false
        event.startDate = originalDate.addingTimeInterval(3_600)
        #expect(CalendarService.makeEventSnapshot(event).eventIdentity == original.eventIdentity)
        event.fixtureOccurrence = originalDate.addingTimeInterval(86_400)
        #expect(CalendarService.makeEventSnapshot(event).eventIdentity != original.eventIdentity)
        let otherCalendar = try fixture.calendar(identifier: "personal")
        event.calendar = otherCalendar; event.fixtureOccurrence = originalDate
        #expect(CalendarService.makeEventSnapshot(event).eventIdentity != original.eventIdentity)
    }

    @Test(arguments: [
        NSWorkspace.didWakeNotification,
        NSNotification.Name.NSSystemClockDidChange,
        NSNotification.Name.NSSystemTimeZoneDidChange,
        NSNotification.Name.NSCalendarDayChanged,
        NSNotification.Name.EKEventStoreChanged,
    ])
    func lifecycleNotificationsRequeryAndRemoveEndedOrDeletedMeetings(name: Notification.Name) throws {
        let fixture = MeetingCalendarFixture()
        let event = try fixture.event()
        fixture.store.fixtures = [event]
        let service = fixture.service()
        defer { service.stop() }
        service.start()
        #expect(service.meetingEvents.count == 1)
        fixture.date = event.endDate
        let center = name == NSWorkspace.didWakeNotification ? fixture.workspaceCenter : fixture.center
        center.post(name: name, object: name == .EKEventStoreChanged ? fixture.store : nil)
        fixture.callbacks.deliver()
        #expect(service.meetingEvents.isEmpty)
        #expect(fixture.store.queries.last?.start == fixture.date)
        service.stop()
        let readsAfterStop = fixture.store.queries.count
        center.post(name: name, object: fixture.store)
        fixture.callbacks.deliver()
        #expect(fixture.store.queries.count == readsAfterStop)
        #expect(service.meetingEvents.isEmpty)
    }

    @Test(arguments: [false, true])
    func queuedNotificationsCannotReviveStoppedOrRestartedMonitoring(restart: Bool) throws {
        let fixture = MeetingCalendarFixture()
        fixture.store.fixtures = [try fixture.event()]
        let service = fixture.service()
        defer { service.stop() }
        service.start()
        for name in [NSWorkspace.didWakeNotification, .NSCalendarDayChanged, .EKEventStoreChanged] {
            let center = name == NSWorkspace.didWakeNotification ? fixture.workspaceCenter : fixture.center
            center.post(name: name, object: name == .EKEventStoreChanged ? fixture.store : nil)
        }
        fixture.timer?.fire()
        service.stop()
        if restart { service.start() }
        let reads = fixture.store.queries.count
        fixture.store.fixtures = []
        fixture.callbacks.deliver()
        #expect(fixture.store.queries.count == reads)
        #expect(service.meetingEvents.count == (restart ? 1 : 0))
    }

    @Test
    func monitoringReadsOneBoundedDayAndDoesNotIncludeFutureWeeks() throws {
        let fixture = MeetingCalendarFixture()
        let current = try fixture.event()
        fixture.store.fixtures = [current]
        for day in 2...32 {
            let outside = try fixture.event(id: "day-\(day)", start: fixture.date.addingTimeInterval(Double(day) * 86_400))
            outside.notes = String(repeating: "Private fixture ", count: 500)
            fixture.store.fixtures.append(outside)
        }
        let service = fixture.service()
        defer { service.stop() }
        service.start()
        service.start()
        #expect(service.meetingEvents.map(\.sourceIdentifier) == ["meeting"])
        #expect(fixture.store.queries.count == 1)
        #expect(fixture.store.queries[0].duration == 86_400)
        #expect(fixture.timer?.timeInterval == 60)
        #expect(fixture.timer?.tolerance == 10)
        fixture.timer?.fire()
        fixture.callbacks.deliver()
        #expect(fixture.store.queries.count == 2)
        service.stop()
        #expect(fixture.timer?.isValid == false)
    }

    @Test
    func calendarUpdateReplacesLinksAndDeduplicatesTheSameOccurrence() throws {
        let fixture = MeetingCalendarFixture()
        let event = try fixture.event()
        fixture.store.fixtures = [event, event]
        let service = fixture.service()
        defer { service.stop() }
        service.start()
        #expect(service.meetingEvents.count == 1)
        event.url = URL(string: "https://meeting.tencent.com/dm/NewMeeting")
        event.startDate = fixture.date.addingTimeInterval(1_200)
        service.refreshMeetings()
        #expect(service.meetingEvents.first?.meetingURL == event.url)
        #expect(service.meetingEvents.first?.startDate == event.startDate)
        fixture.store.fixtures = []
        service.refreshMeetings()
        #expect(service.meetingEvents.isEmpty)
    }
}

@MainActor
private final class MeetingCalendarFixture {
    let store = MeetingEventStore()
    let center = NotificationCenter()
    let workspaceCenter = NotificationCenter()
    let callbacks = MeetingCallbacks()
    var timer: Timer?
    var date = Date(timeIntervalSince1970: 1_000_000)
    var eventAccess = EKAuthorizationStatus.fullAccess

    func service() -> CalendarService {
        CalendarService(store: store, mutations: .live(store: store), environment: CalendarServiceEnvironment(
            authorizationStatus: { [self] kind in kind == .event ? eventAccess : .denied },
            now: { [self] in date }, notificationCenter: center, workspaceNotificationCenter: workspaceCenter,
            enqueue: { [callbacks] in callbacks.append($0) },
            makeTimer: { [self] action in
                let timer = Timer(timeInterval: 60, repeats: true) { _ in action() }
                self.timer = timer
                return timer
            }))
    }

    func calendar(identifier: String = "work") throws -> MeetingCalendar {
        let calendar = try #require(MeetingCalendar.perform(NSSelectorFromString("calendarWithEventStore:"),
            with: store)?.takeUnretainedValue() as? MeetingCalendar)
        calendar.fixtureID = identifier; calendar.title = "Work"
        return calendar
    }

    func event(id: String = "meeting", start: Date? = nil) throws -> MeetingEvent {
        let event = try #require(MeetingEvent.perform(NSSelectorFromString("eventWithEventStore:"), with: store)?.takeUnretainedValue() as? MeetingEvent)
        event.fixtureID = id; event.fixtureExternalID = "external-" + id
        event.title = "Team meeting"; event.startDate = start ?? date.addingTimeInterval(600)
        event.endDate = event.startDate.addingTimeInterval(3_600)
        event.calendar = try calendar()
        event.url = URL(string: "https://meet.google.com/abc-defg-hij")
        return event
    }
}

private final class MeetingCallbacks: @unchecked Sendable {
    private let lock = NSLock()
    private var callbacks: [@MainActor @Sendable () -> Void] = []

    func append(_ callback: @escaping @MainActor @Sendable () -> Void) {
        lock.withLock { callbacks.append(callback) }
    }

    @MainActor func deliver() {
        let pending = lock.withLock { let pending = callbacks; callbacks = []; return pending }
        for callback in pending { callback() }
    }
}

private final class MeetingCalendar: EKCalendar {
    var fixtureID = "work"
    override var calendarIdentifier: String { fixtureID }
}

private final class MeetingEvent: EKEvent {
    var fixtureID = "meeting"
    var fixtureExternalID: String? = "external-meeting"
    var fixtureOccurrence: Date?
    var fixtureDetached = false
    var fixtureRecurring = false
    var fixtureStatus = EKEventStatus.confirmed
    override var eventIdentifier: String! { fixtureID }
    override var calendarItemIdentifier: String { "local-" + fixtureID }
    override var calendarItemExternalIdentifier: String! { fixtureExternalID }
    override var occurrenceDate: Date! { fixtureOccurrence ?? startDate }
    override var isDetached: Bool { fixtureDetached }
    override var hasRecurrenceRules: Bool { fixtureRecurring }
    override var status: EKEventStatus { fixtureStatus }
}

private final class MeetingEventStore: EKEventStore {
    var fixtures: [EKEvent] = []
    var queries: [DateInterval] = []
    var eventPermissionRequests = 0
    var reminderPermissionRequests = 0

    override func predicateForEvents(withStart start: Date, end: Date, calendars: [EKCalendar]?) -> NSPredicate {
        queries.append(DateInterval(start: start, end: end))
        return NSPredicate { value, _ in
            guard let event = value as? EKEvent else { return false }
            return event.startDate < end && event.endDate > start
        }
    }

    override func events(matching predicate: NSPredicate) -> [EKEvent] { fixtures.filter { predicate.evaluate(with: $0) } }
    override func refreshSourcesIfNecessary() {}
    override func requestFullAccessToEvents() async throws -> Bool { eventPermissionRequests += 1; return false }
    override func requestFullAccessToReminders() async throws -> Bool { reminderPermissionRequests += 1; return false }
}
