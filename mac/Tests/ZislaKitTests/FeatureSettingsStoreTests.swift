import Foundation
import Testing

@testable import ZislaCore
@testable import ZislaKit

struct FeatureSettingsStoreTests {
    @Test @MainActor
    func persistsOnlyTheLatestCoalescedSettingsSnapshot() throws {
        let suiteName = "Zisla.FeatureSettingsStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = FeatureSettingsStore(
            defaults: defaults,
            persistenceDelay: .milliseconds(250)
        )
        var first = store.settings
        first.weatherEnabled = false
        store.settings = first

        var latest = first
        latest.clipboardHistoryEnabled = true
        store.settings = latest

        store.flushPendingChanges()

        let data = try #require(defaults.data(forKey: "feature-settings-v1"))
        let persisted = try JSONDecoder().decode(FeatureSettings.self, from: data)
        #expect(persisted == latest)
    }
}
