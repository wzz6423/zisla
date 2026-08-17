import Foundation
import ZislaCore

public enum AIChatClientError: LocalizedError, Equatable {
    case invalidEndpoint(String)
    case invalidResponse
    case http(statusCode: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint: "端点地址无效"
        case .invalidResponse: "模型返回了无法识别的响应"
        case let .http(statusCode): "模型请求失败（HTTP \(statusCode)）"
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

enum AIEndpointSecurity {
    static func permits(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased(),
              !host.isEmpty else {
            return false
        }
        if scheme == "https" { return true }
        guard scheme == "http" else { return false }
        return host == "localhost" || host == "::1" || isIPv4Loopback(host)
    }

    private static func isIPv4Loopback(_ host: String) -> Bool {
        let components = host.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 4,
              components.first == "127",
              components.allSatisfy({ component in
                  guard !component.isEmpty, component.allSatisfy(\.isNumber), let value = Int(component) else {
                      return false
                  }
                  return (0...255).contains(value)
              }) else {
            return false
        }
        return true
    }
}

/// OpenAI Chat Completions-compatible client. Ollama's /v1 endpoint speaks the same protocol, used for local small models to process voice input.
public struct AIChatClient: Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func complete(
        endpoint: AIEndpoint,
        protocolKind: AgentChannelProtocol = .openAICompatible,
        model: String,
        systemPrompt: String,
        messages: [AIOutboundMessage],
        apiKey: String? = nil,
        effort: AgentModelEffort? = nil
    ) async throws -> AIChatResponse {
        let url = try completionURL(for: endpoint, protocolKind: protocolKind, model: model)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        // Callers are short utility completions the user is actively waiting on, so an unreachable
        // endpoint must fail long before URLSession's one-minute default.
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let apiKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !apiKey.isEmpty {
            switch protocolKind {
            case .openAICompatible:
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            case .anthropicMessages:
                request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            case .geminiGenerateContent:
                request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
            }
        }
        let body = requestBody(
            protocolKind: protocolKind,
            model: model,
            systemPrompt: systemPrompt,
            messages: messages,
            effort: effort
        )
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIChatClientError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw AIChatClientError.http(statusCode: http.statusCode)
        }
        let content = try responseContent(data, protocolKind: protocolKind)
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AIChatClientError.invalidResponse }
        return AIChatResponse(content: trimmed)
    }

    private func completionURL(
        for endpoint: AIEndpoint,
        protocolKind: AgentChannelProtocol,
        model: String
    ) throws -> URL {
        let source = endpoint.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var url = URL(string: source), AIEndpointSecurity.permits(url) else {
            throw AIChatClientError.invalidEndpoint(source)
        }
        switch protocolKind {
        case .openAICompatible:
            let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if !path.split(separator: "/").contains("v1") {
                url.appendPathComponent("v1", isDirectory: true)
            }
            url.appendPathComponent("chat")
            url.appendPathComponent("completions")
        case .anthropicMessages:
            let parts = url.path.split(separator: "/").map(String.init)
            if !parts.contains("v1") { url.appendPathComponent("v1", isDirectory: true) }
            if url.lastPathComponent != "messages" { url.appendPathComponent("messages") }
        case .geminiGenerateContent:
            let parts = url.path.split(separator: "/").map(String.init)
            if !parts.contains("v1beta") { url.appendPathComponent("v1beta", isDirectory: true) }
            if url.lastPathComponent != "models" { url.appendPathComponent("models", isDirectory: true) }
            let modelName = model.replacingOccurrences(of: "models/", with: "")
            url.appendPathComponent("\(modelName):generateContent")
        }
        return url
    }

    private func requestBody(
        protocolKind: AgentChannelProtocol,
        model: String,
        systemPrompt: String,
        messages: [AIOutboundMessage],
        effort: AgentModelEffort?
    ) -> [String: Any] {
        switch protocolKind {
        case .openAICompatible:
            var body: [String: Any] = [
                "model": model,
                "stream": false,
                "messages": makeMessages(systemPrompt: systemPrompt, messages: messages),
            ]
            if let effort { body["reasoning_effort"] = effort.rawValue }
            return body
        case .anthropicMessages:
            var body: [String: Any] = [
                "model": model,
                "max_tokens": 4_096,
                "messages": messages.compactMap { message -> [String: Any]? in
                    guard !message.content.isEmpty else { return nil }
                    let role = message.role == .assistant ? "assistant" : "user"
                    return ["role": role, "content": message.content]
                },
            ]
            if !systemPrompt.isEmpty { body["system"] = systemPrompt }
            if let effort { body["output_config"] = ["effort": effort.rawValue] }
            return body
        case .geminiGenerateContent:
            var body: [String: Any] = [
                "contents": messages.compactMap { message -> [String: Any]? in
                    guard !message.content.isEmpty else { return nil }
                    let role = message.role == .assistant ? "model" : "user"
                    return ["role": role, "parts": [["text": message.content]]]
                },
            ]
            if !systemPrompt.isEmpty {
                body["systemInstruction"] = ["parts": [["text": systemPrompt]]]
            }
            return body
        }
    }

    private func responseContent(_ data: Data, protocolKind: AgentChannelProtocol) throws -> String {
        do {
            switch protocolKind {
            case .openAICompatible:
                guard let content = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
                    .choices.first?.message.content else {
                    throw AIChatClientError.invalidResponse
                }
                return content
            case .anthropicMessages:
                return try JSONDecoder().decode(AnthropicMessagesResponse.self, from: data)
                    .content.compactMap(\.text).joined(separator: "\n")
            case .geminiGenerateContent:
                let candidates = try JSONDecoder().decode(GeminiGenerateContentResponse.self, from: data).candidates
                return candidates.first?.content.parts.compactMap(\.text).joined(separator: "\n") ?? ""
            }
        } catch let error as AIChatClientError {
            throw error
        } catch {
            throw AIChatClientError.invalidResponse
        }
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

private struct AnthropicMessagesResponse: Decodable {
    struct Block: Decodable { var text: String? }
    var content: [Block]
}

private struct GeminiGenerateContentResponse: Decodable {
    struct Candidate: Decodable { var content: Content }
    struct Content: Decodable { var parts: [Part] }
    struct Part: Decodable { var text: String? }
    var candidates: [Candidate]
}
