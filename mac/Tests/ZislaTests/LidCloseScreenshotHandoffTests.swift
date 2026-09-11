import Foundation
import Testing

@testable import Zisla
@testable import ZislaKit

/// A screenshot taken while the lid close effect shows must capture the
/// contents behind the overlay instead of the folded picture, so the app asks
/// the controller to step the overlay aside before the frame is captured.
struct LidCloseScreenshotHandoffTests {
    @Test @MainActor
    func dismissalWithoutOverlayIsSafeAndReportsInvisibility() throws {
        let suiteName = "Zisla.LidCloseScreenshotHandoffTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = FeatureSettingsStore(
            defaults: defaults,
            persistenceDelay: .milliseconds(250)
        )
        let controller = LidCloseController(settingsStore: store)

        #expect(!controller.isOverlayVisible)
        controller.dismissOverlayForScreenshot()
        #expect(!controller.isOverlayVisible)
    }
}
