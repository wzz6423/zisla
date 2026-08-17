import Testing

@testable import Zisla

struct MemoryDisplayTests {
    @Test
    func memoryUsageTextUsesOneConsistentPercentage() {
        #expect(SystemMonitorMemoryPresentation.usageText(
            usedBytes: 16_000_000_000,
            totalBytes: 24_000_000_000
        ) == "67%")
        #expect(SystemMonitorMemoryPresentation.usageText(
            usedBytes: 0,
            totalBytes: 0
        ) == "--")
        #expect(SystemMonitorMemoryPresentation.usageText(
            usedBytes: 32_000_000_000,
            totalBytes: 16_000_000_000
        ) == "100%")
    }
}
