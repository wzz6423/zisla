import Foundation
import Testing
import ZislaCore
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

    @Test(arguments: IslandEdge.allCases, ["visible", "hidden", "information-disabled", "notices-disabled"])
    func meetingMouseEventsFollowTheRenderedInformationRow(edge: IslandEdge, state: String) throws {
        let icons = [IslandStatusIcon(id: "cpu", content: .metric(.cpu, text: "31%", image: nil,
            style: .detailed), tooltip: "CPU")]
        var settings = FeatureSettings(islandLayoutStyle: .pill,
            islandPlacement: IslandPlacement(mode: .custom, edge: edge))
        settings.sideNoticesEnabled = state != "notices-disabled"
        settings.islandShowMoreInformation = state != "information-disabled"
        let notice = IslandNotice(id: MeetingCountdown.noticePrefix + "mouse", title: "Meeting", detail: "05:00",
            metadata: ["eventID": "fixture"])
        let information = FloatingIslandInformationLayout(notices: state == "hidden" ? [] : [notice],
            icons: icons, settings: settings, item: nil, at: Date(timeIntervalSince1970: 1_000_000))
        if state == "visible" {
            let row = try #require(information?.primary.first)
            #expect(row.presentation.priority == .meeting && row.presentation.notice.metadata?["eventID"] == "fixture")
        } else {
            #expect(information?.primary.isEmpty ?? true)
        }
        #expect(SideNoticePresenter.compactPanelIgnoresMouseEvents(statusIcons: icons, information: information)
            == (state != "visible"), "Only a rendered meeting button may receive the monitor panel's mouse events")
    }

    @Test(arguments: ["focus-countdown-mouse", "ai-active-mouse"])
    func mousePolicyPreservesPomodoroControlsAndPassiveActivity(id: String) throws {
        let icons = [IslandStatusIcon(id: "cpu", content: .metric(.cpu, text: "31%", image: nil,
            style: .detailed), tooltip: "CPU")]
        let settings = FeatureSettings(islandLayoutStyle: .pill,
            islandPlacement: IslandPlacement(mode: .custom, edge: .top))
        let information = try #require(FloatingIslandInformationLayout(
            notices: [IslandNotice(id: id, title: "Fixture", detail: "00:12:30")],
            icons: icons, settings: settings, item: nil, at: Date(timeIntervalSince1970: 1_000_000)))
        #expect(SideNoticePresenter.compactPanelIgnoresMouseEvents(statusIcons: icons, information: information)
            == !id.hasPrefix("focus-countdown-"))
        #expect(!SideNoticePresenter.compactPanelIgnoresMouseEvents(statusIcons: [], information: information))
        #expect(SideNoticePresenter.compactPanelIgnoresMouseEvents(statusIcons: icons, information: nil))
    }

    private func event() -> CalendarEventSnapshot {
        CalendarEventSnapshot(id: "fixture", title: "Meeting", startDate: Date(timeIntervalSince1970: 1_000_600),
            endDate: Date(timeIntervalSince1970: 1_004_200), isAllDay: false, calendarTitle: "Work",
            eventURL: URL(string: "https://meet.google.com/abc-defg-hij"))
    }
}
