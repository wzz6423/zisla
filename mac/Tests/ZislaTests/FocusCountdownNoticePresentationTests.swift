import Foundation
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

struct FocusCountdownNoticePresentationTests {
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
