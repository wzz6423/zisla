import Foundation
import Testing
@testable import ZislaCore

struct IslandDisplaySettingsTests {
    @Test
    func customIslandCapabilitiesUseOnlyConnectedVisibleDisplays() {
        var settings = FeatureSettings(islandDisplaySettings: [
            "external": IslandDisplaySettings(mode: .pill, placement: IslandPlacement(mode: .custom, edge: .left)),
        ])
        #expect(!settings.supportsStatusIconsInIsland)
        #expect(settings.supportsStatusIconsInIsland(on: ["built-in", "external"]))
        #expect(!settings.supportsStatusIconsInIsland(on: ["built-in", "another"]))
        #expect(!settings.supportsStatusIconsInIsland(on: ["external"]))
        settings.islandDisplaySettings["external"]?.mode = .hidden
        #expect(!settings.supportsStatusIconsInIsland(on: ["built-in", "external"]))
    }
    @Test
    func legacySettingsKeepTheGlobalAppearanceWithoutDisplayOverrides() throws {
        let settings = try JSONDecoder().decode(FeatureSettings.self, from: Data(#"{"islandLayoutStyle":"pill","islandPlacement":{"mode":"custom","edge":"left","offset":0.3},"mediaEnabled":false}"#.utf8))
        #expect(settings.islandDisplaySettings.isEmpty)
        let display = settings.islandDisplaySettings(for: "external")
        #expect(display.mode == .pill)
        #expect(display.placement == settings.islandPlacement)
        #expect(display.placement(for: .custom) == settings.islandPlacement)
        #expect(!settings.mediaEnabled)
    }

    @Test(arguments: IslandDisplayMode.allCases, IslandEdge.allCases)
    func eachDisplayRemembersItsOwnCustomPlacement(mode: IslandDisplayMode, edge: IslandEdge) throws {
        let custom = IslandPlacement(mode: .custom, edge: edge, offset: 0.23, inwardDistance: 28)
        var display = IslandDisplaySettings(mode: mode, placement: custom)
        display.placement = try #require(display.placement(for: .camera))
        let restored = try JSONDecoder().decode(IslandDisplaySettings.self, from: JSONEncoder().encode(display))
        #expect(restored.mode == mode)
        #expect(restored.placement == IslandPlacement())
        #expect(restored.placement(for: .custom) == custom)
    }

    @Test
    func changingOneDisplayPreservesOtherDisplaysAndTheGlobalSettings() throws {
        var settings = FeatureSettings.default
        settings.islandDisplaySettings["built-in"] = IslandDisplaySettings(mode: .notch)
        settings.islandDisplaySettings["external"] = IslandDisplaySettings(mode: .pill,
                                                                           placement: IslandPlacement(mode: .custom, edge: .bottom, offset: 0.8))
        let previous = settings
        settings.islandDisplaySettings["built-in"]?.mode = .hidden
        let restored = try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(settings))
        #expect(restored == settings)
        #expect(restored.islandDisplaySettings["external"] == previous.islandDisplaySettings["external"])
        #expect(restored.islandLayoutStyle == previous.islandLayoutStyle)
        #expect(restored.islandPlacement == previous.islandPlacement)
        #expect(restored.islandDisplaySettings(for: "new-display").mode == .notch)
    }

    @Test(arguments: ["null", "[]", "true", #""invalid""#])
    func malformedOverrideContainersDoNotResetUnrelatedPreferences(payload: String) throws {
        let data = Data(#"{"islandDisplaySettings":\#(payload),"mediaEnabled":false,"islandLayoutStyle":"pill"}"#.utf8)
        let settings = try JSONDecoder().decode(FeatureSettings.self, from: data)
        #expect(settings.islandDisplaySettings.isEmpty)
        #expect(!settings.mediaEnabled)
        #expect(settings.islandLayoutStyle == .pill)
    }

    @Test
    func malformedDisplayFieldsRecoverIndependently() throws {
        let data = Data(#"{"mode":"obsolete","placement":{"mode":"custom","edge":"right","offset":0.7},"lastCustomPlacement":false}"#.utf8)
        let display = try JSONDecoder().decode(IslandDisplaySettings.self, from: data)
        #expect(display.mode == .notch)
        #expect(display.placement == IslandPlacement(mode: .custom, edge: .right, offset: 0.7))
        #expect(display.placement(for: .custom) == display.placement)
        let empty = try JSONDecoder().decode(IslandDisplaySettings.self, from: Data("{}".utf8))
        #expect(empty.placement(for: .custom) == nil)
    }
}
