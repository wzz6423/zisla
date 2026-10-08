import Foundation
import Testing
@testable import ZislaCore

struct LocalVoiceModelRecommendationTests {
    private static let gibibyte: UInt64 = 1_024 * 1_024 * 1_024

    @Test(arguments: [
        (8, LocalVoiceModelRecommendation.gemma4_E2B),
        (12, .gemma4_E2B),
        (16, .gemma4_E4B),
        (24, .gemma4_12B),
        (32, .gemma4_12B),
        (48, .gemma4_26BA4B),
        (128, .gemma4_26BA4B),
    ])
    func appleSiliconGetsAModelWithMemoryHeadroom(
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
        (8, LocalVoiceModelRecommendation.gemma4_E2B),
        (12, .gemma4_E2B),
        (16, .gemma4_E2B),
        (64, .gemma4_E2B),
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
            (16 * Self.gibibyte - 1, .appleSilicon, .gemma4_E2B),
            (24 * Self.gibibyte - 1, .appleSilicon, .gemma4_E4B),
            (48 * Self.gibibyte - 1, .appleSilicon, .gemma4_12B),
            (8 * Self.gibibyte - 1, .intel, nil),
            (16 * Self.gibibyte - 1, .intel, .gemma4_E2B),
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
    func extremeMemoryDoesNotOverflowOrPromoteToADenseWorkstationModel() {
        let appleSilicon = LocalVoiceHardware(physicalMemoryBytes: .max, processor: .appleSilicon)
        let intel = LocalVoiceHardware(physicalMemoryBytes: .max, processor: .intel)
        #expect(LocalVoiceModelRecommendation.recommended(for: appleSilicon) == .gemma4_26BA4B)
        #expect(LocalVoiceModelRecommendation.recommended(for: intel) == .gemma4_E2B)
    }

    @Test
    func recommendationsUseVerifiedQuantizedTagsWithoutMixingOlderFamilies() {
        let expected: [(LocalVoiceModelRecommendation, String, String, Double)] = [
            (.gemma4_E2B, "Gemma 4 E2B QAT", "gemma4:e2b-it-qat", 4.3),
            (.gemma4_E4B, "Gemma 4 E4B QAT", "gemma4:e4b-it-qat", 6.1),
            (.gemma4_12B, "Gemma 4 12B QAT", "gemma4:12b-it-qat", 7.2),
            (.gemma4_26BA4B, "Gemma 4 26B A4B QAT", "gemma4:26b-a4b-it-qat", 16.0),
        ]
        #expect(LocalVoiceModelRecommendation.allCases.count == expected.count)
        for (recommendation, name, tag, downloadGigabytes) in expected {
            #expect(recommendation.displayName == name)
            #expect(recommendation.ollamaModelID == tag)
            #expect(recommendation.approximateOllamaDownloadGigabytes == downloadGigabytes)
        }
    }
}
