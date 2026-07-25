import Foundation

/// 支持的 AI 供应方。CLI 与持久化都以其 rawValue 作稳定标识。
public enum AIProvider: String, Codable, CaseIterable, Sendable {
    case claude
    case codex
    case gemini
    case grok
    case gpt
    case qwen
    case coder
    case trae
    case opencode
    case harness
    case doubao

    /// 大小写与常见别名归一，未知返回 nil 交由上层报错。
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

/// 单条 AI 任务进度。progress 为 nil 表示不确定进度（转圈）。
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

/// 一次 AI 调用的用量采样。cost / model 可缺省。
public struct AIUsageSample: Codable, Equatable, Sendable {
    /// 本地日志事件的稳定标识；手工 `zislactl usage` 记录保持为空。
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

/// 普通、消息和系统状态通知的展示样式；旧状态文件缺省解码为 `.standard`。
public enum NoticeStyle: String, Codable, Sendable {
    case standard
    case message
    case status
}

/// 岛两侧的临时通知条。
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
    /// 展示样式；缺省时为 `.standard`。
    public var style: NoticeStyle
    /// 消息来源 App 显示名（仅 `style == .message` 时有意义）。
    public var appName: String?
    /// 可选 bundle id，用于解析安装 App 图标。
    public var appBundleIdentifier: String?
    /// 状态通知左侧使用的 SF Symbol 名称。
    public var symbolName: String?

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
        symbolName: String? = nil
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
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, detail, kind, side, createdAt, progress, artworkData
        case style, appName, appBundleIdentifier, symbolName
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
    }
}

/// 外部消息经 IPC 推送时的可测试模型：一次生成左右两侧普通 IslandNotice。
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

    /// 折叠空白/换行并截断到短展示长度，超出加省略号。
    public static func normalizeContent(_ raw: String, maxLength: Int = maxContentLength) -> String {
        let parts = raw.split { $0.isWhitespace || $0.isNewline }.filter { !$0.isEmpty }
        let collapsed = parts.joined(separator: " ")
        guard collapsed.count > maxLength else { return collapsed }
        let end = collapsed.index(collapsed.startIndex, offsetBy: maxLength)
        return String(collapsed[..<end]) + "…"
    }

    /// 左侧：App + 发件人；右侧：消息正文。共享 pairID 前缀与时间戳。
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

/// 落盘的聚合状态。
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
