import Testing

@testable import ZislaKit

struct LegacyAlarmNotificationCleanupTests {
    @Test
    func selectsOnlyLegacyAlarmNotifications() {
        let identifiers = [
            "zisla.alarm.first",
            "zisla.pomodoro.first",
            "zisla.alarmx",
            "third-party.alarm",
            "zisla.alarm.second",
        ]

        #expect(
            LegacyAlarmNotificationCleanup.identifiersToRemove(from: identifiers)
                == ["zisla.alarm.first", "zisla.alarm.second"]
        )
    }

    @Test
    func ignoresEmptyAndUnrelatedNotificationSets() {
        #expect(LegacyAlarmNotificationCleanup.identifiersToRemove(from: []) == [])
        #expect(
            LegacyAlarmNotificationCleanup.identifiersToRemove(
                from: ["zisla.pomodoro.completed", "zisla.alarm"]
            ) == []
        )
    }
}
