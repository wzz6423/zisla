import Foundation
import Testing
@testable import ZislaCore
@testable import ZislaKit

@Suite(.serialized)
struct AIModelDiscoveryServiceTests {
    @Test(arguments: AIEndpointKind.allCases)
    func localCatalogNeedsNoKeyAndNormalizesModelNames(kind: AIEndpointKind) async throws {
        DiscoveryStubURLProtocol.reset()
        DiscoveryStubURLProtocol.nextResponseBody = kind == .ollama
            ? #"{"models":[{"name":" qwen3.5:4b "},{"name":"qwen3.5:4b"},{"name":""},{"name":"gemma4:e2b"}]}"#
            : #"{"data":[{"id":" qwen3.5:4b "},{"id":"qwen3.5:4b"},{"id":""},{"id":"gemma4:e2b"}]}"#
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DiscoveryStubURLProtocol.self]
        let service = AIModelDiscoveryService(session: URLSession(configuration: configuration))
        let models = try await service.models(for: AIEndpoint(name: kind.defaultEndpointName, baseURL: kind.defaultBaseURL, kind: kind))

        #expect(models.map(\.name) == ["gemma4:e2b", "qwen3.5:4b"])
        let request = try #require(DiscoveryStubURLProtocol.lastRequest)
        #expect(request.url?.absoluteString == (kind == .ollama ? "http://127.0.0.1:11434/api/tags" : "http://127.0.0.1:1234/v1/models"))
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.httpBody == nil)
    }

    @Test
    func authenticatedLMStudioCatalogUsesBearerKeyAndAcceptsAnEmptyCatalog() async throws {
        DiscoveryStubURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DiscoveryStubURLProtocol.self]
        let service = AIModelDiscoveryService(session: URLSession(configuration: configuration))
        let models = try await service.models(for: AIEndpoint(name: "LM Studio", baseURL: "http://localhost:1234"), apiKey: " lm-test-key \n")

        #expect(models.isEmpty)
        #expect(DiscoveryStubURLProtocol.lastRequest?.url?.absoluteString == "http://localhost:1234/v1/models")
        #expect(DiscoveryStubURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer lm-test-key")
    }

    @Test(arguments: ["{}", "null", "{", #"{"data":[{"id":42}]}"#])
    func malformedCatalogIsAnErrorRatherThanAnEmptySuccess(body: String) async throws {
        DiscoveryStubURLProtocol.reset()
        DiscoveryStubURLProtocol.nextResponseBody = body
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DiscoveryStubURLProtocol.self]
        let service = AIModelDiscoveryService(session: URLSession(configuration: configuration))

        await #expect(throws: DecodingError.self) {
            try await service.models(for: AIEndpoint(name: "LM Studio", baseURL: AIEndpointKind.openAICompatible.defaultBaseURL))
        }
    }

    @Test
    func unavailableLocalServiceCanRecoverWithoutChangingItsConfiguration() async throws {
        DiscoveryStubURLProtocol.reset()
        DiscoveryStubURLProtocol.nextError = URLError(.cannotConnectToHost)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DiscoveryStubURLProtocol.self]
        let service = AIModelDiscoveryService(session: URLSession(configuration: configuration))
        let endpoint = AIEndpoint(name: "LM Studio", baseURL: AIEndpointKind.openAICompatible.defaultBaseURL)
        await #expect(throws: URLError.self) { try await service.models(for: endpoint) }

        DiscoveryStubURLProtocol.nextError = nil
        DiscoveryStubURLProtocol.nextResponseBody = #"{"data":[{"id":"available-model"}]}"#
        let models = try await service.models(for: endpoint)
        #expect(models.map(\.name) == ["available-model"])
        #expect(endpoint.baseURL == AIEndpointKind.openAICompatible.defaultBaseURL)
    }

    @Test
    func authorizationHeaderUsesNonEmptyTrimmedAPIKey() {
        #expect(AIModelDiscoveryService.authorizationHeader(for: nil) == nil)
        #expect(AIModelDiscoveryService.authorizationHeader(for: "  ") == nil)
        #expect(AIModelDiscoveryService.authorizationHeader(for: "  sk-test  ") == "Bearer sk-test")
    }

    @Test
    func modelsRequestHas30SecondTimeout() async throws {
        DiscoveryStubURLProtocol.reset()
        DiscoveryStubURLProtocol.nextResponseBody = #"{"data":[{"id":"gpt-4"}]}"#
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DiscoveryStubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let service = AIModelDiscoveryService(session: session)
        let endpoint = AIEndpoint(name: "测试", baseURL: "https://api.example.com/v1", kind: .openAICompatible)

        _ = try await service.models(for: endpoint)

        let request = try #require(DiscoveryStubURLProtocol.lastRequest)
        #expect(request.timeoutInterval == 30)
    }

    @Test(arguments: AIEndpointKind.allCases)
    func automaticCatalogUsesTheSelectedService(kind: AIEndpointKind) async throws {
        DiscoveryStubURLProtocol.reset()
        DiscoveryStubURLProtocol.nextResponseBody = kind == .ollama
            ? #"{"models":[{"name":"qwen3.5:4b"}]}"#
            : #"{"models":[{"type":"llm","key":"qwen/qwen3.8-27b","loaded_instances":[]},{"type":"embedding","key":"embedding-only"}]}"#
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DiscoveryStubURLProtocol.self]
        let catalog = try await AIModelDiscoveryService(session: URLSession(configuration: configuration)).localCatalog(
            for: AIEndpoint(name: kind.defaultEndpointName, baseURL: kind.defaultBaseURL, kind: kind)
        )
        #expect(catalog.serverState == .ready)
        #expect(catalog.models.map(\.name) == [kind == .ollama ? "qwen3.5:4b" : "qwen/qwen3.8-27b"])
        #expect(DiscoveryStubURLProtocol.lastRequest?.url?.path == (kind == .ollama ? "/api/tags" : "/api/v1/models"))
    }

    @Test(arguments: [404, 405])
    func olderServersCanUseTheOpenAICompatibleCatalog(status: Int) async throws {
        let fixture = try LMStudioFixture()
        defer { fixture.remove() }
        let service = localService(fixture: fixture)
        DiscoveryStubURLProtocol.nextError = nil
        DiscoveryStubURLProtocol.responsesByPath = [
            "/api/v1/models": (status, "{}"),
            "/v1/models": (200, #"{"data":[{"id":"legacy-model"}]}"#),
        ]
        let catalog = try await service.localCatalog(for: lmStudioEndpoint)
        #expect(catalog.models.map(\.name) == ["legacy-model"])
        #expect(catalog.serverState == .ready)
        #expect(fixture.commands.isEmpty)
    }

    @Test(arguments: ["http://localhost:1234", "http://localhost:1234/", "http://localhost:1234/v1/", "http://[::1]:1234/v1"])
    func nativeCatalogAcceptsSupportedBaseURLForms(address: String) async throws {
        let fixture = try LMStudioFixture()
        defer { fixture.remove() }
        let service = localService(fixture: fixture)
        DiscoveryStubURLProtocol.nextError = nil
        DiscoveryStubURLProtocol.nextResponseBody = #"{"models":[]}"#
        let catalog = try await service.localCatalog(for: AIEndpoint(name: "LM Studio", baseURL: address))
        #expect(catalog.models.isEmpty)
        #expect(catalog.serverState == .ready)
        let host = address.contains("[::1]") ? "[::1]" : "localhost"
        #expect(DiscoveryStubURLProtocol.lastRequest?.url?.absoluteString == "http://\(host):1234/api/v1/models")
    }

    @Test(arguments: [false, true])
    func stoppedHTTPServerStillListsDownloadedLMStudioModelIDs(running: Bool) async throws {
        let fixture = try LMStudioFixture(running: running)
        defer { fixture.remove() }
        let service = localService(fixture: fixture)
        let endpoint = AIEndpoint(name: "LM Studio", baseURL: "http://localhost:1234/v1")
        let catalog = try await service.localCatalog(for: endpoint)

        #expect(catalog.models.map(\.name) == ["google/gemma-4", "qwen/qwen3.8-27b"])
        #expect(catalog.serverState == (running ? .unreachable : .stopped))
        #expect(!fixture.commands.contains("start"))
        #expect(!fixture.commands.contains("load"))
        #expect(!fixture.commands.contains("get"))
        await #expect(throws: URLError.self) { try await service.models(for: endpoint) }
    }

    @Test
    func emptyInstalledCatalogDoesNotPretendTheServerIsReady() async throws {
        let fixture = try LMStudioFixture(catalog: "[]")
        defer { fixture.remove() }
        let catalog = try await localService(fixture: fixture).localCatalog(for: lmStudioEndpoint)
        #expect(catalog.models.isEmpty)
        #expect(catalog.serverState == .stopped)
    }

    @Test(arguments: [
        "https://models.example/v1", "http://127.0.0.1:1234/proxy/v1",
        "https://localhost:1234/v1", "http://localhost:1234/v1?provider=remote",
    ])
    func localCatalogNeverFallsBackForOtherEndpoints(address: String) async throws {
        let fixture = try LMStudioFixture()
        defer { fixture.remove() }
        let service = localService(fixture: fixture)
        await #expect(throws: URLError.self) {
            try await service.localCatalog(for: AIEndpoint(name: "Other", baseURL: address))
        }
        #expect(fixture.commands.isEmpty)
    }

    @Test
    func offlineOllamaDoesNotUseLMStudioModels() async throws {
        let fixture = try LMStudioFixture()
        defer { fixture.remove() }
        let service = localService(fixture: fixture)
        await #expect(throws: URLError.self) {
            try await service.localCatalog(for: AIEndpoint(name: "Ollama", baseURL: AIEndpointKind.ollama.defaultBaseURL, kind: .ollama))
        }
        #expect(fixture.commands.isEmpty)
    }

    @Test(arguments: [401, 403, 500])
    func authenticationAndServerErrorsRemainVisible(statusCode: Int) async throws {
        let fixture = try LMStudioFixture()
        defer { fixture.remove() }
        let service = localService(fixture: fixture)
        DiscoveryStubURLProtocol.nextError = nil
        DiscoveryStubURLProtocol.statusCode = statusCode
        await #expect(throws: AIModelDiscoveryError.self) {
            try await service.localCatalog(for: lmStudioEndpoint, apiKey: "test-key")
        }
        #expect(fixture.commands.isEmpty)
    }

    @Test(arguments: [URLError.Code.cancelled, .timedOut])
    func cancellationAndTimeoutDoNotInvokeLocalCLI(code: URLError.Code) async throws {
        let fixture = try LMStudioFixture()
        defer { fixture.remove() }
        let service = localService(fixture: fixture)
        DiscoveryStubURLProtocol.nextError = URLError(code)
        await #expect(throws: URLError.self) { try await service.localCatalog(for: lmStudioEndpoint) }
        #expect(fixture.commands.isEmpty)
    }

    @Test
    func explicitStartBindsToLoopbackAndRequiresAnHTTPResponse() async throws {
        let fixture = try LMStudioFixture()
        defer { fixture.remove() }
        let service = localService(fixture: fixture)
        await #expect(throws: URLError.self) { try await service.startLMStudioServer(for: lmStudioEndpoint) }
        #expect(fixture.commands == ["server", "status", "--json", "server", "start", "--bind", "127.0.0.1", "--port", "1234"])

        DiscoveryStubURLProtocol.nextError = nil
        DiscoveryStubURLProtocol.nextResponseBody = #"{"models":[{"type":"llm","key":"qwen/qwen3.8-27b"}]}"#
        let catalog = try await service.startLMStudioServer(for: lmStudioEndpoint, apiKey: "test-key")
        #expect(catalog.serverState == .ready)
        #expect(catalog.models.map(\.name) == ["qwen/qwen3.8-27b"])
        #expect(DiscoveryStubURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
        #expect(!fixture.commands.contains("test-key"))
    }

    private var lmStudioEndpoint: AIEndpoint {
        AIEndpoint(name: "LM Studio", baseURL: AIEndpointKind.openAICompatible.defaultBaseURL)
    }

    private func localService(fixture: LMStudioFixture) -> AIModelDiscoveryService {
        DiscoveryStubURLProtocol.reset()
        DiscoveryStubURLProtocol.nextError = URLError(.cannotConnectToHost)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DiscoveryStubURLProtocol.self]
        return AIModelDiscoveryService(session: URLSession(configuration: configuration), lmStudio: fixture.service)
    }

    @Test
    func rejectsInsecureEndpointsAndRedactsHTTPResponseBody() async throws {
        let service = AIModelDiscoveryService()
        let impersonator = AIEndpoint(
            name: "Remote",
            baseURL: "http://127.evil.example/v1",
            kind: .openAICompatible
        )

        await #expect(throws: AIModelDiscoveryError.self) {
            try await service.models(for: impersonator, apiKey: "secret-api-key")
        }

        DiscoveryStubURLProtocol.reset()
        DiscoveryStubURLProtocol.statusCode = 403
        DiscoveryStubURLProtocol.nextResponseBody = #"{"error":"secret-provider-body"}"#
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DiscoveryStubURLProtocol.self]
        let stubbed = AIModelDiscoveryService(session: URLSession(configuration: configuration))
        do {
            _ = try await stubbed.models(
                for: AIEndpoint(name: "Remote", baseURL: "https://api.example/v1"),
                apiKey: "secret-api-key"
            )
            Issue.record("HTTP 错误应抛出异常")
        } catch {
            #expect(error.localizedDescription == "读取模型目录失败（HTTP 403）")
            #expect(!error.localizedDescription.contains("secret-provider-body"))
            #expect(!error.localizedDescription.contains("secret-api-key"))
        }
    }
}
private final class DiscoveryStubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var nextResponseBody: String?
    nonisolated(unsafe) static var statusCode = 200
    nonisolated(unsafe) static var nextError: URLError?
    nonisolated(unsafe) static var responsesByPath: [String: (Int, String)] = [:]

    nonisolated static override func canInit(with request: URLRequest) -> Bool { true }

    nonisolated static override func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        if let error = Self.nextError {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let stub = Self.responsesByPath[request.url!.path]
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: stub?.0 ?? Self.statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let body = stub?.1 ?? Self.nextResponseBody ?? #"{"data":[]}"#
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func reset() {
        lastRequest = nil
        nextResponseBody = nil
        statusCode = 200
        nextError = nil
        responsesByPath = [:]
    }
}
