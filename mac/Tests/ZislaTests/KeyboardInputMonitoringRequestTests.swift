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

}
