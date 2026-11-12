import Foundation
import Testing
import ZislaCore
@testable import ZislaKit

struct MeetingWorkflowTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func event(_ id: String, start: Double = 600, end: Double = 4_200) -> CalendarEventSnapshot {
        CalendarEventSnapshot(id: id, title: id, startDate: now.addingTimeInterval(start),
            endDate: now.addingTimeInterval(end), isAllDay: false, calendarTitle: "Work",
            eventURL: URL(string: "https://meet.google.com/abc-defg-hij"),
            eventIdentity: CalendarEventIdentity(calendarIdentifier: "work", eventIdentifier: id))
    }

    @Test
    func cancelledDeclinedAllDayRemindersEndedAndMissingLinksAreFiltered() {
        let valid = event("valid")
        var cancelled = event("cancelled"); cancelled.isCancelled = true
        var declined = event("declined"); declined.isDeclined = true
        var allDay = event("all-day"); allDay.isAllDay = true
        var reminder = event("reminder"); reminder.kind = .reminder
        let ended = event("ended", start: -3_600, end: 0)
        var missing = event("missing"); missing.eventURL = nil
        var unsafe = event("unsafe"); unsafe.eventURL = URL(string: "http://meet.google.com/abc-defg-hij")
        let invalidRange = event("invalid", start: 600, end: 600)
        var invalidDate = event("nonfinite"); invalidDate.endDate = Date(timeIntervalSince1970: .infinity)
        var invalidStart = event("nonfinite-start"); invalidStart.startDate = Date(timeIntervalSince1970: -.infinity)
        #expect(MeetingWorkflow.meetings(in: [cancelled, declined, allDay, reminder, ended, missing, unsafe, invalidRange, invalidDate, invalidStart, valid], at: now) == [valid])
        #expect(MeetingWorkflow.meetings(in: [], at: now).isEmpty)
    }

    @Test
    func currentMeetingUsesAnAbsoluteHalfOpenTimeRange() {
        let item = event("meeting")
        #expect(MeetingWorkflow.currentMeeting(in: [item], at: item.startDate.addingTimeInterval(-0.001)) == nil)
        #expect(MeetingWorkflow.currentMeeting(in: [item], at: item.startDate) == item)
        #expect(MeetingWorkflow.currentMeeting(in: [item], at: item.endDate.addingTimeInterval(-0.001)) == item)
        #expect(MeetingWorkflow.currentMeeting(in: [item], at: item.endDate) == nil)
        #expect(MeetingWorkflow.currentMeeting(in: [item], at: item.endDate.addingTimeInterval(86_400)) == nil)
    }

    @Test
    func overlappingMeetingsAndDuplicateRowsAreSelectedDeterministically() {
        let current = event("current", start: -60, end: 3_600)
        let second = event("second", start: 0, end: 1_800)
        let future = event("future", start: 600, end: 4_200)
        var duplicate = current; duplicate.id = "duplicate"
        #expect(MeetingWorkflow.meetings(in: [future, duplicate, second, current], at: now).map(\.id) == ["current", "second", "future"])
        #expect(MeetingWorkflow.currentMeeting(in: [future, second, current], at: now) == current)
        #expect(MeetingWorkflow.nextMeeting(in: [future, second, current], at: now) == current)
        var noIdentity = current; noIdentity.eventIdentity = nil
        #expect(MeetingWorkflow.meetings(in: [noIdentity, noIdentity], at: now) == [noIdentity])
    }

    @Test
    func calendarAndOriginalOccurrenceSeparateEventsWithTheSameServerIdentifier() {
        let first = event("meeting")
        var otherCalendar = first; otherCalendar.id = "other-calendar"
        otherCalendar.eventIdentity?.calendarIdentifier = "personal"
        var repeated = first; repeated.id = "next-occurrence"
        repeated.eventIdentity?.occurrenceDate = now.addingTimeInterval(86_400)
        #expect(MeetingWorkflow.meetings(in: [repeated, first, otherCalendar], at: now).count == 3)
    }

    @Test
    func overnightAndDSTEventsAreIndependentOfDisplayTimeZone() throws {
        let start = try #require(ISO8601DateFormatter().date(from: "2026-11-01T01:30:00-07:00"))
        let end = try #require(ISO8601DateFormatter().date(from: "2026-11-01T01:30:00-08:00"))
        var item = event("dst"); item.startDate = start; item.endDate = end
        #expect(MeetingWorkflow.currentMeeting(in: [item], at: start.addingTimeInterval(1_800)) == item)
        let overnightStart = try #require(ISO8601DateFormatter().date(from: "2026-11-10T23:55:00+08:00"))
        item.startDate = overnightStart; item.endDate = overnightStart.addingTimeInterval(1_800)
        #expect(MeetingWorkflow.currentMeeting(in: [item], at: overnightStart.addingTimeInterval(900)) == item)
    }
}
