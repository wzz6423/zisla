import AppKit
import Combine
import EventKit
import Foundation
import Testing
import ZislaCore
@testable import ZislaKit

@MainActor
struct CalendarMeetingServiceTests {
    @Test
    func meetingMonitoringAndTimerQueriesLeaveTheMainThreadAvailable() async {
        let fixture = MeetingCalendarFixture()
        let probe = CalendarResponsivenessProbe()
        let service = fixture.service(queries: .live(makeStore: { MeetingEventStore(probe: probe) }))
        defer { service.stop() }
        service.start(monitorAgenda: false)
        await service.pendingMeetingRefresh?.value
        fixture.timer?.fire()
        fixture.callbacks.deliver()
        await service.pendingMeetingRefresh?.value

        #expect(probe.eventQueryMainThreads == [false, false],
                "Meeting monitoring and timer refreshes must not block the UI run loop")
    }

    @Test(arguments: ["stop", "restart", "permission", "replacement", "cancel"])
    func lateMeetingQueryCannotRestoreStoppedRevokedOrReplacedData(change: String) async throws {
        let fixture = MeetingCalendarFixture()
        let oldSnapshot = CalendarService.makeEventSnapshot(try fixture.event(id: "old"))
        let newSnapshot = CalendarService.makeEventSnapshot(try fixture.event(id: "new"))
        let gate = MeetingSleeps()
        let service = fixture.service(queries: CalendarQueryOperations(
            events: { interval, _ in
                if interval.start == oldSnapshot.startDate.addingTimeInterval(-600) {
                    await gate.sleep(.zero)
                    return [oldSnapshot]
                }
                return [newSnapshot]
            }, reminders: { _, _, completion in completion([]) }
        ))
        defer { gate.resumeAll(); service.stop() }
        let oldRefresh = service.refreshMeetings()
        for await _ in gate.started { break }
        if change == "stop" || change == "restart" { service.stop() }
        if change == "permission" { fixture.eventAccess = .denied }
        if change == "replacement" || change == "restart" {
            fixture.date = fixture.date.addingTimeInterval(1)
            if change == "restart" {
                service.start(monitorAgenda: false)
                await service.pendingMeetingRefresh?.value
            } else {
                await service.refreshMeetings().value
            }
        }
        if change == "cancel" { oldRefresh.cancel() }
        gate.resume()
        await oldRefresh.value

        let expected = change == "replacement" || change == "restart" ? [newSnapshot] : []
        #expect(service.meetingEvents == expected, "A late EventKit result must not override the current monitoring state")
        #expect(fixture.store.eventPermissionRequests == 0)
        #expect(fixture.store.reminderPermissionRequests == 0)
    }

    @Test
    func agendaQueryDropsEventSnapshotsWhenPermissionIsRevokedWhileLoading() async throws {
        let fixture = MeetingCalendarFixture()
        let snapshot = CalendarService.makeEventSnapshot(try fixture.event())
        let gate = MeetingSleeps()
        let service = fixture.service(queries: CalendarQueryOperations(
            events: { _, refreshSources in
                if refreshSources { await gate.sleep(.zero) }
                return [snapshot]
            }, reminders: { _, _, completion in completion([]) }
        ))
        defer { gate.resumeAll(); service.stop() }
        let refresh = Task { await service.refresh(referenceDate: fixture.date) }
        for await _ in gate.started { break }
        fixture.eventAccess = .denied
        gate.resume()
        await refresh.value

        #expect(service.events.isEmpty, "A suspended query must not publish event data after read permission is revoked")
        #expect(service.meetingEvents.isEmpty)
        #expect(!service.isLoading)
    }

    @Test
    func lateReminderCompletionDropsOnlyRemindersAfterPermissionIsRevoked() async throws {
        let fixture = MeetingCalendarFixture()
        let event = CalendarService.makeEventSnapshot(try fixture.event())
        let reminder = CalendarEventSnapshot(id: "reminder", title: "Reminder", startDate: fixture.date,
                                             endDate: fixture.date, isAllDay: false, calendarTitle: "Fixture", kind: .reminder)
        fixture.reminderAccess = .fullAccess
        let pendingCompletion = PendingSnapshotCompletion()
        let service = fixture.service(queries: CalendarQueryOperations(
            events: { _, _ in [event] }, reminders: { _, _, receive in
                await MainActor.run { pendingCompletion.completion = receive }
            }
        ))
        defer { service.stop() }
        await service.refresh(referenceDate: fixture.date)
        #expect(service.isLoading)
        fixture.reminderAccess = .denied
        let completeReminders = try #require(pendingCompletion.completion)
        completeReminders([reminder])
        fixture.callbacks.deliver()

        #expect(service.events == [event], "Revoking reminders must retain still-authorized event data")
        #expect(!service.isLoading)
    }

    @Test(arguments: ["cancel", "stop", "restart"], [false, true])
    func cancelledQueuedReminderQueryUnlocksLoadingAndAllowsAnotherRefresh(change: String, preloaded: Bool) async throws {
        let fixture = MeetingCalendarFixture()
        let snapshot = CalendarService.makeEventSnapshot(try fixture.event())
        let gate = MeetingSleeps()
        let service = fixture.service(queries: CalendarQueryOperations(
            events: { _, _ in [snapshot] }, reminders: { _, _, completion in
                await gate.sleep(.zero)
                guard !Task.isCancelled else { return }
                completion([])
            }
        ))
        defer { gate.resumeAll(); service.stop() }
        if preloaded { await service.refresh(referenceDate: fixture.date) }
        let previousEvents = service.events
        let previousError = service.errorDescription
        fixture.reminderAccess = .fullAccess
        let refresh = Task { await service.refresh(referenceDate: fixture.date) }
        for await _ in gate.started { break }
        #expect(service.isLoading)
        refresh.cancel()
        if change == "stop" || change == "restart" { service.stop() }
        if change == "restart" {
            service.start(monitorAgenda: false)
            await service.pendingMeetingRefresh?.value
        }
        gate.resume()
        await refresh.value

        #expect(!service.isLoading, "A cancelled reminder query must release the loading state without a completion callback")
        #expect(service.events == previousEvents, "Cancelling a query must retain the previously displayed events")
        #expect(service.errorDescription == previousError, "Cancelling a query must preserve the prior error state")
        fixture.reminderAccess = .denied
        await service.refresh(referenceDate: fixture.date)
        #expect(service.events == [snapshot], "A later refresh must recover after the cancelled reminder query")
        #expect(!service.isLoading)
    }

    @Test(arguments: [EKAuthorizationStatus.notDetermined, .denied])
    func meetingOnlyMonitoringDoesNotRequestAgendaPermissionsAfterStoreChanges(status: EKAuthorizationStatus) async {
        let fixture = MeetingCalendarFixture()
        fixture.eventAccess = status; fixture.reminderAccess = .notDetermined
        let service = fixture.service(controlAgendaSleep: true)
        defer { service.stop(); fixture.sleeps.resumeAll() }
        service.start(monitorAgenda: false)
        fixture.center.post(name: .EKEventStoreChanged, object: fixture.store)
        fixture.workspaceCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        fixture.timer?.fire()
        fixture.callbacks.deliver()
        if let refresh = service.scheduledRefresh {
            for await _ in fixture.sleeps.started { break }
            fixture.sleeps.resume()
            await refresh.value
        }
        #expect(fixture.store.queries.isEmpty)
        #expect(fixture.store.eventPermissionRequests == 0)
        #expect(fixture.store.reminderPermissionRequests == 0)
        #expect(fixture.sleeps.delays.isEmpty)
    }

    @Test
    func changingMonitoringModeCancelsAgendaRefreshAndCanResumeIt() async throws {
        let fixture = MeetingCalendarFixture()
        fixture.store.fixtures = [try fixture.event()]
        let service = fixture.service(controlAgendaSleep: true)
        defer { service.stop(); fixture.sleeps.resumeAll() }
        service.start()
        await service.pendingMeetingRefresh?.value
        fixture.center.post(name: .EKEventStoreChanged, object: fixture.store)
        fixture.callbacks.deliver()
        let oldRefresh = try #require(service.scheduledRefresh)
        for await _ in fixture.sleeps.started { break }
        service.start(monitorAgenda: false)
        fixture.eventAccess = .notDetermined; fixture.reminderAccess = .notDetermined
        fixture.sleeps.resume()
        await oldRefresh.value
        #expect(fixture.store.eventPermissionRequests == 0)
        #expect(fixture.store.reminderPermissionRequests == 0)
        service.start(monitorAgenda: true)
        fixture.center.post(name: .EKEventStoreChanged, object: fixture.store)
        fixture.callbacks.deliver()
        let newRefresh = try #require(service.scheduledRefresh)
        for await _ in fixture.sleeps.started { break }
        fixture.sleeps.resume()
        await newRefresh.value
        #expect(fixture.store.eventPermissionRequests == 1)
        #expect(fixture.store.reminderPermissionRequests == 1)
        #expect(service.errorDescription != nil)
    }

    @Test(arguments: ["stop", "restart", "meeting-only", "resume-agenda"])
    func lateDebounceCannotRequestPermissionsAfterLifecycleChange(change: String) async throws {
        let fixture = MeetingCalendarFixture()
        fixture.eventAccess = .notDetermined; fixture.reminderAccess = .notDetermined
        let service = fixture.service(controlAgendaSleep: true)
        defer { service.stop(); fixture.sleeps.resumeAll() }
        service.start()
        await service.pendingMeetingRefresh?.value
        fixture.center.post(name: .EKEventStoreChanged, object: fixture.store)
        fixture.callbacks.deliver()
        let refresh = try #require(service.scheduledRefresh)
        for await _ in fixture.sleeps.started { break }
        if change == "stop" || change == "restart" { service.stop() }
        if change == "meeting-only" || change == "resume-agenda" { service.start(monitorAgenda: false) }
        if change == "restart" || change == "resume-agenda" { service.start(); await service.pendingMeetingRefresh?.value }
        fixture.sleeps.resume()
        await refresh.value
        #expect(fixture.store.eventPermissionRequests == 0)
        #expect(fixture.store.reminderPermissionRequests == 0)
        #expect(fixture.store.queries.isEmpty)
    }

    @Test
    func replacedDebounceCannotRequestPermissionsButItsSuccessorCan() async throws {
        let fixture = MeetingCalendarFixture()
        fixture.eventAccess = .notDetermined; fixture.reminderAccess = .notDetermined
        let service = fixture.service(controlAgendaSleep: true)
        defer { service.stop(); fixture.sleeps.resumeAll() }
        service.start()
        await service.pendingMeetingRefresh?.value
        fixture.center.post(name: .EKEventStoreChanged, object: fixture.store)
        fixture.callbacks.deliver()
        let oldRefresh = try #require(service.scheduledRefresh)
        for await _ in fixture.sleeps.started { break }
        fixture.center.post(name: .EKEventStoreChanged, object: fixture.store)
        fixture.callbacks.deliver()
        let newRefresh = try #require(service.scheduledRefresh)
        for await _ in fixture.sleeps.started { break }
        fixture.sleeps.resume()
        await oldRefresh.value
        #expect(fixture.store.eventPermissionRequests == 0)
        #expect(fixture.store.reminderPermissionRequests == 0)
        fixture.sleeps.resume()
        await newRefresh.value
        #expect(fixture.store.eventPermissionRequests == 1)
        #expect(fixture.store.reminderPermissionRequests == 1)
    }

    @Test(arguments: ["stop", "restart", "meeting-only", "resume-agenda"])
    func lateReminderCompletionCannotRestartAgendaOrRequestPermissions(change: String) async {
        let fixture = MeetingCalendarFixture()
        fixture.reminderAccess = .fullAccess
        let service = fixture.service()
        defer { service.stop() }
        service.start()
        await service.pendingMeetingRefresh?.value
        await service.refresh(referenceDate: fixture.date)
        #expect(service.isLoading)
        if change == "stop" || change == "restart" { service.stop() }
        if change == "meeting-only" || change == "resume-agenda" { service.start(monitorAgenda: false) }
        if change == "restart" || change == "resume-agenda" { service.start(); await service.pendingMeetingRefresh?.value }
        fixture.eventAccess = .notDetermined; fixture.reminderAccess = .notDetermined
        let reads = fixture.store.queries.count
        fixture.store.completeReminders()
        fixture.callbacks.deliver()
        if let refresh = service.scheduledRefresh { await refresh.value }
        #expect(fixture.store.queries.count == reads)
        #expect(fixture.store.eventPermissionRequests == 0)
        #expect(fixture.store.reminderPermissionRequests == 0)
        #expect(service.events.isEmpty)
        #expect(!service.isLoading)
    }

    @Test
    func overlappingExplicitRefreshWithoutMonitoringStillLoadsTheLatestWeek() async throws {
        let fixture = MeetingCalendarFixture()
        let first = try fixture.event()
        let next = try fixture.event(id: "next-week", start: fixture.date.addingTimeInterval(21 * 86_400))
        fixture.store.fixtures = [first, next]
        fixture.reminderAccess = .fullAccess
        let service = fixture.service()
        defer { service.stop() }
        await service.refresh(referenceDate: fixture.date)
        await service.refresh(referenceDate: next.startDate)
        fixture.reminderAccess = .denied
        fixture.store.completeReminders()
        fixture.callbacks.deliver()
        let refresh = try #require(service.scheduledRefresh)
        await refresh.value
        #expect(service.events.map(\.sourceIdentifier) == ["next-week"])
        #expect(service.meetingEvents.map(\.sourceIdentifier) == ["meeting"])
        #expect(fixture.store.eventPermissionRequests == 0)
        #expect(fixture.store.reminderPermissionRequests == 0)
        #expect(!service.isLoading)
    }

    @Test(arguments: ["event", "reminder"], ["stop", "restart", "meeting-only", "resume-agenda", "cancel"])
    func latePermissionResultDoesNotResumeRefreshOrRequestAnotherPermission(kind: String, change: String) async throws {
        let fixture = MeetingCalendarFixture()
        fixture.store.fixtures = [try fixture.event()]
        fixture.eventAccess = kind == "event" ? .notDetermined : .fullAccess
        fixture.reminderAccess = .notDetermined
        fixture.store.permissionGate = fixture.sleeps
        fixture.store.controlledPermissionKind = kind
        let service = fixture.service()
        defer { service.stop(); fixture.sleeps.resumeAll() }
        service.start()
        await service.pendingMeetingRefresh?.value
        let refresh = Task { await service.refresh(referenceDate: fixture.date) }
        for await _ in fixture.sleeps.started { break }
        if change == "stop" || change == "restart" { service.stop() }
        if change == "meeting-only" || change == "resume-agenda" { service.start(monitorAgenda: false) }
        if change == "restart" || change == "resume-agenda" { service.start(); await service.pendingMeetingRefresh?.value }
        if change == "cancel" { refresh.cancel() }
        let meetings = service.meetingEvents
        let reads = fixture.store.queries.count
        fixture.eventAccess = .fullAccess; fixture.reminderAccess = .fullAccess
        fixture.sleeps.resume()
        await refresh.value
        if let scheduled = service.scheduledRefresh { await scheduled.value }
        #expect(service.meetingEvents == meetings)
        #expect(fixture.store.queries.count == reads)
        #expect(fixture.store.eventPermissionRequests == (kind == "event" ? 1 : 0))
        #expect(fixture.store.reminderPermissionRequests == (kind == "reminder" ? 1 : 0))
        #expect(!service.isLoading)
    }

    @Test(arguments: [false, true])
    func explicitPermissionActionDoesNotResumeAfterLifecycleChange(restart: Bool) async {
        let fixture = MeetingCalendarFixture()
        fixture.eventAccess = .notDetermined; fixture.reminderAccess = .notDetermined
        fixture.store.permissionGate = fixture.sleeps
        let service = fixture.service()
        defer { service.stop(); fixture.sleeps.resumeAll() }
        let permission = Task { await service.requestAccess() }
        for await _ in fixture.sleeps.started { break }
        service.stop()
        if restart { service.start(); await service.pendingMeetingRefresh?.value }
        fixture.eventAccess = .fullAccess; fixture.reminderAccess = .fullAccess
        fixture.sleeps.resume()
        await permission.value
        #expect(service.meetingEvents.isEmpty)
        #expect(fixture.store.queries.isEmpty)
        #expect(fixture.store.eventPermissionRequests == 1)
        #expect(fixture.store.reminderPermissionRequests == 0)
    }

    @Test(arguments: [EKAuthorizationStatus.notDetermined, .denied, .restricted, .writeOnly])
    func passiveMeetingMonitoringNeverRequestsOrReadsUnauthorizedEvents(status: EKAuthorizationStatus) async {
        let fixture = MeetingCalendarFixture()
        fixture.eventAccess = status
        let service = fixture.service()
        defer { service.stop() }
        service.start()
        await service.pendingMeetingRefresh?.value
        await service.refreshMeetings().value
        #expect(service.meetingEvents.isEmpty)
        #expect(fixture.store.queries.isEmpty)
        #expect(fixture.store.eventPermissionRequests == 0)
        #expect(fixture.store.reminderPermissionRequests == 0)
    }

    @Test
    func permissionRevocationClearsMeetingsAndGrantRestoresWithoutPrompt() async throws {
        let fixture = MeetingCalendarFixture()
        fixture.store.fixtures = [try fixture.event()]
        let service = fixture.service()
        defer { service.stop() }
        service.start()
        await service.pendingMeetingRefresh?.value
        #expect(service.meetingEvents.count == 1)
        fixture.eventAccess = .denied
        await service.refreshMeetings().value
        #expect(service.meetingEvents.isEmpty)
        let readsBeforeGrant = fixture.store.queries.count
        fixture.eventAccess = .fullAccess
        await service.refreshMeetings().value
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
        await service.refreshMeetings().value
        #expect(service.meetingEvents.count == 1)
        fixture.eventAccess = .denied
        await service.refresh(referenceDate: fixture.date)
        #expect(service.events.isEmpty)
        #expect(service.meetingEvents.isEmpty)
        #expect(service.errorDescription != nil)
    }

    @Test
    func resolveMeetingUsesTheCurrentLinkAfterRenamingAndRescheduling() throws {
        let fixture = MeetingCalendarFixture()
        let event = try fixture.event()
        let snapshot = CalendarService.makeEventSnapshot(event)
        event.title = "Renamed"; event.startDate = event.startDate.addingTimeInterval(3_600)
        event.endDate = event.endDate.addingTimeInterval(3_600)
        event.url = URL(string: "https://zoom.us/j/123456789")
        fixture.store.identifierEvent = event
        let service = fixture.service()
        defer { service.stop() }
        let current = try #require(service.resolveMeeting(snapshot))
        #expect(current.meetingURL == event.url)
        #expect(current.title == "Renamed")
        #expect(current.startDate == event.startDate)
        #expect(current.eventIdentity == snapshot.eventIdentity)
        #expect(fixture.store.identifierLookups == [snapshot.sourceIdentifier])
        #expect(fixture.store.queries.isEmpty)
    }

    @Test(arguments: ["deleted", "cancelled", "all-day", "ended", "unsafe-link", "wrong-calendar"])
    func staleOrIneligibleMeetingsCannotBeResolvedForJoining(reason: String) throws {
        let fixture = MeetingCalendarFixture()
        let event = try fixture.event()
        let snapshot = CalendarService.makeEventSnapshot(event)
        switch reason {
        case "cancelled": event.fixtureStatus = .canceled
        case "all-day": event.isAllDay = true
        case "ended": fixture.date = event.endDate
        case "unsafe-link": event.url = URL(string: "https://meet.google.com.attacker.test/abc-defg-hij")
        case "wrong-calendar": event.calendar = try fixture.calendar(identifier: "other")
        default: break
        }
        fixture.store.identifierEvent = reason == "deleted" ? nil : event
        fixture.store.fixtures = reason == "deleted" ? [] : [event]
        let service = fixture.service()
        defer { service.stop() }
        #expect(service.resolveMeeting(snapshot) == nil)
        #expect(fixture.store.identifierLookups == [snapshot.sourceIdentifier])
        #expect(fixture.store.eventPermissionRequests == 0)
        #expect(fixture.store.reminderPermissionRequests == 0)
    }

    @Test(arguments: [EKAuthorizationStatus.notDetermined, .denied, .restricted, .writeOnly])
    func joiningDoesNotReadOrPromptAfterCalendarPermissionIsUnavailable(status: EKAuthorizationStatus) throws {
        let fixture = MeetingCalendarFixture()
        let snapshot = CalendarService.makeEventSnapshot(try fixture.event())
        fixture.eventAccess = status
        let service = fixture.service()
        defer { service.stop() }
        #expect(service.resolveMeeting(snapshot) == nil)
        #expect(fixture.store.identifierLookups.isEmpty)
        #expect(fixture.store.queries.isEmpty)
        #expect(fixture.store.eventPermissionRequests == 0)
        #expect(fixture.store.reminderPermissionRequests == 0)
    }

    @Test(arguments: ["identity", "source"])
    func joiningWithoutTheOriginalIdentityOrSourceDoesNotReadTheStore(missing: String) throws {
        let fixture = MeetingCalendarFixture()
        var snapshot = CalendarService.makeEventSnapshot(try fixture.event())
        if missing == "identity" { snapshot.eventIdentity = nil }
        else { snapshot.sourceIdentifier = nil }
        let service = fixture.service()
        defer { service.stop() }
        #expect(service.resolveMeeting(snapshot) == nil)
        #expect(fixture.store.identifierLookups.isEmpty)
        #expect(fixture.store.queries.isEmpty)
    }

    @Test
    func repeatedOccurrenceIsResolvedByItsStableIdentityInsteadOfTheFirstEvent() throws {
        let fixture = MeetingCalendarFixture()
        let first = try fixture.event()
        first.fixtureRecurring = true; first.fixtureOccurrence = first.startDate
        let selected = try fixture.event(start: first.startDate.addingTimeInterval(86_400))
        selected.fixtureRecurring = true; selected.fixtureOccurrence = selected.startDate
        let snapshot = CalendarService.makeEventSnapshot(selected)
        let originalOccurrence = selected.startDate!
        selected.fixtureDetached = true; selected.fixtureRecurring = false
        selected.startDate = originalOccurrence.addingTimeInterval(600)
        selected.endDate = originalOccurrence.addingTimeInterval(4_200)
        selected.url = URL(string: "https://meeting.tencent.com/dm/UpdatedMeeting")
        fixture.store.identifierEvent = first
        fixture.store.fixtures = [first, selected]
        let service = fixture.service()
        defer { service.stop() }
        let current = try #require(service.resolveMeeting(snapshot))
        #expect(current.eventIdentity == snapshot.eventIdentity)
        #expect(current.eventIdentity?.occurrenceDate == originalOccurrence)
        #expect(current.meetingURL == selected.url)
        #expect(current.startDate == selected.startDate)
        #expect(fixture.store.queries.last == DateInterval(start: snapshot.startDate.addingTimeInterval(-1),
                                                           end: snapshot.endDate.addingTimeInterval(1)))
    }

    @Test
    func anUnlocatableMovedOccurrenceFailsWithoutJoiningAnotherOccurrence() throws {
        let fixture = MeetingCalendarFixture()
        let event = try fixture.event()
        event.fixtureRecurring = true; event.fixtureOccurrence = event.startDate
        let snapshot = CalendarService.makeEventSnapshot(event)
        let other = try fixture.event(start: event.startDate.addingTimeInterval(86_400))
        other.fixtureRecurring = true; other.fixtureOccurrence = other.startDate
        fixture.store.identifierEvent = other
        event.startDate = event.startDate.addingTimeInterval(3 * 86_400)
        event.endDate = event.startDate.addingTimeInterval(3_600)
        fixture.store.fixtures = [other, event]
        let service = fixture.service()
        defer { service.stop() }
        #expect(service.resolveMeeting(snapshot) == nil)
    }

    @Test
    func cancelledAndAllDayEventsAreExcludedAtTheEventKitBoundary() async throws {
        let fixture = MeetingCalendarFixture()
        let normal = try fixture.event(id: "normal")
        let cancelled = try fixture.event(id: "cancelled"); cancelled.fixtureStatus = .canceled
        let allDay = try fixture.event(id: "all-day"); allDay.isAllDay = true
        fixture.store.fixtures = [allDay, cancelled, normal]
        let service = fixture.service()
        defer { service.stop() }
        await service.refreshMeetings().value
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
    func lifecycleNotificationsRequeryAndRemoveEndedOrDeletedMeetings(name: Notification.Name) async throws {
        let fixture = MeetingCalendarFixture()
        let event = try fixture.event()
        fixture.store.fixtures = [event]
        let service = fixture.service()
        defer { service.stop() }
        service.start()
        await service.pendingMeetingRefresh?.value
        #expect(service.meetingEvents.count == 1)
        fixture.date = event.endDate
        let center = name == NSWorkspace.didWakeNotification ? fixture.workspaceCenter : fixture.center
        center.post(name: name, object: name == .EKEventStoreChanged ? fixture.store : nil)
        fixture.callbacks.deliver()
        await service.pendingMeetingRefresh?.value
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
    func queuedNotificationsCannotReviveStoppedOrRestartedMonitoring(restart: Bool) async throws {
        let fixture = MeetingCalendarFixture()
        fixture.store.fixtures = [try fixture.event()]
        let service = fixture.service()
        defer { service.stop() }
        service.start()
        await service.pendingMeetingRefresh?.value
        for name in [NSWorkspace.didWakeNotification, .NSCalendarDayChanged, .EKEventStoreChanged] {
            let center = name == NSWorkspace.didWakeNotification ? fixture.workspaceCenter : fixture.center
            center.post(name: name, object: name == .EKEventStoreChanged ? fixture.store : nil)
        }
        fixture.timer?.fire()
        service.stop()
        if restart { service.start(); await service.pendingMeetingRefresh?.value }
        let reads = fixture.store.queries.count
        fixture.store.fixtures = []
        fixture.callbacks.deliver()
        #expect(fixture.store.queries.count == reads)
        #expect(service.meetingEvents.count == (restart ? 1 : 0))
    }

    @Test
    func monitoringReadsOneBoundedDayAndDoesNotIncludeFutureWeeks() async throws {
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
        await service.pendingMeetingRefresh?.value
        service.start()
        await service.pendingMeetingRefresh?.value
        #expect(service.meetingEvents.map(\.sourceIdentifier) == ["meeting"])
        #expect(fixture.store.queries.count == 1)
        #expect(fixture.store.queries[0].duration == 86_400)
        #expect(fixture.timer?.timeInterval == 60)
        #expect(fixture.timer?.tolerance == 10)
        fixture.timer?.fire()
        fixture.callbacks.deliver()
        await service.pendingMeetingRefresh?.value
        #expect(fixture.store.queries.count == 2)
        service.stop()
        #expect(fixture.timer?.isValid == false)
    }

    @Test
    func calendarUpdateReplacesLinksAndDeduplicatesTheSameOccurrence() async throws {
        let fixture = MeetingCalendarFixture()
        let event = try fixture.event()
        fixture.store.fixtures = [event, event]
        let service = fixture.service()
        defer { service.stop() }
        service.start()
        await service.pendingMeetingRefresh?.value
        #expect(service.meetingEvents.count == 1)
        event.url = URL(string: "https://meeting.tencent.com/dm/NewMeeting")
        event.startDate = fixture.date.addingTimeInterval(1_200)
        await service.refreshMeetings().value
        #expect(service.meetingEvents.first?.meetingURL == event.url)
        #expect(service.meetingEvents.first?.startDate == event.startDate)
        fixture.store.fixtures = []
        await service.refreshMeetings().value
        #expect(service.meetingEvents.isEmpty)
    }
}

@MainActor
private final class PendingSnapshotCompletion {
    var completion: (@Sendable ([CalendarEventSnapshot]) -> Void)?
}

@MainActor
private final class MeetingCalendarFixture {
    let store = MeetingEventStore()
    let center = NotificationCenter()
    let workspaceCenter = NotificationCenter()
    let callbacks = MeetingCallbacks()
    let sleeps = MeetingSleeps()
    var timer: Timer?
    var date = Date(timeIntervalSince1970: 1_000_000)
    var eventAccess = EKAuthorizationStatus.fullAccess
    var reminderAccess = EKAuthorizationStatus.denied

    func service(controlAgendaSleep: Bool = false, queries: CalendarQueryOperations? = nil) -> CalendarService {
        CalendarService(store: store, mutations: .live(store: store), environment: CalendarServiceEnvironment(
            authorizationStatus: { [self] kind in kind == .event ? eventAccess : reminderAccess },
            now: { [self] in date }, notificationCenter: center, workspaceNotificationCenter: workspaceCenter,
            enqueue: { [callbacks] in callbacks.append($0) },
            makeTimer: { [self] action in
                let timer = Timer(timeInterval: 60, repeats: true) { _ in action() }
                self.timer = timer
                return timer
            }, sleep: { [sleeps] delay in
                if controlAgendaSleep { await sleeps.sleep(delay) }
                else { try await Task.sleep(for: delay) }
            }, authorizationPromptHost: { nil }
        ), queries: queries ?? CalendarQueryOperations(
            events: { [self] interval, refreshSources in
                await MainActor.run {
                    if refreshSources { store.refreshSourcesIfNecessary() }
                    let predicate = store.predicateForEvents(withStart: interval.start, end: interval.end, calendars: nil)
                    return store.events(matching: predicate).map(CalendarService.makeEventSnapshot)
                }
            }, reminders: { [self] interval, calendar, completion in
                await MainActor.run {
                    let predicate = store.predicateForReminders(in: nil)
                    store.fetchReminders(matching: predicate) { reminders in
                        completion(CalendarService.makeReminderSnapshots(from: reminders ?? [], calendar: calendar, dueWithin: interval))
                    }
                }
            }
        ))
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

private final class MeetingSleeps: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private var recordedDelays: [Duration] = []
    let started: AsyncStream<Void>
    private let startedContinuation: AsyncStream<Void>.Continuation

    init() {
        let stream = AsyncStream<Void>.makeStream()
        started = stream.stream; startedContinuation = stream.continuation
    }

    var delays: [Duration] { lock.withLock { recordedDelays } }

    func sleep(_ delay: Duration) async {
        await withCheckedContinuation { continuation in
            lock.withLock { continuations.append(continuation); recordedDelays.append(delay) }
            startedContinuation.yield(())
        }
    }

    func resume() {
        let pending = lock.withLock { continuations.isEmpty ? nil : continuations.removeFirst() }
        pending?.resume()
    }

    func resumeAll() {
        let pending = lock.withLock { let pending = continuations; continuations = []; return pending }
        for continuation in pending { continuation.resume() }
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
    private let probe: CalendarResponsivenessProbe?
    var fixtures: [EKEvent] = []
    var queries: [DateInterval] = []
    var identifierEvent: EKEvent?
    var identifierLookups: [String] = []
    var eventPermissionRequests = 0
    var permissionGate: MeetingSleeps?
    var controlledPermissionKind = "event"
    var reminderPermissionRequests = 0
    var reminderCompletion: (([EKReminder]?) -> Void)?
    init(probe: CalendarResponsivenessProbe? = nil) {
        self.probe = probe
        super.init()
        probe?.recordStoreCreation()
    }

    override func event(withIdentifier identifier: String) -> EKEvent? {
        identifierLookups.append(identifier)
        return identifierEvent
    }

    override func predicateForEvents(withStart start: Date, end: Date, calendars: [EKCalendar]?) -> NSPredicate {
        queries.append(DateInterval(start: start, end: end))
        return NSPredicate { value, _ in
            guard let event = value as? EKEvent else { return false }
            return event.startDate < end && event.endDate > start
        }
    }

    override func events(matching predicate: NSPredicate) -> [EKEvent] {
        probe?.recordEventQuery()
        return fixtures.filter { predicate.evaluate(with: $0) }
    }
    override func refreshSourcesIfNecessary() {}
    override func predicateForReminders(in calendars: [EKCalendar]?) -> NSPredicate { NSPredicate(value: true) }
    override func fetchReminders(matching predicate: NSPredicate, completion: @escaping ([EKReminder]?) -> Void) -> Any {
        reminderCompletion = completion
        return NSObject()
    }
    func completeReminders() {
        let completion = reminderCompletion; reminderCompletion = nil
        completion?([])
    }
    override func requestFullAccessToEvents() async throws -> Bool {
        eventPermissionRequests += 1
        if let permissionGate, controlledPermissionKind == "event" { await permissionGate.sleep(.zero) }
        return false
    }
    override func requestFullAccessToReminders() async throws -> Bool {
        reminderPermissionRequests += 1
        if let permissionGate, controlledPermissionKind == "reminder" { await permissionGate.sleep(.zero) }
        return false
    }
}
