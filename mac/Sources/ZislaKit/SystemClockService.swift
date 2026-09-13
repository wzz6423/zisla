import AppKit
import Foundation

@MainActor
public enum SystemClockService {
    public enum Destination: String, Sendable {
        case timer = "clock-timer://"
        case alarm = "clock-alarm://"
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
