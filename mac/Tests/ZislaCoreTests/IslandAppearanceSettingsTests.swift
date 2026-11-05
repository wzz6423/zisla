import Foundation
import Testing
@testable import ZislaCore

struct IslandAppearanceSettingsTests {
    @Test(arguments: IslandEdge.allCases)
    func customPlacementReturnsAfterCameraAndNotchModes(edge: IslandEdge) throws {
        let custom = IslandPlacement(mode: .custom, edge: edge, offset: 0.23, inwardDistance: 37)
        var settings = FeatureSettings(islandLayoutStyle: .pill, islandPlacement: custom)
        settings.islandPlacement = try #require(settings.islandPlacement(for: .camera))
        #expect(settings.islandPlacement == IslandPlacement())
        settings.islandLayoutStyle = .notch
        settings.islandLayoutStyle = .pill
        settings = try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(settings))
        #expect(settings.islandPlacement(for: .custom) == custom,
            "Returning to custom mode must restore the last confirmed edge, offset and inward distance")
    }

    @Test
    func firstCustomSelectionRequiresChoosingAPositionWithoutChangingSettings() {
        let settings = FeatureSettings.default
        #expect(settings.islandPlacement(for: .custom) == nil)
        #expect(settings == .default)
    }

    @Test(arguments: IslandEdge.allCases)
    func confirmedPlacementAndGeometryChangesReplaceTheRememberedPosition(edge: IslandEdge) throws {
        var settings = FeatureSettings.default
        settings.islandPlacement = IslandPlacement(mode: .custom, edge: .top)
        settings.islandPlacement.edge = edge
        settings.islandPlacement.offset = 0
        settings.islandPlacement.inwardDistance = 48
        let expected = settings.islandPlacement
        #expect(settings.lastCustomIslandPlacement == expected)
        settings.islandLayoutStyle = .notch
        settings.islandLayoutStyle = .pill
        #expect(settings.islandPlacement(for: .custom) == expected)
        for _ in 0..<2 {
            settings.islandPlacement = try #require(settings.islandPlacement(for: .camera))
            #expect(settings.lastCustomIslandPlacement == expected)
        }
        settings.islandPlacement = try #require(settings.islandPlacement(for: .custom))
        #expect(settings.islandPlacement == expected)
    }

    @Test(arguments: IslandLayoutStyle.allCases, IslandEdge.allCases)
    func legacyCustomPlacementsBecomeTheRememberedPosition(style: IslandLayoutStyle, edge: IslandEdge) throws {
        let payload = #"{"islandLayoutStyle":"\#(style.rawValue)","islandPlacement":{"mode":"custom","edge":"\#(edge.rawValue)","offset":1,"inwardDistance":28}}"#
        var settings = try JSONDecoder().decode(FeatureSettings.self, from: Data(payload.utf8))
        let expected = IslandPlacement(mode: .custom, edge: edge, offset: 1, inwardDistance: 28)
        #expect(settings.lastCustomIslandPlacement == expected)
        settings.islandPlacement = try #require(settings.islandPlacement(for: .camera))
        #expect(settings.islandPlacement(for: .custom) == expected)
    }

    @Test(arguments: ["null", "{}", #"{"mode":"camera","edge":"left","offset":0.2}"#,
                      #"{"mode":"obsolete"}"#])
    func absentOrNonCustomHistoryStillRequiresChoosingAPosition(history: String) throws {
        let payload = #"{"lastCustomIslandPlacement":\#(history),"islandEdgeInset":17}"#
        let settings = try JSONDecoder().decode(FeatureSettings.self, from: Data(payload.utf8))
        #expect(settings.lastCustomIslandPlacement == nil)
        #expect(settings.islandPlacement(for: .custom) == nil)
        #expect(settings.islandPlacement(for: .camera) == IslandPlacement())
        #expect(settings.islandEdgeInset == 17)
    }

    @Test
    func activeCustomPlacementTakesPrecedenceOverOutdatedHistory() throws {
        let payload = #"{"islandPlacement":{"mode":"custom","edge":"left","offset":0.3,"inwardDistance":20},"lastCustomIslandPlacement":{"mode":"custom","edge":"right","offset":0.8}}"#
        let settings = try JSONDecoder().decode(FeatureSettings.self, from: Data(payload.utf8))
        #expect(settings.lastCustomIslandPlacement == settings.islandPlacement)
        #expect(settings.islandPlacement(for: .custom) == settings.islandPlacement)
    }

    @Test
    func seededCustomPlacementChangesRoundTripWithoutChangingOtherSettings() throws {
        var seed: UInt64 = 0x1_51A_D
        var settings = FeatureSettings.default
        for step in 0..<64 {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let custom = IslandPlacement(mode: .custom, edge: IslandEdge.allCases[Int(seed % 4)],
                offset: Double(seed % 1000) / 100, inwardDistance: Double(seed % 200))
            settings.islandPlacement = custom
            settings.islandLayoutStyle = step.isMultiple(of: 2) ? .notch : .pill
            settings.islandPlacement = try #require(settings.islandPlacement(for: .camera))
            let restored = try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(settings))
            #expect(restored == settings)
            #expect(restored.islandPlacement(for: .custom) == custom)
            settings.islandPlacement = try #require(restored.islandPlacement(for: .custom))
        }
        settings.islandPlacement = IslandPlacement()
        settings.islandLayoutStyle = FeatureSettings.default.islandLayoutStyle
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any])
        var withoutHistory = object
        withoutHistory.removeValue(forKey: "lastCustomIslandPlacement")
        #expect(try JSONDecoder().decode(FeatureSettings.self,
            from: JSONSerialization.data(withJSONObject: withoutHistory)) == .default)
    }

    @Test
    func legacyAndNullSettingsPreserveTheExistingNotchAndMusicAppearance() throws {
        for payload in ["{}", #"{"islandLayoutStyle":null,"islandPlacement":null,"islandPillWidth":null,"islandPillHeight":null,"islandEdgeInset":null}"#] {
            let settings = try JSONDecoder().decode(FeatureSettings.self, from: Data(payload.utf8))
            #expect(settings.islandLayoutStyle == .notch)
            #expect(settings.islandPlacement == IslandPlacement())
            #expect(settings.islandPillWidth == 80 && settings.islandPillHeight == 24)
            #expect(settings.islandEdgeInset == 8)
            #expect(settings.islandNotchBackground == .black)
            #expect(settings.mediaVisualizationStyle == .waveform)
        }
    }

    @Test(arguments: IslandLayoutStyle.allCases, IslandEdge.allCases)
    func savedAppearanceRoundTripsWithoutChangingUnrelatedSettings(style: IslandLayoutStyle, edge: IslandEdge) throws {
        var settings = FeatureSettings.default
        settings.islandLayoutStyle = style
        settings.islandPlacement = IslandPlacement(mode: .custom, edge: edge, offset: 0.23)
        settings.islandEdgeInset = 17
        settings.islandNotchBackground = .liquidGlass
        settings.mediaVisualizationStyle = .glow
        settings.mediaCompactStyle = .detailed
        let decoded = try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded == settings)
        #expect(decoded.islandPlacement.offset == 0.23)
        #expect(decoded.islandPillWidth == 80 && decoded.islandPillHeight == 24)
        #expect(decoded.islandEdgeInset == 17)
        #expect(decoded.islandNotchBackground == .liquidGlass)
        #expect(decoded.islandLayoutStyle == style)
        #expect(decoded.mediaVisualizationStyle == .glow)
    }

    @Test
    func pillDimensionsStayFixedWhileEdgeInsetRemainsNormalized() throws {
        let values: [Double] = [-100, 0, 20, 32, 64, 80, 180, 400, 600, .nan, .infinity, -.infinity]
        for value in values {
            let inset = value.isFinite ? min(64, max(0, value)) : 8
            let constructed = FeatureSettings(islandPillWidth: value, islandPillHeight: value, islandEdgeInset: value)
            #expect(constructed.islandPillWidth == 80)
            #expect(constructed.islandPillHeight == 24)
            #expect(constructed.islandEdgeInset == inset)
            let roundTripped = try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(constructed))
            #expect(roundTripped.islandPillWidth == 80)
            #expect(roundTripped.islandPillHeight == 24)
            #expect(roundTripped == constructed)
            if value.isFinite {
                let payload = "{\"islandPillWidth\":\(value),\"islandPillHeight\":\(value),\"islandEdgeInset\":\(value)}"
                let decoded = try JSONDecoder().decode(FeatureSettings.self, from: Data(payload.utf8))
                #expect(decoded.islandPillWidth == 80)
                #expect(decoded.islandPillHeight == 24)
                #expect(decoded.islandEdgeInset == inset)
            }
        }
    }

    @Test(arguments: [
        #"{"islandPillWidth":"wide","islandPillHeight":[]}"#,
        #"{"islandPillWidth":false,"islandPillHeight":{}}"#,
    ])
    func malformedLegacyPillDimensionsAreIgnored(payload: String) throws {
        let settings = try JSONDecoder().decode(FeatureSettings.self, from: Data(payload.utf8))
        #expect(settings.islandPillWidth == 80 && settings.islandPillHeight == 24)
    }

    @Test
    func theNewLiquidGlassValueDoesNotRepurposeTheOldMigration() throws {
        let legacy = try JSONDecoder().decode(FeatureSettings.self,
            from: Data(#"{"islandNotchBackground":"liquidGlass"}"#.utf8))
        #expect(legacy.islandNotchBackground == .frosted)
        let current = try JSONDecoder().decode(FeatureSettings.self,
            from: Data(#"{"islandNotchBackground":"liquidGlassCrown"}"#.utf8))
        #expect(current.islandNotchBackground == .liquidGlass)
        #expect(String(decoding: try JSONEncoder().encode(IslandNotchBackground.liquidGlass), as: UTF8.self)
            == #""liquidGlassCrown""#)
        #expect(IslandNotchBackground.allCases == [.black, .frosted, .liquidGlass])
        #expect(IslandNotchBackground.black.title == "黑色")
    }

    @Test(arguments: [#"{"islandLayoutStyle":"unknown"}"#, #"{"islandLayoutStyle":1}"#,
                      #"{"islandEdgeInset":false}"#, #"{"islandNotchBackground":"unknown"}"#,
                      #"{"lastCustomIslandPlacement":false}"#, #"{"lastCustomIslandPlacement":[]}"#])
    func malformedAppearanceDoesNotSilentlyApplyAPartialConfiguration(payload: String) {
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(FeatureSettings.self, from: Data(payload.utf8))
        }
    }

    @Test
    func seededEdgeInsetChangesStaySerializableAndDoNotChangeFixedPillDefaults() throws {
        var seed: UInt64 = 0xD1A_1D
        for _ in 0..<96 {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let value = Double(seed % 2000) / 2 - 250
            var changed = FeatureSettings.default
            changed.islandEdgeInset = value
            let decoded = try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(changed))
            #expect(decoded == changed)
            #expect(decoded.islandPillWidth == 80)
            #expect(decoded.islandPillHeight == 24)
            #expect((0...64).contains(decoded.islandEdgeInset))
        }
        #expect(FeatureSettings.default.islandLayoutStyle == .notch)
        #expect(FeatureSettings.default.islandPillWidth == 80)
        #expect(FeatureSettings.default.islandPillHeight == 24)
    }
}
