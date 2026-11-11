import AppKit
import Combine
import Foundation
import Testing
import UserNotifications
import ZislaCore

@testable import Zisla
@testable import ZislaKit

@MainActor
struct NotificationDisplaySelectionTests {
    private let quiet = ScreenSnapshot(displayID: 7,
        frame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
        visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 876), notificationPolicyIdentifier: "quiet")
    private let showing = ScreenSnapshot(displayID: 8,
        frame: CGRect(x: 1_440, y: 0, width: 1_440, height: 900),
        visibleFrame: CGRect(x: 1_440, y: 0, width: 1_440, height: 876), notificationPolicyIdentifier: "showing")

    @Test(arguments: ["stopped", "disconnected", "active-quiet", "active-showing"])
    func currentDisplayOverrideControlsRealPomodoroCompletionWhenTheCoordinatorStops(state: String) throws {
        let suiteName = "Zisla.NotificationDisplay.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let coordinator = OverlayCoordinator(contentView: NSView())
        defer { coordinator.stop() }
        coordinator.updateScreens([quiet, showing], repositionVisiblePanel: false, refreshPersistentPanels: false)
        coordinator.selectActiveDisplay(at: .init(x: quiet.frame.midX, y: quiet.frame.midY))
        var screens = [quiet, showing]
        var pointer = CGPoint(x: showing.frame.midX, y: showing.frame.midY)
        switch state {
        case "stopped":
            coordinator.stop()
            #expect(coordinator.activeDisplayID == nil && !coordinator.isRunning)
        case "disconnected":
            screens = [showing]
            #expect(coordinator.activeDisplayID == quiet.displayID,
                "The callback can still hold the old active ID before the screen-change handler runs")
        case "active-showing":
            coordinator.selectActiveDisplay(at: pointer)
            pointer = CGPoint(x: quiet.frame.midX, y: quiet.frame.midY)
        default:
            break
        }
        let expected = state == "active-quiet" ? "quiet" : "showing"
        let queue = SideNoticeQueue()
        defer { queue.removeAll() }
        queue.configureNotificationScenarios(.init(enabled: true,
            displayOverrides: ["showing": .init(meeting: .init(ordinary: .show))]),
            displayIdentifiers: Set(screens.map(\.notificationScopeIdentifier)))
        queue.setNotificationScenario(.meeting, active: true)
        var now = Date(timeIntervalSince1970: 10_000)
        var sounds = 0
        var requests: [UNNotificationRequest] = []
        var suppressed: [UserCareReminder] = []
        var selected: String?
        let pomodoro = PomodoroService(notificationRequestHandler: { requests.append($0) }, defaults: defaults,
            completionSoundHandler: { sounds += 1 }, language: { .english }, now: { now })
        defer { pomodoro.stop() }
        pomodoro.setFocusDuration(1)
        pomodoro.completionPresentationAllowed = {
            selected = AppDelegate.notificationDisplayIdentifier(activeDisplayID: coordinator.activeDisplayID,
                screens: screens, pointerLocation: pointer, configuration: ScreenLayoutConfiguration())
            return queue.notificationBehavior(for: .ordinary, displayIdentifier: selected) == .show
        }
        pomodoro.onSuppressedCompletion = { suppressed.append($0) }

        pomodoro.start()
        now += pomodoro.focusDuration
        pomodoro.tick()

        #expect(selected == expected)
        #expect(sounds == (expected == "showing" ? 1 : 0))
        #expect(requests.count == (expected == "showing" ? 1 : 0))
        #expect(suppressed == (expected == "showing" ? [] : [.focusCompleted]))
        pomodoro.tick()
        #expect(sounds == (expected == "showing" ? 1 : 0), "Re-evaluating an idle countdown must not duplicate its completion")
        #expect(requests.count == (expected == "showing" ? 1 : 0))
    }

    @Test
    func anUnknownUUIDUsesTheSelectedSessionScopeAndEmptyScreensReturnNil() {
        let unknown = ScreenSnapshot(displayID: .max,
            frame: CGRect(x: 1_440, y: 0, width: 1_440, height: 900),
            visibleFrame: CGRect(x: 1_440, y: 0, width: 1_440, height: 876))
        #expect(ScreenSnapshot.notificationPolicyIdentifier(for: unknown.displayID) == nil)
        let configuration = ScreenLayoutConfiguration(layoutStyle: .pill,
            placement: IslandPlacement(mode: .custom, edge: .left))
        #expect(AppDelegate.notificationDisplayIdentifier(activeDisplayID: nil, screens: [quiet, unknown],
            pointerLocation: .init(x: unknown.frame.midX, y: unknown.frame.midY), configuration: configuration) == "session:4294967295")
        #expect(AppDelegate.notificationDisplayIdentifier(activeDisplayID: 99, screens: [quiet, unknown],
            pointerLocation: .init(x: -10_000, y: -10_000), configuration: configuration) == "quiet")
        #expect(AppDelegate.notificationDisplayIdentifier(activeDisplayID: unknown.displayID, screens: [],
            pointerLocation: .zero, configuration: configuration) == nil)
    }
}
