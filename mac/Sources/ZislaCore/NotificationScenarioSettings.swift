import Foundation

public enum NotificationScenario: String, Codable, CaseIterable, Sendable {
    case focus, meeting, screenRecording

    public var title: String {
        switch self {
        case .focus: "专注与番茄钟"
        case .meeting: "会议场景"
        case .screenRecording: "录屏场景"
        }
    }

    public var symbolName: String {
        switch self {
        case .focus: "moon.fill"
        case .meeting: "video.fill"
        case .screenRecording: "record.circle"
        }
    }
}

public enum ScenarioNotificationBehavior: String, Codable, CaseIterable, Sendable {
    case show, deferUntilEnd, mute

    public var title: String {
        switch self {
        case .show: "正常显示"
        case .deferUntilEnd: "结束后回顾"
        case .mute: "静音并丢弃"
        }
    }
}

public enum ScenarioNoticeImportance: Hashable, Sendable {
    case ordinary, waiting, failure, safety, lowBattery

    public init(notice: IslandNotice) {
        if notice.id == "battery-low" || notice.id.hasPrefix("battery-low:") {
            self = .lowBattery
        } else if notice.kind == .error {
            self = .failure
        } else if notice.kind == .warning {
            self = notice.id.hasPrefix("ai-active-") ? .waiting : .safety
        } else {
            self = .ordinary
        }
    }
}

public struct NotificationScenarioPolicy: Codable, Equatable, Sendable {
    public var ordinary: ScenarioNotificationBehavior
    public var keepsImportant: Bool

    public init(ordinary: ScenarioNotificationBehavior = .deferUntilEnd, keepsImportant: Bool = true) {
        self.ordinary = ordinary
        self.keepsImportant = keepsImportant
    }

    private enum CodingKeys: String, CodingKey { case ordinary, keepsImportant }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ordinary = try container.decodeIfPresent(ScenarioNotificationBehavior.self, forKey: .ordinary) ?? .deferUntilEnd
        keepsImportant = try container.decodeIfPresent(Bool.self, forKey: .keepsImportant) ?? true
    }
}

public struct NotificationScenarioRules: Codable, Equatable, Sendable {
    public var focus: NotificationScenarioPolicy
    public var meeting: NotificationScenarioPolicy
    public var screenRecording: NotificationScenarioPolicy

    public init(focus: NotificationScenarioPolicy = .init(), meeting: NotificationScenarioPolicy = .init(),
                screenRecording: NotificationScenarioPolicy = .init()) {
        self.focus = focus
        self.meeting = meeting
        self.screenRecording = screenRecording
    }

    public subscript(scenario: NotificationScenario) -> NotificationScenarioPolicy {
        get {
            switch scenario {
            case .focus: focus
            case .meeting: meeting
            case .screenRecording: screenRecording
            }
        }
        set {
            switch scenario {
            case .focus: focus = newValue
            case .meeting: meeting = newValue
            case .screenRecording: screenRecording = newValue
            }
        }
    }

    private enum CodingKeys: String, CodingKey { case focus, meeting, screenRecording }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        focus = try container.decodeIfPresent(NotificationScenarioPolicy.self, forKey: .focus) ?? .init()
        meeting = try container.decodeIfPresent(NotificationScenarioPolicy.self, forKey: .meeting) ?? .init()
        screenRecording = try container.decodeIfPresent(NotificationScenarioPolicy.self, forKey: .screenRecording) ?? .init()
    }
}

public struct NotificationScenarioSettings: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var automaticallyDetectsMeetings: Bool
    public var rules: NotificationScenarioRules
    public var displayOverrides: [String: NotificationScenarioRules]

    public init(enabled: Bool = false, automaticallyDetectsMeetings: Bool = false,
                rules: NotificationScenarioRules = .init(), displayOverrides: [String: NotificationScenarioRules] = [:]) {
        self.enabled = enabled
        self.automaticallyDetectsMeetings = automaticallyDetectsMeetings
        self.rules = rules
        self.displayOverrides = displayOverrides
    }

    public func behavior(for importance: ScenarioNoticeImportance, scenarios: Set<NotificationScenario>,
                         displayIdentifier: String? = nil) -> ScenarioNotificationBehavior {
        guard enabled else { return .show }
        let rules = displayIdentifier.flatMap { displayOverrides[$0] } ?? rules
        var result = ScenarioNotificationBehavior.show
        for scenario in scenarios {
            let policy = rules[scenario]
            if importance != .ordinary && policy.keepsImportant { continue }
            switch policy.ordinary {
            case .show: break
            case .deferUntilEnd: result = .deferUntilEnd
            case .mute: return .mute
            }
        }
        return result
    }

    private enum CodingKeys: String, CodingKey { case enabled, automaticallyDetectsMeetings, rules, displayOverrides }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        automaticallyDetectsMeetings = try container.decodeIfPresent(Bool.self, forKey: .automaticallyDetectsMeetings) ?? false
        rules = try container.decodeIfPresent(NotificationScenarioRules.self, forKey: .rules) ?? .init()
        displayOverrides = try container.decodeIfPresent([String: NotificationScenarioRules].self, forKey: .displayOverrides) ?? [:]
    }
}
