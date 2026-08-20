import Testing

@testable import ZislaCore

struct CompactStatusPriorityTests {
    @Test
    func defaultOrderMatchesSettingsPriority() {
        #expect(CompactStatusPriority.defaultOrder == [
            .transient,
            .videoDownload,
            .browserDownload,
            .mail,
            .updateAvailable,
            .focusCountdown,
            .focusMode,
            .aiActivity,
            .media,
            .toolboxReminder,
        ])
    }
}
