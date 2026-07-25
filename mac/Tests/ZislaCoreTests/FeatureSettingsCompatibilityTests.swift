import Foundation
import Testing
@testable import ZislaCore

struct FeatureSettingsCompatibilityTests {
    @Test
    func settingsMissingActivityDurationFailDecoding() {
        let data = Data(#"{"appearanceMode":"light","mediaEnabled":false,"fileShelfEnabled":true,"aiProgressEnabled":true,"downloaderEnabled":true,"updateChecksEnabled":true,"clipboardDetectionEnabled":false,"sideNoticesEnabled":true}"#.utf8)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(FeatureSettings.self, from: data)
        }
}
    @Test
    func activityNoticeDisplayDurationRoundTripsAllCases() throws {
        for duration in ActivityNoticeDisplayDuration.allCases {
            var settings = FeatureSettings.default
            settings.activityNoticeDisplayDuration = duration
            settings.activityNoticeDisplayIDs = [1, 2]

            let encoded = try JSONEncoder().encode(settings)
            let decoded = try JSONDecoder().decode(FeatureSettings.self, from: encoded)

            #expect(decoded.activityNoticeDisplayDuration == duration)
            #expect(decoded.activityNoticeDisplayIDs == [1, 2])
        }
    }

    @Test
    func systemMonitorMenuBarSelectionAndDisplayStyleDefaultForLegacySettingsAndRoundTrip() throws {
        let legacy = Data(#"{"mediaEnabled":true,"fileShelfEnabled":true,"aiProgressEnabled":true,"downloaderEnabled":true,"calendarEnabled":true,"weatherEnabled":true,"updateChecksEnabled":true,"automaticUpdatesEnabled":true,"clipboardDetectionEnabled":false,"sideNoticesEnabled":true,"hoverActivationEnabled":true,"activityNoticeDisplayDuration":"threeSeconds"}"#.utf8)
        let decodedLegacy = try JSONDecoder().decode(FeatureSettings.self, from: legacy)
        #expect(decodedLegacy.systemMonitorMenuBarMetrics == [.cpu])
        #expect(decodedLegacy.systemMonitorMenuBarDisplayStyle == .detailed)
        #expect(!decodedLegacy.menuBarAppIconEnabled)

        var settings = FeatureSettings.default
        settings.systemMonitorMenuBarMetrics = [.gpu, .memory, .fan]
        settings.systemMonitorMenuBarDisplayStyle = .compact
        settings.menuBarAppIconEnabled = true
        let decoded = try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded.systemMonitorMenuBarMetrics == [.gpu, .memory, .fan])
        #expect(decoded.systemMonitorMenuBarDisplayStyle == .compact)
        #expect(decoded.menuBarAppIconEnabled)
    }

    @Test
    func mediaSourceDefaultsForLegacySettingsAndRoundTrips() throws {
        let legacy = Data(#"{"activityNoticeDisplayDuration":"threeSeconds"}"#.utf8)
        let decodedLegacy = try JSONDecoder().decode(FeatureSettings.self, from: legacy)
        #expect(decodedLegacy.mediaSource == .automatic)

        var settings = FeatureSettings.default
        settings.mediaSource = .spotify
        let decoded = try JSONDecoder().decode(
            FeatureSettings.self,
            from: JSONEncoder().encode(settings)
        )
        #expect(decoded.mediaSource == .spotify)
        #expect(MediaSourcePreference.appleMusic.bundleIdentifier == "com.apple.Music")
        #expect(MediaSourcePreference.automatic.bundleIdentifier == nil)
    }

    @Test
    func activityNoticeDisplaySelectionUsesConnectedScreensWhenUnconfiguredOrUnavailable() {
        var settings = FeatureSettings.default
        let connected: Set<UInt32> = [1, 2]

        #expect(settings.resolvedActivityNoticeDisplayIDs(from: connected) == connected)

        settings.activityNoticeDisplayIDs = [2]
        #expect(settings.resolvedActivityNoticeDisplayIDs(from: connected) == [2])

        settings.activityNoticeDisplayIDs = [9]
        #expect(settings.resolvedActivityNoticeDisplayIDs(from: connected) == connected)
    }

    @Test
    func activityNoticeDisplayDurationExpiresAfterMatchesPresets() {
        #expect(ActivityNoticeDisplayDuration.threeSeconds.expiresAfter == 3)
        #expect(ActivityNoticeDisplayDuration.fiveSeconds.expiresAfter == 5)
        #expect(ActivityNoticeDisplayDuration.tenSeconds.expiresAfter == 10)
        #expect(ActivityNoticeDisplayDuration.thirtySeconds.expiresAfter == 30)
        #expect(ActivityNoticeDisplayDuration.always.expiresAfter == nil)
    }

    @Test
    func focusModeNoticeDisplayDurationDefaultsAndRoundTrips() throws {
        #expect(FeatureSettings.default.focusModeNoticeDisplayDuration == .threeSeconds)
        #expect(FocusModeNoticeDisplayDuration.threeSeconds.expiresAfter == 3)
        #expect(FocusModeNoticeDisplayDuration.always.expiresAfter == nil)

        var settings = FeatureSettings.default
        settings.focusModeNoticeDisplayDuration = .always
        let decoded = try JSONDecoder().decode(
            FeatureSettings.self,
            from: JSONEncoder().encode(settings)
        )
        #expect(decoded.focusModeNoticeDisplayDuration == .always)
    }

    @Test
    func toolboxEnabledDefaultsWhenMissingFromLegacyJSON() throws {
        let data = Data(#"{"mediaEnabled":false,"fileShelfEnabled":true,"aiProgressEnabled":true,"downloaderEnabled":true,"calendarEnabled":true,"weatherEnabled":true,"updateChecksEnabled":true,"automaticUpdatesEnabled":true,"clipboardDetectionEnabled":false,"sideNoticesEnabled":true,"hoverActivationEnabled":true,"activityNoticeDisplayDuration":"threeSeconds"}"#.utf8)
        let decoded = try JSONDecoder().decode(FeatureSettings.self, from: data)
        #expect(decoded.toolboxEnabled == true)
        #expect(decoded.toolboxReminderEnabled == false)
        #expect(decoded.focusCountdownIslandEnabled == true)
        #expect(decoded.focusModeNoticeDisplayDuration == .threeSeconds)
        #expect(decoded.mediaEnabled == false)
    }

    @Test
    func focusCountdownIslandDisplayRoundTrips() throws {
        var settings = FeatureSettings.default
        settings.focusCountdownIslandEnabled = false

        let decoded = try JSONDecoder().decode(
            FeatureSettings.self,
            from: JSONEncoder().encode(settings)
        )

        #expect(decoded.focusCountdownIslandEnabled == false)
    }

    @Test
    func lockScreenPresentationOptionsDefaultWhenMissingFromExistingJSON() throws {
        let data = Data(#"{"mediaEnabled":true,"fileShelfEnabled":true,"aiProgressEnabled":true,"downloaderEnabled":true,"calendarEnabled":true,"weatherEnabled":true,"lockScreenInfoEnabled":true,"quickNotesEnabled":true,"updateChecksEnabled":true,"automaticUpdatesEnabled":true,"clipboardDetectionEnabled":false,"sideNoticesEnabled":true,"hoverActivationEnabled":true,"activityNoticeDisplayDuration":"threeSeconds"}"#.utf8)

        let decoded = try JSONDecoder().decode(FeatureSettings.self, from: data)

        #expect(decoded.lockScreenMessage.isEmpty)
        #expect(decoded.lockScreenShowsLunar == true)
    }

    @Test
    func clipboardHistoryDefaultsToDisabledWhenMissingFromExistingJSON() throws {
        let data = Data(#"{"mediaEnabled":true,"fileShelfEnabled":true,"aiProgressEnabled":true,"downloaderEnabled":true,"calendarEnabled":true,"weatherEnabled":true,"updateChecksEnabled":true,"automaticUpdatesEnabled":true,"clipboardDetectionEnabled":false,"sideNoticesEnabled":true,"hoverActivationEnabled":true,"activityNoticeDisplayDuration":"threeSeconds"}"#.utf8)

        let decoded = try JSONDecoder().decode(FeatureSettings.self, from: data)

        #expect(!decoded.clipboardHistoryEnabled)
    }

    @Test
    func quickNotesEnabledDefaultsTrue() {
        #expect(FeatureSettings.default.quickNotesEnabled == true)
    }

    @Test
    func quickNotesEnabledDefaultsTrueWhenMissingFromLegacyJSON() throws {
        let data = Data(#"{"mediaEnabled":true,"fileShelfEnabled":true,"aiProgressEnabled":true,"downloaderEnabled":true,"calendarEnabled":true,"toolboxEnabled":true,"systemMonitorEnabled":true,"weatherEnabled":true,"lockScreenInfoEnabled":true,"updateChecksEnabled":true,"automaticUpdatesEnabled":true,"clipboardDetectionEnabled":false,"sideNoticesEnabled":true,"hoverActivationEnabled":true,"activityNoticeDisplayDuration":"threeSeconds","appearanceMode":"system"}"#.utf8)
        let decoded = try JSONDecoder().decode(FeatureSettings.self, from: data)
        #expect(decoded.quickNotesEnabled == true)
    }

    @Test
    func quickNotesEnabledRoundTrips() throws {
        var settings = FeatureSettings.default
        settings.quickNotesEnabled = false
        let decoded = try JSONDecoder().decode(
            FeatureSettings.self,
            from: JSONEncoder().encode(settings)
        )
        #expect(decoded.quickNotesEnabled == false)
    }


    // MARK: - VoiceInputHotkeyPreset

    @Test
    func voiceInputHotkeyPresetLegacyStringDecoding() throws {
        let cases: [(String, VoiceInputHotkeyPreset)] = [
            (#""optionSpace""#, .optionSpace),
            (#""controlSpace""#, .controlSpace),
            (#""commandShiftV""#, .commandShiftV),
        ]
        for (json, expected) in cases {
            let decoded = try JSONDecoder().decode(VoiceInputHotkeyPreset.self, from: Data(json.utf8))
            #expect(decoded == expected)
            #expect(decoded.keyCode == expected.keyCode)
            #expect(decoded.carbonModifiers == expected.carbonModifiers)
            #expect(decoded.keyDisplayName == expected.keyDisplayName)
        }
    }

    @Test
    func voiceInputHotkeyPresetStructuredRoundTrip() throws {
        let custom = VoiceInputHotkeyPreset(
            keyCode: 40,
            carbonModifiers: 0x0100 | 0x0800,
            keyDisplayName: "K"
        )
        let data = try JSONEncoder().encode(custom)
        let jsonText = String(data: data, encoding: .utf8) ?? ""
        #expect(!jsonText.contains("optionSpace"))
        #expect(jsonText.contains("\"keyCode\""))
        #expect(jsonText.contains("\"carbonModifiers\""))
        #expect(jsonText.contains("\"keyDisplayName\""))
        #expect(jsonText.contains("\"K\""))

        let decoded = try JSONDecoder().decode(VoiceInputHotkeyPreset.self, from: data)
        #expect(decoded == custom)
        #expect(decoded.keyCode == 40)
        #expect(decoded.carbonModifiers == 0x0100 | 0x0800)
        #expect(decoded.keyDisplayName == "K")
        #expect(decoded.modifierSides == nil)
        #expect(decoded.displayName == "⌥⌘ K")
    }

    @Test
    func voiceInputHotkeyPresetPreservesModifierSidesAndMatchesExactly() throws {
        let custom = VoiceInputHotkeyPreset(
            keyCode: 40,
            carbonModifiers: 0,
            keyDisplayName: "K",
            modifierSides: [.leftCommand, .rightShift]
        )

        #expect(custom.requiresInputMonitoring)
        #expect(custom.carbonModifiers == 0x0100 | 0x0200)
        #expect(custom.displayName == "左⌘ + 右⇧ + K")
        #expect(custom.matches(keyCode: 40, modifierSides: [.leftCommand, .rightShift]))
        #expect(!custom.matches(keyCode: 40, modifierSides: [.rightCommand, .rightShift]))
        #expect(!custom.matches(keyCode: 40, modifierSides: [.leftCommand]))
        #expect(!custom.matches(keyCode: 41, modifierSides: [.leftCommand, .rightShift]))

        let data = try JSONEncoder().encode(custom)
        let decoded = try JSONDecoder().decode(VoiceInputHotkeyPreset.self, from: data)
        #expect(decoded == custom)
        #expect(decoded.modifierSides == [.leftCommand, .rightShift])
    }

    @Test
    func voiceInputModifierResolvesBothSidesForOptionCommandAndShift() {
        #expect(VoiceInputModifier(keyCode: 58) == .leftOption)
        #expect(VoiceInputModifier(keyCode: 61) == .rightOption)
        #expect(VoiceInputModifier(keyCode: 55) == .leftCommand)
        #expect(VoiceInputModifier(keyCode: 54) == .rightCommand)
        #expect(VoiceInputModifier(keyCode: 56) == .leftShift)
        #expect(VoiceInputModifier(keyCode: 60) == .rightShift)
        #expect(VoiceInputModifier(keyCode: 49) == nil)
    }

    @Test
    func voiceInputHotkeyPresetSupportsSingleKeysAndStandaloneModifiers() {
        let singleKey = VoiceInputHotkeyPreset(
            keyCode: 40,
            carbonModifiers: 0,
            keyDisplayName: "K"
        )
        #expect(singleKey.displayName == "K")
        #expect(!singleKey.requiresInputMonitoring)
        #expect(!singleKey.isModifierOnly)

        let leftOption = VoiceInputHotkeyPreset(
            keyCode: VoiceInputModifier.leftOption.keyCode,
            carbonModifiers: VoiceInputModifier.leftOption.carbonModifier,
            keyDisplayName: VoiceInputModifier.leftOption.displayName,
            modifierSides: [.leftOption]
        )
        #expect(leftOption.displayName == "左⌥")
        #expect(leftOption.requiresInputMonitoring)
        #expect(leftOption.isModifierOnly)
        #expect(leftOption.matches(
            keyCode: VoiceInputModifier.leftOption.keyCode,
            modifierSides: [.leftOption]
        ))
    }

    @Test
    func voiceInputHotkeyPresetDisplayNames() {
        #expect(VoiceInputHotkeyPreset.optionSpace.displayName == "⌥ Space")
        #expect(VoiceInputHotkeyPreset.controlSpace.displayName == "⌃ Space")
        // 与旧 enum 展示契约一致：⌘⇧ V
        #expect(VoiceInputHotkeyPreset.commandShiftV.displayName == "⌘⇧ V")
        #expect(VoiceInputHotkeyPreset.modifierSymbols(carbonModifiers: 0x0100 | 0x0200) == "⌘⇧")
    }

    @Test
    func voiceInputHotkeyPresetLegacyInsideFeatureSettings() throws {
        // 与其它兼容性测试相同：旧配置仅含必填字段 + 单字符串快捷键预设
        let json = Data(#"""
        {"mediaEnabled":true,"fileShelfEnabled":true,"aiProgressEnabled":true,"downloaderEnabled":true,"calendarEnabled":true,"weatherEnabled":true,"updateChecksEnabled":true,"automaticUpdatesEnabled":true,"clipboardDetectionEnabled":false,"sideNoticesEnabled":true,"hoverActivationEnabled":true,"activityNoticeDisplayDuration":"threeSeconds","voiceInputHotkeyPreset":"controlSpace"}
        """#.utf8)
        let decoded = try JSONDecoder().decode(FeatureSettings.self, from: json)
        #expect(decoded.voiceInputHotkeyPreset == .controlSpace)
        #expect(decoded.voiceInputHotkeyPreset.displayName == "⌃ Space")
    }
}
