import Foundation
import ZislaCore

public enum LocalVoiceHardwareReader {
    public static func read() -> LocalVoiceHardware {
        read(
            physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory,
            sysctlInt: SystemSysctl.intValue(named:)
        )
    }

    static func read(
        physicalMemoryBytes: UInt64,
        sysctlInt: (String) -> Int?
    ) -> LocalVoiceHardware {
        let arm64 = sysctlInt("hw.optional.arm64")
        let processor: LocalVoiceHardware.Processor
        // A translated Intel executable still runs on Apple Silicon hardware.
        if arm64 == 1 || sysctlInt("sysctl.proc_translated") == 1 {
            processor = .appleSilicon
        } else if arm64 == 0 {
            processor = .intel
        } else {
            processor = .unknown
        }
        return LocalVoiceHardware(physicalMemoryBytes: physicalMemoryBytes, processor: processor)
    }
}
