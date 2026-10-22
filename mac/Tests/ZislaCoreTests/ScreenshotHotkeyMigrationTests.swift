import Foundation
import Testing
@testable import ZislaCore

struct ScreenshotHotkeyMigrationTests {
    private static let versionOneTools: [String: VoiceInputHotkeyPreset] = [
        "rectangle": .init(keyCode: 20, carbonModifiers: 0x1000, keyDisplayName: "3"),
        "ellipse": .init(keyCode: 21, carbonModifiers: 0x1000, keyDisplayName: "4"),
        "brush": .init(keyCode: 23, carbonModifiers: 0x1000, keyDisplayName: "5"),
        "arrow": .init(keyCode: 22, carbonModifiers: 0x1000, keyDisplayName: "6"),
        "number": .init(keyCode: 26, carbonModifiers: 0x1000, keyDisplayName: "7"),
        "text": .init(keyCode: 28, carbonModifiers: 0x1000, keyDisplayName: "8"),
        "mosaic": .init(keyCode: 25, carbonModifiers: 0x1000, keyDisplayName: "9"),
    ]

    @Test
    func defaultsHaveSeparateGlobalAndEditorGroups() throws {
        let settings = FeatureSettings.default
        #expect(settings.screenshotHotkey == ScreenshotHotkeyDefaults.pin)
        #expect(settings.screenshotLongHotkey == ScreenshotHotkeyDefaults.stash)
        let toolIDs = ["rectangle", "ellipse", "brush", "highlighter", "arrow", "number", "text", "mosaic", "extraction"]
        let editor = try [settings.screenshotPinHotkey, settings.screenshotStashHotkey]
            + toolIDs.map { try #require(settings.screenshotToolHotkeys[$0]) }
            + [settings.screenshotEditorLongHotkey]
        #expect(editor.map(\.keyDisplayName) == ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "A", "B"])
        #expect(editor.map(\.keyCode) == [18, 19, 20, 21, 23, 22, 26, 28, 25, 29, 0, 11])
        #expect(editor.allSatisfy { $0.carbonModifiers == 0x1000 })
        expectNoCollisions(editor)
    }

    @Test(arguments: ["legacy", "previous", "version1"])
    func completeOldDefaultsMigrateOnceAndLaterOldNumberChoicesSurvive(layout: String) throws {
        let legacy = try oldObject(layout: layout)
        let migrated = try decode(legacy)
        #expect(migrated == FeatureSettings.default)
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

    @Test(arguments: ["legacy", "previous", "version1"],
        ["screenshotHotkey", "screenshotPinHotkey", "screenshotLongHotkey", "screenshotStashHotkey", "screenshotEditorLongHotkey", "tool"])
    func partialLegacyCustomPreservesTheWholeExistingGroupAndAddsFreeShortcuts(layout: String, field: String) throws {
        var object = try oldObject(layout: layout)
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
        for (id, hotkey) in oldTools {
            #expect(migrated.screenshotToolHotkeys[id] == hotkey, "Changed an existing shortcut for \(id)")
        }
        #expect(migrated.screenshotToolHotkeys.count == oldTools.count + 2)
        let occupied = [migrated.screenshotPinHotkey] + Array(oldTools.values)
        for key in ["screenshotStashHotkey", "screenshotEditorLongHotkey"] {
            let actual = key == "screenshotStashHotkey" ? migrated.screenshotStashHotkey : migrated.screenshotEditorLongHotkey
            if let stored = object[key] {
                let expected = try JSONDecoder().decode(VoiceInputHotkeyPreset.self,
                    from: JSONSerialization.data(withJSONObject: stored))
                #expect(actual == expected)
            } else {
                #expect(!occupied.contains { actual.conflicts(with: $0) })
            }
        }
        let allExisting = occupied + [migrated.screenshotStashHotkey, migrated.screenshotEditorLongHotkey]
        let newTools = try ["highlighter", "extraction"].map { try #require(migrated.screenshotToolHotkeys[$0]) }
        for hotkey in newTools {
            #expect(!allExisting.contains { hotkey.conflicts(with: $0) })
            #expect(hotkey.carbonModifiers == 0x1000)
            #expect(!["Q", "M", "N", "W"].contains(hotkey.keyDisplayName))
        }
        expectNoCollisions(newTools)
        #expect(try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(migrated)) == migrated)
    }

    @Test
    func previousToolsWithOneCustomKeyAlsoKeepTextZeroAndGetAFreeEditorLongKey() throws {
        var object = try oldObject(layout: "previous")
        var tools = ScreenshotHotkeyDefaults.previousTools
        tools["rectangle"] = .init(keyCode: 15, carbonModifiers: 0x0800, keyDisplayName: "R")
        object["screenshotToolHotkeys"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(tools))
        let migrated = try decode(object)
        for (id, hotkey) in tools { #expect(migrated.screenshotToolHotkeys[id] == hotkey) }
        #expect(migrated.screenshotToolHotkeys["text"]?.keyCode == 29)
        #expect(!migrated.screenshotEditorLongHotkey.conflicts(with: try #require(tools["text"])))
        #expect(try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(migrated)) == migrated)
    }

    @Test(arguments: [false, true], [false, true])
    func missingToolsUseControlLettersAfterOccupiedDigitsAndAvoidEnabledGlobalShortcuts(voiceEnabled: Bool, assistantEnabled: Bool) throws {
        var object = try oldObject(layout: "version1")
        object["screenshotHotkey"] = try encoded(VoiceInputHotkeyPreset(keyCode: 15, carbonModifiers: 0x0800, keyDisplayName: "R"))
        object["voiceInputEnabled"] = voiceEnabled
        object["voiceInputHotkeyPreset"] = try encoded(VoiceInputHotkeyPreset(keyCode: 0, carbonModifiers: 0x1000, keyDisplayName: "A"))
        object["clipboardAssistantEnabled"] = assistantEnabled
        object["clipboardAssistantTriggerConfiguration"] = try encoded(ClipboardAssistantTriggerConfiguration.hotkey(
            .init(keyCode: 11, carbonModifiers: 0x1000, keyDisplayName: "B")))
        let migrated = try decode(object)
        let newTools = try ["highlighter", "extraction"].map { try #require(migrated.screenshotToolHotkeys[$0]) }
        let expected = voiceEnabled ? (assistantEnabled ? ["C", "D"] : ["B", "C"])
            : (assistantEnabled ? ["A", "C"] : ["A", "B"])
        #expect(newTools.map(\.keyDisplayName) == expected)
        #expect(newTools.allSatisfy { $0.carbonModifiers == 0x1000 })
        expectNoCollisions([migrated.screenshotPinHotkey, migrated.screenshotStashHotkey,
            migrated.screenshotEditorLongHotkey] + Array(migrated.screenshotToolHotkeys.values))
        #expect(try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(migrated)) == migrated)
    }

    @Test(arguments: [false, true], [false, true])
    func completeOldDefaultMigrationDoesNotCollideWithCustomizedGlobalLetters(voiceEnabled: Bool, assistantEnabled: Bool) throws {
        var object = try oldObject(layout: "version1")
        object["voiceInputEnabled"] = voiceEnabled
        object["voiceInputHotkeyPreset"] = try encoded(VoiceInputHotkeyPreset(keyCode: 0, carbonModifiers: 0x1000, keyDisplayName: "A"))
        object["clipboardAssistantEnabled"] = assistantEnabled
        object["clipboardAssistantTriggerConfiguration"] = try encoded(ClipboardAssistantTriggerConfiguration.hotkey(
            .init(keyCode: 11, carbonModifiers: 0x1000, keyDisplayName: "B")))
        let migrated = try decode(object)
        let editor = [migrated.screenshotPinHotkey, migrated.screenshotStashHotkey,
            migrated.screenshotEditorLongHotkey] + Array(migrated.screenshotToolHotkeys.values)
        expectNoCollisions(editor)
        if voiceEnabled { #expect(!editor.contains { $0.conflicts(with: migrated.voiceInputHotkeyPreset) }) }
        if assistantEnabled {
            let hotkey = try #require(migrated.clipboardAssistantTriggerConfiguration.hotkey)
            #expect(!editor.contains { $0.conflicts(with: hotkey) })
        }
        #expect(migrated.screenshotToolHotkeys["highlighter"]?.keyDisplayName == "6")
        #expect(migrated.screenshotToolHotkeys["extraction"]?.keyDisplayName == (voiceEnabled ? (assistantEnabled ? "C" : "B") : "A"))
        #expect(migrated.screenshotEditorLongHotkey.keyDisplayName == (voiceEnabled && assistantEnabled ? "D"
            : voiceEnabled || assistantEnabled ? "C" : "B"))
        #expect(editor.allSatisfy { $0.carbonModifiers == 0x1000 })
        #expect(try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(migrated)) == migrated)
    }

    @Test
    func previousDefaultMigrationRespectsVoiceShortcutInFormerlyFreeNumberSlot() throws {
        var object = try oldObject(layout: "previous")
        let voice = VoiceInputHotkeyPreset(keyCode: 21, carbonModifiers: 0x1000, keyDisplayName: "4", modifierSides: [.leftControl])
        object["voiceInputHotkeyPreset"] = try encoded(voice)
        let migrated = try decode(object)
        let toolIDs = ["rectangle", "ellipse", "brush", "highlighter", "arrow", "number", "text", "mosaic", "extraction"]
        let editor = try [migrated.screenshotPinHotkey, migrated.screenshotStashHotkey]
            + toolIDs.map { try #require(migrated.screenshotToolHotkeys[$0]) }
            + [migrated.screenshotEditorLongHotkey]
        #expect(migrated.voiceInputHotkeyPreset == voice)
        #expect(editor.map(\.keyDisplayName) == ["1", "2", "3", "5", "6", "7", "8", "9", "0", "A", "B", "C"])
        #expect(editor.allSatisfy { !$0.conflicts(with: voice) })
        expectNoCollisions(editor)
        #expect(try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(migrated)) == migrated)
    }

    @Test
    func versionOnePreservesAlreadyRecordedNewTools() throws {
        var object = try oldObject(layout: "version1")
        var tools = Self.versionOneTools
        tools["highlighter"] = .init(keyCode: 15, carbonModifiers: 0x0800, keyDisplayName: "R")
        tools["extraction"] = .init(keyCode: 17, carbonModifiers: 0x0800, keyDisplayName: "T")
        object["screenshotToolHotkeys"] = try encoded(tools)
        #expect(try decode(object).screenshotToolHotkeys == tools)
    }

    @Test
    func fillingMissingStashAndToolKeysRespectsSavedEditorLongAndPhysicalModifierSides() throws {
        var object = try oldObject(layout: "version1")
        var tools = Self.versionOneTools
        tools["rectangle"] = .init(keyCode: 0, carbonModifiers: 0x1000, keyDisplayName: "A", modifierSides: [.leftControl])
        tools["ellipse"] = .init(keyCode: 22, carbonModifiers: 0x1000, keyDisplayName: "6")
        tools["arrow"] = .init(keyCode: 21, carbonModifiers: 0x1000, keyDisplayName: "4")
        object["screenshotToolHotkeys"] = try encoded(tools)
        object.removeValue(forKey: "screenshotStashHotkey")
        object["screenshotEditorLongHotkey"] = try encoded(
            VoiceInputHotkeyPreset(keyCode: 19, carbonModifiers: 0x1000, keyDisplayName: "2", modifierSides: [.rightControl]))
        let migrated = try decode(object)
        #expect(migrated.screenshotStashHotkey.keyDisplayName == "3")
        #expect(migrated.screenshotToolHotkeys["highlighter"]?.keyDisplayName == "0")
        #expect(migrated.screenshotToolHotkeys["extraction"]?.keyDisplayName == "B")
        #expect(migrated.screenshotEditorLongHotkey.modifierSides == [.rightControl])
        #expect(migrated.screenshotToolHotkeys["rectangle"]?.modifierSides == [.leftControl])
        for id in ["highlighter", "extraction"] {
            let newHotkey = try #require(migrated.screenshotToolHotkeys[id])
            #expect(!newHotkey.conflicts(with: migrated.screenshotEditorLongHotkey))
            #expect(!newHotkey.conflicts(with: try #require(tools["rectangle"])))
        }
        expectNoCollisions([migrated.screenshotPinHotkey, migrated.screenshotStashHotkey,
            migrated.screenshotEditorLongHotkey] + Array(migrated.screenshotToolHotkeys.values))
    }

    @Test
    func oldEmptyToolsOnlyReceiveTheTwoNewTools() throws {
        var object = try oldObject(layout: "version1")
        object["screenshotToolHotkeys"] = [String: Any]()
        let migrated = try decode(object)
        #expect(Set(migrated.screenshotToolHotkeys.keys) == ["highlighter", "extraction"])
        #expect(try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(migrated)) == migrated)
    }

    @Test(arguments: [true, false])
    func currentVersionKeepsEmptyAndPartiallyDisabledToolHotkeys(empty: Bool) throws {
        var settings = FeatureSettings.default
        if empty { settings.screenshotToolHotkeys = [:] }
        else { settings.screenshotToolHotkeys.removeValue(forKey: "highlighter") }
        #expect(try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(settings)) == settings)
    }

    @Test
    func currentVersionKeepsExplicitlyChosenPreviousDefaultLayout() throws {
        var settings = FeatureSettings.default
        settings.screenshotToolHotkeys = Self.versionOneTools
        settings.screenshotEditorLongHotkey = .init(keyCode: 29, carbonModifiers: 0x1000, keyDisplayName: "0")
        #expect(try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(settings)) == settings)
    }

    @Test
    func newToolsPreferTheirDefaultsBeforeUnusedEarlierNumbers() throws {
        var object = try oldObject(layout: "version1")
        var tools = Self.versionOneTools
        tools["rectangle"] = .init(keyCode: 15, carbonModifiers: 0x0800, keyDisplayName: "R")
        tools["ellipse"] = .init(keyCode: 17, carbonModifiers: 0x0800, keyDisplayName: "T")
        object["screenshotToolHotkeys"] = try encoded(tools)
        let migrated = try decode(object)
        #expect(migrated.screenshotToolHotkeys["highlighter"]?.keyDisplayName == "3")
        #expect(migrated.screenshotToolHotkeys["extraction"]?.keyDisplayName == "A")
    }

    @Test(arguments: [(UInt32(12), "Q"), (46, "M"), (45, "N"), (13, "W")])
    func riskyLettersAreExcludedFromDefaultsButRemainUserConfigurable(keyCode: UInt32, name: String) throws {
        var object = try oldObject(layout: "version1")
        let custom = VoiceInputHotkeyPreset(keyCode: keyCode, carbonModifiers: 0x1000, keyDisplayName: name)
        var tools = Self.versionOneTools
        tools["rectangle"] = custom
        object["screenshotToolHotkeys"] = try encoded(tools)
        let migrated = try decode(object)
        #expect(migrated.screenshotToolHotkeys["rectangle"] == custom)
        for id in ["highlighter", "extraction"] {
            #expect(!["Q", "M", "N", "W"].contains(try #require(migrated.screenshotToolHotkeys[id]).keyDisplayName))
        }
    }

    @Test
    func malformedMigrationVersionIsRejected() throws {
        var object = try oldObject(layout: "version1")
        object["screenshotHotkeyVersion"] = "invalid"
        #expect(throws: DecodingError.self) { _ = try decode(object) }
    }

    private func oldObject(layout: String) throws -> [String: Any] {
        var legacy = FeatureSettings.default
        if layout == "version1" {
            legacy.screenshotToolHotkeys = Self.versionOneTools
            legacy.screenshotEditorLongHotkey = .init(keyCode: 29, carbonModifiers: 0x1000, keyDisplayName: "0")
            var object = try #require(try encoded(legacy) as? [String: Any])
            object["screenshotHotkeyVersion"] = 1
            return object
        }
        legacy.screenshotPinHotkey = .init(keyCode: 19, carbonModifiers: 0x1000, keyDisplayName: "2")
        legacy.screenshotLongHotkey = .init(keyCode: 20, carbonModifiers: 0x1000, keyDisplayName: "3")
        legacy.screenshotToolHotkeys = layout == "previous" ? ScreenshotHotkeyDefaults.previousTools : ScreenshotHotkeyDefaults.legacyTools
        var object = try #require(try encoded(legacy) as? [String: Any])
        for key in ["screenshotHotkeyVersion", "screenshotStashHotkey", "screenshotEditorLongHotkey"] {
            object.removeValue(forKey: key)
        }
        return object
    }

    private func decode(_ object: [String: Any]) throws -> FeatureSettings {
        try JSONDecoder().decode(FeatureSettings.self, from: JSONSerialization.data(withJSONObject: object))
    }

    private func encoded(_ value: some Encodable) throws -> Any {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
    }

    private func expectNoCollisions(_ hotkeys: [VoiceInputHotkeyPreset]) {
        for (index, hotkey) in hotkeys.enumerated() {
            #expect(!hotkeys.dropFirst(index + 1).contains { hotkey.conflicts(with: $0) })
        }
    }
}
