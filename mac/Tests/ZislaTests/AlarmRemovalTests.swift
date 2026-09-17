import Foundation
import Testing

@testable import Zisla

struct AlarmRemovalTests {
    @Test
    func toolboxDoesNotExposeAnAlarmControl() throws {
        let source = try toolboxSource()

        #expect(!source.contains("AlarmEditorView"))
        #expect(!source.contains("symbol: \"alarm\""))
        #expect(!source.contains("管理闹钟"))
    }

    @Test
    func appModelDoesNotCreateOrScheduleAlarms() throws {
        let source = try appModelSource()

        #expect(!source.contains("AlarmService"))
        #expect(!source.contains("alarms."))
        #expect(source.contains("LegacyAlarmNotificationCleanup.removeScheduledNotifications()"))
    }

    private func toolboxSource() throws -> String {
        try String(
            contentsOf: packageURL.appendingPathComponent("Sources/Zisla/ToolboxModuleView.swift"),
            encoding: .utf8
        )
    }

    private func appModelSource() throws -> String {
        try String(
            contentsOf: packageURL.appendingPathComponent("Sources/Zisla/AppModel.swift"),
            encoding: .utf8
        )
    }

    private var packageURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
