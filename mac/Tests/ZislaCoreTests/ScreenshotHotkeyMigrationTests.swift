import Foundation
import Testing
@testable import ZislaCore

struct ScreenshotHotkeyMigrationTests {
    @Test
    func defaultsHaveSeparateGlobalAndEditorGroups() {
        let settings = FeatureSettings.default
        #expect(settings.screenshotHotkey == ScreenshotHotkeyDefaults.pin)
        #expect(settings.screenshotLongHotkey == ScreenshotHotkeyDefaults.stash)
        #expect(settings.screenshotStashHotkey.keyCode == 19)
        #expect(settings.screenshotEditorLongHotkey.keyCode == 29)
        let editor = [settings.screenshotPinHotkey, settings.screenshotStashHotkey,
            settings.screenshotEditorLongHotkey] + Array(settings.screenshotToolHotkeys.values)
        #expect(editor.count == 10)
        for (index, hotkey) in editor.enumerated() {
            #expect(!editor.dropFirst(index + 1).contains { hotkey.conflicts(with: $0) })
        }
    }

    @Test
    func completeMainDefaultsMigrateOnceAndLaterOldNumberChoicesSurvive() throws {
        let legacy = try legacyObject()
        let migrated = try decode(legacy)
        #expect(migrated.screenshotPinHotkey == ScreenshotHotkeyDefaults.pin)
        #expect(migrated.screenshotLongHotkey == ScreenshotHotkeyDefaults.longCapture)
        #expect(migrated.screenshotToolHotkeys == ScreenshotHotkeyDefaults.tools)
        #expect(migrated.screenshotStashHotkey == ScreenshotHotkeyDefaults.stash)
        #expect(migrated.screenshotEditorLongHotkey == ScreenshotHotkeyDefaults.editorLongCapture)
        var recorded = migrated
        recorded.screenshotPinHotkey = .init(keyCode: 19, carbonModifiers: 0x1000, keyDisplayName: "2")
        recorded.screenshotLongHotkey = .init(keyCode: 20, carbonModifiers: 0x1000, keyDisplayName: "3")
        recorded.screenshotToolHotkeys = ScreenshotHotkeyDefaults.legacyTools
        let restarted = try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(recorded))
        #expect(restarted == recorded)
        #expect(try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(restarted)) == recorded)
    }

    @Test(arguments: ["screenshotHotkey", "screenshotPinHotkey", "screenshotLongHotkey", "tool"])
    func partialLegacyCustomPreservesTheWholeExistingGroupAndAddsFreeShortcuts(field: String) throws {
        var object = try legacyObject()
        let custom = VoiceInputHotkeyPreset(keyCode: 15, carbonModifiers: 0x0800, keyDisplayName: "R")
        let value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(custom))
        if field == "tool" {
            var tools = try #require(object["screenshotToolHotkeys"] as? [String: Any])
            tools["rectangle"] = value
            object["screenshotToolHotkeys"] = tools
        } else {
            object[field] = value
        }
        let migrated = try decode(object)
        for key in ["screenshotHotkey", "screenshotPinHotkey", "screenshotLongHotkey"] {
            let expected = try JSONDecoder().decode(VoiceInputHotkeyPreset.self,
                from: JSONSerialization.data(withJSONObject: try #require(object[key])))
            let actual = key == "screenshotHotkey" ? migrated.screenshotHotkey
                : key == "screenshotPinHotkey" ? migrated.screenshotPinHotkey : migrated.screenshotLongHotkey
            #expect(actual == expected)
        }
        let oldTools = try JSONDecoder().decode([String: VoiceInputHotkeyPreset].self,
            from: JSONSerialization.data(withJSONObject: try #require(object["screenshotToolHotkeys"])))
        #expect(migrated.screenshotToolHotkeys == oldTools)
        let occupied = [migrated.screenshotPinHotkey] + Array(oldTools.values)
        #expect(!occupied.contains { migrated.screenshotStashHotkey.conflicts(with: $0) })
        #expect(!occupied.contains { migrated.screenshotEditorLongHotkey.conflicts(with: $0) })
        #expect(!migrated.screenshotEditorLongHotkey.conflicts(with: migrated.screenshotStashHotkey))
        #expect(try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(migrated)) == migrated)
    }

    @Test
    func previousToolsWithOneCustomKeyAlsoKeepTextZeroAndGetAFreeEditorLongKey() throws {
        var object = try legacyObject()
        var tools = ScreenshotHotkeyDefaults.previousTools
        tools["rectangle"] = .init(keyCode: 15, carbonModifiers: 0x0800, keyDisplayName: "R")
        object["screenshotToolHotkeys"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(tools))
        let migrated = try decode(object)
        #expect(migrated.screenshotToolHotkeys == tools)
        #expect(migrated.screenshotToolHotkeys["text"]?.keyCode == 29)
        #expect(!migrated.screenshotEditorLongHotkey.conflicts(with: try #require(tools["text"])))
        #expect(try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(migrated)) == migrated)
    }

    private func legacyObject() throws -> [String: Any] {
        var legacy = FeatureSettings.default
        legacy.screenshotPinHotkey = .init(keyCode: 19, carbonModifiers: 0x1000, keyDisplayName: "2")
        legacy.screenshotLongHotkey = .init(keyCode: 20, carbonModifiers: 0x1000, keyDisplayName: "3")
        legacy.screenshotToolHotkeys = ScreenshotHotkeyDefaults.legacyTools
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any])
        for key in ["screenshotHotkeyVersion", "screenshotStashHotkey", "screenshotEditorLongHotkey"] {
            object.removeValue(forKey: key)
        }
        return object
    }

    private func decode(_ object: [String: Any]) throws -> FeatureSettings {
        try JSONDecoder().decode(FeatureSettings.self, from: JSONSerialization.data(withJSONObject: object))
    }
}
