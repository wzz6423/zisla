import Combine
import Foundation
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

@MainActor
public final class AIAgentStore: ObservableObject {
    @Published public var state: AIAgentState {
        didSet { schedulePersistence() }
    }
    @Published public private(set) var persistenceError: String?

    private let storageURL: URL
    private let secretStore: AIAgentSecretStoring
    private let persistence: AIAgentStatePersistence
    private var latestPersistenceID: UUID?

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

    public func upsertAccount(_ account: AgentAccount, secret: String? = nil) throws {
        if let secret {
            try secretStore.setSecret(secret, for: account.secretReference)
        }
        if let index = state.accounts.firstIndex(where: { $0.id == account.id }) {
            state.accounts[index] = account
        } else {
            state.accounts.append(account)
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
        guard let account = account(id: accountID) else {
            throw AIAgentSecretStoreError.invalidSecret
        }
        let configuration = try validatedSecret(from: configuration)
        let authentication = try validatedSecret(from: authentication)
        let configurationReference = cliConfigurationReference(for: account)
        let authenticationReference = cliAuthenticationReference(for: account)
        let previousConfiguration = try secretStore.secret(for: configurationReference)
        let previousAuthentication = try secretStore.secret(for: authenticationReference)

        do {
            try secretStore.setSecret(configuration, for: configurationReference)
            try secretStore.setSecret(authentication, for: authenticationReference)
        } catch {
            restoreSecret(previousConfiguration, for: configurationReference)
            restoreSecret(previousAuthentication, for: authenticationReference)
            throw error
        }
    }

    public func replaceCLIConfiguration(_ data: Data, for accountID: UUID) throws {
        guard let account = account(id: accountID) else {
            throw AIAgentSecretStoreError.invalidSecret
        }
        let configuration = try validatedSecret(from: data)
        try secretStore.setSecret(configuration, for: cliConfigurationReference(for: account))
    }

    public func replaceCLIAuthentication(_ data: Data, for accountID: UUID) throws {
        guard let account = account(id: accountID) else {
            throw AIAgentSecretStoreError.invalidSecret
        }
        let authentication = try validatedSecret(from: data)
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
        state.channelModelCatalogs.removeAll { $0.channelID == id }
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

    public func setActiveCLIProfileAccountID(_ accountID: UUID?) {
        state.activeCLIProfileAccountID = accountID
        if accountID == nil {
            state.activeCLIProfilePreservesAuthentication = false
        }
    }

    public func setActiveCLIProfilePreservesAuthentication(_ preservesAuthentication: Bool) {
        state.activeCLIProfilePreservesAuthentication = preservesAuthentication
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

    private func validatedSecret(from data: Data) throws -> String {
        guard let value = String(data: data, encoding: .utf8),
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIAgentSecretStoreError.invalidSecret
        }
        return value
    }

    private func restoreSecret(_ value: String?, for reference: String) {
        if let value {
            try? secretStore.setSecret(value, for: reference)
        } else {
            try? secretStore.removeSecret(for: reference)
        }
    }

}
