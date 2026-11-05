import Foundation

public enum DailyBriefingContentGroup: String, CaseIterable, Identifiable, Sendable {
    case usage, input, system, zisla

    public var id: Self { self }

    public var title: String {
        switch self {
        case .usage: "使用情况"
        case .input: "输入统计"
        case .system: "系统状态"
        case .zisla: "Zisla 功能"
        }
    }

    public var contents: [DailyBriefingContent] {
        DailyBriefingContent.allCases.filter { $0.group == self }
    }
}

public enum DailyBriefingContent: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case localUsage, firstActivity, lastActivity, allDevicesUsage
    case hourlyUsage, applicationUsage, workTime, leisureTime, otherTime, listeningTime
    case characters, topTypingApplication, peakTypingHour, keyPressTrend
    case peakPower, batteryRange, peakFan, powerTrend, notificationCount, unlockCount
    case islandOpenings, clipboardCaptured, clipboardReused, shelfItemsAdded, shelfItemsCopied
    case pomodoroStarted, pomodoroCompleted, completedFocusTime
    case noteCreated, noteSaved, noteDeleted, quickNoteCreated, quickNoteSaved, quickNoteDeleted

    public var id: Self { self }
    public static let defaultSelection = Set(allCases)

    public static func selection(from rawValues: [String]?) -> Set<Self> {
        guard let rawValues else { return defaultSelection }
        return Set(rawValues.compactMap(Self.init(rawValue:)))
    }

    public var group: DailyBriefingContentGroup {
        switch self {
        case .localUsage, .firstActivity, .lastActivity, .allDevicesUsage,
             .hourlyUsage, .applicationUsage, .workTime, .leisureTime, .otherTime, .listeningTime:
            .usage
        case .characters, .topTypingApplication, .peakTypingHour, .keyPressTrend:
            .input
        case .peakPower, .batteryRange, .peakFan, .powerTrend, .notificationCount, .unlockCount:
            .system
        case .islandOpenings, .clipboardCaptured, .clipboardReused, .shelfItemsAdded, .shelfItemsCopied,
             .pomodoroStarted, .pomodoroCompleted, .completedFocusTime,
             .noteCreated, .noteSaved, .noteDeleted, .quickNoteCreated, .quickNoteSaved, .quickNoteDeleted:
            .zisla
        }
    }

    public var title: String {
        switch self {
        case .localUsage: "本机使用时间"
        case .firstActivity: "首次使用"
        case .lastActivity: "最后使用"
        case .allDevicesUsage: "所有设备"
        case .hourlyUsage: "每小时使用时间"
        case .applicationUsage: "应用使用时间"
        case .workTime: "工作"
        case .leisureTime: "休闲娱乐"
        case .otherTime: "其他"
        case .listeningTime: "听歌时长"
        case .characters: "输入字符"
        case .topTypingApplication: "输入最多的应用"
        case .peakTypingHour: "输入高峰"
        case .keyPressTrend: "键盘敲击走势"
        case .peakPower: "功率峰值"
        case .batteryRange: "电量范围"
        case .peakFan: "风扇峰值"
        case .powerTrend: "功率走势"
        case .notificationCount: "系统通知"
        case .unlockCount: "解锁次数"
        case .islandOpenings: "展开次数"
        case .clipboardCaptured: "剪贴板捕获"
        case .clipboardReused: "剪贴板复用"
        case .shelfItemsAdded: "中转新增项目"
        case .shelfItemsCopied: "中转复制项目"
        case .pomodoroStarted: "启动番茄钟"
        case .pomodoroCompleted: "完成番茄钟"
        case .completedFocusTime: "完成专注时长"
        case .noteCreated: "新建便签"
        case .noteSaved: "保存便签"
        case .noteDeleted: "删除便签"
        case .quickNoteCreated: "新建随记"
        case .quickNoteSaved: "保存随记"
        case .quickNoteDeleted: "删除随记"
        }
    }

    public var isDetailMetric: Bool {
        switch self {
        case .localUsage, .firstActivity, .lastActivity, .allDevicesUsage,
             .hourlyUsage, .applicationUsage, .workTime, .leisureTime, .otherTime, .keyPressTrend, .powerTrend:
            false
        default:
            true
        }
    }

    public var activity: DailyBriefingActivity? {
        switch self {
        case .clipboardCaptured: .clipboardCaptured
        case .clipboardReused: .clipboardReused
        case .shelfItemsAdded: .shelfItemsAdded
        case .shelfItemsCopied: .shelfItemsCopied
        case .pomodoroStarted: .pomodoroStarted
        case .pomodoroCompleted: .pomodoroCompleted
        case .noteCreated: .noteCreated
        case .noteSaved: .noteSaved
        case .noteDeleted: .noteDeleted
        case .quickNoteCreated: .quickNoteCreated
        case .quickNoteSaved: .quickNoteSaved
        case .quickNoteDeleted: .quickNoteDeleted
        case .unlockCount: .unlocked
        default: nil
        }
    }

    public var category: DailyBriefingCategory? {
        switch self {
        case .workTime: .work
        case .leisureTime: .leisure
        case .otherTime: .other
        default: nil
        }
    }
}
