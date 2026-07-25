import Foundation
import ZislaCore

public enum AIChatClientError: LocalizedError {
    case invalidEndpoint(String)
    case invalidResponse
    case http(statusCode: Int, body: String)

    public var errorDescription: String? {
        switch self {
        case let .invalidEndpoint(value): "端点地址无效：\(value)"
        case .invalidResponse: "模型返回了无法识别的响应"
        case let .http(statusCode, body): "模型请求失败（HTTP \(statusCode)）：\(body.prefix(180))"
        }
    }
}

public struct AIOutboundMessage: Sendable {
    public var role: AIChatRole
    public var content: String

    public init(role: AIChatRole, content: String) {
        self.role = role
        self.content = content
    }
}

public struct AIChatResponse: Sendable {
    public var content: String

    public init(content: String) {
        self.content = content
    }
}

/// OpenAI Chat Completions 兼容客户端。Ollama 的 /v1 接口走同一协议，用于本地小模型整理语音输入内容。
public struct AIChatClient: Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func complete(
        endpoint: AIEndpoint,
        model: String,
        systemPrompt: String,
        messages: [AIOutboundMessage]
    ) async throws -> AIChatResponse {
        let url = try completionURL(for: endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": model,
            "stream": false,
            "messages": makeMessages(systemPrompt: systemPrompt, messages: messages),
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIChatClientError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw AIChatClientError.http(
                statusCode: http.statusCode,
                body: String(decoding: data, as: UTF8.self)
            )
        }
        let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let message = decoded.choices.first?.message else { throw AIChatClientError.invalidResponse }
        return AIChatResponse(
            content: message.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        )
    }

    private func completionURL(for endpoint: AIEndpoint) throws -> URL {
        let source = endpoint.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var url = URL(string: source), let scheme = url.scheme,
              scheme == "http" || scheme == "https" else {
            throw AIChatClientError.invalidEndpoint(source)
        }
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !path.split(separator: "/").contains("v1") {
            url.appendPathComponent("v1", isDirectory: true)
        }
        url.appendPathComponent("chat")
        url.appendPathComponent("completions")
        return url
    }

    private func makeMessages(systemPrompt: String, messages: [AIOutboundMessage]) -> [[String: Any]] {
        var result: [[String: Any]] = []
        if !systemPrompt.isEmpty {
            result.append(["role": AIChatRole.system.rawValue, "content": systemPrompt])
        }
        for message in messages {
            if message.content.isEmpty { continue }
            result.append(["role": message.role.rawValue, "content": message.content])
        }
        return result
    }
}

private struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        var message: Message
    }

    struct Message: Decodable {
        var content: String?
    }

    var choices: [Choice]
}
