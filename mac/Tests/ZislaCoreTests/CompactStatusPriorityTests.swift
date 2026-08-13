import Testing

@testable import ZislaCore

struct CompactStatusPriorityTests {
    @Test
    func defaultOrderMatchesSettingsPriority() {
        #expect(CompactStatusPriority.defaultOrder == [
            .transient,
            .videoDownload,
            .browserDownload,
            .focusCountdown,
            .toolboxReminder,
            .mail,
            .updateAvailable,
            .aiActivity,
            .media,
            .focusMode,
        ])
    }
}
