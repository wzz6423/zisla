import Foundation
import Testing
import ZislaCore

struct ClipboardAssistantDismissSettingsTests {
    @Test
    func defaultsPersistCommandBackspaceAsAnIndependentDismissShortcut() throws {
        let encoded = try JSONEncoder().encode(FeatureSettings())
        let payload = try JSONDecoder().decode(DismissConfigurationPayload.self, from: encoded)
        let hotkey = try #require(payload.clipboardAssistantDismissConfiguration?.hotkey)
        #expect(hotkey.keyCode == 51)
        #expect(hotkey.carbonModifiers == 0x0100)
        #expect(hotkey.keyDisplayName == "⌫")
        #expect(hotkey != FeatureSettings().clipboardAssistantTriggerConfiguration.hotkey)
    }

    @Test(arguments: ["{}", #"{"clipboardAssistantDismissConfiguration":null}"#])
    func legacySettingsDefaultToCommandBackspaceWithoutChangingThePrimaryShortcut(payload: String) throws {
        let settings = try JSONDecoder().decode(FeatureSettings.self, from: Data(payload.utf8))
        #expect(settings.clipboardAssistantDismissConfiguration == .hotkey(ClipboardAssistantDefaults.dismissHotkey))
        #expect(settings.clipboardAssistantTriggerConfiguration == .default)
    }

    @Test(arguments: [false, true])
    func customAndClearedDismissShortcutsSurviveRelaunch(cleared: Bool) throws {
        let configuration: ClipboardAssistantTriggerConfiguration = cleared ? .none : .hotkey(.commandShiftV)
        let settings = FeatureSettings(
            clipboardAssistantTriggerConfiguration: .none,
            clipboardAssistantDismissConfiguration: configuration,
            clipboardAssistantMouseButton: 3
        )
        let data = try JSONEncoder().encode(settings)
        let payload = try JSONDecoder().decode(DismissConfigurationPayload.self, from: data)
        #expect(payload.clipboardAssistantDismissConfiguration == configuration)
        let restored = try JSONDecoder().decode(FeatureSettings.self, from: data)
        #expect(restored.clipboardAssistantDismissConfiguration == configuration)
        #expect(restored.clipboardAssistantTriggerConfiguration == .none)
        #expect(restored.clipboardAssistantMouseButton == 3)
    }

    @Test
    func clearingThePrimaryShortcutDoesNotClearTheDefaultDismissShortcut() throws {
        var settings = FeatureSettings()
        settings.clipboardAssistantTriggerConfiguration = .none
        let restored = try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(settings))
        #expect(restored.clipboardAssistantTriggerConfiguration == .none)
        #expect(restored.clipboardAssistantDismissConfiguration.hotkey == ClipboardAssistantDefaults.dismissHotkey)
    }

    @Test
    func clearingTheDismissShortcutPreservesThePrimaryShortcutAndMouseTrigger() throws {
        var settings = FeatureSettings(
            clipboardAssistantTriggerConfiguration: .hotkey(.commandShiftV),
            clipboardAssistantMouseButton: 3
        )
        settings.clipboardAssistantDismissConfiguration = .none
        let restored = try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(settings))
        #expect(restored.clipboardAssistantDismissConfiguration == .none)
        #expect(restored.clipboardAssistantTriggerConfiguration.hotkey == .commandShiftV)
        #expect(restored.clipboardAssistantMouseButton == 3)
    }

    @Test
    func customKeyAndModifierCombinationsRoundTripWithoutChangingOtherSettings() throws {
        for keyCode: UInt32 in [0, 18, 51, 117, 126] {
            for modifiers: UInt32 in [0, 0x0100, 0x0200, 0x0800, 0x1000, 0x1900, 0x1B00] {
                let hotkey = VoiceInputHotkeyPreset(
                    keyCode: keyCode, carbonModifiers: modifiers, keyDisplayName: "fixture"
                )
                let settings = FeatureSettings(clipboardAssistantDismissConfiguration: .hotkey(hotkey))
                let restored = try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(settings))
                #expect(restored == settings)
            }
        }
    }

    @Test(arguments: ["true", "17", #""invalid""#, #"{"unknown":{}}"#, #"{"hotkey":{}}"#])
    func malformedDismissConfigurationsAreRejected(value: String) {
        let data = Data("{\"clipboardAssistantDismissConfiguration\":\(value)}".utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(FeatureSettings.self, from: data)
        }
    }

    private struct DismissConfigurationPayload: Decodable {
        let clipboardAssistantDismissConfiguration: ClipboardAssistantTriggerConfiguration?
    }
}
