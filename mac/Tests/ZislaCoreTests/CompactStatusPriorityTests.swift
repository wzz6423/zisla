import Testing

@testable import ZislaCore

struct CompactStatusPriorityTests {
    @Test
    func updateAvailabilityIsPrioritizedImmediatelyAfterTransientStatus() {
        #expect(Array(CompactStatusPriority.defaultOrder.prefix(2)) == [.transient, .updateAvailable])
        #expect(CompactStatusPriority.normalized([.media]).contains(.updateAvailable))
    }
}
