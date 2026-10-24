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
        #expect(migrated["screenshotHotkeyVersion"] as? Int == ScreenshotHotkeyDefaults.currentVersion)
        store.settings.screenshotStashHotkey = .init(keyCode: 15, carbonModifiers: 0x0800, keyDisplayName: "R")
        store.settings.screenshotEditorLongHotkey = .init(keyCode: 17, carbonModifiers: 0x0800, keyDisplayName: "T")
        store.flushPendingChanges()
        let restored = FeatureSettingsStore(defaults: defaults)
        #expect(restored.settings == store.settings)
    }

    @Test(arguments: ["defaults", "custom", "previousWithVoiceShortcut"]) @MainActor
    func oldScreenshotLayoutMigratesAndPersistsOnFirstLoad(layout: String) throws {
        let suiteName = "Zisla.ScreenshotHotkeys.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var old = FeatureSettings.default
        old.screenshotToolHotkeys = ScreenshotHotkeyDefaults.versionOneTools
        old.screenshotEditorLongHotkey = .init(keyCode: 29, carbonModifiers: 0x1000, keyDisplayName: "0")
        if layout == "custom" {
            old.screenshotToolHotkeys["rectangle"] = .init(keyCode: 15, carbonModifiers: 0x0800, keyDisplayName: "R")
            old.screenshotStashHotkey = .init(keyCode: 17, carbonModifiers: 0x0800, keyDisplayName: "T")
        } else if layout == "previousWithVoiceShortcut" {
            old.screenshotToolHotkeys = ScreenshotHotkeyDefaults.previousTools
            old.screenshotPinHotkey = .init(keyCode: 19, carbonModifiers: 0x1000, keyDisplayName: "2")
            old.screenshotLongHotkey = .init(keyCode: 20, carbonModifiers: 0x1000, keyDisplayName: "3")
            old.voiceInputHotkeyPreset = .init(keyCode: 21, carbonModifiers: 0x1000, keyDisplayName: "4")
        }
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        if layout == "previousWithVoiceShortcut" {
            object.removeValue(forKey: "screenshotHotkeyVersion")
            object.removeValue(forKey: "screenshotStashHotkey")
            object.removeValue(forKey: "screenshotEditorLongHotkey")
        } else {
            object["screenshotHotkeyVersion"] = 1
        }
        defaults.set(try JSONSerialization.data(withJSONObject: object), forKey: "feature-settings-v1")

        let store = FeatureSettingsStore(defaults: defaults)
        let data = try #require(defaults.data(forKey: "feature-settings-v1"))
        let persisted = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(persisted["screenshotHotkeyVersion"] as? Int == ScreenshotHotkeyDefaults.currentVersion)
        #expect(try JSONDecoder().decode(FeatureSettings.self, from: data) == store.settings)
        if layout == "custom" {
            #expect(store.settings.screenshotStashHotkey == old.screenshotStashHotkey)
            #expect(store.settings.screenshotEditorLongHotkey == old.screenshotEditorLongHotkey)
            for (id, hotkey) in old.screenshotToolHotkeys {
                #expect(store.settings.screenshotToolHotkeys[id] == hotkey)
            }
            #expect(store.settings.screenshotToolHotkeys.count == 9)
        } else if layout == "previousWithVoiceShortcut" {
            #expect(store.settings.voiceInputHotkeyPreset == old.voiceInputHotkeyPreset)
            let editor = [store.settings.screenshotPinHotkey, store.settings.screenshotStashHotkey,
                store.settings.screenshotEditorLongHotkey] + Array(store.settings.screenshotToolHotkeys.values)
            #expect(editor.allSatisfy { !$0.conflicts(with: old.voiceInputHotkeyPreset) })
            #expect(store.settings.screenshotToolHotkeys["ellipse"]?.keyDisplayName == "5")
            #expect(store.settings.screenshotToolHotkeys.count == 9)
        } else {
            #expect(store.settings == FeatureSettings.default)
        }
        let restored = FeatureSettingsStore(defaults: defaults)
        #expect(restored.settings == store.settings)
        #expect(defaults.data(forKey: "feature-settings-v1") == data)
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
