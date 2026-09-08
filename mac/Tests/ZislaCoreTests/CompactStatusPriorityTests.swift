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
            .focusCountdown,
            .focusMode,
            .aiActivity,
            .media,
            .toolboxReminder,
            .updateAvailable,
        ])
    }
}
