import Foundation
import Testing
@testable import ZislaCore

struct StatusIconDestinationSettingsTests {
    @Test
    func moreInformationDefaultsOnAndMalformedValuesPreserveOtherSettings() throws {
        let original = FeatureSettings(mediaEnabled: false, systemMonitorEnabled: false,
            statusIconDestination: .island)
        #expect(FeatureSettings.default.islandShowMoreInformation)
        var payload = try encoded(original)
        payload.removeValue(forKey: "islandShowMoreInformation")
        #expect(try JSONDecoder().decode(FeatureSettings.self,
            from: JSONSerialization.data(withJSONObject: payload)) == original)
        let invalidValues: [Any] = [NSNull(), "true", 1, [String](), [String: String]()]
        for value in invalidValues {
            payload["islandShowMoreInformation"] = value
            #expect(try JSONDecoder().decode(FeatureSettings.self,
                from: JSONSerialization.data(withJSONObject: payload)) == original)
        }
        var disabled = original
        disabled.islandShowMoreInformation = false
        #expect(try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(disabled)) == disabled)
    }

    @Test
    func legacyAndNullDestinationsPreferTheIslandWhenSupported() throws {
        for json in ["{}", #"{"statusIconDestination":null}"#] {
            let settings = try JSONDecoder().decode(FeatureSettings.self, from: Data(json.utf8))
            let destination = try encoded(settings)["statusIconDestination"] as? String
            #expect(destination == "island")
            #expect(settings.effectiveStatusIconDestination == .menuBar)
            #expect(settings == FeatureSettings.default)
        }
    }

    @Test
    func bothDestinationsRoundTripWithoutChangingEnabledIconsOrTheirAppearance() throws {
        let original = FeatureSettings(
            systemMonitorEnabled: true,
            systemMonitorMenuBarMetrics: Set(SystemMonitorMenuBarMetric.allCases),
            systemMonitorMenuBarDisplayStyle: .detailed,
            systemMonitorMenuBarLayout: .both,
            systemMonitorMenuBarTopRow: [.cpu, .gpu],
            systemMonitorMenuBarBottomRow: [.memory, .disk],
            systemMonitorMenuBarCombinedIconEnabled: true,
            systemMonitorMenuBarCombinedIconMetric: .volume,
            systemMonitorMenuBarCombinedIconAppearance: SystemMonitorCombinedIconAppearance(iconSize: 36),
            systemMonitorMenuBarHeadphoneOptions: SystemMonitorHeadphoneOptions(replacesNetworkIcon: true),
            menuBarAppIconEnabled: true
        )
        for destination in ["menuBar", "island"] {
            var payload = try encoded(original)
            payload["statusIconDestination"] = destination
            let settings = try JSONDecoder().decode(FeatureSettings.self, from: JSONSerialization.data(withJSONObject: payload))
            let restoredDestination = try encoded(settings)["statusIconDestination"] as? String
            #expect(restoredDestination == destination)
            #expect(settings.systemMonitorEnabled == original.systemMonitorEnabled)
            #expect(settings.menuBarAppIconEnabled == original.menuBarAppIconEnabled)
            #expect(settings.systemMonitorMenuBarMetrics == original.systemMonitorMenuBarMetrics)
            #expect(settings.systemMonitorMenuBarLayout == original.systemMonitorMenuBarLayout)
            #expect(settings.systemMonitorMenuBarTopRow == original.systemMonitorMenuBarTopRow)
            #expect(settings.systemMonitorMenuBarBottomRow == original.systemMonitorMenuBarBottomRow)
            #expect(settings.systemMonitorMenuBarDisplayStyle == original.systemMonitorMenuBarDisplayStyle)
            #expect(settings.systemMonitorMenuBarCombinedIconEnabled == original.systemMonitorMenuBarCombinedIconEnabled)
            #expect(settings.systemMonitorMenuBarCombinedIconMetric == original.systemMonitorMenuBarCombinedIconMetric)
            #expect(settings.systemMonitorMenuBarCombinedIconAppearance == original.systemMonitorMenuBarCombinedIconAppearance)
            #expect(settings.systemMonitorMenuBarHeadphoneOptions == original.systemMonitorMenuBarHeadphoneOptions)
            let restored = try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(settings))
            #expect(restored == settings)
        }
    }

    @Test
    func invalidDestinationsUseTheDefaultWithoutResettingOtherSettings() throws {
        var original = FeatureSettings.default
        original.mediaEnabled = false
        original.systemMonitorEnabled = false
        original.menuBarAppIconEnabled = false
        original.systemMonitorMenuBarMetrics = [.memory, .fan]
        original.systemMonitorMenuBarLayout = .none
        original.systemMonitorMenuBarCombinedIconAppearance.iconSize = 36
        let invalidValues: [Any] = ["unknown", true, 0, [String](), [String: String]()]
        for invalid in invalidValues {
            var payload = try encoded(original)
            payload["statusIconDestination"] = invalid
            let settings = try JSONDecoder().decode(FeatureSettings.self, from: JSONSerialization.data(withJSONObject: payload))
            let destination = try encoded(settings)["statusIconDestination"] as? String
            #expect(destination == "island")
            #expect(settings == original)
        }
    }

    @Test
    func onlyCustomPillsCanUseIslandIconsWithoutDiscardingTheSavedChoice() {
        var settings = FeatureSettings.default
        #expect(settings.statusIconDestination == .island)
        for style in IslandLayoutStyle.allCases {
            for mode in IslandPlacementMode.allCases {
                settings.islandLayoutStyle = style
                settings.islandPlacement.mode = mode
                let allowed = style == .pill && mode == .custom
                #expect(settings.supportsStatusIconsInIsland == allowed)
                #expect(settings.effectiveStatusIconDestination == (allowed ? .island : .menuBar))
                #expect(settings.statusIconDestination == .island)
            }
        }
    }

    @Test(arguments: StatusIconDestination.allCases)
    func headphoneConnectionAnimationIsAvailableOnlyWhenIconsUseTheMenuBar(destination: StatusIconDestination) throws {
        var settings = FeatureSettings(statusIconDestination: destination)
        for style in IslandLayoutStyle.allCases {
            for mode in IslandPlacementMode.allCases {
                settings.islandLayoutStyle = style
                settings.islandPlacement.mode = mode
                let usesIsland = destination == .island && style == .pill && mode == .custom
                #expect(settings.supportsHeadphoneConnectionAnimation == !usesIsland)
                #expect(settings.systemMonitorMenuBarHeadphoneOptions.replacesNetworkIcon)
                #expect(try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(settings)) == settings)
            }
        }
    }

    private func encoded(_ settings: FeatureSettings) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any])
    }
}
