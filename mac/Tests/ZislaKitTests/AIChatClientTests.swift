import Foundation
import Testing

@testable import ZislaCore
@testable import ZislaKit

@MainActor
struct AIChatClientTests {
    @Test
    func sendsConfiguredAuthorizationAndTranscriptMessages() async throws {
        StubURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = AIChatClient(session: session)
        let endpoint = AIEndpoint(name: "测试", baseURL: "https://voice.example/v1")

        let response = try await client.complete(
            endpoint: endpoint,
            model: "voice-model",
            systemPrompt: VoiceTranscriptPostProcessor.systemPrompt,
            messages: VoiceTranscriptPostProcessor.messages(for: "明天十点开会"),
            apiKey: " test-key "
        )

        #expect(response.content == "明天十点开会。")
        let request = try #require(StubURLProtocol.lastRequest)
        #expect(request.url?.absoluteString == "https://voice.example/v1/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")

        let body = try #require(requestBody(request))
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["model"] as? String == "voice-model")
        let messages = try #require(json["messages"] as? [[String: String]])
        #expect(messages.count == 2)
        #expect(messages[0]["role"] == "system")
        #expect(messages[1]["content"] == "<transcript>\n明天十点开会\n</transcript>")
    }
}

private func requestBody(_ request: URLRequest) -> Data? {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return nil }
    stream.open()
    defer { stream.close() }

    var body = Data()
    var buffer = [UInt8](repeating: 0, count: 1_024)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        guard count > 0 else { break }
        body.append(buffer, count: count)
    }
    return body.isEmpty ? nil : body
}

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var lastRequest: URLRequest?

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
        client?.urlProtocol(self, didLoad: Data(#"{"choices":[{"message":{"content":"明天十点开会。"}}]}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    @MainActor
    static func reset() {
        lastRequest = nil
    }
}
