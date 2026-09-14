import AppKit
import Foundation
import Testing
import UserNotifications

@testable import ZislaKit

@MainActor
struct SystemClockServiceTests {
    @Test(arguments: [
        (SystemClockService.Destination.timer, "clock-timer://"),
        (SystemClockService.Destination.alarm, "clock-alarm://"),
    ])
    func opensRequestedPageInSystemClock(
        destination: SystemClockService.Destination,
        expectedURL: String
    ) async throws {
        var requestedURLs: [URL] = []
        var requestedApplication: URL?

        try await SystemClockService.open(destination) { urls, application, configuration in
            requestedURLs = urls
            requestedApplication = application
            #expect(configuration.activates)
            #expect(!configuration.createsNewApplicationInstance)
        }

        #expect(requestedURLs.map(\.absoluteString) == [expectedURL])
        #expect(requestedApplication?.path == "/System/Applications/Clock.app")
    }

    @Test(arguments:
        [SystemClockService.Destination.timer, .alarm],
        [CocoaError.Code.fileNoSuchFile, .fileReadNoPermission, .featureUnsupported]
    )
    func openingFailureReachesCaller(
        destination: SystemClockService.Destination,
        code: CocoaError.Code
    ) async {
        let failure = CocoaError(code)

        do {
            try await SystemClockService.open(destination) { _, _, _ in
                throw failure
            }
            Issue.record("系统时钟启动失败时应将错误交给调用方显示")
        } catch {
            #expect((error as NSError).domain == NSCocoaErrorDomain)
            #expect((error as NSError).code == failure.errorCode)
        }
    }

    @Test
    func retirementRemovesOneShotAndRepeatingAlarmsWithoutTouchingOtherNotifications() async {
        let oldAlarmID = "00000000-0000-0000-0000-000000000001"
        let retired = [
            "zisla.alarm.\(oldAlarmID)",
            "zisla.alarm.\(oldAlarmID).2",
            "zisla.alarm.\(oldAlarmID).3",
        ]
        let preserved = [
            "zisla.pomodoro.\(oldAlarmID)",
            "zisla.calendar.\(oldAlarmID)",
            "zisla.alarm",
            "zisla.alarms.\(oldAlarmID)",
            "other.zisla.alarm.\(oldAlarmID)",
            "clock.alarm.\(oldAlarmID)",
            "",
        ]
        var pending = (retired + preserved).map { identifier in
            UNNotificationRequest(identifier: identifier, content: UNMutableNotificationContent(), trigger: nil)
        }

        await SystemClockService.cancelLegacyAlarmNotifications(
            pendingRequests: { pending },
            cancel: { identifiers in
                pending.removeAll { identifiers.contains($0.identifier) }
            }
        )

        #expect(pending.map(\.identifier) == preserved)

        await SystemClockService.cancelLegacyAlarmNotifications(
            pendingRequests: { pending },
            cancel: { identifiers in
                pending.removeAll { identifiers.contains($0.identifier) }
            }
        )

        #expect(pending.map(\.identifier) == preserved, "重复启动不得取消其他通知")
    }

    @Test
    func retirementDoesNotFabricateIdentifiersForAnEmptyQueue() async {
        await SystemClockService.cancelLegacyAlarmNotifications(
            pendingRequests: { [] },
            cancel: { identifiers in
                #expect(identifiers.isEmpty)
            }
        )
    }
}
