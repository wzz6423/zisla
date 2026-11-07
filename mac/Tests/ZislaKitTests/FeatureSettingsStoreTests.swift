import Foundation
import Testing

@testable import ZislaCore
@testable import ZislaKit

struct FeatureSettingsStoreTests {
    @Test @MainActor
    func automaticSystemCleanupChoicesPersistAndResetWithoutChangingVoiceCleanup() throws {
        let suite = "Zisla.SystemCleanupSettings.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FeatureSettingsStore(defaults: defaults)
        store.settings.systemCleanupPolicy = .thirtyDays
        store.settings.systemCleanupScope = .all
        store.settings.voiceRecordingCleanupPolicy = .sevenDays
        store.settings.systemMonitorEnabled = false
        store.flushPendingChanges()
        let restored = FeatureSettingsStore(defaults: defaults)
        #expect(restored.settings == store.settings)
        #expect(restored.settings.systemCleanupPolicy == .thirtyDays)
        #expect(restored.settings.systemCleanupScope == .all)
        #expect(restored.settings.voiceRecordingCleanupPolicy == .sevenDays)
        restored.reset()
        restored.flushPendingChanges()
        let reset = FeatureSettingsStore(defaults: defaults)
        #expect(reset.settings.systemCleanupPolicy == .never)
        #expect(reset.settings.systemCleanupScope == .trustedOnly)
    }

    @Test(arguments: IslandEdge.allCases) @MainActor
    func rememberedCustomPlacementSurvivesStoreRecreationAndReset(edge: IslandEdge) throws {
        let suiteName = "Zisla.IslandPlacement.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = FeatureSettingsStore(defaults: defaults)
        #expect(store.settings.islandPlacement(for: .custom) == nil)
        let custom = IslandPlacement(mode: .custom, edge: edge, offset: 0.73, inwardDistance: 32)
        store.settings.islandLayoutStyle = .pill
        store.settings.islandPlacement = custom
        store.settings.islandPlacement = try #require(store.settings.islandPlacement(for: .camera))
        store.flushPendingChanges()

        let restored = FeatureSettingsStore(defaults: defaults)
        #expect(restored.settings.islandPlacement == IslandPlacement())
        #expect(restored.settings.islandPlacement(for: .custom) == custom)
        restored.settings.islandLayoutStyle = .notch
        restored.settings.islandLayoutStyle = .pill
        restored.settings.islandPlacement = try #require(restored.settings.islandPlacement(for: .custom))
        restored.flushPendingChanges()
        #expect(FeatureSettingsStore(defaults: defaults).settings.islandPlacement == custom)

        restored.reset()
        restored.flushPendingChanges()
        let reset = FeatureSettingsStore(defaults: defaults)
        #expect(reset.settings.islandPlacement == IslandPlacement())
        #expect(reset.settings.islandPlacement(for: .custom) == nil)
    }

    @Test @MainActor
    func moreInformationOptOutPersistsAcrossRelaunchAndResetRestoresItsDefault() throws {
        let suite = "Zisla.FloatingIslandInformation.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FeatureSettingsStore(defaults: defaults, persistenceDelay: .seconds(60))
        #expect(store.settings.islandShowMoreInformation)
        store.settings.islandShowMoreInformation = false
        store.flushPendingChanges()
        let reloaded = FeatureSettingsStore(defaults: defaults, persistenceDelay: .seconds(60))
        #expect(!reloaded.settings.islandShowMoreInformation)
        #expect(reloaded.settings == store.settings)
        reloaded.reset()
        reloaded.flushPendingChanges()
        #expect(FeatureSettingsStore(defaults: defaults).settings.islandShowMoreInformation)
    }

    @Test @MainActor
    func customUserCareIntervalPersistsAcrossDisablingAndResetRestoresTheDefault() throws {
        let suiteName = "Zisla.UserCareInterval.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = FeatureSettingsStore(defaults: defaults)
        store.settings.userCareEnabled = true
        store.settings.userCareReminderInterval = 3_723
        store.flushPendingChanges()
        let restored = FeatureSettingsStore(defaults: defaults)
        #expect(restored.settings.userCareEnabled)
        #expect(restored.settings.userCareReminderInterval == 3_723)
        restored.settings.userCareEnabled = false
        restored.flushPendingChanges()
        let disabled = FeatureSettingsStore(defaults: defaults)
        #expect(disabled.settings.userCareReminderInterval == 3_723)
        disabled.reset()
        disabled.flushPendingChanges()
        #expect(FeatureSettingsStore(defaults: defaults).settings.userCareReminderInterval == 2_700)
    }

    @Test @MainActor
    func userCareOptOutPersistsAndResetRestoresTheEnabledDefault() throws {
        let suiteName = "Zisla.UserCareSettings.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(Data(#"{"petEnabled":false,"sideNoticesEnabled":false}"#.utf8), forKey: "feature-settings-v1")

        let store = FeatureSettingsStore(defaults: defaults)
        #expect(store.settings.userCareEnabled)
        #expect(!store.settings.petEnabled)
        #expect(!store.settings.sideNoticesEnabled)
        store.settings.userCareEnabled = false
        store.flushPendingChanges()
        let restored = FeatureSettingsStore(defaults: defaults)
        #expect(!restored.settings.userCareEnabled)
        #expect(!restored.settings.sideNoticesEnabled)
        restored.reset()
        #expect(restored.settings.userCareEnabled)
        restored.flushPendingChanges()
        #expect(FeatureSettingsStore(defaults: defaults).settings.userCareEnabled)
    }

    @Test(arguments: ["missing", "empty", "null", "invalid"]) @MainActor
    func nonInvasiveDefaultsApplyToNewLegacyAndInvalidStoresAndReset(source: String) throws {
        let suiteName = "Zisla.NonInvasiveDefaults.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        switch source {
        case "empty": defaults.set(Data("{}".utf8), forKey: "feature-settings-v1")
        case "null":
            defaults.set(Data(#"{"dailyBriefing":{"enabled":null},"windowPreviewsEnabled":null,"contextNotesEnabled":null}"#.utf8), forKey: "feature-settings-v1")
        case "invalid": defaults.set(Data("invalid".utf8), forKey: "feature-settings-v1")
        default: break
        }
        let store = FeatureSettingsStore(defaults: defaults)
        #expect(store.settings.dailyBriefing.enabled)
        #expect(store.settings.windowPreviewsEnabled)
        #expect(store.settings.contextNotesEnabled)
        #expect(store.settings.menuBarAppIconEnabled)
        #expect(store.settings.statusIconDestination == .island)
        #expect(store.settings.systemMonitorMenuBarLayout == .stacked)
        #expect(store.settings.systemMonitorMenuBarCombinedIconEnabled)
        #expect(store.settings.systemMonitorMenuBarHeadphoneOptions.replacesNetworkIcon)
        let enabled = store.settings
        store.settings.dailyBriefing.enabled = false
        store.settings.dailyBriefing.minuteOfDay = 1385
        store.settings.windowPreviewsEnabled = false
        store.settings.contextNotesEnabled = false
        store.settings.menuBarAppIconEnabled = false
        store.settings.statusIconDestination = .menuBar
        store.settings.systemMonitorMenuBarLayout = .none
        store.settings.systemMonitorMenuBarCombinedIconEnabled = false
        store.settings.systemMonitorMenuBarHeadphoneOptions.replacesNetworkIcon = false
        store.flushPendingChanges()
        let restored = FeatureSettingsStore(defaults: defaults)
        #expect(restored.settings == store.settings)
        restored.reset()
        #expect(restored.settings == enabled)
        restored.flushPendingChanges()
        #expect(FeatureSettingsStore(defaults: defaults).settings == enabled)
    }

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
