import Foundation
import Testing
@testable import Zisla
@testable import ZislaCore
@testable import ZislaKit

@MainActor
struct VoiceLocalModelConfigurationTests {
    @Test(arguments: AIEndpointKind.allCases, [false, true])
    func localVoiceTargetNeedsNoAPIKeyAndKeepsThinkingPreference(kind: AIEndpointKind, thinkingEnabled: Bool) throws {
        let (store, directory) = makeStore()
        defer {
            store.flushPendingChanges()
            try? FileManager.default.removeItem(at: directory)
        }
        let model = AIAgentLocalModel(name: kind.defaultEndpointName, endpoint: AIEndpoint(name: kind.defaultEndpointName, baseURL: kind.defaultBaseURL, kind: kind), modelName: " local-model \n", thinkingEnabled: thinkingEnabled)
        store.upsertLocalModel(model)

        let target = try AppModel.voicePostProcessingTarget(for: .local(model.id), store: store)
        guard case let .http(endpoint, protocolKind, name, key, effort, localInference, localThinkingEnabled) = target else {
            Issue.record("Enabled local configuration should resolve without a key")
            return
        }
        #expect(endpoint == model.endpoint)
        #expect(protocolKind == .openAICompatible)
        #expect(name == "local-model")
        #expect(key == nil)
        #expect(effort == nil)
        #expect(localInference)
        #expect(localThinkingEnabled == thinkingEnabled)
    }

    @Test
    func localDiscoveryWorksBeforeSelectingAModelAndUsesStoredCredential() throws {
        let (store, directory) = makeStore(key: "lm-test-key")
        defer {
            store.flushPendingChanges()
            try? FileManager.default.removeItem(at: directory)
        }
        var model = AIAgentLocalModel(name: "LM Studio", endpoint: AIEndpoint(name: "LM Studio", baseURL: AIEndpointKind.openAICompatible.defaultBaseURL), modelName: " \n")
        store.upsertLocalModel(model)
        #expect(try AppModel.voicePostProcessingTarget(for: .local(model.id), store: store) == nil)

        let target = try AppModel.voicePostProcessingTarget(for: .local(model.id), store: store, requiresModel: false)
        guard case let .http(_, _, name, key, _, _, _) = target else {
            Issue.record("Model discovery must not require a model name")
            return
        }
        #expect(name.isEmpty)
        #expect(key == "lm-test-key")
        model.isEnabled = false
        store.upsertLocalModel(model)
        #expect(try AppModel.voicePostProcessingTarget(for: .local(model.id), store: store, requiresModel: false) == nil)
        #expect(try AppModel.voicePostProcessingTarget(for: .local(UUID()), store: store, requiresModel: false) == nil)
        #expect(try AppModel.voicePostProcessingTarget(for: nil, store: store) == nil)
    }

    @Test
    func localCredentialReadFailureCannotBecomeAnAnonymousRequest() throws {
        let (store, directory) = makeStore(failReads: true)
        defer {
            store.flushPendingChanges()
            try? FileManager.default.removeItem(at: directory)
        }
        let model = AIAgentLocalModel(name: "LM Studio", endpoint: AIEndpoint(name: "LM Studio", baseURL: AIEndpointKind.openAICompatible.defaultBaseURL), modelName: "local-model")
        store.upsertLocalModel(model)

        for requiresModel in [true, false] {
            #expect(throws: AIAgentSecretStoreError.storageFailed("injected")) {
                try AppModel.voicePostProcessingTarget(for: .local(model.id), store: store, requiresModel: requiresModel)
            }
        }
    }

    @Test
    func cloudVoiceTargetKeepsCredentialsEffortAndValidation() throws {
        let (store, directory) = makeStore(key: " cloud-test-key ")
        defer {
            store.flushPendingChanges()
            try? FileManager.default.removeItem(at: directory)
        }
        let account = AgentAccount(name: "Cloud", provider: "Cloud")
        try store.upsertAccount(account)
        var channel = AgentChannel(name: "Cloud", defaultModel: "cloud-model", effort: .medium, endpointGroups: [AgentEndpointGroup(name: "default", baseURLs: ["https://api.example/v1"], accountIDs: [account.id])])
        store.upsertChannel(channel)

        let target = try AppModel.voicePostProcessingTarget(for: .channel(channel.id), store: store)
        guard case let .http(_, _, name, key, effort, localInference, localThinkingEnabled) = target else {
            Issue.record("Existing cloud configuration should resolve")
            return
        }
        #expect(name == "cloud-model")
        #expect(key == "cloud-test-key")
        #expect(effort == .medium)
        #expect(!localInference)
        #expect(!localThinkingEnabled)
        channel.defaultModel = ""
        store.upsertChannel(channel)
        #expect(try AppModel.voicePostProcessingTarget(for: .channel(channel.id), store: store, requiresModel: false) == nil)
    }

    private func makeStore(key: String? = nil, failReads: Bool = false) -> (AIAgentStore, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-voice-local-target-\(UUID())")
        return (
            AIAgentStore(storageURL: directory.appendingPathComponent("state.json"), secretStore: LocalTargetSecretStore(key: key, failReads: failReads)),
            directory
        )
    }
}

private struct LocalTargetSecretStore: AIAgentSecretStoring {
    let key: String?
    let failReads: Bool

    func secret(for reference: String) throws -> String? {
        if failReads { throw AIAgentSecretStoreError.storageFailed("injected") }
        return key
    }
    func setSecret(_ secret: String, for reference: String) throws {}
    func removeSecret(for reference: String) throws {}
}
