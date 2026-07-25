import Testing
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

    @Test
    func idleToolboxOnlyShowsActivePowerStates() {
        let onlySystem = ToolboxReminder.content(
            isScreenCleaning: false,
            isKeyboardCleaning: false,
            pomodoroMode: .focus,
            pomodoroPhase: .idle,
            pomodoroClock: "25:00",
            keepDisplayAwake: false,
            preventIdleSystemSleep: true
        )
        let inactive = ToolboxReminder.content(
            isScreenCleaning: false,
            isKeyboardCleaning: false,
            pomodoroMode: .focus,
            pomodoroPhase: .paused,
            pomodoroClock: "24:00",
            keepDisplayAwake: false,
            preventIdleSystemSleep: false
        )

        #expect(onlySystem == ToolboxReminderContent(title: "防止休眠", compactTitle: "防休眠"))
        #expect(inactive == nil)
    }
}
