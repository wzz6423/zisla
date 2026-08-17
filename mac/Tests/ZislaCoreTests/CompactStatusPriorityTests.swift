import Testing

@testable import ZislaCore

struct CompactStatusPriorityTests {
    @Test
    func defaultOrderMatchesSettingsPriority() {
        #expect(CompactStatusPriority.defaultOrder == [
            .transient,
            .videoDownload,
            .browserDownload,
            .toolboxReminder,
            .mail,
            .updateAvailable,
            .focusCountdown,
            .aiActivity,
            .media,
            .focusMode,
        ])
    }
}
