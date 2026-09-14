import AppKit
import Foundation
import UserNotifications

@MainActor
public enum SystemClockService {
    public enum Destination: String, Sendable {
        case timer = "clock-timer://"
        case alarm = "clock-alarm://"
    }

    public static func cancelLegacyAlarmNotifications(
        pendingRequests: @MainActor () async -> [UNNotificationRequest] = {
            await UNUserNotificationCenter.current().pendingNotificationRequests()
        },
        cancel: @MainActor ([String]) -> Void = {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: $0)
        }
    ) async {
        let requests = await pendingRequests()
        cancel(requests.map(\.identifier).filter { $0.hasPrefix("zisla.alarm.") })
    }

    public static func open(
        _ destination: Destination,
        opener: @MainActor ([URL], URL, NSWorkspace.OpenConfiguration) async throws -> Void = {
            urls, application, configuration in
            _ = try await NSWorkspace.shared.open(
                urls,
                withApplicationAt: application,
                configuration: configuration
            )
        }
    ) async throws {
        try await opener(
            [URL(string: destination.rawValue)!],
            URL(fileURLWithPath: "/System/Applications/Clock.app"),
            NSWorkspace.OpenConfiguration()
        )
    }
}
