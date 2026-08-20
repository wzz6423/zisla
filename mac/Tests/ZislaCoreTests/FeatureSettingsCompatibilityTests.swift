import Foundation
import Testing
@testable import ZislaCore

struct FeatureSettingsCompatibilityTests {
    @Test
    func aiProgressDefaultsEnabledForNewAndLegacySettings() throws {
        #expect(FeatureSettings.default.aiProgressEnabled)

        let legacy = Data(#"{"activityNoticeDisplayDuration":"threeSeconds"}"#.utf8)
        let decoded = try JSONDecoder().decode(FeatureSettings.self, from: legacy)
        #expect(decoded.aiProgressEnabled)
    }

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
        #expect(FeatureSettings.default.systemMonitorMenuBarMetrics == [.cpu])
        #expect(FeatureSettings.default.systemMonitorMenuBarDisplayStyle == .compact)

        let legacy = Data(#"{"mediaEnabled":true,"fileShelfEnabled":true,"aiProgressEnabled":true,"downloaderEnabled":true,"calendarEnabled":true,"weatherEnabled":true,"updateChecksEnabled":true,"automaticUpdatesEnabled":true,"clipboardDetectionEnabled":false,"sideNoticesEnabled":true,"hoverActivationEnabled":true,"activityNoticeDisplayDuration":"threeSeconds"}"#.utf8)
        let decodedLegacy = try JSONDecoder().decode(FeatureSettings.self, from: legacy)
        #expect(decodedLegacy.systemMonitorMenuBarMetrics == [.cpu])
        #expect(decodedLegacy.systemMonitorMenuBarDisplayStyle == .compact)
        #expect(!decodedLegacy.menuBarAppIconEnabled)

        var settings = FeatureSettings.default
        settings.systemMonitorMenuBarMetrics = [.gpu, .memory, .fan]
        settings.systemMonitorMenuBarDisplayStyle = .detailed
        settings.menuBarAppIconEnabled = true
        let decoded = try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded.systemMonitorMenuBarMetrics == [.gpu, .memory, .fan])
        #expect(decoded.systemMonitorMenuBarDisplayStyle == .detailed)
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
    func mediaCompactStyleDefaultsForLegacySettingsAndRoundTrips() throws {
        let legacy = Data(#"{"activityNoticeDisplayDuration":"threeSeconds"}"#.utf8)
        let decodedLegacy = try JSONDecoder().decode(FeatureSettings.self, from: legacy)
        #expect(decodedLegacy.mediaCompactStyle == .compact)

        var settings = FeatureSettings.default
        settings.mediaCompactStyle = .detailed
        let decoded = try JSONDecoder().decode(
            FeatureSettings.self,
            from: JSONEncoder().encode(settings)
        )
        #expect(decoded.mediaCompactStyle == .detailed)
    }

    @Test
    func updateChannelDefaultsForLegacySettingsAndRoundTrips() throws {
        let legacy = Data(#"{"activityNoticeDisplayDuration":"threeSeconds"}"#.utf8)
        let decodedLegacy = try JSONDecoder().decode(FeatureSettings.self, from: legacy)
        #expect(decodedLegacy.updateChannel == .release)

        var settings = FeatureSettings.default
        settings.updateChannel = .preview
        let decoded = try JSONDecoder().decode(
            FeatureSettings.self,
            from: JSONEncoder().encode(settings)
        )
        #expect(decoded.updateChannel == .preview)
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
        #expect(decoded.toolboxReminderEnabled == true)
        #expect(decoded.focusCountdownIslandEnabled == true)
        #expect(decoded.focusModeNoticeDisplayDuration == .threeSeconds)
        #expect(decoded.mediaEnabled == false)
    }

    @Test
    func islandZOrderAndNotificationMuteDefaultWhenMissingFromLegacyJSON() throws {
        let data = Data(#"{"mediaEnabled":true,"fileShelfEnabled":true,"aiProgressEnabled":true,"downloaderEnabled":true,"calendarEnabled":true,"toolboxEnabled":true,"weatherEnabled":true,"updateChecksEnabled":true,"automaticUpdatesEnabled":true,"clipboardDetectionEnabled":false,"sideNoticesEnabled":true,"hoverActivationEnabled":true,"activityNoticeDisplayDuration":"threeSeconds"}"#.utf8)
        let decoded = try JSONDecoder().decode(FeatureSettings.self, from: data)
        // Legacy configs lack these keys: collapsed island defaults to on-top; notifications default unmuted.
        #expect(decoded.islandCollapsedOnTop == true)
        #expect(decoded.notificationsMuted == false)
    }

    @Test
    func islandZOrderAndNotificationMuteRoundTrip() throws {
        var settings = FeatureSettings.default
        settings.islandCollapsedOnTop = false
        settings.notificationsMuted = true

        let decoded = try JSONDecoder().decode(
            FeatureSettings.self,
            from: JSONEncoder().encode(settings)
        )
        #expect(decoded.islandCollapsedOnTop == false)
        #expect(decoded.notificationsMuted == true)
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
    func browserDownloadIslandDisplayRoundTripsAndDefaultsOnForLegacyJSON() throws {
        var settings = FeatureSettings.default
        #expect(settings.browserDownloadIslandEnabled == true)
        settings.browserDownloadIslandEnabled = false

        let decoded = try JSONDecoder().decode(
            FeatureSettings.self,
            from: JSONEncoder().encode(settings)
        )
        #expect(decoded.browserDownloadIslandEnabled == false)

        let legacy = Data(#"{"mediaEnabled":true,"fileShelfEnabled":true,"aiProgressEnabled":true,"downloaderEnabled":true,"calendarEnabled":true,"weatherEnabled":true,"updateChecksEnabled":true,"automaticUpdatesEnabled":true,"clipboardDetectionEnabled":false,"sideNoticesEnabled":true,"hoverActivationEnabled":true,"activityNoticeDisplayDuration":"threeSeconds"}"#.utf8)
        let legacyDecoded = try JSONDecoder().decode(FeatureSettings.self, from: legacy)
        #expect(legacyDecoded.browserDownloadIslandEnabled == true)
    }

    @Test
    func videoDownloadIslandDisplayRoundTripsAndDefaultsOnForLegacyJSON() throws {
        var settings = FeatureSettings.default
        #expect(settings.videoDownloadIslandEnabled == true)
        settings.videoDownloadIslandEnabled = false

        let decoded = try JSONDecoder().decode(
            FeatureSettings.self,
            from: JSONEncoder().encode(settings)
        )
        #expect(decoded.videoDownloadIslandEnabled == false)

        let legacy = Data(#"{"mediaEnabled":true,"fileShelfEnabled":true,"aiProgressEnabled":true,"downloaderEnabled":true,"calendarEnabled":true,"weatherEnabled":true,"updateChecksEnabled":true,"automaticUpdatesEnabled":true,"clipboardDetectionEnabled":false,"sideNoticesEnabled":true,"hoverActivationEnabled":true,"activityNoticeDisplayDuration":"threeSeconds"}"#.utf8)
        let legacyDecoded = try JSONDecoder().decode(FeatureSettings.self, from: legacy)
        #expect(legacyDecoded.videoDownloadIslandEnabled == true)
    }

    @Test
    func lockScreenPresentationOptionsDefaultWhenMissingFromExistingJSON() throws {
        let data = Data(#"{"mediaEnabled":true,"fileShelfEnabled":true,"aiProgressEnabled":true,"downloaderEnabled":true,"calendarEnabled":true,"weatherEnabled":true,"lockScreenInfoEnabled":true,"quickNotesEnabled":true,"updateChecksEnabled":true,"automaticUpdatesEnabled":true,"clipboardDetectionEnabled":false,"sideNoticesEnabled":true,"hoverActivationEnabled":true,"activityNoticeDisplayDuration":"threeSeconds"}"#.utf8)

        let decoded = try JSONDecoder().decode(FeatureSettings.self, from: data)

        #expect(decoded.lockScreenMessage.isEmpty)
        #expect(decoded.lockScreenShowsLunar == true)
    }

    @Test
    func clipboardHistoryDefaultsToEnabledWhenMissingFromExistingJSON() throws {
        let data = Data(#"{"mediaEnabled":true,"fileShelfEnabled":true,"aiProgressEnabled":true,"downloaderEnabled":true,"calendarEnabled":true,"weatherEnabled":true,"updateChecksEnabled":true,"automaticUpdatesEnabled":true,"clipboardDetectionEnabled":false,"sideNoticesEnabled":true,"hoverActivationEnabled":true,"activityNoticeDisplayDuration":"threeSeconds"}"#.utf8)

        let decoded = try JSONDecoder().decode(FeatureSettings.self, from: data)

        #expect(decoded.clipboardHistoryEnabled)
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


    @Test
    func voiceRecordingRetentionDefaultsAndRoundTrips() throws {
        let legacy = Data(#"{"activityNoticeDisplayDuration":"threeSeconds"}"#.utf8)
        let legacySettings = try JSONDecoder().decode(FeatureSettings.self, from: legacy)
        #expect(legacySettings.voiceRecordingRetentionEnabled)
        #expect(legacySettings.voiceRecordingCleanupPolicy == .never)
        #expect(VoiceRecordingCleanupPolicy.allCases == [
            .sevenDays,
            .fifteenDays,
            .thirtyDays,
            .never,
        ])

        for policy in VoiceRecordingCleanupPolicy.allCases {
            var settings = FeatureSettings.default
            settings.voiceRecordingRetentionEnabled = false
            settings.voiceRecordingCleanupPolicy = policy

            let decoded = try JSONDecoder().decode(
                FeatureSettings.self,
                from: JSONEncoder().encode(settings)
            )

            #expect(!decoded.voiceRecordingRetentionEnabled)
            #expect(decoded.voiceRecordingCleanupPolicy == policy)
        }
    }

    @Test
    func voiceLexiconSelectionDefaultsForLegacySettingsAndRoundTrips() throws {
        #expect(FeatureSettings.default.voiceEnabledLexicons == VoiceLexicon.defaultEnabled)
        let terms = VoiceLexicon.terms(for: VoiceLexicon.defaultEnabled)
        let representativeTerms = [
            "SwiftUI", "床前明月光", "YYDS", "北京", "Apple", "新冠", "民法典", "股票", "高等数学",
            "电影", "英雄联盟", "高铁", "外卖"
        ]
        for term in representativeTerms {
            #expect(terms.contains(term))
        }
        #expect(Set(terms).count == terms.count)

        let contextualTerms = VoiceLexicon.contextualTerms(for: VoiceLexicon.defaultEnabled)
        #expect(contextualTerms.count <= VoiceLexicon.maximumContextualTerms)
        for term in ["人工智能", "唐诗", "YYDS", "北京", "Apple", "新冠", "民法典", "股票", "高等数学", "电影", "英雄联盟", "高铁", "外卖"] {
            #expect(contextualTerms.contains(term))
        }
        #expect(Set(contextualTerms).count == contextualTerms.count)

        for lexicon in VoiceLexicon.allCases {
            #expect(!lexicon.terms.isEmpty)
            #expect(Set(lexicon.terms).count == lexicon.terms.count)
            #expect(!lexicon.title.isEmpty)
            #expect(!lexicon.detail.isEmpty)
        }

        let legacy = Data(#"{"activityNoticeDisplayDuration":"threeSeconds"}"#.utf8)
        let legacySettings = try JSONDecoder().decode(FeatureSettings.self, from: legacy)
        #expect(legacySettings.voiceEnabledLexicons == VoiceLexicon.defaultEnabled)

        var settings = FeatureSettings.default
        settings.voiceEnabledLexicons = [.computerTerms, .internetBuzzwords]
        let decoded = try JSONDecoder().decode(
            FeatureSettings.self,
            from: JSONEncoder().encode(settings)
        )
        #expect(decoded.voiceEnabledLexicons == [.computerTerms, .internetBuzzwords])
    }

    @Test
    func voiceStructuredFormattingDefaultsToFalseForLegacySettings() throws {
        #expect(FeatureSettings.default.voiceStructuredFormattingEnabled == false)

        let legacy = Data(#"{"activityNoticeDisplayDuration":"threeSeconds"}"#.utf8)
        let legacySettings = try JSONDecoder().decode(FeatureSettings.self, from: legacy)
        #expect(legacySettings.voiceStructuredFormattingEnabled == false)
    }

    @Test
    func voiceStructuredFormattingRoundTrips() throws {
        var settings = FeatureSettings.default
        settings.voiceStructuredFormattingEnabled = true

        let decoded = try JSONDecoder().decode(
            FeatureSettings.self,
            from: JSONEncoder().encode(settings)
        )

        #expect(decoded.voiceStructuredFormattingEnabled == true)
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
    func voiceInputHotkeyPresetUsesCarbonForModifierKeyCombinations() throws {
        let custom = VoiceInputHotkeyPreset(
            keyCode: 40,
            carbonModifiers: 0,
            keyDisplayName: "K",
            modifierSides: [.leftCommand, .rightShift]
        )

        #expect(!custom.requiresInputMonitoring)
        #expect(custom.carbonModifiers == 0x0100 | 0x0200)
        #expect(custom.displayName == "⌘⇧ K")
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
        // Matches the legacy enum display contract: ⌘⇧ V
        #expect(VoiceInputHotkeyPreset.commandShiftV.displayName == "⌘⇧ V")
        #expect(VoiceInputHotkeyPreset.modifierSymbols(carbonModifiers: 0x0100 | 0x0200) == "⌘⇧")
    }

    @Test
    func hotkeyConflictUsesRegistrationIdentity() {
        let generic = VoiceInputHotkeyPreset(
            keyCode: 40,
            carbonModifiers: 0x0100,
            keyDisplayName: "K"
        )
        let sideAware = VoiceInputHotkeyPreset(
            keyCode: 40,
            carbonModifiers: 0,
            keyDisplayName: "K",
            modifierSides: [.leftCommand]
        )
        let differentKey = VoiceInputHotkeyPreset(
            keyCode: 41,
            carbonModifiers: 0x0100,
            keyDisplayName: "L"
        )

        #expect(generic.conflicts(with: sideAware))
        #expect(!generic.conflicts(with: differentKey))
    }

    @Test
    func voiceInputHotkeyPresetLegacyInsideFeatureSettings() throws {
        // Same as other compatibility tests: legacy config has required fields + a single-string hotkey preset only
        let json = Data(#"""
        {"mediaEnabled":true,"fileShelfEnabled":true,"aiProgressEnabled":true,"downloaderEnabled":true,"calendarEnabled":true,"weatherEnabled":true,"updateChecksEnabled":true,"automaticUpdatesEnabled":true,"clipboardDetectionEnabled":false,"sideNoticesEnabled":true,"hoverActivationEnabled":true,"activityNoticeDisplayDuration":"threeSeconds","voiceInputHotkeyPreset":"controlSpace"}
        """#.utf8)
        let decoded = try JSONDecoder().decode(FeatureSettings.self, from: json)
        #expect(decoded.voiceInputHotkeyPreset == .controlSpace)
        #expect(decoded.voiceInputHotkeyPreset.displayName == "⌃ Space")
    }

    // MARK: - Island Appearance

    @Test
    func islandAppearanceDefaultsToBlackBackgroundWithLiquidGlass() throws {
        #expect(FeatureSettings.default.islandVisualStyle == .transparent)
        #expect(FeatureSettings.default.islandNotchBackground == .black)
        #expect(IslandVisualStyle.frosted.title == "磨砂玻璃")
        #expect(IslandVisualStyle.transparent.title == "Liquid Glass")
        #expect(IslandNotchBackground.black.title == "刘海")
        #expect(IslandNotchBackground.frosted.title == "磨砂玻璃")

        let legacy = Data(#"{"activityNoticeDisplayDuration":"threeSeconds"}"#.utf8)
        let decodedLegacy = try JSONDecoder().decode(FeatureSettings.self, from: legacy)
        #expect(decodedLegacy.islandVisualStyle == .transparent)
        #expect(decodedLegacy.islandNotchBackground == .black)
    }

    @Test
    func islandVisualStyleRoundTrips() throws {
        var settings = FeatureSettings.default
        settings.islandVisualStyle = .transparent
        let decoded = try JSONDecoder().decode(
            FeatureSettings.self,
            from: JSONEncoder().encode(settings)
        )
        #expect(decoded.islandVisualStyle == .transparent)

        settings.islandVisualStyle = .frosted
        let decodedFrosted = try JSONDecoder().decode(
            FeatureSettings.self,
            from: JSONEncoder().encode(settings)
        )
        #expect(decodedFrosted.islandVisualStyle == .frosted)
    }

    @Test
    func islandNotchBackgroundRoundTrips() throws {
        for background in IslandNotchBackground.allCases {
            var settings = FeatureSettings.default
            settings.islandNotchBackground = background

            let decoded = try JSONDecoder().decode(
                FeatureSettings.self,
                from: JSONEncoder().encode(settings)
            )

            #expect(decoded.islandNotchBackground == background)
        }
    }

    @Test
    func removedLiquidGlassNotchBackgroundMigratesToFrosted() throws {
        let legacy = Data(#""liquidGlass""#.utf8)

        let decoded = try JSONDecoder().decode(IslandNotchBackground.self, from: legacy)

        #expect(decoded == .frosted)
    }

    @Test
    func compactStatusPriorityDefaultsForLegacySettings() throws {
        let legacy = Data(#"{"activityNoticeDisplayDuration":"threeSeconds"}"#.utf8)

        let decoded = try JSONDecoder().decode(FeatureSettings.self, from: legacy)

        #expect(decoded.compactStatusPriority == CompactStatusPriority.defaultOrder)
    }

    @Test
    func compactStatusPriorityRoundTripsCustomOrder() throws {
        var settings = FeatureSettings.default
        settings.compactStatusPriority = [
            .media,
            .aiActivity,
            .focusMode,
            .transient,
            .updateAvailable,
            .mail,
            .videoDownload,
            .browserDownload,
            .focusCountdown,
            .toolboxReminder,
        ]

        let decoded = try JSONDecoder().decode(
            FeatureSettings.self,
            from: JSONEncoder().encode(settings)
        )

        #expect(decoded.compactStatusPriority == settings.compactStatusPriority)
    }

    @Test
    func compactStatusPriorityDeduplicatesAndAppendsMissingValues() throws {
        let data = Data(#"""
        {"activityNoticeDisplayDuration":"threeSeconds","compactStatusPriority":["media","transient","media","aiActivity"]}
        """#.utf8)

        let decoded = try JSONDecoder().decode(FeatureSettings.self, from: data)

        #expect(decoded.compactStatusPriority == [
            .media,
            .transient,
            .aiActivity,
            .videoDownload,
            .browserDownload,
            .mail,
            .updateAvailable,
            .focusCountdown,
            .focusMode,
            .toolboxReminder,
        ])
    }

    @Test
    func screenshotHotkeysDefaultToCtrl1AndCtrl2ForLegacySettings() throws {
        let legacy = Data(#"{"activityNoticeDisplayDuration":"threeSeconds"}"#.utf8)
        let decoded = try JSONDecoder().decode(FeatureSettings.self, from: legacy)

        #expect(decoded.screenshotEnabled)
        #expect(decoded.screenshotHotkey.keyCode == 18)
        #expect(decoded.screenshotHotkey.carbonModifiers == 0x1000)
        #expect(decoded.screenshotHotkey.keyDisplayName == "1")

        #expect(decoded.screenshotPinHotkey.keyCode == 19)
        #expect(decoded.screenshotPinHotkey.carbonModifiers == 0x1000)
        #expect(decoded.screenshotPinHotkey.keyDisplayName == "2")
        #expect(decoded.screenshotHotkey == ScreenshotHotkeyDefaults.capture)
        #expect(decoded.screenshotPinHotkey == ScreenshotHotkeyDefaults.pin)
    }

    @Test
    func screenshotEnabledRoundTripsWithoutChangingCustomizedHotkeys() throws {
        var settings = FeatureSettings.default
        settings.screenshotEnabled = false
        settings.screenshotHotkey = VoiceInputHotkeyPreset(
            keyCode: 45,
            carbonModifiers: 0x0800,
            keyDisplayName: "N"
        )
        settings.screenshotPinHotkey = VoiceInputHotkeyPreset(
            keyCode: 46,
            carbonModifiers: 0x0800,
            keyDisplayName: "M"
        )

        let decoded = try JSONDecoder().decode(
            FeatureSettings.self,
            from: JSONEncoder().encode(settings)
        )

        #expect(!decoded.screenshotEnabled)
        #expect(decoded.screenshotHotkey == settings.screenshotHotkey)
        #expect(decoded.screenshotPinHotkey == settings.screenshotPinHotkey)
    }

    @Test
    func screenshotHotkeysRoundTrip() throws {
        var settings = FeatureSettings.default
        settings.screenshotHotkey = VoiceInputHotkeyPreset(
            keyCode: 45,
            carbonModifiers: 0x0800,
            keyDisplayName: "N"
        )
        settings.screenshotPinHotkey = VoiceInputHotkeyPreset(
            keyCode: 46,
            carbonModifiers: 0x0800,
            keyDisplayName: "M"
        )

        let decoded = try JSONDecoder().decode(
            FeatureSettings.self,
            from: JSONEncoder().encode(settings)
        )

        #expect(decoded.screenshotHotkey.keyCode == 45)
        #expect(decoded.screenshotHotkey.carbonModifiers == 0x0800)
        #expect(decoded.screenshotHotkey.keyDisplayName == "N")

        #expect(decoded.screenshotPinHotkey.keyCode == 46)
        #expect(decoded.screenshotPinHotkey.carbonModifiers == 0x0800)
        #expect(decoded.screenshotPinHotkey.keyDisplayName == "M")
    }

    @Test
    func screenshotPinnedToolbarVisibilityDefaultsOnForLegacySettingsAndRoundTrips() throws {
        #expect(FeatureSettings.default.screenshotPinnedToolbarVisible)

        let legacy = Data(#"{"activityNoticeDisplayDuration":"threeSeconds"}"#.utf8)
        let legacyDecoded = try JSONDecoder().decode(FeatureSettings.self, from: legacy)
        #expect(legacyDecoded.screenshotPinnedToolbarVisible)

        var settings = FeatureSettings.default
        settings.screenshotPinnedToolbarVisible = false
        let decoded = try JSONDecoder().decode(
            FeatureSettings.self,
            from: JSONEncoder().encode(settings)
        )
        #expect(!decoded.screenshotPinnedToolbarVisible)
    }

    @Test
    func backgroundSoundSettingsDefaultForLegacyConfigurationAndRoundTrip() throws {
        let legacy = Data(#"{"activityNoticeDisplayDuration":"threeSeconds"}"#.utf8)
        let legacySettings = try JSONDecoder().decode(FeatureSettings.self, from: legacy)
        #expect(!legacySettings.systemBackgroundSoundEnabled)
        #expect(legacySettings.systemBackgroundSound == .rain)
        #expect(legacySettings.systemBackgroundSoundStopsWhenUnused)

        var settings = FeatureSettings.default
        settings.systemBackgroundSoundEnabled = true
        settings.systemBackgroundSound = .ocean
        settings.systemBackgroundSoundStopsWhenUnused = false
        let decoded = try JSONDecoder().decode(
            FeatureSettings.self,
            from: JSONEncoder().encode(settings)
        )
        #expect(decoded.systemBackgroundSoundEnabled)
        #expect(decoded.systemBackgroundSound == .ocean)
        #expect(!decoded.systemBackgroundSoundStopsWhenUnused)
    }

    @Test
    func backgroundSoundNamesRemainCompatibleAcrossMacOSVersions() throws {
        let legacy = Data(#"{"activityNoticeDisplayDuration":"threeSeconds","systemBackgroundSound":"BalancedNoise"}"#.utf8)
        let legacySettings = try JSONDecoder().decode(FeatureSettings.self, from: legacy)
        #expect(legacySettings.systemBackgroundSound == .balancedNoise)

        var settings = FeatureSettings.default
        settings.systemBackgroundSound = .pinkNoise
        let decoded = try JSONDecoder().decode(
            FeatureSettings.self,
            from: JSONEncoder().encode(settings)
        )
        #expect(decoded.systemBackgroundSound == .pinkNoise)
    }
}
