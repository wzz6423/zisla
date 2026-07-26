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

        #expect(try store.messageConnectionCredentials(for: connection) == credentials)
        let state = try String(decoding: Data(contentsOf: directory.appendingPathComponent("state.json")), as: UTF8.self)
        #expect(!state.contains("cli_example"))
        #expect(!state.contains("secret"))
    }
}
