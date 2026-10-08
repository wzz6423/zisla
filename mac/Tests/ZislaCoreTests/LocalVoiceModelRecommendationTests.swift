import Foundation
import Testing
@testable import ZislaCore

struct LocalVoiceModelRecommendationTests {
    private static let gibibyte: UInt64 = 1_024 * 1_024 * 1_024

    @Test(arguments: [
        (8, LocalVoiceModelRecommendation.qwen35_2B),
        (12, .qwen35_4B),
        (16, .qwen35_4B),
        (24, .qwen35_9B),
        (48, .qwen35_9B),
        (128, .qwen35_9B),
    ])
    func appleSiliconGetsASmallModelWithMemoryHeadroom(
        gibibytes: Int,
        expected: LocalVoiceModelRecommendation
    ) {
        let hardware = LocalVoiceHardware(
            physicalMemoryBytes: UInt64(gibibytes) * Self.gibibyte,
            processor: .appleSilicon
        )
        #expect(LocalVoiceModelRecommendation.recommended(for: hardware) == expected)
    }

    @Test(arguments: [
        (8, LocalVoiceModelRecommendation.qwen35_08B),
        (12, .qwen35_08B),
        (16, .qwen35_2B),
        (64, .qwen35_2B),
    ])
    func intelStaysOnModelsSuitedToCPUInference(
        gibibytes: Int,
        expected: LocalVoiceModelRecommendation
    ) {
        let hardware = LocalVoiceHardware(
            physicalMemoryBytes: UInt64(gibibytes) * Self.gibibyte,
            processor: .intel
        )
        #expect(LocalVoiceModelRecommendation.recommended(for: hardware) == expected)
    }

    @Test
    func memoryThresholdsDoNotRoundUp() {
        let cases: [(UInt64, LocalVoiceHardware.Processor, LocalVoiceModelRecommendation?)] = [
            (8 * Self.gibibyte - 1, .appleSilicon, nil),
            (12 * Self.gibibyte - 1, .appleSilicon, .qwen35_2B),
            (24 * Self.gibibyte - 1, .appleSilicon, .qwen35_4B),
            (8 * Self.gibibyte - 1, .intel, nil),
            (16 * Self.gibibyte - 1, .intel, .qwen35_08B),
        ]
        for (bytes, processor, expected) in cases {
            let hardware = LocalVoiceHardware(physicalMemoryBytes: bytes, processor: processor)
            #expect(LocalVoiceModelRecommendation.recommended(for: hardware) == expected)
        }
    }

    @Test
    func unavailableOrInsufficientHardwareDoesNotPretendToHaveABestModel() {
        for processor in [LocalVoiceHardware.Processor.appleSilicon, .intel, .unknown] {
            for bytes in [UInt64(0), 1, 4 * Self.gibibyte] {
                let hardware = LocalVoiceHardware(physicalMemoryBytes: bytes, processor: processor)
                #expect(LocalVoiceModelRecommendation.recommended(for: hardware) == nil)
            }
        }
        let unknown = LocalVoiceHardware(physicalMemoryBytes: 48 * Self.gibibyte, processor: .unknown)
        #expect(LocalVoiceModelRecommendation.recommended(for: unknown) == nil)
    }

    @Test
    func extremeMemoryDoesNotOverflowOrPromoteToALargeModel() {
        let appleSilicon = LocalVoiceHardware(physicalMemoryBytes: .max, processor: .appleSilicon)
        let intel = LocalVoiceHardware(physicalMemoryBytes: .max, processor: .intel)
        #expect(LocalVoiceModelRecommendation.recommended(for: appleSilicon) == .qwen35_9B)
        #expect(LocalVoiceModelRecommendation.recommended(for: intel) == .qwen35_2B)
    }

    @Test
    func recommendationsUseVerifiedQuantizedTagsWithoutMixingOlderFamilies() {
        let expected: [(LocalVoiceModelRecommendation, String, String, Double)] = [
            (.qwen35_08B, "Qwen3.5-0.8B Q8_0", "qwen3.5:0.8b-q8_0", 1.0),
            (.qwen35_2B, "Qwen3.5-2B Q4_K_M", "qwen3.5:2b-q4_K_M", 1.9),
            (.qwen35_4B, "Qwen3.5-4B Q4_K_M", "qwen3.5:4b-q4_K_M", 3.3),
            (.qwen35_9B, "Qwen3.5-9B Q4_K_M", "qwen3.5:9b-q4_K_M", 6.6),
        ]
        #expect(LocalVoiceModelRecommendation.allCases.count == expected.count)
        for (recommendation, name, tag, downloadGigabytes) in expected {
            #expect(recommendation.displayName == name)
            #expect(recommendation.ollamaModelID == tag)
            #expect(recommendation.approximateOllamaDownloadGigabytes == downloadGigabytes)
        }
    }
}
