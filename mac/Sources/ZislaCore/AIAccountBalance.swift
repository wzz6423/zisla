import Foundation

public enum AIAccountBalanceStatus: String, Codable, Sendable {
    case available, notSignedIn, credentialsUnavailable, credentialsExpired
    case additionalCredentialsRequired, queryUnsupported, connectedAccount
    case unavailable, rateLimited, invalidResponse

    public var title: String {
        switch self {
        case .available: "可用额度"
        case .notSignedIn: "未登录"
        case .credentialsUnavailable: "登录凭据不可用"
        case .credentialsExpired: "登录已过期"
        case .additionalCredentialsRequired: "需要额度查询凭据"
        case .queryUnsupported: "暂不支持额度查询"
        case .connectedAccount: "由所连接账户计费"
        case .unavailable: "额度服务暂不可用"
        case .rateLimited: "额度查询限流"
        case .invalidResponse: "额度响应格式已变化"
        }
    }
}

public enum AIAccountBalanceQoderRegion: String, CaseIterable, Codable, Sendable {
    case global, china
    public var title: String { self == .china ? "中国区" : "国际区" }
}

public enum AIAccountQuotaSeverity: Int, Codable, Comparable, Sendable {
    case normal, warning, critical, exhausted

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Uses remaining allowance: zero is exhausted, with inclusive 10% critical and 20% warning thresholds.
    /// Callers validate the percentage before constructing a severity.
    public init(remainingPercent: Double) {
        if remainingPercent == 0 { self = .exhausted }
        else if remainingPercent <= 10 { self = .critical }
        else if remainingPercent <= 20 { self = .warning }
        else { self = .normal }
    }
}

public enum AIAccountQuotaKind: String, Codable, Sendable {
    case fiveHours, rolling, weekly, daily, monthly, all, credits, budget, predictions, model

    public var title: String {
        switch self {
        case .fiveHours: "5h"
        case .rolling: "滚动额度"
        case .weekly: "每周额度"
        case .daily: "每日额度"
        case .monthly: "每月额度"
        case .all: "全部"
        case .credits: "积分余额"
        case .budget: "可用预算"
        case .predictions: "编辑预测"
        case .model: "模型额度"
        }
    }
}

public enum AIAccountQuotaUnit: String, Codable, Sendable {
    case percent, credits, requests, usd
}

public struct AIAccountQuotaWindow: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let kind: AIAccountQuotaKind
    public let remainingPercent: Double?
    public let remaining: Double?
    public let limit: Double?
    public let unit: AIAccountQuotaUnit
    public let resetsAt: Date?
    public let durationSeconds: Double?
    public let name: String?
    public let nameKey: String?
    public let unlimited: Bool

    public init(id: String, kind: AIAccountQuotaKind, remainingPercent: Double? = nil,
                remaining: Double? = nil, limit: Double? = nil, unit: AIAccountQuotaUnit = .percent,
                resetsAt: Date? = nil, durationSeconds: Double? = nil,
                name: String? = nil, nameKey: String? = nil, unlimited: Bool = false) {
        self.id = id
        self.kind = kind
        self.remainingPercent = remainingPercent
        self.remaining = remaining
        self.limit = limit
        self.unit = unit
        self.resetsAt = resetsAt
        self.durationSeconds = durationSeconds
        self.name = name
        self.nameKey = nameKey
        self.unlimited = unlimited
    }

    /// Requires a real remaining observation or explicit unlimited state, with finite nonnegative amounts.
    /// Only an actual 18,000-second duration may be labeled as a five-hour window.
    public var isValid: Bool {
        !id.isEmpty && id.utf8.count <= 256
            && (remainingPercent.map { $0.isFinite && (0...100).contains($0) } ?? true)
            && (remaining.map { $0.isFinite && $0 >= 0 } ?? true)
            && (limit.map { $0.isFinite && $0 >= 0 } ?? true)
            && (remaining == nil || limit == nil || remaining! <= limit!)
            && (durationSeconds.map { $0.isFinite && $0 > 0 } ?? true)
            && (resetsAt.map { $0.timeIntervalSince1970.isFinite && $0.timeIntervalSince1970 > 0 } ?? true)
            && (unlimited || remainingPercent != nil || remaining != nil)
            && (kind != .fiveHours || durationSeconds == 18_000)
    }

    /// Unlimited allowance stays healthy; an amount without a denominator triggers only an exact-zero alert.
    public var severity: AIAccountQuotaSeverity {
        if unlimited { return .normal }
        if let remainingPercent { return .init(remainingPercent: remainingPercent) }
        return remaining == 0 ? .exhausted : .normal
    }

    /// A missing denominator or unlimited allowance has no measurable arc.
    public var remainingFraction: Double? {
        guard isValid, !unlimited else { return nil }
        if let remainingPercent { return remainingPercent / 100 }
        guard let remaining, let limit, limit > 0 else { return nil }
        return remaining / limit
    }

    /// Keeps provider feature names distinct while localizing known labels and retaining actual window kinds.
    public func label(language: AppLanguage) -> String {
        let title = AppLocalization.string(kind.title, language: language)
        if let nameKey { return AppLocalization.string(nameKey, language: language) }
        guard let name else { return title }
        return durationSeconds != nil && kind != .model ? name + " · " + title : name
    }

    /// Displays the provider's amount unit when available; unknown percentages remain unknown.
    public func value(language: AppLanguage) -> String {
        if unlimited { return AppLocalization.string("不限额度", language: language) }
        if let remaining, unit != .percent {
            let value = remaining.formatted(.number.precision(.fractionLength(0...2)).locale(language.locale))
            return switch unit {
            case .usd: "$" + value
            case .credits: AppLocalization.format("%@ 积分", locale: language.locale, [value])
            case .requests: AppLocalization.format("%@ 次", locale: language.locale, [value])
            case .percent: value
            }
        }
        guard let remainingPercent else { return "—" }
        return remainingPercent.formatted(.number.precision(.fractionLength(0...1)).locale(language.locale)) + "%"
    }
}

public struct AIAccountBalance: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var providers: [AIProvider]
    public var status: AIAccountBalanceStatus
    public var windows: [AIAccountQuotaWindow]
    public var updatedAt: Date?
    public var accountName: String?
    public var detailKey: String?
    public var isDebug: Bool

    public init(id: String, providers: [AIProvider], status: AIAccountBalanceStatus,
                windows: [AIAccountQuotaWindow] = [], updatedAt: Date? = nil,
                accountName: String? = nil, detailKey: String? = nil, isDebug: Bool = false) {
        self.id = id
        self.providers = providers
        self.status = status
        self.windows = windows
        self.updatedAt = updatedAt
        self.accountName = accountName
        self.detailKey = detailKey
        self.isDebug = isDebug
    }

    /// Any unavailable or invalid window disables alerts; valid independent windows use the worst severity.
    public var severity: AIAccountQuotaSeverity? {
        guard status == .available, !windows.isEmpty, windows.allSatisfy(\.isValid) else { return nil }
        return windows.map(\.severity).max()
    }

    public var limitingWindow: AIAccountQuotaWindow? {
        guard severity != nil else { return nil }
        return windows.sorted {
            $0.severity != $1.severity ? $0.severity > $1.severity : ($0.remainingPercent ?? 100) < ($1.remainingPercent ?? 100)
        }.first
    }

    public var noticeID: String { "ai-balance-low-" + id }

    public var displayProvider: AIProvider? {
        providers.first
    }

    public var fiveHourWindow: AIAccountQuotaWindow? {
        windows.first { $0.kind == .fiveHours && !$0.id.hasPrefix("additional:") }
    }

    public var weeklyWindow: AIAccountQuotaWindow? {
        windows.first { $0.kind == .weekly && $0.name == nil && $0.nameKey == nil }
    }

    public func providerTitle(language: AppLanguage) -> String {
        let brands = providers.allSatisfy { $0 == .codex || $0 == .gpt } ? Array(providers.prefix(1)) : providers
        return brands.map { $0 == .gpt ? "ChatGPT" : AIAccountBalanceCatalog.providerName($0) }.joined(separator: " / ")
    }

    /// Reserves the first of at most two lines for a canonical 5h or rolling window.
    /// Additional feature windows keep their true names in the remaining summary and never replace that slot.
    public func compactLines(language: AppLanguage) -> [String] {
        guard severity != nil else { return [] }
        let short = fiveHourWindow
            ?? windows.first { $0.kind == .rolling && !$0.id.hasPrefix("additional:") }
        let weekly = weeklyWindow
        var remaining = windows.filter { $0.id != short?.id && $0.id != weekly?.id }
        if let index = remaining.firstIndex(where: { $0.id == limitingWindow?.id }), index > 0 {
            remaining.insert(remaining.remove(at: index), at: 0)
        }
        var lines: [String] = []
        if let short {
            lines.append(short.label(language: language) + " " + short.value(language: language))
        }
        if let weekly { lines.append("7d " + weekly.value(language: language)) }
        if !remaining.isEmpty {
            let values = remaining.map { window in
                let value = window.value(language: language)
                return window.kind == .all && window.name == nil && window.nameKey == nil ? value : window.label(language: language) + " " + value
            }
            let summary = AppLocalization.string("全部", language: language) + " " + values.joined(separator: " · ")
            if lines.count == 2 { lines[1] += " · " + summary }
            else { lines.append(summary) }
        }
        return lines
    }

    public static func isLowBalanceNotice(_ notice: IslandNotice) -> Bool {
        notice.id.hasPrefix("ai-balance-low-")
    }
}

public enum AIAccountBalanceCatalog {
    public static func supportsBalanceQuery(_ provider: AIProvider) -> Bool {
        let status = placeholder(for: [provider]).status
        return status == .notSignedIn || status == .additionalCredentialsRequired
    }

    /// Live aliases require both monitoring and display; explicit debug aliases override those selections.
    public static func displayedBalances(_ balances: [AIAccountBalance], monitoredProviders: Set<AIProvider>,
                                        displayedProviders: Set<AIProvider>) -> [AIAccountBalance] {
        balances.compactMap { balance in
            guard balance.severity != nil else { return nil }
            var row = balance
            row.providers = row.providers.filter {
                balance.isDebug || (supportsBalanceQuery($0) && monitoredProviders.contains($0) && displayedProviders.contains($0))
            }
            return row.providers.isEmpty ? nil : row
        }
    }

    public static func providerName(_ provider: AIProvider) -> String {
        switch provider {
        case .claude: "Claude"
        case .codex: "Codex"
        case .gpt: "GPT"
        case .gemini: "Gemini"
        case .grok: "Grok"
        case .copilot: "Copilot"
        case .kimi: "Kimi"
        case .qwen: "Qwen"
        case .coder: "Qoder"
        case .zcode: "ZCode"
        case .zed: "Zed"
        case .trae: "TRAE"
        case .opencode: "OpenCode"
        case .harness: "Harness"
        case .doubao: "Doubao"
        case .pi: "Pi"
        case .delta: "Delta"
        case .orca: "Orca"
        case .workbuddy: "WorkBuddy"
        case .workbuddyAI: "WorkBuddy AI"
        case .cursor: "Cursor"
        case .grokBot: "Grok Bot"
        case .muse: "Muse Code"
        }
    }
    /// Shared-account aliases occupy one query group while keeping every provider selectable in the UI.
    public static var groups: [[AIProvider]] {
        var seen: Set<AIProvider> = []
        return AIProvider.allCases.compactMap { provider in
            guard !seen.contains(provider) else { return nil }
            let group: [AIProvider] = switch provider {
            case .codex, .gpt: [.codex, .gpt]
            case .cursor, .grokBot: [.cursor, .grokBot]
            default: [provider]
            }
            seen.formUnion(group)
            return group
        }
    }

    /// Classifies a nonempty account group without claiming a balance or requiring unsupported login access.
    public static func placeholder(for providers: [AIProvider]) -> AIAccountBalance {
        let provider = providers[0]
        let status: AIAccountBalanceStatus = switch provider {
        case .pi, .harness, .orca: .connectedAccount
        case .qwen, .doubao, .delta: .queryUnsupported
        case .coder, .trae: .additionalCredentialsRequired
        default: .notSignedIn
        }
        let detail: String? = switch provider {
        case .coder, .trae: "需要网站登录凭据，桌面登录暂不能用于额度查询"
        case .qwen, .doubao, .delta: "供应商未提供已验证的本地额度查询接口"
        default: nil
        }
        return .init(id: provider.rawValue, providers: providers, status: status, detailKey: detail)
    }

    public static var placeholders: [AIAccountBalance] { groups.map(placeholder(for:)) }
}
