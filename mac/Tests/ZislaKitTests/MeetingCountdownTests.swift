import Foundation
import Testing
import ZislaCore
@testable import ZislaKit

struct MeetingCountdownTests {
    @Test
    func countdownRoundsUpFractionsAndDoesNotBecomeNegative() {
        let event = fixture()
        #expect(MeetingCountdown.clock(for: event, at: event.startDate.addingTimeInterval(-600)) == "10:00")
        #expect(MeetingCountdown.clock(for: event, at: event.startDate.addingTimeInterval(-59.2)) == "01:00")
        #expect(MeetingCountdown.clock(for: event, at: event.startDate.addingTimeInterval(-0.2)) == "00:01")
        #expect(MeetingCountdown.clock(for: event, at: event.startDate) == "00:00")
        #expect(MeetingCountdown.clock(for: event, at: event.startDate.addingTimeInterval(60)) == "00:00")
    }

    @Test(arguments: [AppLanguage.simplifiedChinese, .english, .arabic])
    func pairedNoticesContainOnlyTheLookupIDAndSwitchAtTheStartBoundary(language: AppLanguage) throws {
        let event = fixture()
        let before = MeetingCountdown.notices(for: event, at: event.startDate.addingTimeInterval(-60), locale: language.locale)
        #expect(before.map(\.detail) == ["01:00", "01:00"])
        #expect(before.map(\.side) == [.left, .right])
        #expect(Set(before.map(\.id)).count == 2)
        for notice in before {
            #expect(notice.id.hasPrefix(MeetingCountdown.noticePrefix))
            #expect(notice.title == event.title)
            #expect(notice.metadata == ["eventID": event.id])
            #expect(notice.createdAt == event.startDate)
        }
        let ongoing = MeetingCountdown.notices(for: event, at: event.startDate, locale: language.locale)
        #expect(ongoing.map(\.id) == before.map(\.id))
        #expect(ongoing.map(\.detail) == Array(repeating: AppLocalization.string("会议进行中", locale: language.locale), count: 2))
    }

    private func fixture() -> CalendarEventSnapshot {
        CalendarEventSnapshot(id: "event", title: "Team", startDate: Date(timeIntervalSince1970: 1_000),
            endDate: Date(timeIntervalSince1970: 4_600), isAllDay: false, calendarTitle: "Work",
            eventURL: URL(string: "https://zoom.us/j/123456789?pwd=PrivateFixture"), notes: "Private notes")
    }
}
