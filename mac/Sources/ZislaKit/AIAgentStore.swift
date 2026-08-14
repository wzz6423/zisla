import Combine
import Foundation
import UniformTypeIdentifiers
import ZislaCore

private final class AIAgentStatePersistence: @unchecked Sendable {
    typealias Writer = @Sendable (AIAgentState, URL) throws -> Void

    private let storageURL: URL
    private let delay: TimeInterval
    private let writer: Writer
    private let queue = DispatchQueue(label: "com.zisla.ai-agent.state", qos: .utility)
    private let lock = NSLock()
    private var generation = 0

    init(storageURL: URL, delay: TimeInterval, writer: @escaping Writer) {
        self.storageURL = storageURL
        self.delay = max(0, delay)
        self.writer = writer
    }

    func schedule(
        _ state: AIAgentState,
        completion: @escaping @Sendable (Result<Void, Error>) -> Void
    ) {
        let scheduledGeneration = advanceGeneration()
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.isCurrent(scheduledGeneration) else { return }
            let result = Result { try self.writer(state, self.storageURL) }
            guard self.isCurrent(scheduledGeneration) else { return }
            completion(result)
        }
    }

    func flush(_ state: AIAgentState) -> Result<Void, Error> {
        _ = advanceGeneration()
        return queue.sync { Result { try writer(state, storageURL) } }
    }

    private func advanceGeneration() -> Int {
        lock.lock()
        defer { lock.unlock() }
        generation += 1
        return generation
    }

    private func isCurrent(_ value: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return generation == value
    }
}

public enum AIAgentAttachmentStoreError: LocalizedError, Sendable {
    case unsupportedFile(String)
    case tooLarge(String)
    case importFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedFile(name): "不支持导入 \(name)"
        case let .tooLarge(name): "\(name) 超过 25 MiB 限制"
        case let .importFailed(name): "无法导入 \(name)"
        }
    }
}

@MainActor
public final class AIAgentStore: ObservableObject {
    @Published public var state: AIAgentState {
        didSet { schedulePersistence() }
    }
    @Published public private(set) var persistenceError: String?

    private let storageURL: URL
    private let secretStore: AIAgentSecretStoring
    private let persistence: AIAgentStatePersistence
    private let fileManager = FileManager.default
    private var latestPersistenceID: UUID?
    private static let maximumAttachmentByteCount: Int64 = 25 * 1_024 * 1_024

    public convenience init(
        storageURL: URL = AppPaths.aiAgent,
        secretStore: AIAgentSecretStoring? = nil
    ) {
        self.init(
            storageURL: storageURL,
            secretStore: secretStore ?? AIAgentSecretStoreFactory.makeDefault(),
            persistenceDelay: 0.25,
            persistenceWriter: Self.write
        )
    }

    init(
        storageURL: URL,
        secretStore: AIAgentSecretStoring,
        persistenceDelay: TimeInterval,
        persistenceWriter: @escaping @Sendable (AIAgentState, URL) throws -> Void
    ) {
        self.storageURL = storageURL
        self.secretStore = secretStore
        self.persistence = AIAgentStatePersistence(
            storageURL: storageURL,
            delay: persistenceDelay,
            writer: persistenceWriter
        )
        state = Self.load(from: storageURL)
    }

    public func account(id: UUID) -> AgentAccount? {
        state.accounts.first { $0.id == id }
    }

    public func channel(id: UUID) -> AgentChannel? {
        state.channels.first { $0.id == id }
    }

    public func localModel(id: UUID) -> AIAgentLocalModel? {
        state.localModels.first { $0.id == id }
    }

    public func messageConnection(id: UUID) -> AgentMessageConnection? {
        state.messageConnections.first { $0.id == id }
    }

    public func goal(id: UUID) -> AgentGoal? {
        state.goals.first { $0.id == id }
    }

    public func upsertAccount(_ account: AgentAccount, secret: String? = nil) throws {
        if let index = state.accounts.firstIndex(where: { $0.id == account.id }) {
            state.accounts[index] = account
        } else {
            state.accounts.append(account)
        }
        if let secret {
            try secretStore.setSecret(secret, for: account.secretReference)
        }
    }

    @discardableResult
    public func importProviders(_ providers: [AIAgentImportedProvider]) throws -> Int {
        var importedCount = 0
        var nextState = state
        var references: [String] = []
        do {
            for provider in providers {
                let normalizedURL = provider.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                guard !provider.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      !normalizedURL.isEmpty,
                      !provider.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      !nextState.channels.contains(where: { channel in
                          channel.name.caseInsensitiveCompare(provider.name) == .orderedSame
                              && channel.endpointGroups.flatMap(\.baseURLs).contains { $0.trimmingCharacters(in: CharacterSet(charactersIn: "/")).caseInsensitiveCompare(normalizedURL) == .orderedSame }
                      }) else { continue }
                let account = AgentAccount(name: provider.name, provider: provider.name, balanceProbe: AgentBalanceProbe())
                let channel = AgentChannel(
                    name: provider.name,
                    protocolKind: provider.protocolKind,
                    defaultModel: provider.defaultModel,
                    endpointGroups: [AgentEndpointGroup(name: "默认端点", baseURLs: [provider.baseURL], accountIDs: [account.id])]
                )
                try secretStore.setSecret(provider.apiKey, for: account.secretReference)
                references.append(account.secretReference)
                nextState.accounts.append(account)
                nextState.channels.append(channel)
                importedCount += 1
            }
            state = nextState
            return importedCount
        } catch {
            for reference in references { try? secretStore.removeSecret(for: reference) }
            throw error
        }
    }

    public func removeAccount(id: UUID) throws {
        guard let account = account(id: id) else { return }
        var firstError: Error?
        for reference in [
            account.secretReference,
            cliConfigurationReference(for: account),
            cliAuthenticationReference(for: account),
        ] {
            do {
                try secretStore.removeSecret(for: reference)
            } catch {
                if firstError == nil { firstError = error }
            }
        }
        state.accounts.removeAll { $0.id == id }
        if state.activeCLIProfileAccountID == id {
            state.activeCLIProfileAccountID = nil
            state.activeCLIProfilePreservesAuthentication = false
        }
        for index in state.channels.indices {
            for groupIndex in state.channels[index].endpointGroups.indices {
                state.channels[index].endpointGroups[groupIndex].accountIDs.removeAll { $0 == id }
            }
        }
        for index in state.messageConnections.indices where state.messageConnections[index].accountID == id {
            state.messageConnections[index].accountID = nil
        }
        if let firstError { throw firstError }
    }

    public func secret(for account: AgentAccount) throws -> String? {
        try secretStore.secret(for: account.secretReference)
    }

    public func replaceSecret(_ secret: String, for accountID: UUID) throws {
        guard let account = account(id: accountID) else { return }
        try secretStore.setSecret(secret, for: account.secretReference)
    }

    public func replaceCLIProfile(
        configuration: Data,
        authentication: Data,
        for accountID: UUID
    ) throws {
        try replaceCLIConfiguration(configuration, for: accountID)
        try replaceCLIAuthentication(authentication, for: accountID)
    }

    public func replaceCLIConfiguration(_ data: Data, for accountID: UUID) throws {
        guard let account = account(id: accountID),
              let configuration = String(data: data, encoding: .utf8),
              !configuration.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIAgentSecretStoreError.invalidSecret
        }
        try secretStore.setSecret(configuration, for: cliConfigurationReference(for: account))
    }

    public func replaceCLIAuthentication(_ data: Data, for accountID: UUID) throws {
        guard let account = account(id: accountID),
              let authentication = String(data: data, encoding: .utf8),
              !authentication.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIAgentSecretStoreError.invalidSecret
        }
        try secretStore.setSecret(authentication, for: cliAuthenticationReference(for: account))
    }

    public func cliProfileContents(for account: AgentAccount) throws -> (configuration: Data, authentication: Data)? {
        guard let configuration = try secretStore.secret(for: cliConfigurationReference(for: account)),
              let authentication = try secretStore.secret(for: cliAuthenticationReference(for: account)) else {
            return nil
        }
        return (Data(configuration.utf8), Data(authentication.utf8))
    }

    public func hasCLIProfile(for account: AgentAccount) -> Bool {
        guard account.credentialKind == .cliProfile,
              account.cliProfile?.isComplete == true else {
            return false
        }
        return (try? cliProfileContents(for: account)) != nil
    }

    public func hasCLIConfiguration(for account: AgentAccount) -> Bool {
        (try? secretStore.secret(for: cliConfigurationReference(for: account))) != nil
    }

    public func hasCLIAuthentication(for account: AgentAccount) -> Bool {
        (try? secretStore.secret(for: cliAuthenticationReference(for: account))) != nil
    }

    public func upsertChannel(_ channel: AgentChannel) {
        if let index = state.channels.firstIndex(where: { $0.id == channel.id }) {
            state.channels[index] = channel
        } else {
            state.channels.append(channel)
        }
    }

    @discardableResult
    public func createRemoteProvider(
        name: String,
        protocolKind: AgentChannelProtocol = .openAICompatible,
        defaultModel: String = "",
        baseURL: String = "https://api.openai.com/v1"
    ) -> AgentChannel {
        let account = AgentAccount(
            name: name,
            provider: name,
            balanceProbe: AgentBalanceProbe()
        )
        let channel = AgentChannel(
            name: name,
            protocolKind: protocolKind,
            defaultModel: defaultModel,
            endpointGroups: [AgentEndpointGroup(
                name: "默认端点",
                baseURLs: [baseURL],
                accountIDs: [account.id]
            )]
        )
        var nextState = state
        nextState.accounts.append(account)
        nextState.channels.append(channel)
        state = nextState
        return channel
    }

    public func removeChannel(id: UUID) {
        state.channels.removeAll { $0.id == id }
        state.channelProbes.removeAll { $0.channelID == id }
        state.chatThreads.indices.forEach { index in
            if state.chatThreads[index].channelID == id {
                state.chatThreads[index].channelID = nil
            }
        }
    }

    public func upsertLocalModel(_ model: AIAgentLocalModel) {
        if let index = state.localModels.firstIndex(where: { $0.id == model.id }) {
            state.localModels[index] = model
        } else {
            state.localModels.append(model)
        }
    }

    public func removeLocalModel(id: UUID) {
        state.localModels.removeAll { $0.id == id }
        for index in state.chatThreads.indices where state.chatThreads[index].localModelID == id {
            state.chatThreads[index].localModelID = nil
            state.chatThreads[index].updatedAt = Date()
        }
    }

    public func upsertMessageConnection(_ connection: AgentMessageConnection) {
        var connection = connection
        connection.updatedAt = Date()
        if let index = state.messageConnections.firstIndex(where: { $0.id == connection.id }) {
            state.messageConnections[index] = connection
        } else {
            state.messageConnections.append(connection)
        }
    }

    public func removeMessageConnection(id: UUID) throws {
        if let connection = messageConnection(id: id) {
            try secretStore.removeSecret(for: connection.credentialReference)
        }
        state.messageConnections.removeAll { $0.id == id }
        state.messageConversations.removeAll { $0.connectionID == id }
    }

    public func messageConnectionCredentials(
        for connection: AgentMessageConnection
    ) throws -> AgentMessageConnectionCredentials? {
        guard let raw = try secretStore.secret(for: connection.credentialReference) else { return nil }
        return try JSONDecoder().decode(AgentMessageConnectionCredentials.self, from: Data(raw.utf8))
    }

    public func replaceMessageConnectionCredentials(
        _ credentials: AgentMessageConnectionCredentials,
        for connectionID: UUID
    ) throws {
        guard let connection = messageConnection(id: connectionID) else { return }
        let data = try JSONEncoder().encode(credentials)
        try secretStore.setSecret(String(decoding: data, as: UTF8.self), for: connection.credentialReference)
    }

    public func messageConversation(
        connectionID: UUID,
        externalConversationID: String
    ) -> AgentMessageConversation? {
        state.messageConversations.first {
            $0.connectionID == connectionID && $0.externalConversationID == externalConversationID
        }
    }

    public func upsertMessageConversation(_ conversation: AgentMessageConversation) {
        if let index = state.messageConversations.firstIndex(where: { $0.id == conversation.id }) {
            state.messageConversations[index] = conversation
        } else {
            state.messageConversations.append(conversation)
        }
    }

    public func recordMessageConnectionError(_ error: String?, for connectionID: UUID) {
        guard var connection = messageConnection(id: connectionID) else { return }
        connection.lastError = error
        upsertMessageConnection(connection)
    }

    public func recordBalance(_ snapshot: AgentBalanceSnapshot?, for accountID: UUID) {
        guard let index = state.accounts.firstIndex(where: { $0.id == accountID }) else { return }
        state.accounts[index].balance = snapshot
        state.accounts[index].consecutiveFailures = 0
        state.accounts[index].disabledUntil = nil
    }

    public func recordRouteFailure(for accountID: UUID, at date: Date = Date()) {
        guard let index = state.accounts.firstIndex(where: { $0.id == accountID }) else { return }
        state.accounts[index].consecutiveFailures += 1
        if state.accounts[index].consecutiveFailures >= 2 {
            state.accounts[index].disabledUntil = date.addingTimeInterval(5 * 60)
        }
    }

    public func replaceProbe(_ probe: AgentChannelProbe) {
        state.channelProbes.removeAll {
            $0.endpointGroupID == probe.endpointGroupID && $0.baseURL == probe.baseURL
        }
        state.channelProbes.append(probe)
    }

    public func replaceModelCatalog(_ catalog: AgentChannelModelCatalog) {
        guard !catalog.models.isEmpty || catalog.detail == nil else { return }
        state.channelModelCatalogs.removeAll {
            $0.channelID == catalog.channelID
                && $0.endpointGroupID == catalog.endpointGroupID
                && $0.baseURL == catalog.baseURL
        }
        state.channelModelCatalogs.append(catalog)
    }

    public func models(for channelID: UUID) -> [String] {
        Array(Set(
            state.channelModelCatalogs
                .filter { $0.channelID == channelID }
                .flatMap(\.models)
        )).sorted()
    }

    public func replaceCLIStatuses(_ statuses: [AgentCLIStatus]) {
        state.cliStatuses = statuses
    }

    public func setCLIAutoUpdateEnabled(_ enabled: Bool) {
        state.cliAutoUpdateEnabled = enabled
    }

    public func replaceSkills(_ skills: [AgentSkill]) {
        state.skills = skills
    }

    @discardableResult
    public func createThread(
        useMostRecentModel: Bool = false,
        channelID: UUID? = nil,
        cliKind: AgentCLIKind? = nil,
        accountID: UUID? = nil,
        projectID: UUID? = nil,
        title: String = "新对话"
    ) -> AgentChatThread {
        let mostRecentModelThread = useMostRecentModel ? mostRecentEnabledModelThread() : nil
        let thread = AgentChatThread(
            title: title,
            channelID: channelID ?? mostRecentModelThread?.channelID,
            localModelID: channelID == nil ? mostRecentModelThread?.localModelID : nil,
            cliKind: cliKind,
            accountID: accountID,
            projectID: projectID.flatMap { project(id: $0) == nil ? nil : $0 },
            selectedModel: channelID == nil ? mostRecentModelThread?.selectedModel : nil
        )
        state.chatThreads.insert(thread, at: 0)
        return thread
    }

    private func mostRecentEnabledModelThread() -> AgentChatThread? {
        state.chatThreads
            .sorted { $0.updatedAt > $1.updatedAt }
            .first { thread in
                if let localModelID = thread.localModelID {
                    return localModel(id: localModelID)?.isEnabled == true
                }
                if let channelID = thread.channelID {
                    return channel(id: channelID)?.isEnabled == true
                }
                return false
            }
    }

    public func updateThreadTarget(
        id: UUID,
        cliKind: AgentCLIKind?,
        accountID: UUID?
    ) {
        guard let index = state.chatThreads.firstIndex(where: { $0.id == id }) else { return }
        state.chatThreads[index].cliKind = cliKind
        state.chatThreads[index].accountID = accountID
    }

    public func updateThreadMode(_ mode: AgentChatMode, for id: UUID) {
        guard let index = state.chatThreads.firstIndex(where: { $0.id == id }) else { return }
        state.chatThreads[index].mode = mode
        state.chatThreads[index].updatedAt = Date()
    }

    public func updateThreadGoal(_ goalID: UUID?, for id: UUID) {
        guard let index = state.chatThreads.firstIndex(where: { $0.id == id }) else { return }
        state.chatThreads[index].goalID = goalID.flatMap { goal(id: $0) == nil ? nil : $0 }
        state.chatThreads[index].updatedAt = Date()
    }

    /// Goal mode is an independent switch: turning it on only arms the session prompt slot,
    /// it never creates an external `AgentGoal`.
    public func setThreadGoalMode(_ isEnabled: Bool, for id: UUID) {
        guard let index = state.chatThreads.firstIndex(where: { $0.id == id }) else { return }
        state.chatThreads[index].goalPrompt = isEnabled ? (state.chatThreads[index].goalPrompt ?? "") : nil
        state.chatThreads[index].updatedAt = Date()
    }

    /// Records the composer input as this session's goal prompt; ignored when goal mode is off.
    public func updateThreadGoalPrompt(_ prompt: String, for id: UUID) {
        guard let index = state.chatThreads.firstIndex(where: { $0.id == id }),
              state.chatThreads[index].goalPrompt != nil else { return }
        state.chatThreads[index].goalPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        state.chatThreads[index].updatedAt = Date()
    }

    public func updateThreadProject(_ projectID: UUID?, for id: UUID) {
        guard let index = state.chatThreads.firstIndex(where: { $0.id == id }) else { return }
        state.chatThreads[index].projectID = projectID.flatMap { project(id: $0) == nil ? nil : $0 }
        state.chatThreads[index].updatedAt = Date()
    }

    public func updateThreadAccessMode(_ mode: AgentChatAccessMode, for id: UUID) {
        guard let index = state.chatThreads.firstIndex(where: { $0.id == id }) else { return }
        state.chatThreads[index].accessMode = mode
        state.chatThreads[index].updatedAt = Date()
    }

    public func updateThreadModel(_ model: String?, for id: UUID) {
        guard let index = state.chatThreads.firstIndex(where: { $0.id == id }) else { return }
        let normalized = model?.trimmingCharacters(in: .whitespacesAndNewlines)
        state.chatThreads[index].selectedModel = normalized?.isEmpty == true ? nil : normalized
        state.chatThreads[index].updatedAt = Date()
    }

    public func updateThreadChannel(_ channelID: UUID?, for id: UUID) {
        guard let index = state.chatThreads.firstIndex(where: { $0.id == id }) else { return }
        let resolvedChannelID = channelID.flatMap { channel(id: $0) == nil ? nil : $0 }
        guard state.chatThreads[index].channelID != resolvedChannelID
                || state.chatThreads[index].localModelID != nil else { return }
        state.chatThreads[index].channelID = resolvedChannelID
        state.chatThreads[index].localModelID = nil
        state.chatThreads[index].cliKind = nil
        state.chatThreads[index].accountID = nil
        state.chatThreads[index].selectedModel = nil
        state.chatThreads[index].updatedAt = Date()
    }

    public func updateThreadLocalModel(_ localModelID: UUID?, for id: UUID) {
        guard let index = state.chatThreads.firstIndex(where: { $0.id == id }) else { return }
        let resolvedLocalModelID = localModelID.flatMap { localModel(id: $0) == nil ? nil : $0 }
        guard state.chatThreads[index].localModelID != resolvedLocalModelID
                || state.chatThreads[index].channelID != nil else { return }
        state.chatThreads[index].localModelID = resolvedLocalModelID
        state.chatThreads[index].channelID = nil
        state.chatThreads[index].cliKind = nil
        state.chatThreads[index].accountID = nil
        state.chatThreads[index].selectedModel = nil
        state.chatThreads[index].updatedAt = Date()
    }

    public func updateThreadThinkingDepth(_ depth: AgentChatThinkingDepth, for id: UUID) {
        guard let index = state.chatThreads.firstIndex(where: { $0.id == id }) else { return }
        state.chatThreads[index].thinkingDepth = depth
        state.chatThreads[index].updatedAt = Date()
    }

    @discardableResult
    public func createGoal(title: String) -> AgentGoal? {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        let goal = AgentGoal(title: normalized)
        state.goals.insert(goal, at: 0)
        return goal
    }

    public func project(id: UUID) -> AgentChatProject? {
        state.projects.first { $0.id == id }
    }

    public func sortedProjects() -> [AgentChatProject] {
        state.projects.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned
            }
            return latestActivity(for: lhs) > latestActivity(for: rhs)
        }
    }

    @discardableResult
    public func createProject(
        name: String,
        directoryPath: String = "",
        instructions: String = ""
    ) -> AgentChatProject? {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        let project = AgentChatProject(
            name: normalized,
            instructions: instructions,
            directoryPath: directoryPath
        )
        state.projects.insert(project, at: 0)
        return project
    }

    public func updateProjectInstructions(_ instructions: String, for id: UUID) {
        guard let index = state.projects.firstIndex(where: { $0.id == id }) else { return }
        state.projects[index].instructions = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        state.projects[index].updatedAt = Date()
    }

    public func toggleProjectPinned(id: UUID) {
        guard let index = state.projects.firstIndex(where: { $0.id == id }) else { return }
        state.projects[index].isPinned.toggle()
        state.projects[index].updatedAt = Date()
    }

    public func setProjectCollapsed(_ isCollapsed: Bool, for id: UUID) {
        guard let index = state.projects.firstIndex(where: { $0.id == id }) else { return }
        state.projects[index].isCollapsed = isCollapsed
        state.projects[index].updatedAt = Date()
    }

    public func deleteProject(id: UUID) {
        guard state.projects.contains(where: { $0.id == id }) else { return }
        state.projects.removeAll { $0.id == id }
        state.chatThreads.indices.forEach { index in
            if state.chatThreads[index].projectID == id {
                state.chatThreads[index].projectID = nil
                state.chatThreads[index].updatedAt = Date()
            }
        }
    }

    private func latestActivity(for project: AgentChatProject) -> Date {
        state.chatThreads
            .filter { $0.projectID == project.id }
            .map(\.updatedAt)
            .max() ?? project.updatedAt
    }

    public func updateGoalStatus(_ status: AgentGoalStatus, for id: UUID) {
        guard let index = state.goals.firstIndex(where: { $0.id == id }) else { return }
        state.goals[index].status = status
        state.goals[index].updatedAt = Date()
    }

    /// Newest-first active history: the chat list, the selection fallback and the composer's
    /// reference picker must agree on what "still visible" means, so the filter lives here.
    public func activeThreads() -> [AgentChatThread] {
        state.chatThreads
            .filter { $0.archivedAt == nil }
            .sorted { lhs, rhs in
                if lhs.isPinned != rhs.isPinned {
                    return lhs.isPinned
                }
                return lhs.updatedAt > rhs.updatedAt
            }
    }

    public func archivedThreads() -> [AgentChatThread] {
        state.chatThreads
            .filter { $0.archivedAt != nil }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    public func toggleThreadPinned(id: UUID) {
        guard let index = state.chatThreads.firstIndex(where: { $0.id == id }) else { return }
        state.chatThreads[index].isPinned.toggle()
    }

    public func archiveThread(id: UUID) {
        guard let index = state.chatThreads.firstIndex(where: { $0.id == id }) else { return }
        state.chatThreads[index].archivedAt = Date()
        state.chatThreads[index].updatedAt = Date()
    }

    public func restoreThread(id: UUID) {
        guard let index = state.chatThreads.firstIndex(where: { $0.id == id }) else { return }
        state.chatThreads[index].archivedAt = nil
        state.chatThreads[index].updatedAt = Date()
    }

    public func deleteThread(id: UUID) {
        guard let thread = state.chatThreads.first(where: { $0.id == id }) else { return }
        for attachment in thread.messages.flatMap(\.attachments) {
            removeAttachmentFile(attachment)
        }
        state.chatThreads.removeAll { $0.id == id }
        state.annotations.removeAll { $0.threadID == id }
        state.confirmations.removeAll { $0.threadID == id }
        state.messageConversations.removeAll { $0.threadID == id }
    }

    @discardableResult
    public func forkThread(at messageID: UUID, in threadID: UUID) -> AgentChatThread? {
        guard let source = state.chatThreads.first(where: { $0.id == threadID }),
              let messageIndex = source.messages.firstIndex(where: { $0.id == messageID }) else {
            return nil
        }
        let messages = source.messages.prefix(through: messageIndex).map(copyForFork)
        let fork = AgentChatThread(
            title: "\(source.title) · 分叉",
            channelID: source.channelID,
            localModelID: source.localModelID,
            cliKind: source.cliKind,
            accountID: source.accountID,
            mode: source.mode,
            goalID: source.goalID,
            goalPrompt: source.goalPrompt,
            projectID: source.projectID,
            accessMode: source.accessMode,
            selectedModel: source.selectedModel,
            thinkingDepth: source.thinkingDepth,
            messages: messages
        )
        state.chatThreads.insert(fork, at: 0)
        return fork
    }

    public func annotations(for messageID: UUID) -> [AgentChatAnnotation] {
        state.annotations
            .filter { $0.messageID == messageID }
            .sorted { $0.createdAt < $1.createdAt }
    }

    @discardableResult
    public func addAnnotation(
        threadID: UUID,
        messageID: UUID,
        selectedText: String,
        comment: String
    ) -> AgentChatAnnotation? {
        guard state.chatThreads.contains(where: { $0.id == threadID && $0.messages.contains { $0.id == messageID } }) else {
            return nil
        }
        let annotation = AgentChatAnnotation(
            threadID: threadID,
            messageID: messageID,
            selectedText: selectedText,
            comment: comment
        )
        guard !annotation.selectedText.isEmpty, !annotation.comment.isEmpty else { return nil }
        state.annotations.append(annotation)
        return annotation
    }

    public func deleteAnnotation(id: UUID) {
        state.annotations.removeAll { $0.id == id }
    }

    public func importAttachments(from urls: [URL]) throws -> [AgentChatAttachment] {
        try urls.map(importAttachment)
    }

    public func importTextAttachment(_ content: String, fileName: String = "备忘录.txt") throws -> AgentChatAttachment {
        let data = Data(content.utf8)
        let byteCount = Int64(data.count)
        let normalizedName = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = normalizedName.isEmpty ? "备忘录.txt" : normalizedName
        guard byteCount <= Self.maximumAttachmentByteCount else {
            throw AIAgentAttachmentStoreError.tooLarge(displayName)
        }

        let storagePath = "active/\(UUID().uuidString.lowercased()).txt"
        let destinationURL = AppPaths.aiAgentAttachments.appendingPathComponent(storagePath, isDirectory: false)
        do {
            try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: destinationURL, options: .atomic)
        } catch {
            throw AIAgentAttachmentStoreError.importFailed(displayName)
        }
        return AgentChatAttachment(
            fileName: displayName,
            mimeType: "text/plain",
            byteCount: byteCount,
            storagePath: storagePath,
            kind: .file
        )
    }

    private func copyForFork(_ message: AgentChatMessage) -> AgentChatMessage {
        AgentChatMessage(
            role: message.role,
            content: message.content,
            accountID: message.accountID,
            attachments: message.attachments,
            contextReferences: message.contextReferences,
            appReferences: message.appReferences,
            skillReferences: message.skillReferences,
            mode: message.mode,
            goalTitle: message.goalTitle,
            createdAt: message.createdAt
        )
    }

    public func discardImportedAttachments(_ attachments: [AgentChatAttachment]) {
        attachments.forEach(removeAttachmentFile)
    }

    public func attachmentURL(for attachment: AgentChatAttachment) -> URL? {
        guard attachment.state != .deleted,
              let relativePath = validatedAttachmentPath(attachment.storagePath) else {
            return nil
        }
        let url = AppPaths.aiAgentAttachments.appendingPathComponent(relativePath, isDirectory: false)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    public func contextReferences(for threadIDs: [UUID], excluding threadID: UUID) -> [AgentChatContextReference] {
        var seen = Set<UUID>()
        return threadIDs.compactMap { id in
            guard id != threadID,
                  seen.insert(id).inserted,
                  let thread = state.chatThreads.first(where: { $0.id == id }) else {
                return nil
            }
            let messages = thread.messages.suffix(12).compactMap { message -> AgentChatContextMessage? in
                let content = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !content.isEmpty else { return nil }
                return AgentChatContextMessage(role: message.role, content: String(content.prefix(1_200)))
            }
            guard !messages.isEmpty else { return nil }
            return AgentChatContextReference(threadID: thread.id, title: thread.title, messages: messages)
        }
    }

    public func setActiveCLIProfileAccountID(_ accountID: UUID?) {
        state.activeCLIProfileAccountID = accountID
        if accountID == nil {
            state.activeCLIProfilePreservesAuthentication = false
        }
    }

    public func setActiveCLIProfilePreservesAuthentication(_ preservesAuthentication: Bool) {
        state.activeCLIProfilePreservesAuthentication = preservesAuthentication
    }

    public func updateApplicationEnhancements(_ enhancements: AgentApplicationEnhancements) {
        state.applicationEnhancements = enhancements
    }

    public func importCodexHistory(_ threads: [AgentChatThread]) {
        let existing = Set(state.chatThreads.compactMap(\.externalHistoryID))
        let newThreads = threads.filter {
            guard let identifier = $0.externalHistoryID else { return false }
            return !existing.contains(identifier)
        }
        guard !newThreads.isEmpty else { return }
        state.chatThreads.append(contentsOf: newThreads)
        state.chatThreads.sort { $0.updatedAt > $1.updatedAt }
    }

    public func removeImportedCodexHistory() {
        let ids = state.chatThreads
            .filter { $0.externalHistoryID?.hasPrefix("codex:") == true }
            .map(\.id)
        for id in ids {
            deleteThread(id: id)
        }
    }

    public func append(_ message: AgentChatMessage, to threadID: UUID) {
        guard let index = state.chatThreads.firstIndex(where: { $0.id == threadID }) else { return }
        state.chatThreads[index].messages.append(message)
        state.chatThreads[index].updatedAt = message.createdAt
        if state.chatThreads[index].title == "新对话", message.role == .user {
            let prefix = message.content.trimmingCharacters(in: .whitespacesAndNewlines).prefix(28)
            if !prefix.isEmpty { state.chatThreads[index].title = String(prefix) }
        }
    }

    public func addConfirmation(_ confirmation: AgentConfirmation) {
        state.confirmations.append(confirmation)
    }

    public func resolveConfirmation(id: UUID, state confirmationState: AgentConfirmationState) {
        guard let index = state.confirmations.firstIndex(where: { $0.id == id }) else { return }
        state.confirmations[index].state = confirmationState
    }

    public func updateAutomation(_ automation: AgentAutomation) {
        if let index = state.automations.firstIndex(where: { $0.id == automation.id }) {
            state.automations[index] = automation
        } else {
            state.automations.append(automation)
        }
    }

    private static func load(from url: URL) -> AIAgentState {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(AIAgentState.self, from: data) else {
            return AIAgentState()
        }
        return decoded
    }

    public func flushPendingChanges() {
        latestPersistenceID = UUID()
        recordPersistenceResult(persistence.flush(state))
    }

    nonisolated static func write(_ state: AIAgentState, to storageURL: URL) throws {
        try FileManager.default.createDirectory(
            at: storageURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: storageURL, options: .atomic)
    }

    private func schedulePersistence() {
        let persistenceID = UUID()
        latestPersistenceID = persistenceID
        persistence.schedule(state) { [weak self] result in
            Task { @MainActor [weak self] in
                guard self?.latestPersistenceID == persistenceID else { return }
                self?.recordPersistenceResult(result)
            }
        }
    }

    private func recordPersistenceResult(_ result: Result<Void, Error>) {
        switch result {
        case .success:
            persistenceError = nil
        case let .failure(error):
            persistenceError = error.localizedDescription
        }
    }

    private func cliConfigurationReference(for account: AgentAccount) -> String {
        "\(account.secretReference).cli-configuration"
    }

    private func cliAuthenticationReference(for account: AgentAccount) -> String {
        "\(account.secretReference).cli-authentication"
    }

    private func importAttachment(from url: URL) throws -> AgentChatAttachment {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess { url.stopAccessingSecurityScopedResource() }
        }
        let values = try? url.resourceValues(forKeys: [.contentTypeKey, .fileSizeKey, .isRegularFileKey])
        guard values?.isRegularFile != false else {
            throw AIAgentAttachmentStoreError.unsupportedFile(url.lastPathComponent)
        }
        let byteCount = Int64(values?.fileSize ?? 0)
        guard byteCount <= Self.maximumAttachmentByteCount else {
            throw AIAgentAttachmentStoreError.tooLarge(url.lastPathComponent)
        }
        let type = values?.contentType ?? UTType(filenameExtension: url.pathExtension) ?? .data
        let kind: AgentChatAttachmentKind
        if type.conforms(to: .image) {
            kind = .image
        } else if type.conforms(to: .audio) {
            kind = .audio
        } else {
            kind = .file
        }
        let extensionSuffix = url.pathExtension.isEmpty ? "" : ".\(url.pathExtension)"
        let storagePath = "active/\(UUID().uuidString.lowercased())\(extensionSuffix)"
        let destinationURL = AppPaths.aiAgentAttachments.appendingPathComponent(storagePath, isDirectory: false)
        do {
            try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.copyItem(at: url, to: destinationURL)
        } catch {
            throw AIAgentAttachmentStoreError.importFailed(url.lastPathComponent)
        }
        return AgentChatAttachment(
            fileName: url.lastPathComponent,
            mimeType: type.preferredMIMEType ?? "application/octet-stream",
            byteCount: byteCount,
            storagePath: storagePath,
            kind: kind
        )
    }

    private func updateAttachment(id: UUID, update: (inout AgentChatAttachment) -> Void) {
        for threadIndex in state.chatThreads.indices {
            for messageIndex in state.chatThreads[threadIndex].messages.indices {
                guard let attachmentIndex = state.chatThreads[threadIndex].messages[messageIndex].attachments.firstIndex(where: { $0.id == id }) else {
                    continue
                }
                update(&state.chatThreads[threadIndex].messages[messageIndex].attachments[attachmentIndex])
                state.chatThreads[threadIndex].updatedAt = Date()
                return
            }
        }
    }

    private func removeAttachmentFile(_ attachment: AgentChatAttachment) {
        guard let url = attachmentURL(for: attachment) else { return }
        try? fileManager.removeItem(at: url)
    }

    private func validatedAttachmentPath(_ path: String) -> String? {
        let normalized = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty,
              !normalized.hasPrefix("/"),
              !normalized.split(separator: "/").contains("..") else {
            return nil
        }
        return normalized
    }
}
