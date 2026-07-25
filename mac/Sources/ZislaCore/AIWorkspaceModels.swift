import Foundation

public enum VoiceModelEndpointMode: String, Codable, CaseIterable, Sendable {
    case local
    case remote

    public var displayName: String {
        switch self {
        case .local: "本地"
        case .remote: "远端"
        }
    }

    public var detail: String {
        switch self {
        case .local: "连接此 Mac 上运行的模型服务"
        case .remote: "连接 OpenAI 兼容的远端模型服务"
        }
    }
}

public struct VoiceModelRemoteEndpoint: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var baseURL: String
    public var modelName: String
    /// `nil` 表示旧配置或无需认证的端点。
    public var apiKey: String?
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        baseURL: String = "",
        modelName: String = "",
        apiKey: String? = nil,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.modelName = modelName
        self.apiKey = apiKey
        self.isEnabled = isEnabled
    }
}

public struct VoiceModelEndpointRouter: Sendable {
    private var nextIndex = 0

    public init() {}

    public mutating func next(
        from endpoints: [VoiceModelRemoteEndpoint],
        selectedID: UUID?,
        loadBalancingEnabled: Bool
    ) -> VoiceModelRemoteEndpoint? {
        let enabledEndpoints = endpoints.filter(\.isEnabled)
        guard !enabledEndpoints.isEmpty else { return nil }
        guard loadBalancingEnabled else {
            if let selectedID {
                return enabledEndpoints.first { $0.id == selectedID }
            }
            return enabledEndpoints.first
        }

        let index = nextIndex % enabledEndpoints.count
        nextIndex = (index + 1) % enabledEndpoints.count
        return enabledEndpoints[index]
    }

    public mutating func reset() {
        nextIndex = 0
    }
}

/// Zisla 模型端点协议。本地 OpenAI 兼容端点覆盖 LM Studio 等；Ollama 走原生端口。
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

public enum AIHardwareTier: String, Codable, CaseIterable, Sendable {
    case entry
    case balanced
    case performance
    case highPerformance

    public var displayName: String {
        switch self {
        case .entry: "轻量档"
        case .balanced: "均衡档"
        case .performance: "性能档"
        case .highPerformance: "高配档"
        }
    }
}

/// 用总内存作为跨 Mac 机型可稳定获取的本地推理容量信号；具体量化和上下文长度仍由运行时决定。
public struct AIHardwareProfile: Equatable, Sendable {
    public var machineName: String
    public var memoryBytes: UInt64

    public init(machineName: String, memoryBytes: UInt64) {
        self.machineName = machineName
        self.memoryBytes = memoryBytes
    }

    public var memoryGigabytes: Int {
        let gibibyte = Double(1 << 30)
        return Int((Double(memoryBytes) / gibibyte).rounded())
    }

    public var tier: AIHardwareTier {
        let gibibyte = UInt64(1 << 30)
        switch memoryBytes {
        case ...(UInt64(16) * gibibyte): return .entry
        case ...(UInt64(31) * gibibyte): return .balanced
        case ...(UInt64(47) * gibibyte): return .performance
        default: return .highPerformance
        }
    }

    public var displayDescription: String {
        "\(machineName) · \(memoryGigabytes)GB 内存 · \(tier.displayName)"
    }
}

public struct AIModelRecommendation: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var parameterScale: String
    public var recommendedQuantization: String
    public var reason: String
    public var ollamaModelName: String
    public var lmStudioSearchQuery: String

    public init(
        id: String,
        name: String,
        parameterScale: String,
        recommendedQuantization: String,
        reason: String,
        ollamaModelName: String,
        lmStudioSearchQuery: String
    ) {
        self.id = id
        self.name = name
        self.parameterScale = parameterScale
        self.recommendedQuantization = recommendedQuantization
        self.reason = reason
        self.ollamaModelName = ollamaModelName
        self.lmStudioSearchQuery = lmStudioSearchQuery
    }
}

public enum AIModelRecommendations {
    public static func recommended(for profile: AIHardwareProfile) -> [AIModelRecommendation] {
        switch profile.tier {
        case .entry:
            entryModels
        case .balanced:
            balancedModels
        case .performance:
            performanceModels
        case .highPerformance:
            highPerformanceModels
        }
    }

    private static let entryModels = [
        AIModelRecommendation(
            id: "qwen3-4b", name: "Qwen3 4B", parameterScale: "4B", recommendedQuantization: "Q4",
            reason: "低内存下优先保证响应速度与稳定性。", ollamaModelName: "qwen3:4b",
            lmStudioSearchQuery: "Qwen3-4B Q4_K_M GGUF"
        ),
        AIModelRecommendation(
            id: "qwen2.5-coder-3b", name: "Qwen2.5-Coder 3B", parameterScale: "3B", recommendedQuantization: "Q4",
            reason: "适合轻量代码补全与脚本任务。", ollamaModelName: "qwen2.5-coder:3b",
            lmStudioSearchQuery: "Qwen2.5-Coder-3B Q4_K_M GGUF"
        ),
    ]

    private static let balancedModels = [
        AIModelRecommendation(
            id: "qwen3-8b", name: "Qwen3 8B", parameterScale: "8B", recommendedQuantization: "Q4",
            reason: "通用聊天、总结与轻量推理的平衡选择。", ollamaModelName: "qwen3:8b",
            lmStudioSearchQuery: "Qwen3-8B Q4_K_M GGUF"
        ),
        AIModelRecommendation(
            id: "qwen2.5-coder-7b", name: "Qwen2.5-Coder 7B", parameterScale: "7B", recommendedQuantization: "Q4",
            reason: "以较低资源成本处理日常编码任务。", ollamaModelName: "qwen2.5-coder:7b",
            lmStudioSearchQuery: "Qwen2.5-Coder-7B Q4_K_M GGUF"
        ),
    ]

    private static let performanceModels = [
        AIModelRecommendation(
            id: "qwen3-14b", name: "Qwen3 14B", parameterScale: "14B", recommendedQuantization: "Q4",
            reason: "兼顾复杂任务质量与交互延迟。", ollamaModelName: "qwen3:14b",
            lmStudioSearchQuery: "Qwen3-14B Q4_K_M GGUF"
        ),
        AIModelRecommendation(
            id: "qwen2.5-coder-14b", name: "Qwen2.5-Coder 14B", parameterScale: "14B", recommendedQuantization: "Q4",
            reason: "面向代码生成、重构和调试的优先选择。", ollamaModelName: "qwen2.5-coder:14b",
            lmStudioSearchQuery: "Qwen2.5-Coder-14B Q4_K_M GGUF"
        ),
        AIModelRecommendation(
            id: "qwen3-8b-performance", name: "Qwen3 8B", parameterScale: "8B", recommendedQuantization: "Q4",
            reason: "追求更短首字延迟时使用。", ollamaModelName: "qwen3:8b",
            lmStudioSearchQuery: "Qwen3-8B Q4_K_M GGUF"
        ),
    ]

    private static let highPerformanceModels = [
        AIModelRecommendation(
            id: "qwen3-32b", name: "Qwen3 32B", parameterScale: "32B", recommendedQuantization: "Q4",
            reason: "当前机型的通用主力，优先质量与复杂推理。", ollamaModelName: "qwen3:32b",
            lmStudioSearchQuery: "Qwen3-32B Q4_K_M GGUF"
        ),
        AIModelRecommendation(
            id: "qwen2.5-coder-32b", name: "Qwen2.5-Coder 32B", parameterScale: "32B", recommendedQuantization: "Q4",
            reason: "面向多文件编码、重构和较复杂调试。", ollamaModelName: "qwen2.5-coder:32b",
            lmStudioSearchQuery: "Qwen2.5-Coder-32B Q4_K_M GGUF"
        ),
        AIModelRecommendation(
            id: "qwen3-14b-high", name: "Qwen3 14B", parameterScale: "14B", recommendedQuantization: "Q4",
            reason: "需要更低延迟时的高质量备选。", ollamaModelName: "qwen3:14b",
            lmStudioSearchQuery: "Qwen3-14B Q4_K_M GGUF"
        ),
        AIModelRecommendation(
            id: "qwen3-8b-high", name: "Qwen3 8B", parameterScale: "8B", recommendedQuantization: "Q4",
            reason: "短请求与高频交互的低延迟档。", ollamaModelName: "qwen3:8b",
            lmStudioSearchQuery: "Qwen3-8B Q4_K_M GGUF"
        ),
    ]
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

/// 端点运行时返回的模型目录。仅用于挑选本地小模型，不持久化。
public struct AIDiscoveredModel: Identifiable, Equatable, Sendable {
    public var id: String { name }
    public var name: String

    public init(name: String) {
        self.name = name
    }
}
