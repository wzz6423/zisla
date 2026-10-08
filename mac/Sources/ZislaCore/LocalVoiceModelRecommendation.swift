import Foundation

public struct LocalVoiceHardware: Equatable, Sendable {
    public enum Processor: Equatable, Sendable {
        case appleSilicon
        case intel
        case unknown
    }

    public let physicalMemoryBytes: UInt64
    public let processor: Processor

    public init(physicalMemoryBytes: UInt64, processor: Processor) {
        self.physicalMemoryBytes = physicalMemoryBytes
        self.processor = processor
    }
}

public enum LocalVoiceModelRecommendation: CaseIterable, Equatable, Sendable {
    case qwen35_08B
    case qwen35_2B
    case qwen35_4B
    case qwen35_9B

    public var displayName: String {
        switch self {
        case .qwen35_08B: "Qwen3.5-0.8B Q8_0"
        case .qwen35_2B: "Qwen3.5-2B Q4_K_M"
        case .qwen35_4B: "Qwen3.5-4B Q4_K_M"
        case .qwen35_9B: "Qwen3.5-9B Q4_K_M"
        }
    }

    public var ollamaModelID: String {
        switch self {
        case .qwen35_08B: "qwen3.5:0.8b-q8_0"
        case .qwen35_2B: "qwen3.5:2b-q4_K_M"
        case .qwen35_4B: "qwen3.5:4b-q4_K_M"
        case .qwen35_9B: "qwen3.5:9b-q4_K_M"
        }
    }

    // These are rounded download sizes, including the projector, not runtime memory estimates.
    // Verified against https://ollama.com/library/qwen3.5/tags on 2026-10-08.
    public var approximateOllamaDownloadGigabytes: Double {
        switch self {
        case .qwen35_08B: 1.0
        case .qwen35_2B: 1.9
        case .qwen35_4B: 3.3
        case .qwen35_9B: 6.6
        }
    }

    public static func recommended(for hardware: LocalVoiceHardware) -> Self? {
        let gibibyte: UInt64 = 1_024 * 1_024 * 1_024
        guard hardware.physicalMemoryBytes >= 8 * gibibyte else { return nil }

        // Leave headroom for macOS, other apps, and a modest context. This is a conservative
        // starting point for text cleanup, not a guarantee based on currently free memory.
        switch hardware.processor {
        case .appleSilicon:
            if hardware.physicalMemoryBytes >= 24 * gibibyte { return .qwen35_9B }
            if hardware.physicalMemoryBytes >= 12 * gibibyte { return .qwen35_4B }
            return .qwen35_2B
        case .intel:
            // CPU inference stays on smaller models even when plenty of RAM is installed.
            return hardware.physicalMemoryBytes >= 16 * gibibyte ? .qwen35_2B : .qwen35_08B
        case .unknown:
            return nil
        }
    }
}
