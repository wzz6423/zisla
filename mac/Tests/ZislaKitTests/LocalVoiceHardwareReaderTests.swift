import Testing
import ZislaCore
@testable import ZislaKit

struct LocalVoiceHardwareReaderTests {
    @Test
    func nativeAppleSiliconUsesPhysicalMemoryAndArchitecture() {
        let hardware = LocalVoiceHardwareReader.read(physicalMemoryBytes: 51_539_607_552) { name in
            name == "hw.optional.arm64" ? 1 : nil
        }
        #expect(hardware.processor == .appleSilicon)
        #expect(hardware.physicalMemoryBytes == 51_539_607_552)
        #expect(LocalVoiceModelRecommendation.recommended(for: hardware) == .qwen35_9B)
    }

    @Test(arguments: [Int?.none, 0])
    func rosettaIsRecognizedAsAppleSilicon(arm64: Int?) {
        let hardware = LocalVoiceHardwareReader.read(physicalMemoryBytes: 25_769_803_776) { name in
            switch name {
            case "hw.optional.arm64": arm64
            case "sysctl.proc_translated": 1
            default: nil
            }
        }
        #expect(hardware.processor == .appleSilicon)
        #expect(LocalVoiceModelRecommendation.recommended(for: hardware) == .qwen35_9B)
    }

    @Test(arguments: [Int?.none, 0])
    func intelDoesNotRequireTheRosettaSysctl(translated: Int?) {
        let hardware = LocalVoiceHardwareReader.read(physicalMemoryBytes: 17_179_869_184) { name in
            switch name {
            case "hw.optional.arm64": 0
            case "sysctl.proc_translated": translated
            default: nil
            }
        }
        #expect(hardware.processor == .intel)
        #expect(LocalVoiceModelRecommendation.recommended(for: hardware) == .qwen35_2B)
    }

    @Test(arguments: [Int?.none, -1, 2])
    func unavailableOrUnexpectedArchitectureDoesNotAssumeIntel(value: Int?) {
        let hardware = LocalVoiceHardwareReader.read(physicalMemoryBytes: 51_539_607_552) { _ in value }
        #expect(hardware.processor == .unknown)
        #expect(LocalVoiceModelRecommendation.recommended(for: hardware) == nil)
    }

    @Test
    func missingPhysicalMemoryCannotProduceARecommendation() {
        let hardware = LocalVoiceHardwareReader.read(physicalMemoryBytes: 0) { name in
            name == "hw.optional.arm64" ? 1 : nil
        }
        #expect(hardware.physicalMemoryBytes == 0)
        #expect(LocalVoiceModelRecommendation.recommended(for: hardware) == nil)
    }
}
