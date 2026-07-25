import Foundation

public struct ToolboxReminderContent: Equatable, Sendable {
    public let title: String
    public let compactTitle: String

    public init(title: String, compactTitle: String) {
        self.title = title
        self.compactTitle = compactTitle
    }
}

public enum ToolboxReminder {
    public static func content(
        isScreenCleaning: Bool,
        isKeyboardCleaning: Bool,
        pomodoroMode: PomodoroMode,
        pomodoroPhase: PomodoroPhase,
        pomodoroClock: String,
        keepDisplayAwake: Bool,
        preventIdleSystemSleep: Bool
    ) -> ToolboxReminderContent? {
        if isKeyboardCleaning {
            return ToolboxReminderContent(title: "清洁键盘", compactTitle: "键盘")
        }
        if isScreenCleaning {
            return ToolboxReminderContent(title: "清洁屏幕", compactTitle: "清屏")
        }
        if pomodoroPhase == .running {
            return ToolboxReminderContent(
                title: "\(pomodoroMode.title) \(pomodoroClock)",
                compactTitle: pomodoroClock
            )
        }
        switch (keepDisplayAwake, preventIdleSystemSleep) {
        case (true, true):
            return ToolboxReminderContent(title: "亮屏 · 防休眠", compactTitle: "亮屏")
        case (true, false):
            return ToolboxReminderContent(title: "保持亮屏", compactTitle: "亮屏")
        case (false, true):
            return ToolboxReminderContent(title: "防止休眠", compactTitle: "防休眠")
        case (false, false):
            return nil
        }
    }
}
