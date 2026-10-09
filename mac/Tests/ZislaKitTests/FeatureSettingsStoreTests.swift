import Foundation
import Testing

@testable import ZislaCore
@testable import ZislaKit

struct FeatureSettingsStoreTests {
    @Test @MainActor
    func screenshotEditorHotkeysPersistAndMigrationMarkerIsWrittenOnLoad() throws {
        let suiteName = "Zisla.ScreenshotHotkeys.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(Data("{}".utf8), forKey: "feature-settings-v1")
        let store = FeatureSettingsStore(defaults: defaults)
        let data = try #require(defaults.data(forKey: "feature-settings-v1"))
        let migrated = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(migrated["screenshotHotkeyVersion"] as? Int == 1)
        store.settings.screenshotStashHotkey = .init(keyCode: 15, carbonModifiers: 0x0800, keyDisplayName: "R")
        store.settings.screenshotEditorLongHotkey = .init(keyCode: 17, carbonModifiers: 0x0800, keyDisplayName: "T")
        store.flushPendingChanges()
        let restored = FeatureSettingsStore(defaults: defaults)
        #expect(restored.settings == store.settings)
    }

    @Test @MainActor
    func fileShelfShakeOptOutSurvivesParentChangesAndStoreRecreation() throws {
        let suiteName = "Zisla.FeatureSettingsStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = FeatureSettingsStore(defaults: defaults)
        store.settings.fileShelfShakeEnabled = false
        #expect(store.settings.fileShelfEnabled)
        store.settings.fileShelfEnabled = false
        store.flushPendingChanges()
        let restored = FeatureSettingsStore(defaults: defaults)
        #expect(!restored.settings.fileShelfEnabled)
        #expect(!restored.settings.fileShelfShakeEnabled)
        restored.settings.fileShelfEnabled = true
        #expect(!restored.settings.fileShelfShakeEnabled)
        restored.flushPendingChanges()
        let restarted = FeatureSettingsStore(defaults: defaults)
        #expect(restarted.settings.fileShelfEnabled)
        #expect(!restarted.settings.fileShelfShakeEnabled)
        restarted.reset()
        #expect(restarted.settings.fileShelfEnabled)
        #expect(restarted.settings.fileShelfShakeEnabled)
        restarted.flushPendingChanges()
        #expect(FeatureSettingsStore(defaults: defaults).settings.fileShelfShakeEnabled)
    }

    @Test @MainActor
    func aiResultSweepOptOutSurvivesStoreRecreationAndResetRestoresDefault() throws {
        let suiteName = "Zisla.FeatureSettingsStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = FeatureSettingsStore(defaults: defaults)
        store.settings.aiTaskResultSweepEnabled = false
        store.flushPendingChanges()
        let restored = FeatureSettingsStore(defaults: defaults)
        #expect(!restored.settings.aiTaskResultSweepEnabled)
        restored.reset()
        #expect(restored.settings.aiTaskResultSweepEnabled)
        restored.flushPendingChanges()
        #expect(FeatureSettingsStore(defaults: defaults).settings.aiTaskResultSweepEnabled)
    }

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
