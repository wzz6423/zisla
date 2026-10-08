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

    nonisolated static override func canInit(with request: URLRequest) -> Bool { true }

    nonisolated static override func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        if let error = Self.nextError {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let body = Self.nextResponseBody ?? #"{"data":[]}"#
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func reset() {
        lastRequest = nil
        nextResponseBody = nil
        statusCode = 200
        nextError = nil
    }
}
