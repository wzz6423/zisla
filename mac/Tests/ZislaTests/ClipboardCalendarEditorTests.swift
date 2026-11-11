import AppKit
import EventKit
import Foundation
import Testing
@testable import Zisla
import ZislaCore
@testable import ZislaKit

@MainActor
struct ClipboardCalendarEditorTests {
    @Test func cancellationNeverWritesCalendar() throws {
        let recorder = DraftMutationRecorder()
        let service = CalendarService(store: EKEventStore(), mutations: recorder.commands)
        defer { service.stop() }
        for response in [NSApplication.ModalResponse.alertSecondButtonReturn, .abort, .cancel] {
            try CalendarItemEditor.complete(response: response, calendar: service, draft: draft, kind: .event)
        }
        #expect(recorder.savedDraft == nil)
        #expect(recorder.savedReminder == nil)
    }
    @Test func confirmationPreservesEditedFields() throws {
        let recorder = DraftMutationRecorder()
        let service = CalendarService(store: EKEventStore(), mutations: recorder.commands)
        defer { service.stop() }
        try CalendarItemEditor.complete(response: .alertFirstButtonReturn, calendar: service, draft: draft, kind: .event)
        #expect(recorder.savedDraft == draft)
    }
    @Test func invalidEditsAndPermissionFailureDoNotClaimSuccess() throws {
        let recorder = DraftMutationRecorder()
        let service = CalendarService(store: EKEventStore(), mutations: recorder.commands)
        defer { service.stop() }
        var invalid = draft; invalid.endDate = invalid.startDate
        #expect(throws: CalendarMutationError.invalidDateRange) {
            try CalendarItemEditor.complete(response: .alertFirstButtonReturn, calendar: service, draft: invalid, kind: .event)
        }
        #expect(recorder.savedDraft == nil)
        recorder.failure = .calendarUnavailable
        #expect(throws: CalendarMutationError.calendarUnavailable) {
            try CalendarItemEditor.complete(response: .alertFirstButtonReturn, calendar: service, draft: draft, kind: .event)
        }
        #expect(recorder.savedDraft == nil)
    }
    @Test func existingRemindersStillSave() throws {
        let recorder = DraftMutationRecorder()
        let service = CalendarService(store: EKEventStore(), mutations: recorder.commands)
        defer { service.stop() }
        try CalendarItemEditor.complete(response: .alertFirstButtonReturn, calendar: service, draft: draft, kind: .reminder)
        #expect(recorder.savedDraft == nil)
        #expect(recorder.savedReminder == draft.title)
    }
    @Test func allDayKeepsExclusiveEndAndNormalizesSameDay() throws {
        let recorder = DraftMutationRecorder()
        let service = CalendarService(store: EKEventStore(), mutations: recorder.commands)
        defer { service.stop() }
        var value = draft; value.isAllDay = true
        value.startDate = Calendar.current.startOfDay(for: value.startDate)
        value.endDate = Calendar.current.date(byAdding: .day, value: 1, to: value.startDate)!
        try CalendarItemEditor.complete(response: .alertFirstButtonReturn, calendar: service, draft: value, kind: .event)
        #expect(recorder.savedDraft == value)
        value.endDate = value.startDate
        try CalendarItemEditor.complete(response: .alertFirstButtonReturn, calendar: service, draft: value, kind: .event)
        #expect(recorder.savedDraft?.endDate == Calendar.current.date(byAdding: .day, value: 1, to: value.startDate))
    }

    @Test(arguments: [false, true])
    func clipboardInviteBecomesAJoinableCalendarMeetingOnlyAfterConfirmation(confirm: Bool) throws {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let now = try #require(utc.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 8, minute: 55)))
        let invite = "Meeting 2026-11-10 09:00-10:00\nSubject: Workflow review\nLocation: Room A\nJoin: https://meet.google.com/abc-defg-hij"
        let detection = try #require(ClipboardAssistantDetector.detect(text: invite, enabledKinds: [.meeting],
            systemLanguageIdentifier: "en", now: now, timeZone: utc.timeZone, locale: Locale(identifier: "en_US")))
        let action = try #require(detection.actions.first)
        guard case .editCalendarEvent(let draft) = action else {
            Issue.record("Meeting detection did not produce a calendar draft")
            return
        }
        #expect(draft.notes == invite)
        let store = ClipboardInviteEventStore()
        store.savedCalendar = try #require(EKCalendar.perform(NSSelectorFromString("calendarWithEventStore:"),
            with: store)?.takeUnretainedValue() as? EKCalendar)
        store.savedCalendar?.title = "Fixture"
        let service = CalendarService(store: store, mutations: .live(store: store),
            environment: CalendarServiceEnvironment(authorizationStatus: { _ in .fullAccess }, now: { now },
                notificationCenter: NotificationCenter(), workspaceNotificationCenter: NotificationCenter()))
        defer { service.stop() }
        try CalendarItemEditor.complete(response: confirm ? .alertFirstButtonReturn : .alertSecondButtonReturn,
            calendar: service, draft: draft, kind: .event)
        service.refreshMeetings()
        if confirm {
            let meeting = try #require(service.meetingEvents.first)
            #expect(store.savedEvents.count == 1)
            #expect(meeting.notes == invite)
            #expect(meeting.title == draft.title)
            #expect(meeting.location == "Room A")
            #expect(meeting.startDate == draft.startDate && meeting.endDate == draft.endDate)
            #expect(meeting.meetingURL == URL(string: "https://meet.google.com/abc-defg-hij"))
        } else {
            #expect(store.savedEvents.isEmpty)
            #expect(service.meetingEvents.isEmpty)
        }
    }

    @Test(arguments: [false, true])
    func creatingALinklessMeetingPublishesTheCalendarMeetingOnlyAfterConfirmation(confirm: Bool) throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let draft = ClipboardCalendarDraft(title: "会议", startDate: now.addingTimeInterval(60),
            endDate: now.addingTimeInterval(3_660), location: "Room A", notes: "Agenda")
        let store = ClipboardInviteEventStore()
        store.savedCalendar = try #require(EKCalendar.perform(NSSelectorFromString("calendarWithEventStore:"),
            with: store)?.takeUnretainedValue() as? EKCalendar)
        store.savedCalendar?.title = "Fixture"
        let service = CalendarService(store: store, mutations: .live(store: store),
            environment: CalendarServiceEnvironment(authorizationStatus: { _ in .fullAccess }, now: { now },
                notificationCenter: NotificationCenter(), workspaceNotificationCenter: NotificationCenter()))
        defer { service.stop() }
        try CalendarItemEditor.complete(response: confirm ? .alertFirstButtonReturn : .alertSecondButtonReturn,
            calendar: service, draft: draft, kind: .event)
        service.refreshMeetings()
        if confirm {
            let meeting = try #require(service.meetingEvents.first,
                "A meeting created in Zisla must remain eligible without a join link")
            #expect(store.savedEvents.count == 1)
            #expect(meeting.title == draft.title && meeting.notes == draft.notes && meeting.location == draft.location)
            #expect(meeting.startDate == draft.startDate && meeting.endDate == draft.endDate)
            #expect(meeting.meetingURL == nil)
            #expect(!AgendaModuleView.isJoinableMeeting(meeting, at: now))
        } else {
            #expect(store.savedEvents.isEmpty && service.meetingEvents.isEmpty)
        }
    }

    var draft: ClipboardCalendarDraft {
        ClipboardCalendarDraft(title: "Review", startDate: Date(timeIntervalSince1970: 1_000),
            endDate: Date(timeIntervalSince1970: 4_600), location: "Room A", notes: "https://example.com/meeting")
    }
}
@MainActor
private final class DraftMutationRecorder {
    var savedDraft: ClipboardCalendarDraft?
    var savedReminder: String?
    var failure: CalendarMutationError?
    var commands: CalendarMutationCommands {
        CalendarMutationCommands(
            createEvent: { [self] title, start, end, allDay, location, notes in
                if let failure { throw failure }
                savedDraft = ClipboardCalendarDraft(title: title, startDate: start, endDate: end,
                    isAllDay: allDay, location: location, notes: notes)
            },
            createReminder: { [self] title, _, _ in savedReminder = title },
            delete: { _, _, _ in }, setReminderCompleted: { _, _ in })
    }
}

private final class ClipboardInviteEventStore: EKEventStore {
    var savedCalendar: EKCalendar?
    var savedEvents: [EKEvent] = []
    override var defaultCalendarForNewEvents: EKCalendar? { savedCalendar }
    override func save(_ event: EKEvent, span: EKSpan, commit: Bool) throws { savedEvents.append(event) }
    override func predicateForEvents(withStart start: Date, end: Date, calendars: [EKCalendar]?) -> NSPredicate {
        NSPredicate { value, _ in
            guard let event = value as? EKEvent else { return false }
            return event.startDate < end && event.endDate > start
        }
    }
    override func events(matching predicate: NSPredicate) -> [EKEvent] { savedEvents.filter { predicate.evaluate(with: $0) } }
}
