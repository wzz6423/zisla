import Foundation

/// Common protocols supported by AI Agents. Custom channels can still connect via the OpenAI-compatible protocol.
public enum AgentChannelProtocol: String, Codable, CaseIterable, Sendable {
    case openAICompatible
    case anthropicMessages
    case geminiGenerateContent

    public var displayName: String {
        switch self {
        case .openAICompatible: "OpenAI 兼容"
        case .anthropicMessages: "Anthropic Messages"
        case .geminiGenerateContent: "Gemini"
        }
    }
}

public enum AgentBalanceProbeKind: String, Codable, CaseIterable, Sendable {
    /// OpenAI organization credit grants endpoint; requires an API Key with the appropriate permissions.
    case openAICredits
    /// Anthropic official usage report. This endpoint does not return a prepaid balance; it only records consumed quota.
    case anthropicUsage
    /// User quota endpoint for common compatible gateways such as New API and One API.
    case newAPIQuota
    /// User-specified local executable; stdout must be a balance JSON. Not shell-expanded.
    case customScript

    public var displayName: String {
        switch self {
        case .openAICredits: "OpenAI 官方额度"
        case .anthropicUsage: "Anthropic 官方用量"
        case .newAPIQuota: "New API 兼容额度"
        case .customScript: "自定义脚本"
        }
    }
}

public struct AgentBalanceProbe: Codable, Equatable, Sendable {
    public var kind: AgentBalanceProbeKind
    /// Absolute path to the custom script; not shell-expanded.
    public var scriptPath: String?
    public var minimumBalance: Double?

    public init(
        kind: AgentBalanceProbeKind = .newAPIQuota,
        scriptPath: String? = nil,
        minimumBalance: Double? = nil
    ) {
        self.kind = kind
        self.scriptPath = scriptPath
        self.minimumBalance = minimumBalance.map { max(0, $0) }
    }
}

public struct AgentBalanceSnapshot: Codable, Equatable, Sendable {
    public var available: Double?
    public var used: Double?
    public var currency: String
    public var checkedAt: Date
    public var detail: String?

    public init(
        available: Double?,
        used: Double? = nil,
        currency: String = "USD",
        checkedAt: Date = Date(),
        detail: String? = nil
    ) {
        self.available = available
        self.used = used
        self.currency = currency
        self.checkedAt = checkedAt
        self.detail = detail
    }
}

public enum AgentAccountCredentialKind: String, Codable, CaseIterable, Sendable {
    case apiKey
    case cliProfile

    public var displayName: String {
        switch self {
        case .apiKey: "API Key"
        case .cliProfile: "CLI 登录档案"
        }
    }
}

/// A CLI configuration consists of config and authentication files. Their contents are stored in secure credentials; state records only their target paths.
public struct AgentCLIProfile: Codable, Equatable, Sendable {
    public var cliKind: AgentCLIKind
    public var configurationFilePath: String
    public var authenticationFilePath: String

    public init(
        cliKind: AgentCLIKind,
        configurationFilePath: String? = nil,
        authenticationFilePath: String? = nil
    ) {
        let defaults = Self.defaultFilePaths(for: cliKind)
        self.cliKind = cliKind
        self.configurationFilePath = configurationFilePath ?? defaults.configuration
        self.authenticationFilePath = authenticationFilePath ?? defaults.authentication
    }

    public var isComplete: Bool {
        configurationFilePath.hasPrefix("/")
            && authenticationFilePath.hasPrefix("/")
            && configurationFilePath != authenticationFilePath
    }

    public static func defaultFilePaths(for kind: AgentCLIKind) -> (configuration: String, authentication: String) {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return switch kind {
        case .codex:
            ("\(home)/.codex/config.toml", "\(home)/.codex/auth.json")
        case .claude:
            ("\(home)/.claude.json", "\(home)/.claude/.credentials.json")
        case .gemini:
            ("\(home)/.gemini/settings.json", "\(home)/.gemini/oauth_creds.json")
        case .grok:
            ("\(home)/.grok/config.toml", "\(home)/.grok/auth.json")
        case .opencode:
            ("\(home)/.config/opencode/opencode.json", "\(home)/.local/share/opencode/auth.json")
        case .kimi, .qwen, .qoder, .copilot, .glm:
            ("", "")
        }
    }
}

/// Each account maps to one secure credential record; `secretReference` is not the API key itself.
public struct AgentAccount: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var provider: String
    public var secretReference: String
    public var credentialKind: AgentAccountCredentialKind
    public var cliProfile: AgentCLIProfile?
    public var isEnabled: Bool
    public var balanceProbe: AgentBalanceProbe?
    public var balance: AgentBalanceSnapshot?
    public var consecutiveFailures: Int
    public var disabledUntil: Date?

    public init(
        id: UUID = UUID(),
        name: String,
        provider: String,
        secretReference: String? = nil,
        credentialKind: AgentAccountCredentialKind = .apiKey,
        cliProfile: AgentCLIProfile? = nil,
        isEnabled: Bool = true,
        balanceProbe: AgentBalanceProbe? = nil,
        balance: AgentBalanceSnapshot? = nil,
        consecutiveFailures: Int = 0,
        disabledUntil: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.provider = provider
        self.secretReference = secretReference ?? id.uuidString
        self.credentialKind = credentialKind
        self.cliProfile = cliProfile
        self.isEnabled = isEnabled
        self.balanceProbe = balanceProbe
        self.balance = balance
        self.consecutiveFailures = max(0, consecutiveFailures)
        self.disabledUntil = disabledUntil
    }

    public func isEligible(at date: Date = Date()) -> Bool {
        guard isEnabled, disabledUntil.map({ $0 <= date }) != false else { return false }
        guard let threshold = balanceProbe?.minimumBalance,
              let available = balance?.available else {
            return true
        }
        return available >= threshold
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case provider
        case secretReference
        case credentialKind
        case cliProfile
        case isEnabled
        case balanceProbe
        case balance
        case consecutiveFailures
        case disabledUntil
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        provider = try container.decode(String.self, forKey: .provider)
        secretReference = try container.decodeIfPresent(String.self, forKey: .secretReference) ?? id.uuidString
        credentialKind = try container.decodeIfPresent(AgentAccountCredentialKind.self, forKey: .credentialKind) ?? .apiKey
        cliProfile = try container.decodeIfPresent(AgentCLIProfile.self, forKey: .cliProfile)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        balanceProbe = try container.decodeIfPresent(AgentBalanceProbe.self, forKey: .balanceProbe)
        balance = try container.decodeIfPresent(AgentBalanceSnapshot.self, forKey: .balance)
        consecutiveFailures = max(0, try container.decodeIfPresent(Int.self, forKey: .consecutiveFailures) ?? 0)
        disabledUntil = try container.decodeIfPresent(Date.self, forKey: .disabledUntil)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(provider, forKey: .provider)
        try container.encode(secretReference, forKey: .secretReference)
        try container.encode(credentialKind, forKey: .credentialKind)
        try container.encodeIfPresent(cliProfile, forKey: .cliProfile)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encodeIfPresent(balanceProbe, forKey: .balanceProbe)
        try container.encodeIfPresent(balance, forKey: .balance)
        try container.encode(consecutiveFailures, forKey: .consecutiveFailures)
        try container.encodeIfPresent(disabledUntil, forKey: .disabledUntil)
    }
}

/// Binds a set of URLs to a set of Keys so that multiple URLs and multiple Keys can be jointly rotated on the same channel.
public struct AgentEndpointGroup: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var baseURLs: [String]
    public var accountIDs: [UUID]
    public var isEnabled: Bool
    public var priority: Int

    public init(
        id: UUID = UUID(),
        name: String,
        baseURLs: [String],
        accountIDs: [UUID],
        isEnabled: Bool = true,
        priority: Int = 0
    ) {
        self.id = id
        self.name = name
        self.baseURLs = Self.normalizedURLs(baseURLs)
        var seenAccountIDs = Set<UUID>()
        self.accountIDs = accountIDs.filter { seenAccountIDs.insert($0).inserted }
        self.isEnabled = isEnabled
        self.priority = priority
    }

    public static func normalizedURLs(_ urls: [String]) -> [String] {
        var seen = Set<String>()
        return urls.compactMap { raw in
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, seen.insert(value).inserted else { return nil }
            return value
        }
    }
}

public struct AgentChannel: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var protocolKind: AgentChannelProtocol
    public var defaultModel: String
    public var endpointGroups: [AgentEndpointGroup]
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        protocolKind: AgentChannelProtocol = .openAICompatible,
        defaultModel: String = "",
        endpointGroups: [AgentEndpointGroup] = [],
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.protocolKind = protocolKind
        self.defaultModel = defaultModel
        self.endpointGroups = endpointGroups
        self.isEnabled = isEnabled
    }
}

/// The local model's connection URL is managed only within AI Agent; voice input selects it by ID without duplicating URL configuration.
public struct AIAgentLocalModel: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var endpoint: AIEndpoint
    public var modelName: String
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        endpoint: AIEndpoint,
        modelName: String,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.endpoint = endpoint
        self.modelName = modelName
        self.isEnabled = isEnabled
    }
}

public struct AgentRoute: Equatable, Sendable {
    public var channelID: UUID
    public var endpointGroupID: UUID
    public var accountID: UUID
    public var baseURL: String
    public var protocolKind: AgentChannelProtocol
    public var model: String

    public init(
        channelID: UUID,
        endpointGroupID: UUID,
        accountID: UUID,
        baseURL: String,
        protocolKind: AgentChannelProtocol,
        model: String
    ) {
        self.channelID = channelID
        self.endpointGroupID = endpointGroupID
        self.accountID = accountID
        self.baseURL = baseURL
        self.protocolKind = protocolKind
        self.model = model
    }
}

/// Polls round-robin across the highest-priority available URL/Key combinations in stable order.
public struct AgentRouteRouter: Sendable {
    private struct EndpointKey: Hashable, Sendable {
        var channelID: UUID
        var endpointGroupID: UUID
        var baseURL: String
    }

    private struct EndpointFailure: Sendable {
        var count: Int
        var lastFailureAt: Date
        var disabledUntil: Date?
    }

    private var cursors: [UUID: Int] = [:]
    private var endpointFailures: [EndpointKey: EndpointFailure] = [:]

    public init() {}

    public mutating func nextRoute(
        for channel: AgentChannel,
        accounts: [AgentAccount],
        model: String? = nil,
        at date: Date = Date(),
        unavailableEndpointGroupIDs: Set<UUID> = []
    ) -> AgentRoute? {
        routes(
            for: channel,
            accounts: accounts,
            model: model,
            at: date,
            unavailableEndpointGroupIDs: unavailableEndpointGroupIDs
        ).first
    }

    public mutating func routes(
        for channel: AgentChannel,
        accounts: [AgentAccount],
        model: String? = nil,
        at date: Date = Date(),
        unavailableEndpointGroupIDs: Set<UUID> = []
    ) -> [AgentRoute] {
        guard channel.isEnabled else { return [] }
        let selectedModel = (model ?? channel.defaultModel).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selectedModel.isEmpty else { return [] }
        let accountByID = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
        let groups = channel.endpointGroups.enumerated()
            .filter { $0.element.isEnabled && !unavailableEndpointGroupIDs.contains($0.element.id) }
            .sorted {
                if $0.element.priority != $1.element.priority {
                    return $0.element.priority > $1.element.priority
                }
                return $0.offset < $1.offset
            }
            .map(\.element)
        let priorities = Array(Set(groups.map(\.priority))).sorted(by: >)
        var candidatesByPriority: [[(group: AgentEndpointGroup, url: String, account: AgentAccount)]] = []
        for priority in priorities {
            let candidates = groups.filter { $0.priority == priority }.flatMap { group in
                let eligibleAccounts = group.accountIDs.compactMap { id in
                    accountByID[id].flatMap { $0.isEligible(at: date) ? $0 : nil }
                }
                return group.baseURLs.filter { url in
                    endpointIsAvailable(
                        channelID: channel.id,
                        endpointGroupID: group.id,
                        baseURL: url,
                        at: date
                    )
                }.flatMap { url in
                    eligibleAccounts.map { (group: group, url: url, account: $0) }
                }
            }
            if !candidates.isEmpty { candidatesByPriority.append(candidates) }
        }
        guard let leadingCandidates = candidatesByPriority.first else { return [] }
        let cursor = cursors[channel.id, default: 0]
        cursors[channel.id] = (cursor + 1) % leadingCandidates.count
        return candidatesByPriority.flatMap { candidates in
            let offset = cursor % candidates.count
            let ordered = Array(candidates[offset...]) + Array(candidates[..<offset])
            return ordered.map { candidate in
                AgentRoute(
                    channelID: channel.id,
                    endpointGroupID: candidate.group.id,
                    accountID: candidate.account.id,
                    baseURL: candidate.url,
                    protocolKind: channel.protocolKind,
                    model: selectedModel
                )
            }
        }
    }

    public mutating func recordFailure(for route: AgentRoute, at date: Date = Date()) {
        let key = endpointKey(for: route)
        var failure = endpointFailures[key] ?? EndpointFailure(
            count: 0,
            lastFailureAt: date,
            disabledUntil: nil
        )
        if date.timeIntervalSince(failure.lastFailureAt) >= 5 * 60 {
            failure.count = 0
        }
        failure.count += 1
        failure.lastFailureAt = date
        if failure.count >= 2 {
            failure.disabledUntil = date.addingTimeInterval(5 * 60)
        }
        endpointFailures[key] = failure
    }

    public mutating func recordSuccess(for route: AgentRoute) {
        endpointFailures.removeValue(forKey: endpointKey(for: route))
    }

    private mutating func endpointIsAvailable(
        channelID: UUID,
        endpointGroupID: UUID,
        baseURL: String,
        at date: Date
    ) -> Bool {
        let key = EndpointKey(
            channelID: channelID,
            endpointGroupID: endpointGroupID,
            baseURL: baseURL
        )
        guard let failure = endpointFailures[key], let disabledUntil = failure.disabledUntil else {
            return true
        }
        guard disabledUntil > date else {
            endpointFailures.removeValue(forKey: key)
            return true
        }
        return false
    }

    private func endpointKey(for route: AgentRoute) -> EndpointKey {
        EndpointKey(
            channelID: route.channelID,
            endpointGroupID: route.endpointGroupID,
            baseURL: route.baseURL
        )
    }
}

public enum AgentChannelHealth: String, Codable, Sendable {
    case unknown
    case healthy
    case degraded
    case unavailable
}

public struct AgentChannelProbe: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var channelID: UUID
    public var endpointGroupID: UUID
    public var baseURL: String
    public var health: AgentChannelHealth
    public var latencyMilliseconds: Int?
    public var detail: String?
    public var checkedAt: Date

    public init(
        id: UUID = UUID(),
        channelID: UUID,
        endpointGroupID: UUID,
        baseURL: String,
        health: AgentChannelHealth,
        latencyMilliseconds: Int? = nil,
        detail: String? = nil,
        checkedAt: Date = Date()
    ) {
        self.id = id
        self.channelID = channelID
        self.endpointGroupID = endpointGroupID
        self.baseURL = baseURL
        self.health = health
        self.latencyMilliseconds = latencyMilliseconds
        self.detail = detail
        self.checkedAt = checkedAt
    }
}

/// Cached available models read from a channel's model-list endpoint; stores no authentication information.
public struct AgentChannelModelCatalog: Identifiable, Codable, Equatable, Sendable {
    public var id: String { "\(channelID.uuidString)|\(endpointGroupID.uuidString)|\(baseURL)" }
    public var channelID: UUID
    public var endpointGroupID: UUID
    public var baseURL: String
    public var models: [String]
    public var checkedAt: Date
    public var detail: String?

    public init(
        channelID: UUID,
        endpointGroupID: UUID,
        baseURL: String,
        models: [String],
        checkedAt: Date = Date(),
        detail: String? = nil
    ) {
        self.channelID = channelID
        self.endpointGroupID = endpointGroupID
        self.baseURL = baseURL
        self.models = Array(Set(models.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }))
            .sorted()
        self.checkedAt = checkedAt
        self.detail = detail
    }
}

public enum AgentCLIKind: String, Codable, CaseIterable, Sendable {
    case claude
    case codex
    case gemini
    case grok
    case opencode
    case kimi
    case qwen
    case qoder
    case copilot
    case glm

    public static let detectableCases = allCases
    public static let relayCases: [Self] = [.claude, .codex, .gemini, .grok, .opencode]
    public static let profileCases = relayCases
    public static let managedCases = allCases

    public var displayName: String {
        switch self {
        case .kimi: "Kimi Code"
        case .qwen: "Qwen Code"
        case .qoder: "Qoder CLI"
        case .copilot: "Copilot"
        case .glm: "GLM Coding"
        default: rawValue.capitalized
        }
    }

    public var executableName: String {
        switch self {
        case .qoder: "qodercli"
        case .glm: "chelper"
        default: rawValue
        }
    }

    public var npmPackageName: String? {
        switch self {
        case .claude: "@anthropic-ai/claude-code"
        case .codex: "@openai/codex"
        case .gemini: "@google/gemini-cli"
        case .opencode: "opencode-ai"
        case .qwen: "@qwen-code/qwen-code"
        case .qoder: "@qoder-ai/qodercli"
        case .copilot: "@github/copilot"
        case .glm: "@z_ai/coding-helper"
        case .grok, .kimi: nil
        }
    }
}

/// The original VS Code values captured before Zisla changes the Claude Code extension settings.
/// Keeping this with the agent state makes disabling the integration reversible across app launches.
public struct ClaudeCodeVSCodeSettingsSnapshot: Codable, Equatable, Sendable {
    public var environmentVariables: [String: String]?
    public var hideOnboarding: Bool?
    public var managedEnvironmentVariableNames: [String]
    public var managesOnboarding: Bool

    public init(
        environmentVariables: [String: String]? = nil,
        hideOnboarding: Bool? = nil,
        managedEnvironmentVariableNames: [String] = [],
        managesOnboarding: Bool = false
    ) {
        self.environmentVariables = environmentVariables
        self.hideOnboarding = hideOnboarding
        self.managedEnvironmentVariableNames = Array(Set(managedEnvironmentVariableNames)).sorted()
        self.managesOnboarding = managesOnboarding
    }
}

/// Optional integrations that update local Codex and Claude Code applications while a CLI profile switches.
public struct AgentApplicationEnhancements: Codable, Equatable, Sendable {
    public var preservesCodexOfficialLogin: Bool
    public var unifiesCodexHistory: Bool
    public var claudeCodeVSCodeFollowsProvider: Bool
    public var skipsClaudeCodeOnboarding: Bool
    public var claudeCodeVSCodeSettingsSnapshot: ClaudeCodeVSCodeSettingsSnapshot?

    public init(
        preservesCodexOfficialLogin: Bool = false,
        unifiesCodexHistory: Bool = false,
        claudeCodeVSCodeFollowsProvider: Bool = false,
        skipsClaudeCodeOnboarding: Bool = false,
        claudeCodeVSCodeSettingsSnapshot: ClaudeCodeVSCodeSettingsSnapshot? = nil
    ) {
        self.preservesCodexOfficialLogin = preservesCodexOfficialLogin
        self.unifiesCodexHistory = unifiesCodexHistory
        self.claudeCodeVSCodeFollowsProvider = claudeCodeVSCodeFollowsProvider
        self.skipsClaudeCodeOnboarding = skipsClaudeCodeOnboarding
        self.claudeCodeVSCodeSettingsSnapshot = claudeCodeVSCodeSettingsSnapshot
    }
}

public enum AgentSkillSyncMode: String, Codable, CaseIterable, Sendable {
    case symbolicLink
    case fileCopy

    public var displayName: String {
        switch self {
        case .symbolicLink: "软链接"
        case .fileCopy: "文件复制"
        }
    }

    public var detail: String {
        switch self {
        case .symbolicLink: "节省磁盘空间，修改后立即同步到已启用的 CLI。"
        case .fileCopy: "每次同步复制一份独立文件，适合不支持软链接的环境。"
        }
    }
}

public enum AgentSkillSyncDestination: String, Codable, CaseIterable, Sendable {
    case codex
    case claude
    case agents

    public var displayName: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude Code"
        case .agents: "Agents"
        }
    }
}

public struct AgentSkillSyncConfiguration: Codable, Equatable, Sendable {
    public var mode: AgentSkillSyncMode
    public var enabledDestinations: Set<AgentSkillSyncDestination>

    public init(
        mode: AgentSkillSyncMode = .symbolicLink,
        enabledDestinations: Set<AgentSkillSyncDestination> = []
    ) {
        self.mode = mode
        self.enabledDestinations = enabledDestinations
    }
}

public struct AgentCLIStatus: Identifiable, Codable, Equatable, Sendable {
    public var id: AgentCLIKind { kind }
    public var kind: AgentCLIKind
    public var executablePath: String?
    public var version: String?
    public var checkedAt: Date

    public init(
        kind: AgentCLIKind,
        executablePath: String? = nil,
        version: String? = nil,
        checkedAt: Date = Date()
    ) {
        self.kind = kind
        self.executablePath = executablePath
        self.version = version
        self.checkedAt = checkedAt
    }
}

public struct AIAgentCLIUpdate: Identifiable, Equatable, Sendable {
    public var id: AgentCLIKind { kind }
    public var kind: AgentCLIKind
    public var installedVersion: String
    public var latestVersion: String

    public init(kind: AgentCLIKind, installedVersion: String, latestVersion: String) {
        self.kind = kind
        self.installedVersion = installedVersion
        self.latestVersion = latestVersion
    }
}

public struct AgentSkill: Identifiable, Codable, Equatable, Sendable {
    public var id: String { path }
    public var name: String
    public var path: String
    public var source: String
    public var isEnabled: Bool
    public var modifiedAt: Date?

    public init(name: String, path: String, source: String, isEnabled: Bool = true, modifiedAt: Date? = nil) {
        self.name = name
        self.path = path
        self.source = source
        self.isEnabled = isEnabled
        self.modifiedAt = modifiedAt
    }
}

public enum AgentAutomationTask: String, Codable, CaseIterable, Sendable {
    case balanceCheck
    case channelProbe
    case cliCheck
    case skillScan

    public var displayName: String {
        switch self {
        case .balanceCheck: "余额检测"
        case .channelProbe: "渠道监测"
        case .cliCheck: "CLI 检测"
        case .skillScan: "Skills 扫描"
        }
    }
}

/// The current version's automation runs on a fixed-minute interval while the app is running; it does not install a background daemon.
public struct AgentAutomation: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var task: AgentAutomationTask
    public var intervalMinutes: Int
    public var isEnabled: Bool
    public var lastRunAt: Date?
    public var nextRunAt: Date?

    public init(
        id: UUID = UUID(),
        name: String,
        task: AgentAutomationTask,
        intervalMinutes: Int = 30,
        isEnabled: Bool = true,
        lastRunAt: Date? = nil,
        nextRunAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.task = task
        self.intervalMinutes = max(1, intervalMinutes)
        self.isEnabled = isEnabled
        self.lastRunAt = lastRunAt
        self.nextRunAt = nextRunAt
    }
}

public enum AgentChatRole: String, Codable, Sendable {
    case system
    case user
    case assistant
}

public enum AgentChatMode: String, Codable, CaseIterable, Sendable {
    case standard
    case plan

    public var displayName: String {
        switch self {
        case .standard: "对话"
        case .plan: "计划"
        }
    }
}

public enum AgentChatAccessMode: String, Codable, CaseIterable, Sendable {
    case autoReview
    case readOnly
    case workspaceWrite
    case fullAccess

    public var displayName: String {
        switch self {
        case .autoReview: "Auto review"
        case .readOnly: "只读"
        case .workspaceWrite: "工作区写入"
        case .fullAccess: "完全访问"
        }
    }

    public var symbolName: String {
        switch self {
        case .autoReview: "shield.lefthalf.filled"
        case .readOnly: "eye"
        case .workspaceWrite: "pencil.and.list.clipboard"
        case .fullAccess: "exclamationmark.shield"
        }
    }
}

public enum AgentChatThinkingDepth: String, Codable, CaseIterable, Sendable {
    case low
    case medium
    case high
    case extraHigh

    public var displayName: String {
        switch self {
        case .low: "低"
        case .medium: "中"
        case .high: "高"
        case .extraHigh: "极高"
        }
    }
}

public enum AgentGoalStatus: String, Codable, CaseIterable, Sendable {
    case active
    case completed
    case abandoned

    public var displayName: String {
        switch self {
        case .active: "进行中"
        case .completed: "已完成"
        case .abandoned: "已停止"
        }
    }
}

public struct AgentGoal: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var status: AgentGoalStatus
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        status: AgentGoalStatus = .active,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

}

/// A GPT-style project groups related conversations and adds shared relay context.
public struct AgentChatProject: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var instructions: String
    public var directoryPath: String
    public var isPinned: Bool
    public var isCollapsed: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        instructions: String = "",
        directoryPath: String = "",
        isPinned: Bool = false,
        isCollapsed: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.instructions = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        self.directoryPath = directoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        self.isPinned = isPinned
        self.isCollapsed = isCollapsed
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case instructions
        case directoryPath
        case isPinned
        case isCollapsed
        case createdAt
        case updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        instructions = (try container.decodeIfPresent(String.self, forKey: .instructions))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        directoryPath = (try container.decodeIfPresent(String.self, forKey: .directoryPath))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        isCollapsed = try container.decodeIfPresent(Bool.self, forKey: .isCollapsed) ?? false
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(instructions, forKey: .instructions)
        try container.encode(directoryPath, forKey: .directoryPath)
        try container.encode(isPinned, forKey: .isPinned)
        try container.encode(isCollapsed, forKey: .isCollapsed)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

public enum AgentChatAttachmentKind: String, Codable, Sendable {
    case image
    case audio
    case file

    public var displayName: String {
        switch self {
        case .image: "图片"
        case .audio: "音频"
        case .file: "文件"
        }
    }
}

public enum AgentChatAttachmentState: String, Codable, Sendable {
    case active
    case archived
    case deleted
}

public struct AgentChatAttachment: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var fileName: String
    public var mimeType: String
    public var byteCount: Int64
    /// Relative to the AI Agent attachment directory, never an externally selected path.
    public var storagePath: String
    public var kind: AgentChatAttachmentKind
    public var state: AgentChatAttachmentState
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        fileName: String,
        mimeType: String,
        byteCount: Int64,
        storagePath: String,
        kind: AgentChatAttachmentKind,
        state: AgentChatAttachmentState = .active,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.fileName = fileName
        self.mimeType = mimeType
        self.byteCount = max(0, byteCount)
        self.storagePath = storagePath
        self.kind = kind
        self.state = state
        self.createdAt = createdAt
    }
}

public struct AgentChatContextMessage: Codable, Equatable, Sendable {
    public var role: AgentChatRole
    public var content: String

    public init(role: AgentChatRole, content: String) {
        self.role = role
        self.content = content
    }
}

/// A bounded history snapshot selected by the user through an @ mention.
public struct AgentChatContextReference: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID { threadID }
    public var threadID: UUID
    public var title: String
    public var messages: [AgentChatContextMessage]

    public init(threadID: UUID, title: String, messages: [AgentChatContextMessage]) {
        self.threadID = threadID
        self.title = title
        self.messages = messages
    }
}

/// A locally running application explicitly included through an @ reference.
public struct AgentChatAppReference: Identifiable, Codable, Equatable, Sendable {
    public var id: String { "\(bundleIdentifier)|\(processIdentifier)" }
    public var name: String
    public var bundleIdentifier: String
    public var processIdentifier: Int

    public init(name: String, bundleIdentifier: String, processIdentifier: Int) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.processIdentifier = processIdentifier
    }
}

/// A Skill explicitly selected for one forwarded user message.
public struct AgentChatSkillReference: Identifiable, Codable, Equatable, Sendable {
    public var id: String { path }
    public var name: String
    public var path: String

    public init(name: String, path: String) {
        self.name = name
        self.path = path
    }
}

public enum AgentChatSlashCommand: Equatable, Sendable {
    case message(content: String, skillReferences: [AgentChatSkillReference])
    case setMode(AgentChatMode, content: String)
    case setGoalPrompt(content: String)
}

public enum AgentChatSlashCommandError: LocalizedError, Equatable, Sendable {
    case missingSkillName
    case unavailableSkill(String)

    public var errorDescription: String? {
        switch self {
        case .missingSkillName:
            "请输入要调用的 Skill 名称。"
        case let .unavailableSkill(name):
            "未找到已启用的 Skill：\(name)。请在设置的 CLI 与 Skills 中启用它。"
        }
    }
}

/// Parses commands handled by the chat entry while leaving execution to the selected local CLI.
public enum AgentChatSlashCommandParser {
    public static func parse(
        _ rawValue: String,
        skills: [AgentSkill]
    ) throws -> AgentChatSlashCommand {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.hasPrefix("/") else {
            return .message(content: value, skillReferences: [])
        }

        let tokens = value.dropFirst().split(
            maxSplits: 1,
            omittingEmptySubsequences: true,
            whereSeparator: { $0.isWhitespace }
        )
        guard let commandToken = tokens.first else {
            return .message(content: value, skillReferences: [])
        }
        let command = commandToken.lowercased()
        let arguments = tokens.count > 1
            ? String(tokens[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            : ""

        // File paths are ordinary message content, not Skill invocations.
        guard !commandToken.contains("/") else {
            return .message(content: value, skillReferences: [])
        }

        switch command {
        case "plan":
            return .setMode(.plan, content: arguments)
        case "goal":
            return .setGoalPrompt(content: arguments)
        default:
            return try skillCommands(value, from: skills)
        }
    }

    private static func skillCommands(
        _ value: String,
        from skills: [AgentSkill]
    ) throws -> AgentChatSlashCommand {
        var remaining = value
        var references: [AgentChatSkillReference] = []

        while remaining.hasPrefix("/") {
            let tokens = remaining.dropFirst().split(
                maxSplits: 1,
                omittingEmptySubsequences: true,
                whereSeparator: { $0.isWhitespace }
            )
            guard let name = tokens.first else { break }
            guard !name.contains("/") else {
                break
            }
            let arguments = tokens.count > 1
                ? String(tokens[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                : ""

            let reference: AgentChatSkillReference
            if name.caseInsensitiveCompare("skill") == .orderedSame {
                guard !arguments.isEmpty else {
                    throw AgentChatSlashCommandError.missingSkillName
                }
                guard let match = skillMatch(in: arguments, from: skills) else {
                    let requested = arguments.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? arguments
                    throw AgentChatSlashCommandError.unavailableSkill(requested)
                }
                reference = AgentChatSkillReference(name: match.skill.name, path: match.skill.path)
                remaining = match.content
            } else {
                reference = try skillReference(named: String(name), from: skills)
                remaining = arguments
            }
            if !references.contains(reference) {
                references.append(reference)
            }
        }
        guard !references.isEmpty else {
            return .message(content: value, skillReferences: [])
        }
        return .message(content: remaining, skillReferences: references)
    }

    private static func skillReference(
        named name: String,
        from skills: [AgentSkill]
    ) throws -> AgentChatSkillReference {
        guard let skill = skills.first(where: {
            $0.isEnabled && $0.name.caseInsensitiveCompare(name) == .orderedSame
        }) else {
            throw AgentChatSlashCommandError.unavailableSkill(name)
        }
        return AgentChatSkillReference(name: skill.name, path: skill.path)
    }

    private static func skillMatch(
        in arguments: String,
        from skills: [AgentSkill]
    ) -> (skill: AgentSkill, content: String)? {
        skills
            .filter(\.isEnabled)
            .compactMap { skill -> (skill: AgentSkill, content: String)? in
                let name = skill.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty,
                      arguments.count >= name.count,
                      arguments.prefix(name.count).caseInsensitiveCompare(name) == .orderedSame else {
                    return nil
                }
                let remainder = String(arguments.dropFirst(name.count))
                guard remainder.isEmpty || remainder.first?.isWhitespace == true else { return nil }
                return (skill, remainder.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            .max { $0.skill.name.count < $1.skill.name.count }
    }
}

public struct AgentChatMessage: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var role: AgentChatRole
    public var content: String
    public var accountID: UUID?
    public var attachments: [AgentChatAttachment]
    public var contextReferences: [AgentChatContextReference]
    public var appReferences: [AgentChatAppReference]
    public var skillReferences: [AgentChatSkillReference]
    public var mode: AgentChatMode
    public var goalTitle: String?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        role: AgentChatRole,
        content: String,
        accountID: UUID? = nil,
        attachments: [AgentChatAttachment] = [],
        contextReferences: [AgentChatContextReference] = [],
        appReferences: [AgentChatAppReference] = [],
        skillReferences: [AgentChatSkillReference] = [],
        mode: AgentChatMode = .standard,
        goalTitle: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.accountID = accountID
        self.attachments = attachments
        self.contextReferences = contextReferences
        self.appReferences = appReferences
        self.skillReferences = skillReferences
        self.mode = mode
        self.goalTitle = goalTitle
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case role
        case content
        case accountID
        case attachments
        case contextReferences
        case appReferences
        case skillReferences
        case mode
        case goalTitle
        case createdAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        role = try container.decode(AgentChatRole.self, forKey: .role)
        content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        accountID = try container.decodeIfPresent(UUID.self, forKey: .accountID)
        attachments = try container.decodeIfPresent([AgentChatAttachment].self, forKey: .attachments) ?? []
        contextReferences = try container.decodeIfPresent([AgentChatContextReference].self, forKey: .contextReferences) ?? []
        appReferences = try container.decodeIfPresent([AgentChatAppReference].self, forKey: .appReferences) ?? []
        skillReferences = try container.decodeIfPresent([AgentChatSkillReference].self, forKey: .skillReferences) ?? []
        mode = try container.decodeIfPresent(AgentChatMode.self, forKey: .mode) ?? .standard
        goalTitle = try container.decodeIfPresent(String.self, forKey: .goalTitle)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(role, forKey: .role)
        try container.encode(content, forKey: .content)
        try container.encodeIfPresent(accountID, forKey: .accountID)
        try container.encode(attachments, forKey: .attachments)
        try container.encode(contextReferences, forKey: .contextReferences)
        try container.encode(appReferences, forKey: .appReferences)
        try container.encode(skillReferences, forKey: .skillReferences)
        try container.encode(mode, forKey: .mode)
        try container.encodeIfPresent(goalTitle, forKey: .goalTitle)
        try container.encode(createdAt, forKey: .createdAt)
    }
}

public struct AgentChatAnnotation: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var threadID: UUID
    public var messageID: UUID
    public var selectedText: String
    public var comment: String
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        threadID: UUID,
        messageID: UUID,
        selectedText: String,
        comment: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.threadID = threadID
        self.messageID = messageID
        self.selectedText = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        self.comment = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        self.createdAt = createdAt
    }
}

public enum AgentConfirmationState: String, Codable, Sendable {
    case pending
    case confirmed
    case declined
}

public struct AgentConfirmation: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var threadID: UUID
    public var title: String
    public var detail: String?
    public var state: AgentConfirmationState
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        threadID: UUID,
        title: String,
        detail: String? = nil,
        state: AgentConfirmationState = .pending,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.threadID = threadID
        self.title = title
        self.detail = detail
        self.state = state
        self.createdAt = createdAt
    }
}

public struct AgentChatThread: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var channelID: UUID?
    /// Local models share the same configuration source as voice processing, but do not need an account/channel.
    public var localModelID: UUID?
    public var cliKind: AgentCLIKind?
    public var accountID: UUID?
    /// Stable identifier for a source conversation imported into Zisla's unified history.
    public var externalHistoryID: String?
    public var mode: AgentChatMode
    public var goalID: UUID?
    /// Non-nil while goal mode is enabled: the composer input becomes this session's goal prompt.
    /// instead of creating an external `AgentGoal`.
    public var goalPrompt: String?
    public var projectID: UUID?
    public var accessMode: AgentChatAccessMode
    public var selectedModel: String?
    public var thinkingDepth: AgentChatThinkingDepth
    public var isPinned: Bool
    public var archivedAt: Date?
    public var messages: [AgentChatMessage]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String = "新对话",
        channelID: UUID? = nil,
        localModelID: UUID? = nil,
        cliKind: AgentCLIKind? = nil,
        accountID: UUID? = nil,
        externalHistoryID: String? = nil,
        mode: AgentChatMode = .standard,
        goalID: UUID? = nil,
        goalPrompt: String? = nil,
        projectID: UUID? = nil,
        accessMode: AgentChatAccessMode = .autoReview,
        selectedModel: String? = nil,
        thinkingDepth: AgentChatThinkingDepth = .high,
        isPinned: Bool = false,
        archivedAt: Date? = nil,
        messages: [AgentChatMessage] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.channelID = channelID
        self.localModelID = localModelID
        self.cliKind = cliKind
        self.accountID = accountID
        self.externalHistoryID = externalHistoryID
        self.mode = mode
        self.goalID = goalID
        self.goalPrompt = goalPrompt
        self.projectID = projectID
        self.accessMode = accessMode
        self.selectedModel = selectedModel?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.thinkingDepth = thinkingDepth
        self.isPinned = isPinned
        self.archivedAt = archivedAt
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case channelID
        case localModelID
        case cliKind
        case accountID
        case externalHistoryID
        case mode
        case goalID
        case goalPrompt
        case projectID
        case accessMode
        case selectedModel
        case thinkingDepth
        case isPinned
        case archivedAt
        case messages
        case createdAt
        case updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "新对话"
        channelID = try container.decodeIfPresent(UUID.self, forKey: .channelID)
        localModelID = try container.decodeIfPresent(UUID.self, forKey: .localModelID)
        cliKind = try container.decodeIfPresent(AgentCLIKind.self, forKey: .cliKind)
        accountID = try container.decodeIfPresent(UUID.self, forKey: .accountID)
        externalHistoryID = try container.decodeIfPresent(String.self, forKey: .externalHistoryID)
        mode = try container.decodeIfPresent(AgentChatMode.self, forKey: .mode) ?? .standard
        goalID = try container.decodeIfPresent(UUID.self, forKey: .goalID)
        goalPrompt = try container.decodeIfPresent(String.self, forKey: .goalPrompt)
        projectID = try container.decodeIfPresent(UUID.self, forKey: .projectID)
        accessMode = try container.decodeIfPresent(AgentChatAccessMode.self, forKey: .accessMode) ?? .autoReview
        selectedModel = try container.decodeIfPresent(String.self, forKey: .selectedModel)
        thinkingDepth = try container.decodeIfPresent(AgentChatThinkingDepth.self, forKey: .thinkingDepth) ?? .high
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        archivedAt = try container.decodeIfPresent(Date.self, forKey: .archivedAt)
        messages = try container.decodeIfPresent([AgentChatMessage].self, forKey: .messages) ?? []
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(channelID, forKey: .channelID)
        try container.encodeIfPresent(localModelID, forKey: .localModelID)
        try container.encodeIfPresent(cliKind, forKey: .cliKind)
        try container.encodeIfPresent(accountID, forKey: .accountID)
        try container.encodeIfPresent(externalHistoryID, forKey: .externalHistoryID)
        try container.encode(mode, forKey: .mode)
        try container.encodeIfPresent(goalID, forKey: .goalID)
        try container.encodeIfPresent(goalPrompt, forKey: .goalPrompt)
        try container.encodeIfPresent(projectID, forKey: .projectID)
        try container.encode(accessMode, forKey: .accessMode)
        try container.encodeIfPresent(selectedModel, forKey: .selectedModel)
        try container.encode(thinkingDepth, forKey: .thinkingDepth)
        try container.encode(isPinned, forKey: .isPinned)
        try container.encodeIfPresent(archivedAt, forKey: .archivedAt)
        try container.encode(messages, forKey: .messages)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

public enum AgentMessageConnectionKind: String, Codable, CaseIterable, Sendable {
    case feishu
    case weChatOfficial
    case webhook

    public var displayName: String {
        switch self {
        case .feishu: "飞书"
        case .weChatOfficial: "微信公众号"
        case .webhook: "通用 Webhook"
        }
    }
}

/// Platform passwords and tokens are stored separately in secure credentials; state records only connection behavior and callback addresses.
public struct AgentMessageConnectionCredentials: Codable, Equatable, Sendable {
    public var appID: String
    public var appSecret: String
    public var verificationToken: String
    public var outboundURL: String

    public init(
        appID: String = "",
        appSecret: String = "",
        verificationToken: String = "",
        outboundURL: String = ""
    ) {
        self.appID = appID
        self.appSecret = appSecret
        self.verificationToken = verificationToken
        self.outboundURL = outboundURL
    }
}

public struct AgentMessageConnection: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: AgentMessageConnectionKind
    public var callbackBaseURL: String
    public var listenerPort: Int
    public var cliKind: AgentCLIKind?
    public var accountID: UUID?
    public var isEnabled: Bool
    public var lastError: String?
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        kind: AgentMessageConnectionKind,
        callbackBaseURL: String = "",
        listenerPort: Int = 8787,
        cliKind: AgentCLIKind? = nil,
        accountID: UUID? = nil,
        isEnabled: Bool = true,
        lastError: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.callbackBaseURL = callbackBaseURL
        self.listenerPort = min(max(listenerPort, 1_024), 65_535)
        self.cliKind = cliKind
        self.accountID = accountID
        self.isEnabled = isEnabled
        self.lastError = lastError
        self.updatedAt = updatedAt
    }

    public var callbackPath: String {
        "/ai-agent/connect/\(id.uuidString.lowercased())"
    }

    public var callbackURL: String? {
        let base = callbackBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return nil }
        return base.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + callbackPath
    }

    public var credentialReference: String {
        "message-connection.\(id.uuidString)"
    }
}

/// Maps external sessions consistently to unified chat histories so contexts never mix across platforms or contacts.
public struct AgentMessageConversation: Identifiable, Codable, Equatable, Sendable {
    public var id: String { "\(connectionID.uuidString)|\(externalConversationID)" }
    public var connectionID: UUID
    public var externalConversationID: String
    public var threadID: UUID
    public var updatedAt: Date

    public init(
        connectionID: UUID,
        externalConversationID: String,
        threadID: UUID,
        updatedAt: Date = Date()
    ) {
        self.connectionID = connectionID
        self.externalConversationID = externalConversationID
        self.threadID = threadID
        self.updatedAt = updatedAt
    }
}

public struct AIAgentState: Codable, Equatable, Sendable {
    public var accounts: [AgentAccount]
    public var channels: [AgentChannel]
    public var localModels: [AIAgentLocalModel]
    public var channelProbes: [AgentChannelProbe]
    public var channelModelCatalogs: [AgentChannelModelCatalog]
    public var cliStatuses: [AgentCLIStatus]
    public var cliAutoUpdateEnabled: Bool
    public var skills: [AgentSkill]
    public var skillSyncConfiguration: AgentSkillSyncConfiguration
    public var applicationEnhancements: AgentApplicationEnhancements
    public var automations: [AgentAutomation]
    public var goals: [AgentGoal]
    public var projects: [AgentChatProject]
    public var chatThreads: [AgentChatThread]
    public var annotations: [AgentChatAnnotation]
    public var confirmations: [AgentConfirmation]
    public var messageConnections: [AgentMessageConnection]
    public var messageConversations: [AgentMessageConversation]
    /// The last CLI profile account ID activated by AI Agent, used to save back CLI-refreshed auth files before switching.
    public var activeCLIProfileAccountID: UUID?
    /// Whether the active CLI profile intentionally leaves its authentication file under external ownership.
    public var activeCLIProfilePreservesAuthentication: Bool

    public init(
        accounts: [AgentAccount] = [],
        channels: [AgentChannel] = [],
        localModels: [AIAgentLocalModel] = [],
        channelProbes: [AgentChannelProbe] = [],
        channelModelCatalogs: [AgentChannelModelCatalog] = [],
        cliStatuses: [AgentCLIStatus] = [],
        cliAutoUpdateEnabled: Bool = false,
        skills: [AgentSkill] = [],
        skillSyncConfiguration: AgentSkillSyncConfiguration = AgentSkillSyncConfiguration(),
        applicationEnhancements: AgentApplicationEnhancements = AgentApplicationEnhancements(),
        automations: [AgentAutomation] = [],
        goals: [AgentGoal] = [],
        projects: [AgentChatProject] = [],
        chatThreads: [AgentChatThread] = [],
        annotations: [AgentChatAnnotation] = [],
        confirmations: [AgentConfirmation] = [],
        messageConnections: [AgentMessageConnection] = [],
        messageConversations: [AgentMessageConversation] = [],
        activeCLIProfileAccountID: UUID? = nil,
        activeCLIProfilePreservesAuthentication: Bool = false
    ) {
        self.accounts = accounts
        self.channels = channels
        self.localModels = localModels
        self.channelProbes = channelProbes
        self.channelModelCatalogs = channelModelCatalogs
        self.cliStatuses = cliStatuses
        self.cliAutoUpdateEnabled = cliAutoUpdateEnabled
        self.skills = skills
        self.skillSyncConfiguration = skillSyncConfiguration
        self.applicationEnhancements = applicationEnhancements
        self.automations = automations
        self.goals = goals
        self.projects = projects
        self.chatThreads = chatThreads
        self.annotations = annotations
        self.confirmations = confirmations
        self.messageConnections = messageConnections
        self.messageConversations = messageConversations
        self.activeCLIProfileAccountID = activeCLIProfileAccountID
        self.activeCLIProfilePreservesAuthentication = activeCLIProfilePreservesAuthentication
    }

    private enum CodingKeys: String, CodingKey {
        case accounts
        case channels
        case localModels
        case channelProbes
        case channelModelCatalogs
        case cliStatuses
        case cliAutoUpdateEnabled
        case skills
        case skillSyncConfiguration
        case applicationEnhancements
        case automations
        case goals
        case projects
        case chatThreads
        case annotations
        case confirmations
        case messageConnections
        case messageConversations
        case activeCLIProfileAccountID
        case activeCLIProfilePreservesAuthentication
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accounts = try container.decodeIfPresent([AgentAccount].self, forKey: .accounts) ?? []
        channels = try container.decodeIfPresent([AgentChannel].self, forKey: .channels) ?? []
        localModels = try container.decodeIfPresent([AIAgentLocalModel].self, forKey: .localModels) ?? []
        channelProbes = try container.decodeIfPresent([AgentChannelProbe].self, forKey: .channelProbes) ?? []
        channelModelCatalogs = try container.decodeIfPresent([AgentChannelModelCatalog].self, forKey: .channelModelCatalogs) ?? []
        cliStatuses = try container.decodeIfPresent([AgentCLIStatus].self, forKey: .cliStatuses) ?? []
        cliAutoUpdateEnabled = try container.decodeIfPresent(Bool.self, forKey: .cliAutoUpdateEnabled) ?? false
        skills = try container.decodeIfPresent([AgentSkill].self, forKey: .skills) ?? []
        skillSyncConfiguration = try container.decodeIfPresent(AgentSkillSyncConfiguration.self, forKey: .skillSyncConfiguration) ?? AgentSkillSyncConfiguration()
        applicationEnhancements = try container.decodeIfPresent(AgentApplicationEnhancements.self, forKey: .applicationEnhancements) ?? AgentApplicationEnhancements()
        automations = try container.decodeIfPresent([AgentAutomation].self, forKey: .automations) ?? []
        goals = try container.decodeIfPresent([AgentGoal].self, forKey: .goals) ?? []
        projects = try container.decodeIfPresent([AgentChatProject].self, forKey: .projects) ?? []
        chatThreads = try container.decodeIfPresent([AgentChatThread].self, forKey: .chatThreads) ?? []
        annotations = try container.decodeIfPresent([AgentChatAnnotation].self, forKey: .annotations) ?? []
        confirmations = try container.decodeIfPresent([AgentConfirmation].self, forKey: .confirmations) ?? []
        messageConnections = try container.decodeIfPresent([AgentMessageConnection].self, forKey: .messageConnections) ?? []
        messageConversations = try container.decodeIfPresent([AgentMessageConversation].self, forKey: .messageConversations) ?? []
        activeCLIProfileAccountID = try container.decodeIfPresent(UUID.self, forKey: .activeCLIProfileAccountID)
        activeCLIProfilePreservesAuthentication = try container.decodeIfPresent(
            Bool.self,
            forKey: .activeCLIProfilePreservesAuthentication
        ) ?? false
    }
}
