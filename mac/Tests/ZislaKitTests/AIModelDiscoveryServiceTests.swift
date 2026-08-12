import Foundation
import Testing
@testable import ZislaCore
@testable import ZislaKit

@Suite(.serialized)
struct AIModelDiscoveryServiceTests {
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

    nonisolated static override func canInit(with request: URLRequest) -> Bool { true }

    nonisolated static override func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
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
    }
}
