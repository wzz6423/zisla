import Foundation
import Testing
@testable import ZislaCore
@testable import ZislaKit

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
}
private final class DiscoveryStubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var nextResponseBody: String?

    nonisolated static override func canInit(with request: URLRequest) -> Bool { true }

    nonisolated static override func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
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
    }
}
