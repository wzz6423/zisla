import Foundation
import Testing
import ZislaCore
import ZislaKit
@testable import Zisla

@MainActor
struct LocalModelDiscoveryStateTests {
    @Test(arguments: AIEndpointKind.allCases)
    func enabledConfigurationLoadsModelsWithoutAManualFetch(kind: AIEndpointKind) async throws {
        let endpoint = AIEndpoint(name: kind.defaultEndpointName, baseURL: kind.defaultBaseURL, kind: kind)
        let state = LocalModelDiscoveryState { requested, key, action in
            #expect(requested == endpoint)
            #expect(key == "test-key")
            #expect(action == .discover)
            return AILocalModelCatalog(models: [AIDiscoveredModel(name: "installed-model")])
        }
        let task = try #require(state.refresh(endpoint: endpoint, apiKey: "test-key", isEnabled: true, delay: .zero))
        #expect(state.isLoading)
        await task.value
        #expect(state.catalog?.models.map(\.name) == ["installed-model"])
        #expect(!state.isLoading)
        #expect(state.error == nil)
    }

    @Test
    func disablingDuringDebouncePreventsDiscovery() async throws {
        let state = LocalModelDiscoveryState { _, _, _ in
            Issue.record("A disabled configuration must not contact a model service")
            return AILocalModelCatalog(models: [])
        }
        let pending = try #require(state.refresh(endpoint: endpoint, apiKey: nil, isEnabled: true, delay: .seconds(60)))
        let disabled = state.refresh(endpoint: endpoint, apiKey: nil, isEnabled: false)
        #expect(disabled == nil)
        await disabled?.value
        await pending.value
        #expect(state.catalog == nil)
        #expect(state.error == nil)
        #expect(!state.isLoading)
    }

    @Test(arguments: [false, true])
    func oldRequestsCannotReplaceNewEndpointResults(fails: Bool) async throws {
        let gate = DiscoveryGate()
        let state = LocalModelDiscoveryState { endpoint, key, _ in
            if key == "old-key" { return try await gate.load() }
            #expect(endpoint.kind == .ollama)
            #expect(key == "new-key")
            return AILocalModelCatalog(models: [AIDiscoveredModel(name: "new-model")])
        }
        let old = try #require(state.refresh(endpoint: endpoint, apiKey: "old-key", isEnabled: true, delay: .zero))
        await gate.waitUntilStarted()
        let updated = AIEndpoint(name: "Ollama", baseURL: AIEndpointKind.ollama.defaultBaseURL, kind: .ollama)
        let current = try #require(state.refresh(endpoint: updated, apiKey: "new-key", isEnabled: true, delay: .zero))
        await current.value
        gate.finish(fails: fails)
        await old.value
        #expect(state.catalog?.models.map(\.name) == ["new-model"])
        #expect(state.error == nil)
        #expect(!state.isLoading)
    }

    @Test
    func leavingTheViewCancelsPendingResults() async throws {
        let gate = DiscoveryGate()
        let state = LocalModelDiscoveryState { _, _, _ in try await gate.load() }
        let pending = try #require(state.refresh(endpoint: endpoint, apiKey: nil, isEnabled: true, delay: .zero))
        await gate.waitUntilStarted()
        state.cancel()
        gate.finish(fails: false)
        await pending.value
        #expect(state.catalog == nil)
        #expect(state.error == nil)
        #expect(!state.isLoading)
    }

    @Test
    func failureClearsModelsAndCanRecover() async throws {
        let state = LocalModelDiscoveryState { _, key, _ in
            if key == "invalid" { throw URLError(.userAuthenticationRequired) }
            return AILocalModelCatalog(models: [], serverState: .stopped)
        }
        await state.refresh(endpoint: endpoint, apiKey: nil, isEnabled: true, delay: .zero)?.value
        #expect(state.catalog?.serverState == .stopped)
        await state.refresh(endpoint: endpoint, apiKey: "invalid", isEnabled: true, delay: .zero)?.value
        #expect(state.error != nil)
        #expect(state.catalog == nil)
        #expect(!state.isLoading)
        await state.refresh(endpoint: endpoint, apiKey: "valid", isEnabled: true, delay: .zero)?.value
        #expect(state.error == nil)
        #expect(state.catalog?.models.isEmpty == true)
        #expect(state.catalog?.serverState == .stopped)
    }

    @Test
    func explicitStartUsesTheCurrentEndpointAndCredential() async throws {
        let expected = endpoint
        let state = LocalModelDiscoveryState { endpoint, key, action in
            #expect(endpoint == expected)
            #expect(key == "local-test-key")
            #expect(action == .startServer)
            return AILocalModelCatalog(models: [AIDiscoveredModel(name: "ready-model")])
        }
        await state.refresh(endpoint: expected, apiKey: "local-test-key", isEnabled: true, action: .startServer, delay: .zero)?.value
        #expect(state.catalog?.serverState == .ready)
        #expect(state.error == nil)
    }

    private var endpoint: AIEndpoint {
        AIEndpoint(name: "LM Studio", baseURL: AIEndpointKind.openAICompatible.defaultBaseURL)
    }
}

@MainActor
private final class DiscoveryGate {
    private var continuation: CheckedContinuation<AILocalModelCatalog, Error>?
    private var started: CheckedContinuation<Void, Never>?

    func load() async throws -> AILocalModelCatalog {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            started?.resume()
            started = nil
        }
    }

    func waitUntilStarted() async {
        if continuation != nil { return }
        await withCheckedContinuation { started = $0 }
    }

    func finish(fails: Bool) {
        if fails {
            continuation?.resume(throwing: URLError(.cannotConnectToHost))
        } else {
            continuation?.resume(returning: AILocalModelCatalog(models: [AIDiscoveredModel(name: "old-model")]))
        }
        continuation = nil
    }
}
