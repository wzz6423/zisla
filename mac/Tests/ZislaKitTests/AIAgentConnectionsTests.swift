import Foundation
import Testing
@testable import ZislaCore
@testable import ZislaKit

@Suite(.serialized)
@MainActor
struct AIAgentConnectionsTests {
    @Test
    func feishuVerificationReturnsChallengeOnlyForConfiguredToken() throws {
        let connection = AgentMessageConnection(name: "飞书", kind: .feishu)
        let service = AIAgentMessageConnectionService()
        let request = AIAgentInboundHTTPRequest(
            method: "POST",
            path: connection.callbackPath,
            query: [:],
            headers: [:],
            body: Data(#"{"type":"url_verification","token":"verify","challenge":"challenge-value"}"#.utf8)
        )

        let result = service.process(
            request,
            for: connection,
            credentials: AgentMessageConnectionCredentials(verificationToken: "verify")
        )

        guard case let .response(response) = result,
              let object = try JSONSerialization.jsonObject(with: response.body) as? [String: String] else {
            Issue.record("应返回飞书 URL 验证响应")
            return
        }
        #expect(response.statusCode == 200)
        #expect(object["challenge"] == "challenge-value")
    }

    @Test
    func feishuTextMessageBuildsInboundMessage() {
        let connection = AgentMessageConnection(name: "飞书", kind: .feishu)
        let service = AIAgentMessageConnectionService()
        let request = AIAgentInboundHTTPRequest(
            method: "POST",
            path: connection.callbackPath,
            query: [:],
            headers: [:],
            body: Data(#"{"header":{"event_type":"im.message.receive_v1","token":"verify"},"event":{"sender":{"sender_id":{"open_id":"ou_sender"}},"message":{"message_type":"text","chat_id":"oc_chat","content":"{\"text\":\"你好\"}"}}}"#.utf8)
        )

        let result = service.process(
            request,
            for: connection,
            credentials: AgentMessageConnectionCredentials(verificationToken: "verify")
        )

        guard case let .message(message, acknowledgement) = result else {
            Issue.record("应解析飞书文本消息")
            return
        }
        #expect(acknowledgement.statusCode == 200)
        #expect(message.connectionID == connection.id)
        #expect(message.conversationID == "oc_chat")
        #expect(message.sender == "ou_sender")
        #expect(message.content == "你好")
    }

    @Test
    func genericWebhookRequiresBearerToken() {
        let connection = AgentMessageConnection(name: "Webhook", kind: .webhook)
        let service = AIAgentMessageConnectionService()
        let request = AIAgentInboundHTTPRequest(
            method: "POST",
            path: connection.callbackPath,
            query: [:],
            headers: ["authorization": "Bearer secret"],
            body: Data(#"{"conversation_id":"thread-1","sender":"source","content":"hello"}"#.utf8)
        )

        let result = service.process(
            request,
            for: connection,
            credentials: AgentMessageConnectionCredentials(verificationToken: "secret")
        )

        guard case let .message(message, _) = result else {
            Issue.record("应解析带有效 Bearer Token 的通用 Webhook")
            return
        }
        #expect(message.conversationID == "thread-1")
        #expect(message.content == "hello")
    }

    @Test
    func duplicateQueryItemsUseTheLastValueWithoutCrashing() throws {
        let data = Data(
            "GET /callback?nonce=old&nonce=new HTTP/1.1\r\nHost: localhost\r\n\r\n".utf8
        )

        let request = try #require(AIAgentMessageConnectionServer.parseRequest(data))

        #expect(request.path == "/callback")
        #expect(request.query == ["nonce": "new"])
    }

    @Test
    func completeOversizedRequestIsRejectedBeforeParsing() {
        var data = Data("GET /callback HTTP/1.1\r\nHost: localhost\r\n\r\n".utf8)
        data.append(Data(repeating: 0, count: 1_048_576 - data.count))

        #expect(AIAgentMessageConnectionServer.parseRequest(data) == nil)
    }

    @Test
    func genericWebhookRejectsPlainHTTPOutboundURLs() async {
        let connection = AgentMessageConnection(name: "Webhook", kind: .webhook)
        let service = AIAgentMessageConnectionService()
        let message = AIAgentInboundMessage(
            connectionID: connection.id,
            conversationID: "conversation",
            sender: "sender",
            content: "request"
        )
        let credentials = AgentMessageConnectionCredentials(
            verificationToken: "secret",
            outboundURL: "http://example.com/reply"
        )

        await #expect(throws: AIAgentMessageConnectionError.self) {
            try await service.send("response", replyingTo: message, via: connection, credentials: credentials)
        }
    }

    @Test
    func webhookFailureDoesNotExposePlatformResponseBody() async throws {
        MessageConnectionStubURLProtocol.reset()
        MessageConnectionStubURLProtocol.statusCode = 502
        MessageConnectionStubURLProtocol.responseBody = #"{"error":"secret-platform-body"}"#
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MessageConnectionStubURLProtocol.self]
        let service = AIAgentMessageConnectionService(session: URLSession(configuration: configuration))
        let connection = AgentMessageConnection(name: "Webhook", kind: .webhook)
        let message = AIAgentInboundMessage(
            connectionID: connection.id,
            conversationID: "conversation",
            sender: "sender",
            content: "request"
        )
        let credentials = AgentMessageConnectionCredentials(
            verificationToken: "secret-token",
            outboundURL: "https://example.com/reply"
        )

        do {
            try await service.send("response", replyingTo: message, via: connection, credentials: credentials)
            Issue.record("HTTP 错误应抛出异常")
        } catch {
            #expect(error.localizedDescription == "平台发送失败（HTTP 502）")
            #expect(!error.localizedDescription.contains("secret-platform-body"))
            #expect(!error.localizedDescription.contains("secret-token"))
        }
    }

    @Test
    func connectionRegistryEnforcesCapacityAndExpiresSlowReaders() async {
        let capacityRegistry = AIAgentConnectionRegistry(
            maximumActiveConnections: 2,
            readTimeout: 30,
            queue: DispatchQueue(label: "zisla-connection-capacity-test")
        )
        let noTimeout: @Sendable () -> Void = {}
        let first = capacityRegistry.begin(onTimeout: noTimeout)
        let second = capacityRegistry.begin(onTimeout: noTimeout)

        #expect(capacityRegistry.activeCount == 2)
        #expect(capacityRegistry.begin(onTimeout: noTimeout) == nil)

        if let first { capacityRegistry.finish(first) }
        #expect(capacityRegistry.activeCount == 1)
        if let second { capacityRegistry.finish(second) }
        #expect(capacityRegistry.activeCount == 0)

        let timeoutRegistry = AIAgentConnectionRegistry(
            maximumActiveConnections: 1,
            readTimeout: 0.02,
            queue: DispatchQueue(label: "zisla-connection-timeout-test")
        )
        let timedOut = await withCheckedContinuation { continuation in
            let token = timeoutRegistry.begin {
                continuation.resume(returning: true)
            }
            #expect(token != nil)
        }

        #expect(timedOut)
        #expect(timeoutRegistry.activeCount == 0)
        let finishedToken = timeoutRegistry.begin(onTimeout: noTimeout)
        #expect(finishedToken != nil)
        if let finishedToken {
            timeoutRegistry.finish(finishedToken)
            #expect(!timeoutRegistry.completeRead(finishedToken))
        }
    }

    @Test
    func connectionCredentialsStayInPrivateDatabase() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-message-connection-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AIAgentStore(
            storageURL: directory.appendingPathComponent("state.json"),
            secretStore: DatabaseAIAgentSecretStore(storageURL: directory.appendingPathComponent("secrets.sqlite"))
        )
        let connection = AgentMessageConnection(name: "飞书", kind: .feishu)
        let credentials = AgentMessageConnectionCredentials(
            appID: "cli_example",
            appSecret: "secret",
            verificationToken: "verify"
        )

        store.upsertMessageConnection(connection)
        try store.replaceMessageConnectionCredentials(credentials, for: connection.id)
        store.flushPendingChanges()

        #expect(try store.messageConnectionCredentials(for: connection) == credentials)
        let state = try String(decoding: Data(contentsOf: directory.appendingPathComponent("state.json")), as: UTF8.self)
        #expect(!state.contains("cli_example"))
        #expect(!state.contains("secret"))
    }
}

private final class MessageConnectionStubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var statusCode = 200
    nonisolated(unsafe) static var responseBody = "{}"

    nonisolated override class func canInit(with request: URLRequest) -> Bool { true }
    nonisolated override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.responseBody.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    nonisolated static func reset() {
        statusCode = 200
        responseBody = "{}"
    }
}
