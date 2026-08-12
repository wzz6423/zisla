import Foundation
import Testing

@testable import ZislaCore
@testable import ZislaKit

@MainActor
@Suite(.serialized)
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

    @Test
    func throwsInvalidResponseWhenContentIsMissing() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.nextResponseBody = #"{"choices":[{"message":{}}]}"#
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = AIChatClient(session: session)
        let endpoint = AIEndpoint(name: "测试", baseURL: "https://test.example/v1")

        await #expect(throws: AIChatClientError.invalidResponse) {
            try await client.complete(
                endpoint: endpoint,
                model: "test-model",
                systemPrompt: "system",
                messages: [AIOutboundMessage(role: .user, content: "test")]
            )
        }
    }

    @Test
    func throwsInvalidResponseWhenContentIsWhitespaceOnly() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.nextResponseBody = #"{"choices":[{"message":{"content":"  \n\t  "}}]}"#
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = AIChatClient(session: session)
        let endpoint = AIEndpoint(name: "测试", baseURL: "https://test.example/v1")

        await #expect(throws: AIChatClientError.invalidResponse) {
            try await client.complete(
                endpoint: endpoint,
                model: "test-model",
                systemPrompt: "system",
                messages: [AIOutboundMessage(role: .user, content: "test")]
            )
        }
    }

    @Test
    func sendsAnthropicMessagesRequestAndDecodesTextBlocks() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.nextResponseBody = #"{"content":[{"type":"text","text":"Anthropic reply"}]}"#
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let client = AIChatClient(session: URLSession(configuration: configuration))

        let response = try await client.complete(
            endpoint: AIEndpoint(name: "Anthropic", baseURL: "https://anthropic.example/v1"),
            protocolKind: .anthropicMessages,
            model: "claude-sonnet",
            systemPrompt: "system",
            messages: [AIOutboundMessage(role: .user, content: "hello")],
            apiKey: "anthropic-key"
        )

        #expect(response.content == "Anthropic reply")
        let request = try #require(StubURLProtocol.lastRequest)
        #expect(request.url?.absoluteString == "https://anthropic.example/v1/messages")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "anthropic-key")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        let body = try #require(requestBody(request))
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["system"] as? String == "system")
        #expect((json["messages"] as? [[String: Any]])?.count == 1)
    }

    @Test
    func sendsGeminiGenerateContentRequestAndDecodesParts() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.nextResponseBody = #"{"candidates":[{"content":{"parts":[{"text":"Gemini reply"}]}}]}"#
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let client = AIChatClient(session: URLSession(configuration: configuration))

        let response = try await client.complete(
            endpoint: AIEndpoint(name: "Gemini", baseURL: "https://gemini.example"),
            protocolKind: .geminiGenerateContent,
            model: "gemini-2.5-pro",
            systemPrompt: "system",
            messages: [AIOutboundMessage(role: .user, content: "hello")],
            apiKey: "gemini-key"
        )

        #expect(response.content == "Gemini reply")
        let request = try #require(StubURLProtocol.lastRequest)
        #expect(request.url?.absoluteString == "https://gemini.example/v1beta/models/gemini-2.5-pro:generateContent")
        #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "gemini-key")
        let body = try #require(requestBody(request))
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["systemInstruction"] != nil)
        #expect((json["contents"] as? [[String: Any]])?.count == 1)
    }

    @Test
    func rejectsRemotePlainHTTPButAllowsLoopbackHTTP() async throws {
        StubURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let client = AIChatClient(session: URLSession(configuration: configuration))
        let remote = AIEndpoint(name: "Remote", baseURL: "http://api.example/v1")
        let loopbackImpersonator = try #require(URL(string: "http://127.evil.example/v1"))
        let hostlessHTTPS = try #require(URL(string: "https:///v1"))

        #expect(!AIEndpointSecurity.permits(loopbackImpersonator))
        #expect(!AIEndpointSecurity.permits(hostlessHTTPS))

        await #expect(throws: AIChatClientError.invalidEndpoint(remote.baseURL)) {
            try await client.complete(
                endpoint: remote,
                model: "model",
                systemPrompt: "",
                messages: [AIOutboundMessage(role: .user, content: "hello")],
                apiKey: "secret"
            )
        }

        let localResponse = try await client.complete(
            endpoint: AIEndpoint(name: "Local", baseURL: "http://127.0.0.1:11434/v1", kind: .ollama),
            model: "local-model",
            systemPrompt: "",
            messages: [AIOutboundMessage(role: .user, content: "hello")]
        )
        #expect(localResponse.content == "明天十点开会。")
    }

    @Test
    func httpErrorsDoNotExposeProviderResponseBody() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.statusCode = 401
        StubURLProtocol.nextResponseBody = #"{"error":"secret-provider-body"}"#
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let client = AIChatClient(session: URLSession(configuration: configuration))

        do {
            _ = try await client.complete(
                endpoint: AIEndpoint(name: "Remote", baseURL: "https://api.example/v1"),
                model: "model",
                systemPrompt: "",
                messages: [AIOutboundMessage(role: .user, content: "hello")],
                apiKey: "secret-api-key"
            )
            Issue.record("HTTP 错误应抛出异常")
        } catch {
            #expect(error.localizedDescription == "模型请求失败（HTTP 401）")
            #expect(!error.localizedDescription.contains("secret-provider-body"))
            #expect(!error.localizedDescription.contains("secret-api-key"))
        }
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
        let body = Self.nextResponseBody ?? #"{"choices":[{"message":{"content":"明天十点开会。"}}]}"#
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    @MainActor
    static func reset() {
        lastRequest = nil
        nextResponseBody = nil
        statusCode = 200
    }
}
