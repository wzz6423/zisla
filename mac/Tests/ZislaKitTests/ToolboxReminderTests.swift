import Testing
import ZislaCore
@testable import ZislaKit

struct ToolboxReminderTests {
    @Test
    func cleaningStateTakesPriorityOverTimerAndPowerAssertions() {
        let content = ToolboxReminder.content(
            isScreenCleaning: true,
            isKeyboardCleaning: true,
            pomodoroMode: .focus,
            pomodoroPhase: .running,
            pomodoroClock: "24:59",
            keepDisplayAwake: true,
            preventIdleSystemSleep: true
        )

        #expect(content == ToolboxReminderContent(title: "清洁键盘", compactTitle: "键盘"))
    }

    @Test
    func runningPomodoroTakesPriorityOverPowerAssertions() {
        let content = ToolboxReminder.content(
            isScreenCleaning: false,
            isKeyboardCleaning: false,
            pomodoroMode: .rest,
            pomodoroPhase: .running,
            pomodoroClock: "04:59",
            keepDisplayAwake: true,
            preventIdleSystemSleep: true
        )

        #expect(content == ToolboxReminderContent(title: "休息 04:59", compactTitle: "04:59"))
    }

    @Test(arguments: [false, true], [false, true])
    func idleToolboxOnlyShowsActivePowerStates(display: Bool, system: Bool) throws {
        let content = ToolboxReminder.content(
            isScreenCleaning: false,
            isKeyboardCleaning: false,
            pomodoroMode: .focus,
            pomodoroPhase: .paused,
            pomodoroClock: "24:00",
            keepDisplayAwake: display,
            preventIdleSystemSleep: system
        )

        guard display || system else {
            #expect(content == nil)
            return
        }
        let reminder = try #require(content)
        for side in [NoticeSide.left, .right] {
            let notice = reminder.notice(for: side)
            #expect(notice.id == "toolbox-reminder-\(side.rawValue)" && notice.side == side)
            #expect(notice.detail == (display ? "亮屏" : "防休眠"))
            #expect(notice.symbolName == (display ? "sun.max.fill" : "laptopcomputer"))
            #expect(notice.metadata?[ToolboxReminder.secondarySymbolKey] == (display && system ? "laptopcomputer" : nil))
        }
    }
}
