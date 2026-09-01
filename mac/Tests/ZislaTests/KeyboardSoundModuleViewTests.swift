import Foundation
import CoreGraphics
import Testing

@testable import Zisla
@testable import KeyboardKit

@Suite(.serialized)
struct KeyboardSoundModuleViewTests {
    @Test
    @MainActor
    func rightCommandFlagsChangedPreservesPresses() {
        let rightCommand = UInt16(54)
        #expect(
            KeyboardMonitor.modifierIsDown(
                keyCode: rightCommand,
                flags: CGEventFlags(rawValue: 0x0000_0000_0000_0010),
                pressedModifierKeyCodes: []
            )
        )
        #expect(
            !KeyboardMonitor.modifierIsDown(
                keyCode: rightCommand,
                flags: CGEventFlags(rawValue: 0x0000_0000_0000_0008),
                pressedModifierKeyCodes: [rightCommand]
            )
        )
        #expect(
            KeyboardMonitor.modifierIsDown(
                keyCode: rightCommand,
                flags: .maskCommand,
                pressedModifierKeyCodes: []
            )
        )
        #expect(
            !KeyboardMonitor.modifierIsDown(
                keyCode: rightCommand,
                flags: .maskCommand,
                pressedModifierKeyCodes: [rightCommand]
            )
        )
    }

    @Test
    func islandKeyboardModuleIsReadOnlyAndFollowsAIMonitor() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let viewSource = try String(
            contentsOf: root.appendingPathComponent("Sources/Zisla/KeyboardSoundModuleView.swift"),
            encoding: .utf8
        )

        #expect(!viewSource.contains("Toggle("))
        #expect(!viewSource.contains("Picker("))
        #expect(!viewSource.contains("keyboardEnabled ="))
        #expect(!viewSource.contains("monitoringStateText"))
        #expect(!viewSource.contains("查看输入统计"))
        #expect(!viewSource.contains("openTypingStats()"))
        #expect(!viewSource.contains("只读监控"))
        #expect(!viewSource.contains("输入监控正在运行"))
        #expect(viewSource.contains("KeyboardTypingStatsDashboardView"))
        #expect(viewSource.contains("KeyboardTypingStatsDashboardView(summary: summary)"))
        #expect(!viewSource.contains("compact:"))

        let dashboardSource = try String(
            contentsOf: root.appendingPathComponent("Sources/Zisla/KeyboardTypingStatsDashboardView.swift"),
            encoding: .utf8
        )
        #expect(dashboardSource.contains("输入趋势"))
        #expect(dashboardSource.contains("历史"))
        #expect(dashboardSource.contains("键盘"))
        #expect(dashboardSource.contains("应用时间线"))
        #expect(dashboardSource.contains("今日按键"))
        #expect(dashboardSource.contains("累计按键"))
        #expect(dashboardSource.contains("private var activityPanels"))
        #expect(dashboardSource.contains("frame(height: 110)"))
        #expect(!dashboardSource.contains("let compact"))
        #expect(dashboardSource.contains("KeyboardHeatmapView"))
        #expect(dashboardSource.contains("Key(\"digit1\", \"1\", 18)"))
        #expect(dashboardSource.contains("Key(\"leftArrow\", \"←\", 123)"))
        #expect(dashboardSource.contains("Key(\"rightShift\", \"shift\", 60"))

        // 今日/累计按键需按内容自然排列：keyboardCount 不能再撑满等分宽度，
        // 靠外层 HStack 的 Spacer 保持左对齐。
        let keyboardCountBody = try #require(
            dashboardSource
                .components(separatedBy: "private func keyboardCount")
                .dropFirst()
                .first?
                .components(separatedBy: "\n    private ")
                .first
        )
        #expect(!keyboardCountBody.contains("maxWidth: .infinity"))
        #expect(dashboardSource.contains("keyboardCount(\"累计按键\", summary.allTimeKeyPressCount)\n                Spacer()"))

        let modules = IslandModule.allCases
        let aiIndex = try #require(modules.firstIndex(of: .aiMonitor))
        let keyboardIndex = try #require(modules.firstIndex(of: .keyboardSound))
        #expect(keyboardIndex == modules.index(after: aiIndex))
    }
}
