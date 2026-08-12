import CryptoKit
import Foundation
import Network
import ZislaCore

private let aiAgentMaximumRequestByteCount = 1_048_576

public struct AIAgentInboundHTTPRequest: Sendable {
    public var method: String
    public var path: String
    public var query: [String: String]
    public var headers: [String: String]
    public var body: Data

    init(method: String, path: String, query: [String: String], headers: [String: String], body: Data) {
        self.method = method
        self.path = path
        self.query = query
        self.headers = headers
        self.body = body
    }
}

public struct AIAgentInboundHTTPResponse: Sendable {
    public var statusCode: Int
    public var contentType: String
    public var body: Data

    public init(statusCode: Int, contentType: String = "application/json; charset=utf-8", body: Data = Data()) {
        self.statusCode = statusCode
        self.contentType = contentType
        self.body = body
    }

    static func json(_ object: [String: Any], statusCode: Int = 200) -> Self {
        let body = (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
        return Self(statusCode: statusCode, body: body)
    }

    static func text(_ text: String, statusCode: Int = 200) -> Self {
        Self(statusCode: statusCode, contentType: "text/plain; charset=utf-8", body: Data(text.utf8))
    }
}

public struct AIAgentInboundMessage: Sendable {
    public var connectionID: UUID
    public var conversationID: String
    public var sender: String
    public var content: String

    public init(connectionID: UUID, conversationID: String, sender: String, content: String) {
        self.connectionID = connectionID
        self.conversationID = conversationID
        self.sender = sender
        self.content = content
    }
}

public enum AIAgentConnectionRequestResult: Sendable {
    case response(AIAgentInboundHTTPResponse)
    case message(AIAgentInboundMessage, acknowledgement: AIAgentInboundHTTPResponse)
}

public enum AIAgentMessageConnectionError: LocalizedError, Sendable {
    case invalidCallback
    case missingCredentials
    case unsupportedEncryptedEvent
    case invalidPlatformResponse
    case http(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidCallback: "连接回调无效或未通过校验"
        case .missingCredentials: "连接凭证尚未配置完整"
        case .unsupportedEncryptedEvent: "当前不支持平台回调加密；请在平台侧关闭事件加密后重试"
        case .invalidPlatformResponse: "平台返回了无法识别的结果"
        case let .http(status): "平台发送失败（HTTP \(status)）"
        }
    }
}

/// The minimal callback protocol shared by Feishu, WeChat Official Accounts, and custom webhooks.
public struct AIAgentMessageConnectionService: Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func process(
        _ request: AIAgentInboundHTTPRequest,
        for connection: AgentMessageConnection,
        credentials: AgentMessageConnectionCredentials
    ) -> AIAgentConnectionRequestResult {
        guard request.path == connection.callbackPath else {
            return .response(.text("not found", statusCode: 404))
        }
        switch connection.kind {
        case .feishu:
            return processFeishu(request, connection: connection, credentials: credentials)
        case .weChatOfficial:
            return processWeChat(request, connection: connection, credentials: credentials)
        case .webhook:
            return processWebhook(request, connection: connection, credentials: credentials)
        }
    }

    public func send(
        _ content: String,
        replyingTo message: AIAgentInboundMessage,
        via connection: AgentMessageConnection,
        credentials: AgentMessageConnectionCredentials
    ) async throws {
        switch connection.kind {
        case .feishu:
            try await sendFeishu(content, conversationID: message.conversationID, credentials: credentials)
        case .weChatOfficial:
            try await sendWeChat(content, recipientID: message.conversationID, credentials: credentials)
        case .webhook:
            try await sendWebhook(content, replyingTo: message, credentials: credentials)
        }
    }

    private func processFeishu(
        _ request: AIAgentInboundHTTPRequest,
        connection: AgentMessageConnection,
        credentials: AgentMessageConnectionCredentials
    ) -> AIAgentConnectionRequestResult {
        guard request.method == "POST",
              let object = jsonObject(request.body) else {
            return .response(.text("bad request", statusCode: 400))
        }
        if object["encrypt"] != nil {
            return .response(.text("encrypted callbacks are not supported", statusCode: 422))
        }
        let header = object["header"] as? [String: Any]
        let token = (object["token"] as? String) ?? (header?["token"] as? String)
        guard valid(token: token, expected: credentials.verificationToken) else {
            return .response(.text("unauthorized", statusCode: 401))
        }
        if object["type"] as? String == "url_verification",
           let challenge = object["challenge"] as? String {
            return .response(.json(["challenge": challenge]))
        }
        guard header?["event_type"] as? String == "im.message.receive_v1",
              let event = object["event"] as? [String: Any],
              let message = event["message"] as? [String: Any],
              message["message_type"] as? String == "text",
              let conversationID = message["chat_id"] as? String,
              let content = feishuText(from: message["content"]),
              !content.isEmpty else {
            return .response(.json([:]))
        }
        let sender = ((event["sender"] as? [String: Any])?["sender_id"] as? [String: Any])?["open_id"] as? String ?? conversationID
        return .message(
            AIAgentInboundMessage(
                connectionID: connection.id,
                conversationID: conversationID,
                sender: sender,
                content: content
            ),
            acknowledgement: .json([:])
        )
    }

    private func processWeChat(
        _ request: AIAgentInboundHTTPRequest,
        connection: AgentMessageConnection,
        credentials: AgentMessageConnectionCredentials
    ) -> AIAgentConnectionRequestResult {
        guard validWeChatSignature(request.query, token: credentials.verificationToken) else {
            return .response(.text("unauthorized", statusCode: 401))
        }
        if request.method == "GET", let echo = request.query["echostr"] {
            return .response(.text(echo))
        }
        guard request.method == "POST",
              let values = xmlValues(request.body),
              values["MsgType"] == "text",
              let sender = values["FromUserName"],
              let content = values["Content"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else {
            return .response(.text("success"))
        }
        return .message(
            AIAgentInboundMessage(
                connectionID: connection.id,
                conversationID: sender,
                sender: sender,
                content: content
            ),
            acknowledgement: .text("success")
        )
    }

    private func processWebhook(
        _ request: AIAgentInboundHTTPRequest,
        connection: AgentMessageConnection,
        credentials: AgentMessageConnectionCredentials
    ) -> AIAgentConnectionRequestResult {
        guard request.method == "POST",
              !credentials.verificationToken.isEmpty,
              request.headers["authorization"] == "Bearer \(credentials.verificationToken)",
              let object = jsonObject(request.body),
              let conversationID = object["conversation_id"] as? String,
              let content = object["content"] as? String,
              !conversationID.isEmpty,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .response(.text("bad request", statusCode: 400))
        }
        let sender = object["sender"] as? String ?? conversationID
        return .message(
            AIAgentInboundMessage(
                connectionID: connection.id,
                conversationID: conversationID,
                sender: sender,
                content: content
            ),
            acknowledgement: .json(["accepted": true])
        )
    }

    private func sendFeishu(
        _ content: String,
        conversationID: String,
        credentials: AgentMessageConnectionCredentials
    ) async throws {
        guard !credentials.appID.isEmpty, !credentials.appSecret.isEmpty else {
            throw AIAgentMessageConnectionError.missingCredentials
        }
        let tokenResponse = try await requestJSON(
            url: URL(string: "https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal")!,
            body: ["app_id": credentials.appID, "app_secret": credentials.appSecret]
        )
        guard let token = tokenResponse["tenant_access_token"] as? String, !token.isEmpty else {
            throw AIAgentMessageConnectionError.invalidPlatformResponse
        }
        var components = URLComponents(string: "https://open.feishu.cn/open-apis/im/v1/messages")!
        components.queryItems = [URLQueryItem(name: "receive_id_type", value: "chat_id")]
        var request = try jsonRequest(
            url: components.url!,
            body: [
                "receive_id": conversationID,
                "msg_type": "text",
                "content": String(decoding: try JSONSerialization.data(withJSONObject: ["text": content]), as: UTF8.self),
            ]
        )
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = try await responseJSON(for: request)
    }

    private func sendWeChat(
        _ content: String,
        recipientID: String,
        credentials: AgentMessageConnectionCredentials
    ) async throws {
        guard !credentials.appID.isEmpty, !credentials.appSecret.isEmpty else {
            throw AIAgentMessageConnectionError.missingCredentials
        }
        var components = URLComponents(string: "https://api.weixin.qq.com/cgi-bin/token")!
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "client_credential"),
            URLQueryItem(name: "appid", value: credentials.appID),
            URLQueryItem(name: "secret", value: credentials.appSecret),
        ]
        let tokenResponse = try await responseJSON(for: URLRequest(url: components.url!))
        guard let token = tokenResponse["access_token"] as? String, !token.isEmpty else {
            throw AIAgentMessageConnectionError.invalidPlatformResponse
        }
        let request = try jsonRequest(
            url: URL(string: "https://api.weixin.qq.com/cgi-bin/message/custom/send?access_token=\(token)")!,
            body: [
                "touser": recipientID,
                "msgtype": "text",
                "text": ["content": content],
            ]
        )
        _ = try await responseJSON(for: request)
    }

    private func sendWebhook(
        _ content: String,
        replyingTo message: AIAgentInboundMessage,
        credentials: AgentMessageConnectionCredentials
    ) async throws {
        let outboundURL = credentials.outboundURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: outboundURL),
              url.scheme?.lowercased() == "https",
              url.host != nil else {
            throw AIAgentMessageConnectionError.missingCredentials
        }
        var request = try jsonRequest(
            url: url,
            body: [
                "conversation_id": message.conversationID,
                "recipient": message.sender,
                "content": content,
            ]
        )
        if !credentials.verificationToken.isEmpty {
            request.setValue("Bearer \(credentials.verificationToken)", forHTTPHeaderField: "Authorization")
        }
        _ = try await responseJSON(for: request)
    }

    private func requestJSON(url: URL, body: [String: Any]) async throws -> [String: Any] {
        try await responseJSON(for: jsonRequest(url: url, body: body))
    }

    private func jsonRequest(url: URL, body: [String: Any]) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func responseJSON(for request: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIAgentMessageConnectionError.invalidPlatformResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AIAgentMessageConnectionError.http(http.statusCode)
        }
        guard let object = jsonObject(data) else {
            throw AIAgentMessageConnectionError.invalidPlatformResponse
        }
        if let code = object["code"] as? Int, code != 0 {
            throw AIAgentMessageConnectionError.http(code)
        }
        if let code = object["errcode"] as? Int, code != 0 {
            throw AIAgentMessageConnectionError.http(code)
        }
        return object
    }

    private func valid(token: String?, expected: String) -> Bool {
        !expected.isEmpty && token == expected
    }

    private func validWeChatSignature(_ query: [String: String], token: String) -> Bool {
        guard !token.isEmpty,
              let signature = query["signature"],
              let timestamp = query["timestamp"],
              let nonce = query["nonce"] else {
            return false
        }
        let source = [token, timestamp, nonce].sorted().joined()
        let digest = Insecure.SHA1.hash(data: Data(source.utf8))
        let expected = digest.map { String(format: "%02x", $0) }.joined()
        return signature == expected
    }

    private func feishuText(from value: Any?) -> String? {
        guard let content = value as? String,
              let object = jsonObject(Data(content.utf8)) else { return nil }
        return object["text"] as? String
    }

    private func jsonObject(_ data: Data) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func xmlValues(_ data: Data) -> [String: String]? {
        let parser = XMLParser(data: data)
        let delegate = AIAgentXMLValuesParser()
        parser.delegate = delegate
        return parser.parse() ? delegate.values : nil
    }
}

private final class AIAgentXMLValuesParser: NSObject, XMLParserDelegate {
    var values: [String: String] = [:]
    private var currentElement: String?
    private var currentValue = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        currentValue = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentValue.append(string)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard currentElement == elementName else { return }
        values[elementName] = currentValue
        currentElement = nil
    }
}

final class AIAgentConnectionRegistry: @unchecked Sendable {
    struct Token: Hashable, Sendable {
        fileprivate let id = UUID()
    }

    private struct State {
        var deadline: DispatchWorkItem?
    }

    private let maximumActiveConnections: Int
    private let readTimeout: TimeInterval
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var states: [Token: State] = [:]

    init(maximumActiveConnections: Int, readTimeout: TimeInterval, queue: DispatchQueue) {
        self.maximumActiveConnections = max(1, maximumActiveConnections)
        self.readTimeout = max(0.001, readTimeout)
        self.queue = queue
    }

    var activeCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return states.count
    }

    func begin(onTimeout: @escaping @Sendable () -> Void) -> Token? {
        lock.lock()
        guard states.count < maximumActiveConnections else {
            lock.unlock()
            return nil
        }
        let token = Token()
        let deadline = DispatchWorkItem { [weak self] in
            guard self?.expire(token) == true else { return }
            onTimeout()
        }
        states[token] = State(deadline: deadline)
        lock.unlock()
        queue.asyncAfter(deadline: .now() + readTimeout, execute: deadline)
        return token
    }

    func completeRead(_ token: Token) -> Bool {
        lock.lock()
        guard let deadline = states[token]?.deadline else {
            lock.unlock()
            return false
        }
        states[token]?.deadline = nil
        lock.unlock()
        deadline.cancel()
        return true
    }

    func finish(_ token: Token) {
        lock.lock()
        let deadline = states.removeValue(forKey: token)?.deadline
        lock.unlock()
        deadline?.cancel()
    }

    private func expire(_ token: Token) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard states[token]?.deadline != nil else { return false }
        states.removeValue(forKey: token)
        return true
    }
}

/// The local HTTP listener only hands callbacks over to the workspace; the public internet can reach this port through the user's existing reverse proxy or tunnel.
@MainActor
final class AIAgentMessageConnectionServer {
    typealias Handler = @MainActor (AIAgentInboundHTTPRequest) async -> AIAgentInboundHTTPResponse

    private let handler: Handler
    private let queue: DispatchQueue
    private let connectionRegistry: AIAgentConnectionRegistry
    private var listeners: [Int: NWListener] = [:]

    init(
        maximumActiveConnections: Int = 100,
        readTimeout: TimeInterval = 30,
        handler: @escaping Handler
    ) {
        let queue = DispatchQueue(label: "com.zisla.ai-agent.message-connections", qos: .utility)
        self.queue = queue
        self.connectionRegistry = AIAgentConnectionRegistry(
            maximumActiveConnections: maximumActiveConnections,
            readTimeout: readTimeout,
            queue: queue
        )
        self.handler = handler
    }

    func update(ports: Set<Int>) -> [Int: String] {
        let validPorts = Set(ports.filter { (1_024...65_535).contains($0) })
        for port in listeners.keys.filter({ !validPorts.contains($0) }) {
            listeners[port]?.cancel()
            listeners[port] = nil
        }
        var failures: [Int: String] = [:]
        for port in validPorts where listeners[port] == nil {
            do {
                let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: UInt16(port))!)
                listener.newConnectionHandler = { [weak self] connection in
                    self?.accept(connection)
                }
                listener.start(queue: queue)
                listeners[port] = listener
            } catch {
                failures[port] = error.localizedDescription
            }
        }
        return failures
    }

    func stop() {
        for listener in listeners.values { listener.cancel() }
        listeners = [:]
    }

    private nonisolated func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        guard let token = connectionRegistry.begin(onTimeout: { [weak connection] in
            guard let connection else { return }
            connection.send(
                content: Self.serialized(.text("request timeout", statusCode: 408)),
                completion: .contentProcessed { _ in connection.cancel() }
            )
        }) else {
            connection.send(
                content: Self.serialized(.text("service unavailable", statusCode: 503)),
                completion: .contentProcessed { _ in connection.cancel() }
            )
            return
        }
        receive(connection, buffered: Data(), token: token)
    }

    private nonisolated func receive(
        _ connection: NWConnection,
        buffered: Data,
        token: AIAgentConnectionRegistry.Token
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, complete, error in
            guard let self else { connection.cancel(); return }
            var dataBuffer = buffered
            if let data { dataBuffer.append(data) }
            if dataBuffer.count >= aiAgentMaximumRequestByteCount {
                guard self.connectionRegistry.completeRead(token) else {
                    connection.cancel()
                    return
                }
                connection.send(
                    content: Self.serialized(.text("payload too large", statusCode: 413)),
                    completion: .contentProcessed { _ in
                        self.connectionRegistry.finish(token)
                        connection.cancel()
                    }
                )
                return
            }
            if let request = Self.parseRequest(dataBuffer) {
                guard self.connectionRegistry.completeRead(token) else {
                    connection.cancel()
                    return
                }
                let registry = self.connectionRegistry
                Task { @MainActor [weak self, registry] in
                    let response = await self?.handler(request) ?? .text("service unavailable", statusCode: 503)
                    connection.send(content: Self.serialized(response), completion: .contentProcessed { _ in
                        registry.finish(token)
                        connection.cancel()
                    })
                }
                return
            }
            guard error == nil, !complete else {
                self.connectionRegistry.finish(token)
                connection.cancel()
                return
            }
            self.receive(connection, buffered: dataBuffer, token: token)
        }
    }

    nonisolated static func parseRequest(_ data: Data) -> AIAgentInboundHTTPRequest? {
        guard data.count < aiAgentMaximumRequestByteCount else { return nil }
        let separator = Data("\r\n\r\n".utf8)
        guard let headerRange = data.range(of: separator),
              let headerText = String(data: data[..<headerRange.lowerBound], encoding: .utf8) else {
            return nil
        }
        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count == 3 else { return nil }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            let pair = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard pair.count == 2 else { continue }
            headers[pair[0].trimmingCharacters(in: .whitespaces).lowercased()] = pair[1].trimmingCharacters(in: .whitespaces)
        }
        let contentLength = Int(headers["content-length"] ?? "0") ?? -1
        guard (0...1_048_576).contains(contentLength) else { return nil }
        let bodyStart = headerRange.upperBound
        guard data.distance(from: bodyStart, to: data.endIndex) >= contentLength else { return nil }
        let target = parts[1]
        let components = URLComponents(string: "http://localhost\(target)")
        let query = (components?.queryItems ?? []).reduce(into: [String: String]()) { values, item in
            if let value = item.value { values[item.name] = value }
        }
        let body = Data(data[bodyStart..<data.index(bodyStart, offsetBy: contentLength)])
        return AIAgentInboundHTTPRequest(
            method: parts[0].uppercased(),
            path: components?.path ?? target,
            query: query,
            headers: headers,
            body: body
        )
    }

    private nonisolated static func serialized(_ response: AIAgentInboundHTTPResponse) -> Data {
        let reason = switch response.statusCode {
        case 200: "OK"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 408: "Request Timeout"
        case 404: "Not Found"
        case 413: "Payload Too Large"
        case 422: "Unprocessable Content"
        default: "Service Unavailable"
        }
        let header = "HTTP/1.1 \(response.statusCode) \(reason)\r\nContent-Type: \(response.contentType)\r\nContent-Length: \(response.body.count)\r\nConnection: close\r\n\r\n"
        var data = Data(header.utf8)
        data.append(response.body)
        return data
    }
}
