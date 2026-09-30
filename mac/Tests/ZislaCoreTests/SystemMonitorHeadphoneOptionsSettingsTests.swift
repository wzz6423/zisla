import Foundation
import Testing
import ZislaCore

struct SystemMonitorHeadphoneOptionsSettingsTests {
    @Test
    func defaultSettingsPersistHeadphoneOptionsInOneNestedField() throws {
        let object = try Self.object(FeatureSettings.default)
        let payload = try #require(object[Self.optionsKey] as? [String: Any])
        let options = try JSONDecoder().decode(SystemMonitorHeadphoneOptions.self, from: JSONSerialization.data(withJSONObject: payload))
        #expect(!options.replacesNetworkIcon)
        #expect(options.prioritizesNetworkErrors)
        #expect(!options.usesVolumeColor)
        #expect(options.showsBatteryLevels)
        #expect(options.symbolScale == 1.6)
        #expect(payload.count == 5)
        #expect(object["replacesNetworkIcon"] == nil)
        #expect(object["showsBatteryLevels"] == nil)
    }

    @Test
    func explicitHeadphoneOptionsRoundTripWithoutChangingExistingSelections() throws {
        let options = SystemMonitorHeadphoneOptions(
            replacesNetworkIcon: true, prioritizesNetworkErrors: false,
            usesVolumeColor: true, showsBatteryLevels: false, symbolScale: 1.75
        )
        let input: [String: Any] = [
            Self.optionsKey: try Self.object(options),
            "systemMonitorMenuBarLayout": "both",
            "systemMonitorMenuBarMetrics": ["gpu", "fan"],
            "systemMonitorMenuBarTopRow": ["memory", "cpu", "network"],
            "systemMonitorMenuBarBottomRow": ["fan", "fan"],
            "systemMonitorMenuBarCombinedIconEnabled": true,
            "systemMonitorMenuBarCombinedIconMetric": "volume",
        ]
        let settings = try JSONDecoder().decode(FeatureSettings.self, from: JSONSerialization.data(withJSONObject: input))
        let object = try Self.object(settings)
        let payload = try #require(object[Self.optionsKey] as? [String: Any])
        let decoded = try JSONDecoder().decode(SystemMonitorHeadphoneOptions.self, from: JSONSerialization.data(withJSONObject: payload))
        #expect(decoded == options)
        #expect(settings.systemMonitorMenuBarLayout == .both)
        #expect(settings.systemMonitorMenuBarMetrics == [.gpu, .fan])
        #expect(settings.systemMonitorMenuBarTopRow == [.memory, .cpu, .network])
        #expect(settings.systemMonitorMenuBarBottomRow == [.fan, .fan])
        #expect(settings.systemMonitorMenuBarCombinedIconEnabled)
        #expect(settings.systemMonitorMenuBarCombinedIconMetric == .volume)
    }

    private static let optionsKey = "systemMonitorMenuBarHeadphoneOptions"

    @Test
    func legacyMissingNullAndPartialOptionsPreserveDefaults() throws {
        for payload in ["{}", #"{"systemMonitorMenuBarHeadphoneOptions":null}"#,
                        #"{"systemMonitorMenuBarHeadphoneOptions":{}}"#] {
            let settings = try JSONDecoder().decode(FeatureSettings.self, from: Data(payload.utf8))
            #expect(settings.systemMonitorMenuBarHeadphoneOptions == SystemMonitorHeadphoneOptions())
        }
        let partial = try JSONDecoder().decode(SystemMonitorHeadphoneOptions.self,
            from: Data(#"{"replacesNetworkIcon":true,"symbolScale":null}"#.utf8))
        #expect(partial == SystemMonitorHeadphoneOptions(replacesNetworkIcon: true))
    }

    @Test
    func invalidTypesAreRejectedAndScaleIsBounded() throws {
        for payload in [#"{"replacesNetworkIcon":1}"#, #"{"symbolScale":"large"}"#] {
            #expect(throws: DecodingError.self) {
                try JSONDecoder().decode(SystemMonitorHeadphoneOptions.self, from: Data(payload.utf8))
            }
        }
        for (input, expected) in [(0.0, 1.0), (100, 1.8), (.nan, 1.6), (.infinity, 1.6)] {
            var options = SystemMonitorHeadphoneOptions()
            options.symbolScale = input
            #expect(options.normalized.symbolScale == expected)
            #expect(SystemMonitorHeadphoneOptions(symbolScale: input).symbolScale == expected)
        }
    }

    private static func object(_ value: some Encodable) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
    }
}
