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
    case gemma4_E2B
    case gemma4_E4B
    case gemma4_12B
    case gemma4_26BA4B

    public var displayName: String {
        switch self {
        case .gemma4_E2B: "Gemma 4 E2B QAT"
        case .gemma4_E4B: "Gemma 4 E4B QAT"
        case .gemma4_12B: "Gemma 4 12B QAT"
        case .gemma4_26BA4B: "Gemma 4 26B A4B QAT"
        }
    }

    public var ollamaModelID: String {
        switch self {
        case .gemma4_E2B: "gemma4:e2b-it-qat"
        case .gemma4_E4B: "gemma4:e4b-it-qat"
        case .gemma4_12B: "gemma4:12b-it-qat"
        case .gemma4_26BA4B: "gemma4:26b-a4b-it-qat"
        }
    }

    // These are rounded download sizes, including the projector, not runtime memory estimates.
    // Verified against https://ollama.com/library/gemma4/tags on 2026-10-08.
    public var approximateOllamaDownloadGigabytes: Double {
        switch self {
        case .gemma4_E2B: 4.3
        case .gemma4_E4B: 6.1
        case .gemma4_12B: 7.2
        case .gemma4_26BA4B: 16.0
        }
    }

    public static func recommended(for hardware: LocalVoiceHardware) -> Self? {
        let gibibyte: UInt64 = 1_024 * 1_024 * 1_024
        guard hardware.physicalMemoryBytes >= 8 * gibibyte else { return nil }

        // Leave headroom for macOS, other apps, and a modest context. Full weights include
        // E2B/E4B embeddings and all MoE experts (https://ai.google.dev/gemma/docs/core).
        // This is a text-cleanup starting point, not a guarantee based on currently free memory.
        switch hardware.processor {
        case .appleSilicon:
            if hardware.physicalMemoryBytes >= 48 * gibibyte { return .gemma4_26BA4B }
            if hardware.physicalMemoryBytes >= 24 * gibibyte { return .gemma4_12B }
            if hardware.physicalMemoryBytes >= 16 * gibibyte { return .gemma4_E4B }
            return .gemma4_E2B
        case .intel:
            // CPU inference stays on smaller models even when plenty of RAM is installed.
            return .gemma4_E2B
        case .unknown:
            return nil
        }
    }
}
