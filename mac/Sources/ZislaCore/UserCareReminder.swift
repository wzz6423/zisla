import Foundation

public enum UserCareReminder: CaseIterable, Equatable, Sendable {
    case rest
    case water
    case walk
    case eyes
    case lunch
    case nap
    case bedtime
    case tomorrow
    case posture
    case stretch
    case breathe
    case focusCompleted
    case restCompleted

    public func localizationKey(petEnabled: Bool) -> String {
        switch (self, petEnabled) {
        case (.rest, false): "忙了一阵了，歇一会儿吧。"
        case (.rest, true): "人，忙了一阵了，陪我歇一会儿吧。"
        case (.water, false): "喝口水吧，慢慢来。"
        case (.water, true): "人，喝口水吧，我等你。"
        case (.walk, false): "起来走走，伸展一下身体吧。"
        case (.walk, true): "人，起来走走，带我转一圈吧。"
        case (.eyes, false): "看看远处，让眼睛放松一下吧。"
        case (.eyes, true): "人，看看远处，也看看我吧。"
        case (.lunch, false): "到午间了，记得吃饭，也休息一会儿。"
        case (.lunch, true): "人，到午间了，吃点东西，陪我歇一会儿吧。"
        case (.nap, false): "午间小憩一会儿，下午再慢慢忙吧。"
        case (.nap, true): "人，陪我午睡一小会儿，下午再忙吧。"
        case (.bedtime, false): "已经很晚了，早点休息吧。"
        case (.bedtime, true): "人，已经很晚了，我们早点休息吧。"
        case (.tomorrow, false): "今天辛苦了，余下的事留给明天吧。"
        case (.tomorrow, true): "人，今天辛苦了，明天我再陪你吧。"
        case (.posture, false): "换个坐姿，坐得舒服一点吧。"
        case (.posture, true): "人，换个舒服的坐姿吧。"
        case (.stretch, false): "放松肩颈，轻轻伸展一下吧。"
        case (.stretch, true): "人，放松肩颈，和我伸个懒腰吧。"
        case (.breathe, false): "慢慢呼吸，给自己一点空隙吧。"
        case (.breathe, true): "人，慢慢呼吸，我陪着你。"
        case (.focusCompleted, false): "时间到啦，歇一会儿吧～"
        case (.focusCompleted, true): "人，时间到啦，该休息了～"
        case (.restCompleted, false): "休息结束啦，按自己的节奏继续吧～"
        case (.restCompleted, true): "人，休息好啦，我陪你继续～"
        }
    }

    public func localizedMessage(petEnabled: Bool, language: AppLanguage) -> String {
        let body = AppLocalization.string(localizationKey(petEnabled: petEnabled), language: language)
        let decoration = switch self {
        case .rest, .focusCompleted: "🍵"
        case .water: "💧"
        case .walk, .posture, .breathe: "🌿"
        case .eyes: "👀"
        case .lunch: "🍚"
        case .nap: "💤"
        case .bedtime, .tomorrow: "🌙"
        case .stretch, .restCompleted: petEnabled ? "(๑•̀ㅂ•́)و✧" : "🌿"
        }
        return "\(body) \(decoration)"
    }
}

public struct UserCareSchedule: Sendable {
    public static let reminderInterval: TimeInterval = UserCareInterval.defaultSeconds
    public static let naturalBreakInterval: TimeInterval = 5 * 60

    private var activeSince: TimeInterval?
    private var nextReminderIndex = 0
    public private(set) var interval: TimeInterval

    public init(interval: TimeInterval = UserCareInterval.defaultSeconds) {
        self.interval = UserCareInterval.normalized(interval)
    }

    public var isWorking: Bool { activeSince != nil }

    public mutating func reset() {
        activeSince = nil
    }

    public mutating func setInterval(_ interval: TimeInterval) {
        let interval = UserCareInterval.normalized(interval)
        guard self.interval != interval else { return }
        self.interval = interval
        reset()
    }

    public func timeUntilReminder(at uptime: TimeInterval) -> TimeInterval {
        guard let activeSince else { return interval }
        return max(0, activeSince + interval - uptime)
    }

    public mutating func update(
        at uptime: TimeInterval,
        isActive: Bool,
        idleSeconds: TimeInterval?,
        localHour: Int
    ) -> UserCareReminder? {
        guard isActive, let idleSeconds,
              idleSeconds >= 0, idleSeconds < Self.naturalBreakInterval else {
            reset()
            return nil
        }
        guard let activeSince else {
            self.activeSince = uptime
            return nil
        }
        guard uptime >= activeSince + interval else { return nil }

        // A delayed tick consumes one interval, so hidden or suspended time cannot build a backlog.
        self.activeSince = uptime
        let reminders: [UserCareReminder]
        if (12..<14).contains(localHour) {
            reminders = [.lunch, .nap]
        } else if localHour >= 23 || localHour < 6 {
            reminders = [.bedtime, .tomorrow]
        } else {
            reminders = [.rest, .water, .walk, .eyes, .posture, .stretch, .breathe]
        }
        let reminder = reminders[nextReminderIndex % reminders.count]
        nextReminderIndex = (nextReminderIndex + 1) % reminders.count
        return reminder
    }
}
