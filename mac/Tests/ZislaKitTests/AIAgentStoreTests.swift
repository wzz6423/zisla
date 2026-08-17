import Foundation
import Testing
@testable import ZislaCore
@testable import ZislaKit

@Suite(.serialized)
@MainActor
struct AIAgentStoreTests {

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

        store.setCLIAutoUpdateEnabled(true)
        store.flushPendingChanges()

        #expect(store.persistenceError != nil)
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
