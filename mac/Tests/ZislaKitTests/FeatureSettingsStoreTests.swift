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

    @Test @MainActor
    func migratesMissingUpdateChannelToTheBundleDefault() throws {
        let suiteName = "Zisla.FeatureSettingsStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(
            Data(#"{"activityNoticeDisplayDuration":"threeSeconds"}"#.utf8),
            forKey: "feature-settings-v1"
        )

        let store = FeatureSettingsStore(defaults: defaults, defaultUpdateChannel: .preview)
        #expect(store.settings.updateChannel == .preview)

        let data = try #require(defaults.data(forKey: "feature-settings-v1"))
        let persisted = try JSONDecoder().decode(FeatureSettings.self, from: data)
        #expect(persisted.updateChannel == .preview)
    }

    @Test @MainActor
    func preservesAnExplicitlySelectedUpdateChannel() throws {
        let suiteName = "Zisla.FeatureSettingsStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var settings = FeatureSettings.default
        settings.updateChannel = .release
        defaults.set(try JSONEncoder().encode(settings), forKey: "feature-settings-v1")

        let store = FeatureSettingsStore(defaults: defaults, defaultUpdateChannel: .preview)
        #expect(store.settings.updateChannel == .release)
    }

    @Test @MainActor
    func resetRestoresTheBundledManualUpdateChannel() throws {
        let suiteName = "Zisla.FeatureSettingsStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = FeatureSettingsStore(defaults: defaults, defaultUpdateChannel: .preview)
        store.settings.updateChannel = .release
        store.reset()

        #expect(store.settings.updateChannel == .preview)
    }
}
