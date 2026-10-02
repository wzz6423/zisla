import Foundation
import Testing
@testable import ZislaCore

struct SystemMonitorMenuBarLayoutTests {
    @Test
    func bothModesCanBePersistedWithoutAnotherSettingsField() throws {
        let settings = try JSONDecoder().decode(
            FeatureSettings.self,
            from: Data(#"{"systemMonitorMenuBarLayout":"both"}"#.utf8)
        )
        #expect(settings.systemMonitorMenuBarLayout.rawValue == "both")
        #expect(settings.systemMonitorMenuBarLayout.individualEnabled)
        #expect(settings.systemMonitorMenuBarLayout.stackedEnabled)
    }

    @Test
    func bothModesCanBeDisabledWithoutClearingSelections() throws {
        let settings = try JSONDecoder().decode(
            FeatureSettings.self,
            from: Data(#"{"systemMonitorMenuBarLayout":"none","systemMonitorMenuBarMetrics":["gpu","fan"],"systemMonitorMenuBarTopRow":["network","cpu"],"systemMonitorMenuBarBottomRow":["fan","memory"],"systemMonitorMenuBarCombinedIconEnabled":true}"#.utf8)
        )
        #expect(settings.systemMonitorMenuBarLayout.rawValue == "none")
        #expect(!settings.systemMonitorMenuBarLayout.individualEnabled)
        #expect(!settings.systemMonitorMenuBarLayout.stackedEnabled)
        #expect(settings.systemMonitorMenuBarMetrics == [.gpu, .fan])
        #expect(settings.systemMonitorMenuBarTopRow == [.network, .cpu])
        #expect(settings.systemMonitorMenuBarBottomRow == [.fan, .memory])
        #expect(settings.systemMonitorMenuBarCombinedIconEnabled)
    }

    @Test
    func flagsDescribeAllFourStates() {
        for (layout, individual, stacked) in Self.states {
            #expect(layout.individualEnabled == individual)
            #expect(layout.stackedEnabled == stacked)
        }
    }

    @Test
    func changingOneFlagPreservesTheOtherAndIsIdempotent() {
        for (original, individual, stacked) in Self.states {
            for enabled in [false, true] {
                var layout = original
                layout.individualEnabled = enabled
                #expect(layout.individualEnabled == enabled)
                #expect(layout.stackedEnabled == stacked)
                let afterIndividualChange = layout
                layout.individualEnabled = enabled
                #expect(layout == afterIndividualChange)

                layout = original
                layout.stackedEnabled = enabled
                #expect(layout.stackedEnabled == enabled)
                #expect(layout.individualEnabled == individual)
                let afterStackedChange = layout
                layout.stackedEnabled = enabled
                #expect(layout == afterStackedChange)
            }
        }
    }

    @Test
    func everyStateIsReachableInEitherSwitchOrder() {
        for original in SystemMonitorMenuBarLayout.allCases {
            for (expected, individual, stacked) in Self.states {
                var layout = original
                layout.individualEnabled = individual
                layout.stackedEnabled = stacked
                #expect(layout == expected)
                layout = original
                layout.stackedEnabled = stacked
                layout.individualEnabled = individual
                #expect(layout == expected)
            }
        }
    }

    @Test
    func repeatedSwitchingPreservesAllOtherSettingsAndSelections() {
        var settings = FeatureSettings.default
        settings.systemMonitorEnabled = true
        settings.systemMonitorMenuBarMetrics = [.gpu, .network, .fan]
        settings.systemMonitorMenuBarTopRow = [.network, .cpu]
        settings.systemMonitorMenuBarBottomRow = [.fan, .memory]
        settings.systemMonitorMenuBarCombinedIconEnabled = true
        settings.systemMonitorMenuBarCombinedIconMetric = .brightness
        let original = settings
        for _ in 0..<32 {
            for (expected, individual, stacked) in Self.states {
                settings.systemMonitorMenuBarLayout.individualEnabled = individual
                settings.systemMonitorMenuBarLayout.stackedEnabled = stacked
                #expect(settings.systemMonitorMenuBarLayout == expected)
                var withoutModeChange = settings
                withoutModeChange.systemMonitorMenuBarLayout = original.systemMonitorMenuBarLayout
                #expect(withoutModeChange == original)
            }
        }
    }

    @Test
    func legacyMissingNullAndRawValuesKeepTheirOriginalModes() throws {
        for (payload, expected) in [
            ("{}", SystemMonitorMenuBarLayout.individual),
            (#"{"systemMonitorMenuBarLayout":null}"#, .individual),
            (#"{"systemMonitorMenuBarLayout":"individual"}"#, .individual),
            (#"{"systemMonitorMenuBarLayout":"stacked"}"#, .stacked),
        ] {
            let settings = try JSONDecoder().decode(FeatureSettings.self, from: Data(payload.utf8))
            #expect(settings.systemMonitorMenuBarLayout == expected)
            #expect(settings.systemMonitorMenuBarLayout.individualEnabled == (expected == .individual))
            #expect(settings.systemMonitorMenuBarLayout.stackedEnabled == (expected == .stacked))
        }
        #expect(FeatureSettings.default.systemMonitorMenuBarLayout == .individual)
    }

    @Test
    func allFourLayoutsRoundTripUsingOnlyTheExistingPersistenceKey() throws {
        let originalData = try JSONEncoder().encode(FeatureSettings.default)
        let originalPayload = try #require(JSONSerialization.jsonObject(with: originalData) as? [String: Any])
        for (layout, individual, stacked) in Self.states {
            let settings = FeatureSettings(
                systemMonitorMenuBarMetrics: [.gpu, .fan],
                systemMonitorMenuBarLayout: layout,
                systemMonitorMenuBarTopRow: [.network, .cpu],
                systemMonitorMenuBarBottomRow: [.fan, .memory],
                systemMonitorMenuBarCombinedIconEnabled: true,
                systemMonitorMenuBarCombinedIconMetric: .volume
            )
            let data = try JSONEncoder().encode(settings)
            let payload = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(Set(payload.keys) == Set(originalPayload.keys))
            #expect(payload["systemMonitorMenuBarLayout"] as? String == layout.rawValue)
            let restored = try JSONDecoder().decode(FeatureSettings.self, from: data)
            #expect(restored == settings)
            #expect(restored.systemMonitorMenuBarLayout.individualEnabled == individual)
            #expect(restored.systemMonitorMenuBarLayout.stackedEnabled == stacked)
            #expect(restored.systemMonitorMenuBarCombinedIconEnabled)
        }
    }

    @Test
    func bothModeTitleIsTranslatedInEveryLanguage() throws {
        #expect(AppLanguage.allCases.count == 17)
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/Localization")
        let key = SystemMonitorMenuBarLayout.both.menuTitle
        for language in AppLanguage.allCases {
            let url = root.appendingPathComponent("\(language.rawValue).lproj/Localizable.strings")
            let table = try #require(NSDictionary(contentsOf: url) as? [String: String])
            let translated = try #require(table[key], "Missing both title for \(language.rawValue)")
            #expect(!translated.isEmpty)
            #expect(AppLocalization.string(key, language: language) == translated)
            if language != .simplifiedChinese {
                #expect(translated != key)
            }
        }
        #expect(AppLocalization.string(key, language: .english) == "Separate and Merged")
        #expect(SystemMonitorMenuBarLayout.none.menuTitle == "无")
    }

    private static let states: [(SystemMonitorMenuBarLayout, Bool, Bool)] = [
        (.individual, true, false),
        (.stacked, false, true),
        (.both, true, true),
        (.none, false, false),
    ]
}
