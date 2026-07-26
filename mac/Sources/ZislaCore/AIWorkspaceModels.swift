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

    fileprivate var capacityRank: Int {
        switch self {
        case .entry: 0
        case .balanced: 1
        case .performance: 2
        case .highPerformance: 3
        }
    }
}

/// Describes the hardware signals that determine local-model capacity and expected throughput.
public struct AIHardwareProfile: Equatable, Sendable {
    public var machineName: String
    public var memoryBytes: UInt64
    public var cpuName: String?
    public var cpuCoreCount: Int?
    public var cpuPerformanceCoreCount: Int?
    public var cpuEfficiencyCoreCount: Int?
    public var gpuName: String?
    public var gpuCoreCount: Int?

    public init(
        machineName: String,
        memoryBytes: UInt64,
        cpuName: String? = nil,
        cpuCoreCount: Int? = nil,
        cpuPerformanceCoreCount: Int? = nil,
        cpuEfficiencyCoreCount: Int? = nil,
        gpuName: String? = nil,
        gpuCoreCount: Int? = nil
    ) {
        self.machineName = machineName
        self.memoryBytes = memoryBytes
        self.cpuName = cpuName
        self.cpuCoreCount = cpuCoreCount
        self.cpuPerformanceCoreCount = cpuPerformanceCoreCount
        self.cpuEfficiencyCoreCount = cpuEfficiencyCoreCount
        self.gpuName = gpuName
        self.gpuCoreCount = gpuCoreCount
    }

    public var memoryGigabytes: Int {
        let gibibyte = Double(1 << 30)
        return Int((Double(memoryBytes) / gibibyte).rounded())
    }

    public var tier: AIHardwareTier {
        guard let computeTier else { return memoryTier }
        return memoryTier.capacityRank <= computeTier.capacityRank ? memoryTier : computeTier
    }

    public var cpuDescription: String {
        var parts = [cpuName ?? "未能读取型号"]
        if let cpuCoreCount {
            let topology = [
                cpuPerformanceCoreCount.map { "\($0) 性能" },
                cpuEfficiencyCoreCount.map { "\($0) 能效" },
            ]
            .compactMap { $0 }
            .joined(separator: " + ")
            parts.append(topology.isEmpty ? "\(cpuCoreCount) 核" : "\(cpuCoreCount) 核（\(topology)）")
        }
        return parts.joined(separator: " · ")
    }

    public var gpuDescription: String {
        var parts = [gpuName ?? "未能读取型号"]
        if let gpuCoreCount {
            parts.append("\(gpuCoreCount) 核")
        }
        return parts.joined(separator: " · ")
    }

    public var memoryDescription: String {
        "\(memoryGigabytes)GB 统一内存"
    }

    public var recommendationDescription: String {
        let recommendations = AIModelRecommendations.recommended(for: self)
        let preferredModel = recommendations.first?.name ?? "无推荐"
        return "\(preferredModel) · \(tier.displayName) · 基于 CPU、GPU 与统一内存综合判定"
    }

    public var compactHardwareDescription: String {
        var parts = [machineName]
        if let cpuName, !cpuName.isEmpty {
            parts.append(cpuName)
        }
        if let cpuCoreCount {
            let topology = [
                cpuPerformanceCoreCount.map { "\($0) 性能" },
                cpuEfficiencyCoreCount.map { "\($0) 能效" },
            ]
            .compactMap { $0 }
            .joined(separator: " + ")
            let coreDescription = topology.isEmpty ? "\(cpuCoreCount) 核" : "\(cpuCoreCount) 核（\(topology)）"
            parts.append("CPU \(coreDescription)")
        }
        if let gpuName, !gpuName.isEmpty, gpuName != cpuName {
            parts.append(gpuName)
        }
        if let gpuCoreCount {
            parts.append("GPU \(gpuCoreCount) 核")
        }
        parts.append(memoryDescription)
        return parts.joined(separator: " · ")
    }

    private var memoryTier: AIHardwareTier {
        let gibibyte = UInt64(1 << 30)
        switch memoryBytes {
        case ...(UInt64(16) * gibibyte): return .entry
        case ...(UInt64(31) * gibibyte): return .balanced
        case ...(UInt64(47) * gibibyte): return .performance
        default: return .highPerformance
        }
    }

    private var computeTier: AIHardwareTier? {
        let cpuScore = Self.computeScore(forCPUCoreCount: cpuCoreCount)
        let gpuScore = Self.computeScore(forGPUCoreCount: gpuCoreCount)
        let score = cpuScore + gpuScore
        guard score > 0 else { return nil }

        switch score {
        case 4...: return .highPerformance
        case 3: return .performance
        case 2: return .balanced
        default: return .entry
        }
    }

    private static func computeScore(forCPUCoreCount coreCount: Int?) -> Int {
        guard let coreCount else { return 0 }
        switch coreCount {
        case 8...: return 2
        case 4...: return 1
        default: return 0
        }
    }

    private static func computeScore(forGPUCoreCount coreCount: Int?) -> Int {
        guard let coreCount else { return 0 }
        switch coreCount {
        case 16...: return 2
        case 4...: return 1
        default: return 0
        }
    }

    public var displayDescription: String {
        "\(memoryDescription) · \(tier.displayName)"
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
    public var ollamaPullCommand: String
    public var ollamaRunCommand: String

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
        self.ollamaPullCommand = "ollama pull \(ollamaModelName)"
        self.ollamaRunCommand = "ollama run \(ollamaModelName)"
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
            id: "qwen3-4b", name: "Qwen 3", parameterScale: "4B", recommendedQuantization: "Q4_K_M",
            reason: "轻量聊天模型，中文理解优秀，适合整理语音转写文本。", ollamaModelName: "qwen3:4b",
            lmStudioSearchQuery: "Qwen3 4B Instruct GGUF"
        ),
        AIModelRecommendation(
            id: "gemma3-4b", name: "Gemma 3", parameterScale: "4B", recommendedQuantization: "Q4_K_M",
            reason: "Google 轻量模型，适合快速文本整理与润色。", ollamaModelName: "gemma3:4b",
            lmStudioSearchQuery: "Gemma 3 4B IT GGUF"
        ),
    ]

    private static let balancedModels = [
        AIModelRecommendation(
            id: "qwen3-8b", name: "Qwen 3", parameterScale: "8B", recommendedQuantization: "Q4_K_M",
            reason: "中等规模聊天模型，中文处理能力强，适合整理转写内容。", ollamaModelName: "qwen3:8b",
            lmStudioSearchQuery: "Qwen3 8B Instruct GGUF"
        ),
        AIModelRecommendation(
            id: "gemma3-12b", name: "Gemma 3", parameterScale: "12B", recommendedQuantization: "Q4_K_M",
            reason: "Google 中型模型，均衡的文本理解与生成能力。", ollamaModelName: "gemma3:12b",
            lmStudioSearchQuery: "Gemma 3 12B IT GGUF"
        ),
    ]

    private static let performanceModels = [
        AIModelRecommendation(
            id: "qwen3-14b", name: "Qwen 3", parameterScale: "14B", recommendedQuantization: "Q4_K_M",
            reason: "高性能中文聊天模型，适合复杂的转写文本整理任务。", ollamaModelName: "qwen3:14b",
            lmStudioSearchQuery: "Qwen3 14B Instruct GGUF"
        ),
        AIModelRecommendation(
            id: "gemma3-27b", name: "Gemma 3", parameterScale: "27B", recommendedQuantization: "Q4_K_M",
            reason: "Google 大型模型，提供高质量的文本理解与生成。", ollamaModelName: "gemma3:27b",
            lmStudioSearchQuery: "Gemma 3 27B IT GGUF"
        ),
    ]

    private static let highPerformanceModels = [
        AIModelRecommendation(
            id: "qwen3-32b", name: "Qwen 3", parameterScale: "32B", recommendedQuantization: "Q4_K_M",
            reason: "旗舰级中文聊天模型，顶级的转写文本整理与润色能力。", ollamaModelName: "qwen3:32b",
            lmStudioSearchQuery: "Qwen3 32B Instruct GGUF"
        ),
        AIModelRecommendation(
            id: "mistral-small-24b", name: "Mistral Small", parameterScale: "24B", recommendedQuantization: "Q4_K_M",
            reason: "Mistral 高性能模型，多语言文本处理能力出色。", ollamaModelName: "mistral-small3.1:24b",
            lmStudioSearchQuery: "Mistral Small 3.1 24B Instruct GGUF"
        ),
        AIModelRecommendation(
            id: "gemma3-27b-high", name: "Gemma 3", parameterScale: "27B", recommendedQuantization: "Q4_K_M",
            reason: "高质量文本理解与生成的通用备选。", ollamaModelName: "gemma3:27b",
            lmStudioSearchQuery: "Gemma 3 27B IT GGUF"
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

/// The model endpoint catalog returned by the endpoint at runtime. Used only for selecting small local models; not persisted.
public struct AIDiscoveredModel: Identifiable, Equatable, Sendable {
    public var id: String { name }
    public var name: String

    public init(name: String) {
        self.name = name
    }
}
