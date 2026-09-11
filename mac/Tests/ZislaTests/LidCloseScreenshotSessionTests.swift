import Foundation
import Testing

@testable import Zisla
@testable import ZislaKit

/// While the lid close effect shows, the screenshot session captures the fold
/// in its frame and then has the overlay step off the screen so the selection
/// panels can present at once; the overlay returns when the session ends. The
/// controller owns that handoff, so both directions must be safe to call.
struct LidCloseScreenshotSessionTests {
    @Test @MainActor
    func hidingAndRestoringWithoutOverlayIsSafe() throws {
        let suiteName = "Zisla.LidCloseScreenshotSessionTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = FeatureSettingsStore(
            defaults: defaults,
            persistenceDelay: .milliseconds(250)
        )
        let controller = LidCloseController(settingsStore: store)

        controller.setOverlayHiddenForScreenshotSession(true)
        #expect(!controller.isOverlayVisible)
        controller.setOverlayHiddenForScreenshotSession(false)
        #expect(!controller.isOverlayVisible)
    }
}
