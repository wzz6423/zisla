import Foundation
import Testing
import ZislaCore

@testable import ZislaKit

struct IslandAppIconStoreTests {
    @Test(arguments: ["fresh", "missing", "null", "invalid"])
    @MainActor
    func newAndLegacyStoresDefaultTheLogoOnWithoutChangingSavedChoices(source: String) throws {
        let suite = "Zisla.IslandAppIconDefaults.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        if source != "fresh" {
            var payload: [String: Any] = ["mediaEnabled": false, "systemMonitorEnabled": false,
                "menuBarAppIconEnabled": false, "statusIconDestination": "menuBar"]
            if source == "null" { payload["islandAppIconEnabled"] = NSNull() }
            if source == "invalid" { payload["islandAppIconEnabled"] = "false" }
            defaults.set(try JSONSerialization.data(withJSONObject: payload), forKey: "feature-settings-v1")
        }
        let store = FeatureSettingsStore(defaults: defaults, persistenceDelay: .seconds(60), defaultUpdateChannel: .release)
        defer { store.flushPendingChanges() }
        #expect(store.settings.islandAppIconEnabled)
        if source != "fresh" {
            #expect(!store.settings.mediaEnabled)
            #expect(!store.settings.systemMonitorEnabled)
            #expect(!store.settings.menuBarAppIconEnabled)
            #expect(store.settings.statusIconDestination == .menuBar)
        }
    }

    @Test(arguments: [false, true]) @MainActor
    func logoOptOutSurvivesStoreRecreationAndResetRestoresTheEnabledDefault(showsMenuBarIcon: Bool) throws {
        let suite = "Zisla.IslandAppIconPersistence.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FeatureSettingsStore(defaults: defaults, persistenceDelay: .seconds(60), defaultUpdateChannel: .release)
        defer { store.flushPendingChanges() }
        store.settings.menuBarAppIconEnabled = showsMenuBarIcon
        let original = store.settings
        store.settings.islandAppIconEnabled = false
        store.flushPendingChanges()
        let saved = try #require(defaults.data(forKey: "feature-settings-v1"))
        let persisted = try JSONDecoder().decode(FeatureSettings.self, from: saved)
        #expect(persisted == store.settings)
        #expect(!persisted.islandAppIconEnabled)
        let reloaded = FeatureSettingsStore(defaults: defaults, persistenceDelay: .seconds(60), defaultUpdateChannel: .release)
        defer { reloaded.flushPendingChanges() }
        #expect(reloaded.settings == persisted)
        reloaded.settings.islandAppIconEnabled = true
        #expect(reloaded.settings == original, "The logo switch must change only its own saved preference")
        reloaded.settings.islandAppIconEnabled = false
        reloaded.settings.islandLayoutStyle = .pill
        reloaded.settings.islandPlacement = IslandPlacement(mode: .custom, edge: .left)
        reloaded.settings.statusIconDestination = .menuBar
        reloaded.flushPendingChanges()
        let changedMode = FeatureSettingsStore(defaults: defaults, persistenceDelay: .seconds(60), defaultUpdateChannel: .release)
        defer { changedMode.flushPendingChanges() }
        #expect(!changedMode.settings.islandAppIconEnabled)
        #expect(changedMode.settings.menuBarAppIconEnabled == showsMenuBarIcon)
        changedMode.reset()
        changedMode.flushPendingChanges()
        let reset = FeatureSettingsStore(defaults: defaults, defaultUpdateChannel: .release)
        #expect(reset.settings == FeatureSettings.default)
        #expect(reset.settings.islandAppIconEnabled)
    }
}
