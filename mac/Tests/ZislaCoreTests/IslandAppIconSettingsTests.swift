import Foundation
import Testing

@testable import ZislaCore

struct IslandAppIconSettingsTests {
    @Test
    func logoDefaultsOnForNewAndLegacySettingsWithoutResettingOtherChoices() throws {
        #expect(FeatureSettings.default.islandAppIconEnabled)
        #expect(FeatureSettings().islandAppIconEnabled)
        #expect(try JSONDecoder().decode(FeatureSettings.self, from: Data("{}".utf8)).islandAppIconEnabled)
        let original = FeatureSettings(mediaEnabled: false, systemMonitorEnabled: false,
            menuBarAppIconEnabled: false, statusIconDestination: .menuBar, islandShowMoreInformation: false)
        var payload = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        payload.removeValue(forKey: "islandAppIconEnabled")
        #expect(try JSONDecoder().decode(FeatureSettings.self,
            from: JSONSerialization.data(withJSONObject: payload)) == original)
        for invalid in [NSNull(), "false", 0, [String](), [String: String]()] as [Any] {
            payload["islandAppIconEnabled"] = invalid
            #expect(try JSONDecoder().decode(FeatureSettings.self,
                from: JSONSerialization.data(withJSONObject: payload)) == original,
                "Malformed logo settings must preserve the saved menu bar and monitoring choices")
        }
    }

    @Test(arguments: [false, true], [false, true])
    func savedLogoAndMenuBarChoicesRoundTripIndependently(showsLogo: Bool, showsMenuBarIcon: Bool) throws {
        var settings = FeatureSettings(menuBarAppIconEnabled: showsMenuBarIcon, islandAppIconEnabled: showsLogo)
        for style in IslandLayoutStyle.allCases {
            for mode in IslandPlacementMode.allCases {
                settings.islandLayoutStyle = style
                settings.islandPlacement.mode = mode
                for destination in StatusIconDestination.allCases {
                    settings.statusIconDestination = destination
                    let encoded = try JSONEncoder().encode(settings)
                    let payload = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
                    #expect(payload["islandAppIconEnabled"] as? Bool == showsLogo)
                    #expect(try JSONDecoder().decode(FeatureSettings.self, from: encoded) == settings)
                    #expect(settings.islandAppIconEnabled == showsLogo)
                    #expect(settings.menuBarAppIconEnabled == showsMenuBarIcon)
                }
            }
        }
    }
}
