import Foundation
import Testing
@testable import ZislaCore
@testable import ZislaKit

@Suite(.serialized)
@MainActor
struct AIAgentWorkspaceRoutingTests {
    @Test
    func apiRelayTriesEveryRouteAndQuarantinesOnlyTheFailingURL() async throws {
        WorkspaceRouteURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [WorkspaceRouteURLProtocol.self]
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-api-routing-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let secrets = WorkspaceRouteSecretStore()
        let store = AIAgentStore(
            storageURL: directory.appendingPathComponent("state.json"),
            secretStore: secrets
        )
        let missingKeyAccount = AgentAccount(name: "无 Key", provider: "OpenAI")
        let workingAccount = AgentAccount(name: "可用 Key", provider: "OpenAI")
        try store.upsertAccount(missingKeyAccount)
        try store.upsertAccount(workingAccount, secret: "working-key")
        let group = AgentEndpointGroup(
            name: "主组",
            baseURLs: ["https://one.example/v1", "https://two.example/v1"],
            accountIDs: [missingKeyAccount.id, workingAccount.id]
        )
        let channel = AgentChannel(
            name: "远程渠道",
            defaultModel: "gpt-test",
            endpointGroups: [group]
        )
        store.upsertChannel(channel)
        let thread = store.createThread(channelID: channel.id)
        let workspace = AIAgentWorkspace(
            store: store,
            chatClient: AIChatClient(session: URLSession(configuration: configuration))
        )

        await workspace.send("第一次", to: thread.id)
        await workspace.send("第二次", to: thread.id)
        await workspace.send("第三次", to: thread.id)

        #expect(WorkspaceRouteURLProtocol.requestHosts == [
            "one.example", "two.example",
            "one.example", "two.example",
            "two.example",
        ])
        #expect(WorkspaceRouteURLProtocol.authorizationHeaders.allSatisfy { $0 == "Bearer working-key" })
        #expect(store.account(id: missingKeyAccount.id)?.consecutiveFailures == 0)
        #expect(store.account(id: workingAccount.id)?.consecutiveFailures == 0)
        #expect(store.state.chatThreads.first(where: { $0.id == thread.id })?.messages.count == 6)
        #expect(workspace.lastError == nil)
    }

    @Test
    func authenticationFailuresDoNotQuarantineAHealthyEndpoint() async throws {
        WorkspaceRouteURLProtocol.reset()
        WorkspaceRouteURLProtocol.statusCodesByHost = ["one.example": 401]
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [WorkspaceRouteURLProtocol.self]
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-api-auth-routing-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AIAgentStore(
            storageURL: directory.appendingPathComponent("state.json"),
            secretStore: WorkspaceRouteSecretStore()
        )
        let account = AgentAccount(name: "API 账号", provider: "OpenAI")
        try store.upsertAccount(account, secret: "test-key")
        let channel = AgentChannel(
            name: "远程渠道",
            defaultModel: "gpt-test",
            endpointGroups: [AgentEndpointGroup(
                name: "主组",
                baseURLs: ["https://one.example/v1", "https://two.example/v1"],
                accountIDs: [account.id]
            )]
        )
        store.upsertChannel(channel)
        let thread = store.createThread(channelID: channel.id)
        let workspace = AIAgentWorkspace(
            store: store,
            chatClient: AIChatClient(session: URLSession(configuration: configuration))
        )

        for index in 1...5 {
            await workspace.send("第\(index)次", to: thread.id)
        }

        #expect(WorkspaceRouteURLProtocol.requestHosts == [
            "one.example", "two.example",
            "two.example",
            "one.example", "two.example",
            "two.example",
            "one.example", "two.example",
        ])
        #expect(workspace.lastError == nil)
    }
}

private final class WorkspaceRouteSecretStore: AIAgentSecretStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]

    func secret(for reference: String) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return values[reference]
    }

    func setSecret(_ secret: String, for reference: String) throws {
        lock.lock()
        defer { lock.unlock() }
        values[reference] = secret
    }

    func removeSecret(for reference: String) throws {
        lock.lock()
        defer { lock.unlock() }
        values.removeValue(forKey: reference)
    }
}

private final class WorkspaceRouteURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHosts: [String] = []
    nonisolated(unsafe) static var authorizationHeaders: [String?] = []
    nonisolated(unsafe) static var statusCodesByHost = ["one.example": 500]

    static func reset() {
        requestHosts = []
        authorizationHeaders = []
        statusCodesByHost = ["one.example": 500]
    }

    nonisolated override class func canInit(with request: URLRequest) -> Bool { true }
    nonisolated override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let host = request.url?.host ?? ""
        Self.requestHosts.append(host)
        Self.authorizationHeaders.append(request.value(forHTTPHeaderField: "Authorization"))
        let statusCode = Self.statusCodesByHost[host] ?? 200
        let body = statusCode == 200
            ? Data(#"{"choices":[{"message":{"content":"ok"}}]}"#.utf8)
            : Data(#"{"error":"unavailable"}"#.utf8)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
