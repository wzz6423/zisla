import Foundation

/// Supported AI providers. `rawValue` is used as a stable identifier in CLI output and persistence.
public enum AIProvider: String, Codable, CaseIterable, Sendable {
    case claude
    case codex
    case gemini
    case grok
    case gpt
    case copilot
    case kimi
    case qwen
    case coder
    case trae
    case opencode
    case harness
    case doubao

    /// Normalises case and common aliases; returns nil for unknown tokens, letting the caller report the error.
    public init?(token: String) {
        switch token.lowercased() {
        case "claude", "claude-code", "claude-cli", "claude-desktop", "anthropic-claude":
            self = .claude
        case "codex", "openai-codex", "codex-cli", "codex-desktop", "codex-app":
            self = .codex
        case "gemini", "google-gemini", "gemini-cli", "gemini-code-assist":
            self = .gemini
        case "grok", "grok-cli", "xai", "x-ai":
            self = .grok
        case "gpt", "openai", "chatgpt", "chat-gpt", "openai-gpt":
            self = .gpt
        case "copilot", "github-copilot", "github copilot", "copilot-cli", "copilot-chat", "github.copilot-chat":
            self = .copilot
        case "kimi", "kimi-code", "kimi-code-cli", "kimi-vscode", "moonshot-kimi", "moonshot-ai.kimi-code":
            self = .kimi
        case "qwen", "tongyi", "qwen-code", "qwen-code-cli", "qwen-vscode":
            self = .qwen
        case "coder", "qwen-coder", "qoder", "qoder-cli", "qoderwork", "qoder-work",
             "qoderworkcn", "qoderwork-cn", "qoderwork cn", "qoderwake", "qoder-wake":
            self = .coder
        case "trae", "trae-work", "traework", "trae-work-cn", "trae-solo", "trae-solo-cn", "trae-cn":
            self = .trae
        case "opencode", "open-code", "open_code":
            self = .opencode
        case "harness", "harnext", "harnext-cli", "harness-cli":
            self = .harness
        case "doubao", "豆包":
            self = .doubao
        default: return nil
        }
    }
}

public enum AIProgressStatus: String, Codable, Sendable {
    case queued
    case running
    case blocked
    case error
    case succeeded
    case failed

    public var isActive: Bool {
        switch self {
        case .queued, .running, .blocked, .error:
            true
        case .succeeded, .failed:
            false
        }
    }

    public var noticeKind: NoticeKind {
        switch self {
        case .queued, .running: .info
        case .blocked: .warning
        case .error, .failed: .error
        case .succeeded: .success
        }
    }
}

/// Single AI task progress record. `progress == nil` indicates indeterminate progress (spinner).
public struct AIProgressTask: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var provider: AIProvider
    public var title: String
    public var detail: String?
    public var progress: Double?
    public var status: AIProgressStatus
    public var updatedAt: Date
    public var sessionURL: URL?
    public var effort: String?
    public var startedAt: Date?

    public init(
        id: String,
        provider: AIProvider,
        title: String,
        detail: String? = nil,
        progress: Double?,
        status: AIProgressStatus = .running,
        updatedAt: Date,
        sessionURL: URL? = nil,
        effort: String? = nil,
        startedAt: Date? = nil
    ) {
        self.id = id
        self.provider = provider
        self.title = title
        self.detail = detail
        self.progress = progress
        self.status = status
        self.updatedAt = updatedAt
        self.sessionURL = sessionURL
        self.effort = effort
        self.startedAt = startedAt
    }
}

/// A daily AI usage aggregate. `cost` and `model` are optional.
public struct AIUsageSample: Codable, Equatable, Sendable {
    /// Stable identifier for an internally maintained daily aggregate.
    public var sourceID: String?
    public var provider: AIProvider
    public var timestamp: Date
    public var inputTokens: Int
    public var outputTokens: Int
    public var costUSD: Double?
    public var model: String?

    public init(
        sourceID: String? = nil,
        provider: AIProvider,
        timestamp: Date,
        inputTokens: Int,
        outputTokens: Int,
        costUSD: Double? = nil,
        model: String? = nil
    ) {
        self.sourceID = sourceID
        self.provider = provider
        self.timestamp = timestamp
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.costUSD = costUSD
        self.model = model
    }

    public var totalTokens: Int { inputTokens + outputTokens }
}

public enum NoticeKind: String, Codable, Sendable {
    case info
    case success
    case warning
    case error

    public init?(token: String) {
        self.init(rawValue: token.lowercased())
    }
}

public enum NoticeSide: String, Codable, Sendable {
    case left
    case right

    public init?(token: String) {
        self.init(rawValue: token.lowercased())
    }
}

/// Presentation style for regular, message, and system-status notices; old state files decode absent values as `.standard`.
public enum NoticeStyle: String, Codable, Sendable {
    case standard
    case message
    case status
    case headphone
}

/// A single battery reading in an accessory notice. `level == nil` means the system did not provide a charge level for that device.
public struct NoticeBatteryLevel: Codable, Equatable, Sendable, Identifiable {
    public var label: String
    public var level: Int?

    public init(label: String, level: Int?) {
        self.label = label
        self.level = level.map { min(max($0, 0), 100) }
    }

    public var id: String { label }
}

/// Transient notice strip shown on either side of the island.
public struct IslandNotice: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var detail: String?
    public var kind: NoticeKind
    public var side: NoticeSide
    public var createdAt: Date
    public var progress: Double?
    /// Optional media artwork used by the compact playback wing. It is not
    /// required for AI or ordinary notices and remains absent in old state files.
    public var artworkData: Data?
    /// Presentation style; defaults to `.standard` when absent.
    public var style: NoticeStyle
    /// Source app display name (meaningful only when `style == .message`).
    public var appName: String?
    /// Optional bundle ID used to resolve the installed app's icon.
    public var appBundleIdentifier: String?
    /// SF Symbol name used on the left side of a status notice.
    public var symbolName: String?
    /// Individual battery readings for attached accessories; when absent, preserves the existing display and decoding behaviour for old notices.
    public var batteryLevels: [NoticeBatteryLevel]?

    public init(
        id: String = UUID().uuidString,
        title: String,
        detail: String? = nil,
        kind: NoticeKind = .info,
        side: NoticeSide = .right,
        createdAt: Date = Date(),
        progress: Double? = nil,
        artworkData: Data? = nil,
        style: NoticeStyle = .standard,
        appName: String? = nil,
        appBundleIdentifier: String? = nil,
        symbolName: String? = nil,
        batteryLevels: [NoticeBatteryLevel]? = nil
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.kind = kind
        self.side = side
        self.createdAt = createdAt
        self.progress = progress.map { min(max($0, 0), 1) }
        self.artworkData = artworkData
        self.style = style
        self.appName = appName
        self.appBundleIdentifier = appBundleIdentifier
        self.symbolName = symbolName
        self.batteryLevels = batteryLevels
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, detail, kind, side, createdAt, progress, artworkData
        case style, appName, appBundleIdentifier, symbolName, batteryLevels
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        detail = try container.decodeIfPresent(String.self, forKey: .detail)
        kind = try container.decode(NoticeKind.self, forKey: .kind)
        side = try container.decode(NoticeSide.self, forKey: .side)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        progress = try container.decodeIfPresent(Double.self, forKey: .progress)
        artworkData = try container.decodeIfPresent(Data.self, forKey: .artworkData)
        style = try container.decodeIfPresent(NoticeStyle.self, forKey: .style) ?? .standard
        appName = try container.decodeIfPresent(String.self, forKey: .appName)
        appBundleIdentifier = try container.decodeIfPresent(String.self, forKey: .appBundleIdentifier)
        symbolName = try container.decodeIfPresent(String.self, forKey: .symbolName)
        batteryLevels = try container.decodeIfPresent([NoticeBatteryLevel].self, forKey: .batteryLevels)
    }
}

/// Testable model for an inbound IPC message notification: produces a pair of left/right `IslandNotice` values in one shot.
public struct MessageNotification: Equatable, Sendable {
    public static let maxContentLength = 48

    public var appName: String
    public var sender: String
    public var content: String
    public var appBundleIdentifier: String?
    public var createdAt: Date
    public var pairID: String

    public init(
        appName: String,
        sender: String,
        content: String,
        appBundleIdentifier: String? = nil,
        createdAt: Date = Date(),
        pairID: String = UUID().uuidString
    ) {
        self.appName = appName
        self.sender = sender
        self.content = Self.normalizeContent(content)
        self.appBundleIdentifier = appBundleIdentifier.flatMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        self.createdAt = createdAt
        self.pairID = pairID
    }

    /// Collapses whitespace/newlines and truncates to the short display length, appending an ellipsis when over the limit.
    public static func normalizeContent(_ raw: String, maxLength: Int = maxContentLength) -> String {
        let parts = raw.split { $0.isWhitespace || $0.isNewline }.filter { !$0.isEmpty }
        let collapsed = parts.joined(separator: " ")
        guard collapsed.count > maxLength else { return collapsed }
        let end = collapsed.index(collapsed.startIndex, offsetBy: maxLength)
        return String(collapsed[..<end]) + "…"
    }

    /// Left side: app + sender; right side: message body. Both share the same `pairID` prefix and timestamp.
    public func makeNotices() -> (left: IslandNotice, right: IslandNotice) {
        let left = IslandNotice(
            id: "message-\(pairID)-left",
            title: sender,
            detail: appName,
            kind: .info,
            side: .left,
            createdAt: createdAt,
            style: .message,
            appName: appName,
            appBundleIdentifier: appBundleIdentifier
        )
        let right = IslandNotice(
            id: "message-\(pairID)-right",
            title: content,
            detail: nil,
            kind: .info,
            side: .right,
            createdAt: createdAt,
            style: .message,
            appName: appName,
            appBundleIdentifier: appBundleIdentifier
        )
        return (left, right)
    }
}

/// Persisted aggregate state.
public struct AIState: Codable, Equatable, Sendable {
    public var tasks: [AIProgressTask]
    public var usageSamples: [AIUsageSample]
    public var notices: [IslandNotice]

    public init(
        tasks: [AIProgressTask] = [],
        usageSamples: [AIUsageSample] = [],
        notices: [IslandNotice] = []
    ) {
        self.tasks = tasks
        self.usageSamples = usageSamples
        self.notices = notices
    }

    public static let empty = AIState()
}
