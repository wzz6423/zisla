import Foundation

public enum AIModelConfigurationSource: String, Codable, Hashable, Sendable {
    case local
    case channel
}

/// References one model configuration without duplicating its endpoint or credentials in feature settings.
public struct AIModelConfigurationReference: Codable, Equatable, Hashable, Sendable {
    public var source: AIModelConfigurationSource
    public var id: UUID

    public init(source: AIModelConfigurationSource, id: UUID) {
        self.source = source
        self.id = id
    }

    public static func local(_ id: UUID) -> Self {
        Self(source: .local, id: id)
    }

    public static func channel(_ id: UUID) -> Self {
        Self(source: .channel, id: id)
    }
}

/// Zisla model endpoint protocol. Local OpenAI-compatible endpoints cover LM Studio and similar; Ollama uses its native port.
public enum AIEndpointKind: String, Codable, CaseIterable, Sendable {
    case openAICompatible
    case ollama

    public var displayName: String {
        switch self {
        case .openAICompatible: "OpenAI 兼容 / LM Studio"
        case .ollama: "Ollama"
        }
    }

    public var defaultEndpointName: String {
        switch self {
        case .openAICompatible: "LM Studio"
        case .ollama: "Ollama"
        }
    }

    public var defaultBaseURL: String {
        switch self {
        case .openAICompatible: "http://127.0.0.1:1234/v1"
        case .ollama: "http://127.0.0.1:11434/v1"
        }
    }
}

public enum AIChatRole: String, Codable, Sendable {
    case system
    case user
    case assistant
    case tool
}

public struct AIEndpoint: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var baseURL: String
    public var kind: AIEndpointKind
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        baseURL: String,
        kind: AIEndpointKind = .openAICompatible,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.kind = kind
        self.isEnabled = isEnabled
    }
}

/// The model endpoint catalog returned at runtime for configuration pickers; not persisted.
public struct AIDiscoveredModel: Identifiable, Equatable, Sendable {
    public var id: String { name }
    public var name: String

    public init(name: String) {
        self.name = name
    }
}
