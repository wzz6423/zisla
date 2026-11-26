import Foundation
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

struct FocusCountdownNoticePresentationTests {
    @Test @MainActor
    func reorderingAndCancelingCountdownsRefreshesBothSidesWithoutLeavingStaleControls() throws {
        let suite = "FocusCountdownNoticePresentation.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let pomodoro = PomodoroService(notificationRequestHandler: { _ in }, defaults: defaults)
        defer { pomodoro.stop() }
        let queue = SideNoticeQueue()
        defer { queue.removeAll() }
        let first = pomodoro.addCountdown(name: "Tea", duration: 30)
        let second = pomodoro.addCountdown(name: "Meeting", duration: 60)
        pomodoro.toggleCountdown(id: first)
        pomodoro.toggleCountdown(id: second)
        AppModel.refreshFocusCountdownNotices(for: pomodoro, in: queue)
        #expect(queue.left.count == 2 && queue.right.count == 2)
        #expect(SideNoticeLayoutEngine.orderedFocusCountdownNotices(for: queue.left + queue.right).map(\.title) == ["Tea", "Meeting"])
        pomodoro.toggleCountdown(id: first)
        AppModel.refreshFocusCountdownNotices(for: pomodoro, in: queue)
        #expect(SideNoticeLayoutEngine.orderedFocusCountdownNotices(for: queue.left + queue.right).map(\.title) == ["Meeting", "Tea"])
        pomodoro.renameCountdown(id: second, name: "Call")
        AppModel.refreshFocusCountdownNotices(for: pomodoro, in: queue)
        #expect(SideNoticeLayoutEngine.orderedFocusCountdownNotices(for: queue.left + queue.right).first?.title == "Call")
        pomodoro.cancelCountdown(id: second)
        AppModel.refreshFocusCountdownNotices(for: pomodoro, in: queue)
        #expect(queue.left.count == 1 && queue.right.count == 1)
        #expect(queue.left.first?.metadata?["timerID"] == first.uuidString)
        pomodoro.cancelCountdown(id: first)
        AppModel.refreshFocusCountdownNotices(for: pomodoro, in: queue)
        #expect(queue.left.isEmpty && queue.right.isEmpty)
    }

    @Test @MainActor
    func pausingWithinTheDisplayedSecondRefreshesProgressAndResumingReplacesBothNotices() throws {
        let suiteName = "FocusCountdownNoticePresentation.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var now = Date(timeIntervalSince1970: 10_000)
        let pomodoro = PomodoroService(notificationRequestHandler: { _ in }, defaults: defaults, now: { now })
        defer { pomodoro.stop() }
        let queue = SideNoticeQueue()
        defer { queue.removeAll() }
        pomodoro.setFocusDuration(100)
        pomodoro.start()
        now += 25
        AppModel.refreshFocusCountdownNotices(for: pomodoro, in: queue)
        let running = try #require(queue.left.first)
        #expect(running.detail == "00:01:15" && running.progress == 0.25)
        now += 0.1
        pomodoro.pause()
        AppModel.refreshFocusCountdownNotices(for: pomodoro, in: queue)
        let paused = try #require(queue.left.first)
        #expect(paused.id == running.id && paused.detail == running.detail)
        #expect(try #require(paused.progress) > 0.25,
                "Pausing must freeze the actual elapsed fraction even when the clock text has not changed")
        #expect(queue.right.first?.progress == paused.progress)
        now += 1_000
        AppModel.refreshFocusCountdownNotices(for: pomodoro, in: queue)
        #expect(queue.left.first == paused)
        pomodoro.start()
        AppModel.refreshFocusCountdownNotices(for: pomodoro, in: queue)
        #expect(queue.left.count == 1 && queue.right.count == 1)
        #expect(queue.left.first?.id != running.id && queue.right.first?.id == pomodoro.focusCountdownNoticeID(for: .right))
        #expect(queue.left.first?.progress == paused.progress)
    }

    @Test @MainActor
    func runningRestCountdownIsEligibleForIslandPresentation() {
        #expect(AppModel.shouldPresentPomodoroCountdown(
            mode: .focus,
            phase: .running,
            isScreenCleaning: false,
            isKeyboardCleaning: false
        ))
        #expect(AppModel.shouldPresentPomodoroCountdown(
            mode: .rest,
            phase: .running,
            isScreenCleaning: false,
            isKeyboardCleaning: false
        ))
        #expect(AppModel.shouldPresentPomodoroCountdown(
            mode: .rest,
            phase: .paused,
            isScreenCleaning: false,
            isKeyboardCleaning: false
        ))
        #expect(!AppModel.shouldPresentPomodoroCountdown(
            mode: .rest,
            phase: .running,
            isScreenCleaning: true,
            isKeyboardCleaning: false
        ))
    }

    @Test(arguments: [PomodoroMode.focus, .rest], [PomodoroPhase.idle, .running, .paused]) @MainActor
    func countdownStaysAvailableUntilResetAndCleaningAlwaysSuppressesIt(
        mode: PomodoroMode, phase: PomodoroPhase
    ) {
        for screenCleaning in [false, true] {
            for keyboardCleaning in [false, true] {
                #expect(AppModel.shouldPresentPomodoroCountdown(
                    mode: mode, phase: phase,
                    isScreenCleaning: screenCleaning, isKeyboardCleaning: keyboardCleaning
                ) == (phase != .idle && !screenCleaning && !keyboardCleaning),
                "Only an active, unobstructed Pomodoro may expose its countdown controls")
            }
        }
    }
}
