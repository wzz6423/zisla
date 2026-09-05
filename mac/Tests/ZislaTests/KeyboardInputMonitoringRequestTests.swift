import Foundation
import Testing

@testable import KeyboardKit

@Suite(.serialized)
@MainActor
struct KeyboardInputMonitoringRequestTests {
    @Test
    func inputMonitoringIsRequestedOnlyWhenMissingAndNotAlreadySpent() {
        #expect(KeyboardSoundController.shouldRequestInputMonitoring(
            hasAccess: false,
            hasRequestedBefore: false
        ))
        #expect(!KeyboardSoundController.shouldRequestInputMonitoring(
            hasAccess: true,
            hasRequestedBefore: false
        ))
        #expect(!KeyboardSoundController.shouldRequestInputMonitoring(
            hasAccess: false,
            hasRequestedBefore: true
        ))
    }

    @Test
    func aSpentPromptStaysSpentOnTheNextLaunch() throws {
        let suiteName = "Zisla.KeyboardInputMonitoringRequestTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(!InputMonitoringPermissionManager(defaults: defaults).hasRequestedOnce)

        // `request()` itself cannot run here — it raises the real system dialog — so write the key
        // exactly as it does and read it back through a manager standing in for the next launch.
        defaults.set(true, forKey: "inputMonitoringDidRequestAutomatically")
        #expect(InputMonitoringPermissionManager(defaults: defaults).hasRequestedOnce)
    }

    @Test
    func listenerStartupAndTheSettingsButtonBothGoThroughTheGuardedRequest() throws {
        let source = try Self.source(of: "KeyboardSoundController.swift")

        let apply = try #require(Self.region(
            "    public func apply(",
            upTo: "    public func requestInputMonitoring()",
            in: source
        ))
        #expect(apply.contains("requestInputMonitoringIfNeeded()"))

        let opensSettings = try #require(Self.region(
            "    public func openInputMonitoringSettings()",
            upTo: "    static func shouldRequestInputMonitoring(",
            in: source
        ))
        // Asking has to come before the System Settings fallback, or the one-click grant is skipped.
        let asks = try #require(opensSettings.range(of: "requestInputMonitoringIfNeeded()"))
        let fallback = try #require(opensSettings.range(of: "model.openInputMonitoringSettings()"))
        #expect(asks.lowerBound < fallback.lowerBound)
    }

    @Test
    func requestingMarksThePromptSpentAndRaisesItThroughTheAuthorizationHost() throws {
        let source = try Self.source(of: "InputMonitoringPermissionManager.swift")
        let request = try #require(Self.region(
            "    func request()",
            upTo: "    func openSystemSettings()",
            in: source
        ))

        #expect(request.contains("defaults.set(true, forKey: Key.didRequest)"))
        // Zisla is an accessory app: without the activated host the dialog can open behind another
        // app and the single prompt is spent unseen.
        #expect(request.contains("GlobalHotkeyManager.requestInputMonitoringAccess()"))
    }

    private static func source(of fileName: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent("Sources/KeyboardKit/\(fileName)"),
            encoding: .utf8
        )
    }

    private static func region(_ declaration: String, upTo next: String, in source: String) -> String? {
        guard let start = source.range(of: declaration),
              let end = source.range(of: next, range: start.upperBound..<source.endIndex)
        else { return nil }
        return String(source[start.upperBound..<end.lowerBound])
    }
}
