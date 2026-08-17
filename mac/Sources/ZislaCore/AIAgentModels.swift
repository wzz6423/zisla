import Foundation

/// Protocols supported by remote model providers. Custom providers can use the OpenAI-compatible protocol.
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

public enum AgentModelEffort: String, Codable, CaseIterable, Sendable {
    case low
    case medium
    case high
    case xhigh
    case max
    case ultra

    public var displayName: String {
        switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        case .xhigh: "XHigh"
        case .max: "Max"
        case .ultra: "Ultra"
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
    public var effort: AgentModelEffort
    public var endpointGroups: [AgentEndpointGroup]
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        protocolKind: AgentChannelProtocol = .openAICompatible,
        defaultModel: String = "",
        effort: AgentModelEffort = .high,
        endpointGroups: [AgentEndpointGroup] = [],
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.protocolKind = protocolKind
        self.defaultModel = defaultModel
        self.effort = effort
        self.endpointGroups = endpointGroups
        self.isEnabled = isEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case protocolKind
        case defaultModel
        case effort
        case endpointGroups
        case isEnabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        protocolKind = try container.decode(AgentChannelProtocol.self, forKey: .protocolKind)
        defaultModel = try container.decode(String.self, forKey: .defaultModel)
        effort = try container.decodeIfPresent(AgentModelEffort.self, forKey: .effort) ?? .high
        endpointGroups = try container.decode([AgentEndpointGroup].self, forKey: .endpointGroups)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
    }
}

/// Voice settings select local models by ID without duplicating their connection URLs.
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
    case glm
    case copilot

    public static let detectableCases = allCases
    public static let relayCases: [Self] = [.claude, .codex, .gemini, .grok, .opencode]
    public static let profileCases = relayCases
    public static let managedCases = allCases

    public var displayName: String {
        switch self {
        case .kimi: "Kimi Code"
        case .qwen: "Qwen Code"
        case .qoder: "Qoder CLI"
        case .copilot: "GitHub Copilot"
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
    /// The last activated CLI profile account, used to save refreshed auth files before switching.
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
        activeCLIProfileAccountID = try container.decodeIfPresent(UUID.self, forKey: .activeCLIProfileAccountID)
        activeCLIProfilePreservesAuthentication = try container.decodeIfPresent(
            Bool.self,
            forKey: .activeCLIProfilePreservesAuthentication
        ) ?? false
    }
}
