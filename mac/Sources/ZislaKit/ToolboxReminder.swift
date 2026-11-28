import Foundation
import ZislaCore

public struct ToolboxReminderContent: Equatable, Sendable {
    public let title: String
    public let compactTitle: String
    private let symbolName: String?
    private let secondarySymbolName: String?

    public init(title: String, compactTitle: String, symbolName: String? = nil, secondarySymbolName: String? = nil) {
        self.title = title
        self.compactTitle = compactTitle
        self.symbolName = symbolName
        self.secondarySymbolName = secondarySymbolName
    }

    public func notice(for side: NoticeSide) -> IslandNotice {
        IslandNotice(id: "toolbox-reminder-\(side.rawValue)", title: title, detail: compactTitle,
                     side: side, symbolName: symbolName,
                     metadata: secondarySymbolName.map { [ToolboxReminder.secondarySymbolKey: $0] })
    }
}

public enum ToolboxReminder {
    public static let displayAwakeSymbol = "sun.max.fill"
    public static let preventIdleSleepSymbol = "laptopcomputer"
    public static let secondarySymbolKey = "toolboxSecondarySymbol"

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
            return ToolboxReminderContent(title: "亮屏 · 防休眠", compactTitle: "亮屏",
                                          symbolName: displayAwakeSymbol, secondarySymbolName: preventIdleSleepSymbol)
        case (true, false):
            return ToolboxReminderContent(title: "保持亮屏", compactTitle: "亮屏", symbolName: displayAwakeSymbol)
        case (false, true):
            return ToolboxReminderContent(title: "防止休眠", compactTitle: "防休眠", symbolName: preventIdleSleepSymbol)
        case (false, false):
            return nil
        }
    }
}
