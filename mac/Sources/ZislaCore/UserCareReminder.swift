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
        }
    }
}

public struct UserCareSchedule: Sendable {
    public static let reminderInterval: TimeInterval = 45 * 60
    public static let naturalBreakInterval: TimeInterval = 5 * 60

    private var activeSince: TimeInterval?
    private var nextReminderIndex = 0

    public init() {}

    public var isWorking: Bool { activeSince != nil }

    public mutating func reset() {
        activeSince = nil
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
        guard uptime - activeSince >= Self.reminderInterval else { return nil }

        // A delayed tick consumes one interval, so hidden or suspended time cannot build a backlog.
        self.activeSince = uptime
        let reminders: [UserCareReminder]
        if (12..<14).contains(localHour) {
            reminders = [.lunch, .nap]
        } else if localHour >= 23 || localHour < 6 {
            reminders = [.bedtime, .tomorrow]
        } else {
            reminders = [.rest, .water, .walk, .eyes]
        }
        let reminder = reminders[nextReminderIndex % reminders.count]
        nextReminderIndex = (nextReminderIndex + 1) % 4
        return reminder
    }
}
