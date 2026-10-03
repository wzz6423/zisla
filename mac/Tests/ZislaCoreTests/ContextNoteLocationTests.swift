import Foundation
import Testing
@testable import ZislaCore

struct ContextNoteLocationTests {
    @Test
    func completePageAddressSurvivesTitleAndBrowserChanges() throws {
        let url = try #require(URL(string: "https://example.test/article?id=1#section"))
        let location = ContextNoteLocation.webPage(url: url, title: "Old title", applicationName: "Safari")
        #expect(location.matches(.webPage(url: url, title: "New title", applicationName: "Chrome")))
        for address in ["https://example.test/article?id=2#section", "https://example.test/article?id=1#other", "https://example.test/other?id=1#section"] {
            #expect(!location.matches(.webPage(url: try #require(URL(string: address)), title: "Old title", applicationName: "Safari")))
        }
    }

    @Test
    func windowsAndDisplaysHaveSeparateIdentities() {
        let window = ContextNoteLocation.window(bundleIdentifier: "test.editor", applicationName: "Editor", title: "a.txt")
        #expect(window.matches(.window(bundleIdentifier: "test.editor", applicationName: "Localized editor", title: "a.txt")))
        #expect(!window.matches(.window(bundleIdentifier: "test.editor", applicationName: "Editor", title: "b.txt")))
        #expect(!window.matches(.window(bundleIdentifier: "test.other", applicationName: "Editor", title: "a.txt")))
        let desktop = ContextNoteLocation.desktop(displayID: "display-a", displayName: "Display")
        #expect(desktop.matches(.desktop(displayID: "display-a", displayName: "Renamed")))
        #expect(!desktop.matches(.desktop(displayID: "display-b", displayName: "Display")))
        #expect(!window.matches(desktop))
    }

    @Test
    func everyLocationRoundTripsAndMalformedDataIsRejected() throws {
        let locations: [ContextNoteLocation] = [
            .webPage(url: try #require(URL(string: "https://example.test/?q=%E4%B8%AD#one")), title: "Page", applicationName: "Browser"),
            .window(bundleIdentifier: "test.editor", applicationName: "Editor", title: "文档"),
            .desktop(displayID: "display-a", displayName: "Display"),
        ]
        for location in locations {
            #expect(try JSONDecoder().decode(ContextNoteLocation.self, from: JSONEncoder().encode(location)) == location)
        }
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(ContextNoteLocation.self, from: Data("{}".utf8)) }
    }

    @Test
    func settingIsOptInAndCompatibleWithExistingPreferences() throws {
        #expect(!FeatureSettings.default.contextNotesEnabled)
        #expect(try !JSONDecoder().decode(FeatureSettings.self, from: Data("{}".utf8)).contextNotesEnabled)
        for enabled in [true, false] {
            var settings = FeatureSettings.default
            settings.contextNotesEnabled = enabled
            #expect(try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(settings)).contextNotesEnabled == enabled)
        }
    }

    @Test(arguments: ["{}", "{\"contextNotesEnabled\":true}", "{\"contextNoteHoldHotkey\":null}"])
    func oldPreferencesDefaultToHoldingCommand(json: String) throws {
        let settings = try JSONDecoder().decode(FeatureSettings.self, from: Data(json.utf8))
        #expect(settings.contextNoteHoldHotkey == FeatureSettings.default.contextNoteHoldHotkey)
        #expect(settings.contextNoteHoldHotkey.carbonModifiers == 0x0100)
        #expect(settings.contextNoteHoldHotkey.keyCode == 55)
        #expect(settings.contextNoteHoldHotkey.modifierSides == nil)
    }

    @Test(arguments: [VoiceInputHotkeyPreset.controlSpace,
                     VoiceInputHotkeyPreset(keyCode: 61, carbonModifiers: 0x0800, keyDisplayName: "R⌥", modifierSides: [.rightOption])])
    func customNoteHotkeysRoundTrip(hotkey: VoiceInputHotkeyPreset) throws {
        var settings = FeatureSettings(contextNoteHoldHotkey: hotkey)
        settings.contextNotesEnabled = true
        let restored = try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(settings))
        #expect(restored.contextNoteHoldHotkey == hotkey)
        #expect(restored.contextNotesEnabled)
    }
}
