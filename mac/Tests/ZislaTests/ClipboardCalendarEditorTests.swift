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
            delete: { _, _ in }, setReminderCompleted: { _, _ in })
    }
}
