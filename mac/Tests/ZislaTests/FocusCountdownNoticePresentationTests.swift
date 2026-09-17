import Foundation
import Testing
import ZislaKit

@testable import Zisla

struct FocusCountdownNoticePresentationTests {
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
        #expect(!AppModel.shouldPresentPomodoroCountdown(
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

    @Test
    func restartedFocusCountdownUsesRunScopedNoticeIDsAndClearsStaleRuns() throws {
        let source = try appModelSource()

        #expect(source.contains("id: pomodoro.focusCountdownNoticeID(for: .left)"))
        #expect(source.contains("id: pomodoro.focusCountdownNoticeID(for: .right)"))
        #expect(source.contains("except: Set(notices.map(\\.id))"))
        #expect(source.contains("notices.removeAll(withIDPrefix: focusCountdownNoticePrefix)"))
    }

    private func appModelSource() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Zisla/AppModel.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }
}
