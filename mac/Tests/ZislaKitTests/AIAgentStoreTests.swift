import Foundation
import Testing
@testable import ZislaCore
@testable import ZislaKit

@Suite(.serialized)
@MainActor
struct AIAgentStoreTests {

    @Test
    func localThinkingPreferencesSurviveReloadIndependently() throws {
        let (store, directory) = makeStore()
        defer {
            store.flushPendingChanges()
            try? FileManager.default.removeItem(at: directory)
        }
        let endpoint = AIEndpoint(name: "LM Studio", baseURL: AIEndpointKind.openAICompatible.defaultBaseURL)
        var first = AIAgentLocalModel(name: "Fast", endpoint: endpoint, modelName: "google/gemma-4-e4b")
        var second = AIAgentLocalModel(name: "Careful", endpoint: endpoint, modelName: "google/gemma-4-e4b", thinkingEnabled: true)
        store.upsertLocalModel(first)
        store.upsertLocalModel(second)
        store.flushPendingChanges()

        let storageURL = directory.appendingPathComponent("state.json")
        let restored = AIAgentStore(storageURL: storageURL, secretStore: StubSecretStore())
        #expect(restored.localModel(id: first.id) == first)
        #expect(restored.localModel(id: second.id) == second)
        first.thinkingEnabled = true
        second.thinkingEnabled = false
        restored.upsertLocalModel(first)
        restored.upsertLocalModel(second)
        restored.flushPendingChanges()

        let reopened = AIAgentStore(storageURL: storageURL, secretStore: StubSecretStore())
        #expect(reopened.state.localModels == [first, second])
        #expect(reopened.localModel(id: first.id)?.thinkingEnabled == true)
        #expect(reopened.localModel(id: second.id)?.thinkingEnabled == false)
    }

    @Test
    func failedThinkingPreferenceWritePreservesDiskStateAndCanRecover() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-local-thinking-write-\(UUID())")
        let storageURL = directory.appendingPathComponent("state.json")
        let failureMarker = directory.appendingPathComponent("inject-write-failure")
        let store = AIAgentStore(
            storageURL: storageURL,
            secretStore: StubSecretStore(),
            persistenceDelay: 60,
            persistenceWriter: { state, url in
                if FileManager.default.fileExists(atPath: failureMarker.path) {
                    throw CocoaError(.fileWriteNoPermission)
                }
                try AIAgentStore.write(state, to: url)
            }
        )
        defer {
            store.flushPendingChanges()
            try? FileManager.default.removeItem(at: directory)
        }
        var model = AIAgentLocalModel(
            name: "LM Studio",
            endpoint: AIEndpoint(name: "LM Studio", baseURL: AIEndpointKind.openAICompatible.defaultBaseURL),
            modelName: "google/gemma-4-e4b"
        )
        store.upsertLocalModel(model)
        store.flushPendingChanges()
        let previous = try Data(contentsOf: storageURL)
        try Data().write(to: failureMarker)
        model.thinkingEnabled = true
        store.upsertLocalModel(model)
        store.flushPendingChanges()
        #expect(store.persistenceError != nil)
        #expect(try Data(contentsOf: storageURL) == previous)
        #expect(store.localModel(id: model.id)?.thinkingEnabled == true)

        try FileManager.default.removeItem(at: failureMarker)
        store.flushPendingChanges()
        #expect(store.persistenceError == nil)
        let restored = AIAgentStore(storageURL: storageURL, secretStore: StubSecretStore())
        #expect(restored.localModel(id: model.id) == model)
    }

    @Test
    func localCredentialsSurviveReloadWithoutEnteringConfigurationJSON() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-local-secrets-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let storageURL = directory.appendingPathComponent("state.json")
        let credentialsURL = directory.appendingPathComponent("secrets.sqlite")
        let secrets = DatabaseAIAgentSecretStore(storageURL: credentialsURL)
        let store = AIAgentStore(storageURL: storageURL, secretStore: secrets)
        let model = AIAgentLocalModel(name: "LM Studio", endpoint: AIEndpoint(name: "LM Studio", baseURL: "http://127.0.0.1:1234/v1"), modelName: "model")
        let account = AgentAccount(id: model.id, name: "Cloud", provider: "Cloud")
        try store.upsertAccount(account, secret: "cloud-test-key")
        store.upsertLocalModel(model)
        try store.replaceLocalModelSecret("  local-test-key \n", for: model.id)
        store.flushPendingChanges()

        let restored = AIAgentStore(storageURL: storageURL, secretStore: secrets)
        #expect(restored.localModel(id: model.id) == model)
        #expect(try restored.secret(for: model) == "local-test-key")
        #expect(try restored.secret(for: account) == "cloud-test-key")
        let configuration = try String(contentsOf: storageURL, encoding: .utf8)
        #expect(!configuration.contains("local-test-key"))
        #expect(!configuration.contains("cloud-test-key"))
        let permissions = try FileManager.default.attributesOfItem(atPath: credentialsURL.path)[.posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o600)

        try restored.removeLocalModel(id: model.id)
        restored.flushPendingChanges()
        #expect(restored.localModel(id: model.id) == nil)
        #expect(try restored.secret(for: model) == nil)
        #expect(try restored.secret(for: account) == "cloud-test-key")
    }

    @Test
    func localCredentialsAreOptionalAndCanBeCleared() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-local-optional-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let secrets = FailureInjectingSecretStore()
        let store = AIAgentStore(storageURL: directory.appendingPathComponent("state.json"), secretStore: secrets)
        let model = AIAgentLocalModel(name: "Ollama", endpoint: AIEndpoint(name: "Ollama", baseURL: AIEndpointKind.ollama.defaultBaseURL, kind: .ollama), modelName: "")
        store.upsertLocalModel(model)
        defer { store.flushPendingChanges() }

        #expect(try store.secret(for: model) == nil)
        try store.replaceLocalModelSecret("fake-key", for: model.id)
        #expect(try store.secret(for: model) == "fake-key")
        try store.replaceLocalModelSecret(" \n\t", for: model.id)
        #expect(try store.secret(for: model) == nil)
        try store.replaceLocalModelSecret("ignored-key", for: UUID())
        #expect(store.state.localModels == [model])
    }

    @Test
    func failedLocalCredentialChangesPreserveThePreviousState() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-local-secret-failure-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let secrets = FailureInjectingSecretStore()
        let store = AIAgentStore(storageURL: directory.appendingPathComponent("state.json"), secretStore: secrets)
        let model = AIAgentLocalModel(name: "LM Studio", endpoint: AIEndpoint(name: "LM Studio", baseURL: "http://127.0.0.1:1234/v1"), modelName: "model")
        store.upsertLocalModel(model)
        defer { store.flushPendingChanges() }
        try store.replaceLocalModelSecret("previous-key", for: model.id)
        secrets.failWrites(endingWith: model.secretReference)

        #expect(throws: AIAgentSecretStoreError.storageFailed("injected")) {
            try store.replaceLocalModelSecret("new-key", for: model.id)
        }
        #expect(try store.secret(for: model) == "previous-key")
        secrets.failRemovals = true
        #expect(throws: AIAgentSecretStoreError.storageFailed("injected")) {
            try store.removeLocalModel(id: model.id)
        }
        #expect(throws: AIAgentSecretStoreError.storageFailed("injected")) {
            try store.replaceLocalModelSecret("", for: model.id)
        }
        #expect(store.localModel(id: model.id) == model)
        #expect(try store.secret(for: model) == "previous-key")
    }

    @Test
    func remoteChannelConfigurationSurvivesReload() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let account = AgentAccount(
            name: "生产 OpenAI",
            provider: "OpenAI"
        )
        let channel = AgentChannel(
            name: "生产 OpenAI",
            defaultModel: "gpt-4.1-mini",
            endpointGroups: [AgentEndpointGroup(
                name: "主端点",
                baseURLs: ["https://api.example.com/v1"],
                accountIDs: [account.id]
            )]
        )

        try store.upsertAccount(account, secret: "sk-test")
        store.upsertChannel(channel)
        store.flushPendingChanges()

        let restored = AIAgentStore(
            storageURL: directory.appendingPathComponent("state.json"),
            secretStore: StubSecretStore()
        )
        #expect(restored.account(id: account.id) == account)
        #expect(restored.channel(id: channel.id) == channel)
    }

    @Test
    func failedSecretWriteDoesNotPublishAccount() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-ai-agent-account-failure-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let secretStore = FailureInjectingSecretStore()
        let store = AIAgentStore(
            storageURL: directory.appendingPathComponent("state.json"),
            secretStore: secretStore
        )
        let account = AgentAccount(name: "OpenAI", provider: "OpenAI")
        secretStore.failWrites(endingWith: account.secretReference)

        #expect(throws: AIAgentSecretStoreError.storageFailed("injected")) {
            try store.upsertAccount(account, secret: "sk-test")
        }

        #expect(store.account(id: account.id) == nil)
    }

    @Test
    func failedCLIAuthenticationWriteRestoresPreviousProfile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-ai-agent-profile-failure-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let secretStore = FailureInjectingSecretStore()
        let store = AIAgentStore(
            storageURL: directory.appendingPathComponent("state.json"),
            secretStore: secretStore
        )
        let account = AgentAccount(
            name: "Codex",
            provider: "Codex",
            credentialKind: .cliProfile,
            cliProfile: AgentCLIProfile(cliKind: .codex)
        )
        try store.upsertAccount(account)
        try store.replaceCLIProfile(
            configuration: Data("old-config".utf8),
            authentication: Data("old-auth".utf8),
            for: account.id
        )
        secretStore.failWrites(endingWith: ".cli-authentication")

        #expect(throws: AIAgentSecretStoreError.storageFailed("injected")) {
            try store.replaceCLIProfile(
                configuration: Data("new-config".utf8),
                authentication: Data("new-auth".utf8),
                for: account.id
            )
        }

        let contents = try #require(try store.cliProfileContents(for: account))
        #expect(contents.configuration == Data("old-config".utf8))
        #expect(contents.authentication == Data("old-auth".utf8))
    }

    @Test
    func creatingRemoteProviderCreatesAnAccountAndDefaultEndpointTogether() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let provider = store.createRemoteProvider(
            name: "测试 Provider",
            defaultModel: "gpt-test",
            baseURL: "https://api.example.com/v1"
        )

        let group = try #require(provider.endpointGroups.first)
        let accountID = try #require(group.accountIDs.first)
        let account = try #require(store.account(id: accountID))

        #expect(store.state.channels == [provider])
        #expect(store.state.accounts == [account])
        #expect(provider.name == "测试 Provider")
        #expect(provider.defaultModel == "gpt-test")
        #expect(group.baseURLs == ["https://api.example.com/v1"])
        #expect(account.name == provider.name)
        #expect(account.provider == provider.name)
    }


    @Test
    func persistenceCoalescesRapidChangesAndWritesTheLatestSnapshot() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-ai-agent-persistence-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let writes = PersistenceWriteCounter()
        let storageURL = directory.appendingPathComponent("state.json")
        let store = AIAgentStore(
            storageURL: storageURL,
            secretStore: StubSecretStore(),
            persistenceDelay: 0.05,
            persistenceWriter: { state, url in
                try AIAgentStore.write(state, to: url)
                writes.record(state)
            }
        )

        let modelID = UUID()
        for name in ["第一个", "第二个", "最终模型"] {
            store.upsertLocalModel(AIAgentLocalModel(
                id: modelID,
                name: name,
                endpoint: AIEndpoint(name: name, baseURL: "http://localhost:11434", kind: .ollama),
                modelName: "qwen3"
            ))
        }

        for _ in 0..<50 where writes.count == 0 {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(writes.count == 1)
        #expect(writes.lastState?.localModels.first?.name == "最终模型")
        let persisted = try JSONDecoder().decode(AIAgentState.self, from: Data(contentsOf: storageURL))
        #expect(persisted.localModels.first?.name == "最终模型")
        #expect(store.persistenceError == nil)
    }

    @Test
    func persistenceFailureIsObservable() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-ai-agent-persistence-error-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let parentFile = directory.appendingPathComponent("not-a-directory")
        try Data("occupied".utf8).write(to: parentFile)
        let store = AIAgentStore(
            storageURL: parentFile.appendingPathComponent("state.json"),
            secretStore: StubSecretStore()
        )

        store.setCLIAutoUpdateEnabled(false, for: .codex)
        store.flushPendingChanges()

        #expect(store.persistenceError != nil)
        #expect(!store.state.isCLIAutoUpdateEnabled(for: .codex))
    }

    @Test
    func cliAutoUpdatePreferencesSurviveStatusRefreshAndReload() {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        store.setCLIAutoUpdateEnabled(false, for: .codex)
        store.setCLIAutoUpdateEnabled(true, for: .claude)
        store.setCLIAutoUpdateEnabled(false, for: .qwen)
        store.replaceCLIStatuses([AgentCLIStatus(kind: .codex, executablePath: "/test/codex", version: "1.0.0")])
        store.replaceCLIStatuses([])
        store.flushPendingChanges()

        let restored = AIAgentStore(
            storageURL: directory.appendingPathComponent("state.json"),
            secretStore: StubSecretStore()
        )
        #expect(!restored.state.isCLIAutoUpdateEnabled(for: .codex))
        #expect(restored.state.isCLIAutoUpdateEnabled(for: .claude))
        #expect(!restored.state.isCLIAutoUpdateEnabled(for: .qwen))
        #expect(restored.state.isCLIAutoUpdateEnabled(for: .gemini))
        #expect(restored.state.cliStatuses.isEmpty)
        #expect(store.persistenceError == nil)
    }


    private func makeStore() -> (AIAgentStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-ai-agent-store-\(UUID().uuidString)", isDirectory: true)
        let store = AIAgentStore(
            storageURL: directory.appendingPathComponent("state.json"),
            secretStore: StubSecretStore()
        )
        return (store, directory)
    }

}

private struct StubSecretStore: AIAgentSecretStoring {
    func secret(for reference: String) throws -> String? { nil }
    func setSecret(_ secret: String, for reference: String) throws {}
    func removeSecret(for reference: String) throws {}
}

private final class FailureInjectingSecretStore: AIAgentSecretStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]
    private var failingWriteSuffix: String?
    var failRemovals = false

    func failWrites(endingWith suffix: String) {
        lock.lock()
        defer { lock.unlock() }
        failingWriteSuffix = suffix
    }

    func secret(for reference: String) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return values[reference]
    }

    func setSecret(_ secret: String, for reference: String) throws {
        lock.lock()
        defer { lock.unlock() }
        if let failingWriteSuffix, reference.hasSuffix(failingWriteSuffix) {
            throw AIAgentSecretStoreError.storageFailed("injected")
        }
        values[reference] = secret
    }

    func removeSecret(for reference: String) throws {
        lock.lock()
        defer { lock.unlock() }
        if failRemovals { throw AIAgentSecretStoreError.storageFailed("injected") }
        values.removeValue(forKey: reference)
    }
}

private final class PersistenceWriteCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var states: [AIAgentState] = []

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return states.count
    }

    var lastState: AIAgentState? {
        lock.lock()
        defer { lock.unlock() }
        return states.last
    }

    func record(_ state: AIAgentState) {
        lock.lock()
        defer { lock.unlock() }
        states.append(state)
    }
}
