import Foundation
import Testing
import ZislaKit
@testable import Zisla

@MainActor
struct MeetingJoinActionTests {
    @Test
    func joiningUsesTheRevalidatedLinkAndOpensItExactlyOnce() {
        let original = event()
        var updated = original
        updated.eventURL = URL(string: "https://zoom.us/j/123456789")
        var resolved: [CalendarEventSnapshot] = []
        var opened: [URL] = []
        #expect(MeetingJoinAction.perform(original, resolve: {
            resolved.append($0); return updated
        }, open: { opened.append($0); return true }) == .opened)
        #expect(resolved == [original])
        #expect(opened == [updated.meetingURL])
    }

    @Test(arguments: [false, true])
    func unavailableOrUnsupportedRevalidatedMeetingsNeverOpenAURL(unsupported: Bool) {
        var current = event()
        current.eventURL = URL(string: "https://example.com/meeting")
        var opens = 0
        let result = MeetingJoinAction.perform(event(), resolve: { _ in unsupported ? current : nil },
            open: { _ in opens += 1; return true })
        #expect(result == .unavailable)
        #expect(opens == 0)
    }

    @Test
    func anOpenerFailureIsReportedWithoutRetryingOrClaimingTheMeetingWasJoined() {
        let current = event()
        var opens = 0
        #expect(MeetingJoinAction.perform(current, resolve: { $0 }, open: { _ in
            opens += 1; return false
        }) == .failed)
        #expect(opens == 1)
    }

    @Test
    func agendaJoinVisibilityUsesTheSameMeetingValidation() {
        let date = Date(timeIntervalSince1970: 1_000_000)
        var current = event()
        #expect(AgendaModuleView.isJoinableMeeting(current, at: date))
        #expect(!AgendaModuleView.isJoinableMeeting(current, at: current.endDate))
        current.isCancelled = true
        #expect(!AgendaModuleView.isJoinableMeeting(current, at: date))
        current.isCancelled = false; current.kind = .reminder
        #expect(!AgendaModuleView.isJoinableMeeting(current, at: date))
    }

    private func event() -> CalendarEventSnapshot {
        CalendarEventSnapshot(id: "fixture", title: "Meeting", startDate: Date(timeIntervalSince1970: 1_000_600),
            endDate: Date(timeIntervalSince1970: 1_004_200), isAllDay: false, calendarTitle: "Work",
            eventURL: URL(string: "https://meet.google.com/abc-defg-hij"))
    }
}
