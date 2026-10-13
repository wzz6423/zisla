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

}
