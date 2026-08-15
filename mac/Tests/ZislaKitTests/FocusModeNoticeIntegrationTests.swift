import Foundation
import Testing
@testable import ZislaCore
@testable import ZislaKit

/// 测试专注模式变化后，提示能否正确进入队列并被识别为 compact notice
@MainActor
struct FocusModeNoticeIntegrationTests {
    @Test
    func focusModeTransitionNoticeEnqueuesSuccessfully() {
        let queue = SideNoticeQueue(capacityPerSide: 3)

        // 模拟专注模式开启的过渡提示
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

        // 模拟专注模式持久状态提示
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

        // focus-transition 应该被识别为 compact notice
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

        // focus-mode- 应该被识别为 compact notice
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
