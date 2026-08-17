import Foundation
import Testing
@testable import ZislaCore
@testable import ZislaKit

/// Verifies that focus mode changes enqueue notices recognized as compact notices.
@MainActor
struct FocusModeNoticeIntegrationTests {
    @Test
    func focusModeTransitionNoticeEnqueuesSuccessfully() {
        let queue = SideNoticeQueue(capacityPerSide: 3)

        // Simulate the transition notice shown when focus mode turns on.
        let transitionNotice = IslandNotice(
            id: "focus-transition",
            title: "工作",
            detail: "已开启",
            kind: .success,
            side: .left,
            style: .status,
            symbolName: "briefcase.fill"
        )

        queue.enqueue(transitionNotice, expiresAfter: 3)

        #expect(queue.left.count == 1)
        #expect(queue.left.first?.id == "focus-transition")
    }

    @Test
    func focusModeStatusNoticeEnqueuesSuccessfully() {
        let queue = SideNoticeQueue(capacityPerSide: 3)

        // Simulate the persistent focus mode status notices.
        let leftNotice = IslandNotice(
            id: "focus-mode-left",
            title: "工作",
            kind: .info,
            side: .left,
            style: .status,
            symbolName: "briefcase.fill"
        )
        let rightNotice = IslandNotice(
            id: "focus-mode-right",
            title: "ON",
            kind: .success,
            side: .right,
            style: .status
        )

        queue.enqueue(leftNotice, expiresAfter: nil)
        queue.enqueue(rightNotice, expiresAfter: nil)

        #expect(queue.left.count == 1)
        #expect(queue.right.count == 1)
        #expect(queue.left.first?.id == "focus-mode-left")
        #expect(queue.right.first?.id == "focus-mode-right")
    }

    @Test
    func focusTransitionNoticeIsRecognizedAsCompactNotice() {
        let transitionNotice = IslandNotice(
            id: "focus-transition",
            title: "工作",
            detail: "已开启",
            kind: .success,
            side: .left,
            style: .status,
            symbolName: "briefcase.fill"
        )

        let engine = SideNoticeLayoutEngine()
        let presentation = engine.presentation(for: [transitionNotice])

        // A focus-transition notice is recognized as compact.
        #expect(presentation.hasCompactContent)
        #expect(presentation.panelSize == CGSize(width: 40, height: 34))
    }

    @Test
    func focusModeNoticeIsRecognizedAsCompactNotice() {
        let focusModeNotice = IslandNotice(
            id: "focus-mode-left",
            title: "工作",
            kind: .info,
            side: .left,
            style: .status,
            symbolName: "briefcase.fill"
        )

        let engine = SideNoticeLayoutEngine()
        let presentation = engine.presentation(for: [focusModeNotice])

        // Notices with the focus-mode- prefix are recognized as compact.
        #expect(presentation.hasCompactContent)
        #expect(presentation.activeFocusModeNotice?.id == "focus-mode-left")
    }

    @Test
    func focusModeNoticeRemainsVisibleWithAlwaysDuration() {
        let notices = [
            IslandNotice(
                id: "focus-mode-left",
                title: "工作",
                kind: .info,
                side: .left,
                style: .status,
                symbolName: "briefcase.fill"
            ),
        ]

        let mustRemain = CompactStatusVisibilityPolicy.mustRemainVisible(
            notices: notices,
            activityDuration: .threeSeconds,
            focusDuration: .always
        )

        #expect(mustRemain)
    }

    @Test
    func focusModeNoticeDoesNotRemainVisibleWithThreeSecondsDuration() {
        let notices = [
            IslandNotice(
                id: "focus-mode-left",
                title: "工作",
                kind: .info,
                side: .left,
                style: .status,
                symbolName: "briefcase.fill"
            ),
        ]

        let mustRemain = CompactStatusVisibilityPolicy.mustRemainVisible(
            notices: notices,
            activityDuration: .threeSeconds,
            focusDuration: .threeSeconds
        )

        #expect(!mustRemain)
    }
}
