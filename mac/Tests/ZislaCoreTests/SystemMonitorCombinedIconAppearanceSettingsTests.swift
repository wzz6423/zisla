import Foundation
import Testing
import ZislaCore

struct SystemMonitorCombinedIconAppearanceSettingsTests {
    @Test
    func defaultSettingsEncodeAppearanceModelDefaults() throws {
        let object = try Self.object(FeatureSettings.default)
        let appearance = try #require(object[Self.appearanceKey] as? [String: Any])
        let decoded = try JSONDecoder().decode(
            SystemMonitorCombinedIconAppearance.self,
            from: JSONSerialization.data(withJSONObject: appearance)
        )
        #expect(decoded == SystemMonitorCombinedIconAppearance())
        #expect(appearance.count == 9)
    }

    @Test
    func explicitAppearanceRoundTripsWithoutChangingExistingSelections() throws {
        let appearance = SystemMonitorCombinedIconAppearance(
            iconSize: 30,
            ringStrokeStyle: .bold,
            indicatorStyle: .arc,
            showsBatteryPercentage: true,
            showsChargingIndicator: true,
            showsPercentageWhenConnected: true,
            usesStatusColors: false,
            batteryTextScale: 1.9,
            wifiScale: 1.4
        )
        let input: [String: Any] = [
            Self.appearanceKey: try Self.object(appearance),
            "systemMonitorMenuBarLayout": "both",
            "systemMonitorMenuBarMetrics": ["fan", "network"],
            "systemMonitorMenuBarTopRow": ["network", "memory"],
            "systemMonitorMenuBarBottomRow": ["fan"],
            "systemMonitorMenuBarCombinedIconEnabled": true,
            "systemMonitorMenuBarCombinedIconMetric": "brightness",
        ]
        let settings = try JSONDecoder().decode(
            FeatureSettings.self,
            from: JSONSerialization.data(withJSONObject: input)
        )
        let output = try Self.object(settings)
        let persisted = try #require(output[Self.appearanceKey] as? [String: Any])
        let decoded = try JSONDecoder().decode(
            SystemMonitorCombinedIconAppearance.self,
            from: JSONSerialization.data(withJSONObject: persisted)
        )
        #expect(decoded == appearance)
        #expect(settings.systemMonitorMenuBarLayout == .both)
        #expect(settings.systemMonitorMenuBarMetrics == [.fan, .network])
        #expect(settings.systemMonitorMenuBarTopRow == [.network, .memory])
        #expect(settings.systemMonitorMenuBarBottomRow == [.fan])
        #expect(settings.systemMonitorMenuBarCombinedIconEnabled)
        #expect(settings.systemMonitorMenuBarCombinedIconMetric == .brightness)
    }

    @Test
    func initializerUsesModelDefaultsAndAcceptsAnExplicitAppearance() {
        #expect(FeatureSettings().systemMonitorMenuBarCombinedIconAppearance == SystemMonitorCombinedIconAppearance())
        let appearance = SystemMonitorCombinedIconAppearance(iconSize: 36, indicatorStyle: .arc, wifiScale: 1.8)
        let settings = FeatureSettings(systemMonitorMenuBarCombinedIconAppearance: appearance)
        #expect(settings.systemMonitorMenuBarCombinedIconAppearance == appearance)
        #expect(settings.systemMonitorMenuBarLayout == .individual)
        #expect(!settings.systemMonitorMenuBarCombinedIconEnabled)
    }

    @Test
    func missingAndNullAppearanceKeepDefaultsAndLegacySelections() throws {
        let empty = try JSONDecoder().decode(FeatureSettings.self, from: Data("{}".utf8))
        #expect(empty.systemMonitorMenuBarCombinedIconAppearance == SystemMonitorCombinedIconAppearance())
        for layout in ["individual", "stacked"] {
            for includesNull in [false, true] {
                var input: [String: Any] = [
                    "systemMonitorMenuBarLayout": layout,
                    "systemMonitorMenuBarMetrics": ["gpu", "fan"],
                    "systemMonitorMenuBarTopRow": ["memory", "cpu", "network"],
                    "systemMonitorMenuBarBottomRow": ["gpu", "gpu"],
                    "systemMonitorMenuBarCombinedIconEnabled": true,
                    "systemMonitorMenuBarCombinedIconMetric": "volume",
                ]
                if includesNull { input[Self.appearanceKey] = NSNull() }
                let settings = try JSONDecoder().decode(FeatureSettings.self, from: JSONSerialization.data(withJSONObject: input))
                #expect(settings.systemMonitorMenuBarCombinedIconAppearance == SystemMonitorCombinedIconAppearance())
                #expect(settings.systemMonitorMenuBarLayout.rawValue == layout)
                #expect(settings.systemMonitorMenuBarMetrics == [.gpu, .fan])
                #expect(settings.systemMonitorMenuBarTopRow == [.memory, .cpu, .network])
                #expect(settings.systemMonitorMenuBarBottomRow == [.gpu, .gpu])
                #expect(settings.systemMonitorMenuBarCombinedIconEnabled)
                #expect(settings.systemMonitorMenuBarCombinedIconMetric == .volume)
            }
        }
    }

    @Test
    func partialAppearanceUsesModelDecoderDefaultsAndBounds() throws {
        let settings = try JSONDecoder().decode(
            FeatureSettings.self,
            from: Data(#"{"systemMonitorMenuBarCombinedIconAppearance":{"iconSize":2,"batteryTextScale":9,"wifiScale":null,"ringStrokeStyle":"standard","indicatorStyle":null,"showsChargingIndicator":true,"showsBatteryPercentage":null}}"#.utf8)
        )
        #expect(settings.systemMonitorMenuBarCombinedIconAppearance == SystemMonitorCombinedIconAppearance(
            iconSize: 16, ringStrokeStyle: .light, showsChargingIndicator: true, batteryTextScale: 1.98
        ))
    }

    @Test
    func malformedAppearanceIsRejectedInsteadOfSilentlyDiscarded() {
        for appearance in [
            #""invalid""#, "[]", "5", "false", #"{"iconSize":"large"}"#,
            #"{"indicatorStyle":"unknown"}"#, #"{"ringStrokeStyle":"unknown"}"#,
            #"{"showsBatteryPercentage":1}"#,
        ] {
            let input = Data("{\"\(Self.appearanceKey)\":\(appearance)}".utf8)
            #expect(throws: DecodingError.self) {
                try JSONDecoder().decode(FeatureSettings.self, from: input)
            }
        }
    }

    @Test
    func unknownFieldsAndSupportedStrokeAliasesRemainCompatible() throws {
        for (raw, expected) in [("standard", SystemMonitorMenuBarRingStrokeStyle.light), ("normal", .regular), ("heavy", .bold)] {
            let input = Data("{\"\(Self.appearanceKey)\":{\"ringStrokeStyle\":\"\(raw)\",\"futureOption\":{\"enabled\":true}},\"futureSettings\":42}".utf8)
            let settings = try JSONDecoder().decode(FeatureSettings.self, from: input)
            #expect(settings.systemMonitorMenuBarCombinedIconAppearance.ringStrokeStyle == expected)
            #expect(settings.systemMonitorMenuBarCombinedIconAppearance.iconSize == 22)
            #expect(settings.systemMonitorMenuBarLayout == .individual)
        }
    }

    @Test
    func encodingDoesNotMutateRawSelectionsAndDecodeNormalizesAppearance() throws {
        var settings = FeatureSettings.default
        settings.systemMonitorMenuBarTopRow = [.memory, .cpu, .network]
        settings.systemMonitorMenuBarBottomRow = [.gpu, .gpu]
        settings.systemMonitorMenuBarCombinedIconAppearance.iconSize = -10
        settings.systemMonitorMenuBarCombinedIconAppearance.wifiScale = 3
        settings.systemMonitorMenuBarCombinedIconAppearance.batteryTextScale = 1
        let original = settings
        let decoded = try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(settings))
        #expect(settings == original)
        #expect(decoded.systemMonitorMenuBarCombinedIconAppearance == original.systemMonitorMenuBarCombinedIconAppearance.normalized)
        #expect(decoded.systemMonitorMenuBarCombinedIconAppearance.iconSize == 16)
        #expect(decoded.systemMonitorMenuBarCombinedIconAppearance.wifiScale == 1.8)
        #expect(decoded.systemMonitorMenuBarCombinedIconAppearance.batteryTextScale == 1.62)
        #expect(decoded.systemMonitorMenuBarTopRow == original.systemMonitorMenuBarTopRow)
        #expect(decoded.systemMonitorMenuBarBottomRow == original.systemMonitorMenuBarBottomRow)
    }

    @Test
    func nonFiniteRawAppearanceCannotBeEncodedAndNormalizesSafely() {
        let fields: [WritableKeyPath<SystemMonitorCombinedIconAppearance, Double>] = [\.iconSize, \.wifiScale, \.batteryTextScale]
        for field in fields {
            for value in [Double.nan, .infinity, -.infinity] {
                var settings = FeatureSettings.default
                settings.systemMonitorMenuBarCombinedIconAppearance[keyPath: field] = value
                #expect(settings.systemMonitorMenuBarCombinedIconAppearance.normalized == SystemMonitorCombinedIconAppearance())
                #expect(throws: EncodingError.self) { try JSONEncoder().encode(settings) }
            }
        }
    }

    @Test
    func boundedAppearanceCombinationsRoundTripWithoutChangingOtherSettings() throws {
        let budget = 3_000
        var checked = 0
        var settings = FeatureSettings.default
        settings.systemMonitorMenuBarLayout = .both
        settings.systemMonitorMenuBarMetrics = [.memory, .fan]
        settings.systemMonitorMenuBarTopRow = [.network, .cpu]
        settings.systemMonitorMenuBarBottomRow = [.fan]
        settings.systemMonitorMenuBarCombinedIconEnabled = true
        settings.systemMonitorMenuBarCombinedIconMetric = .brightness
        for size in [16.0, 22, 36] {
            for stroke in SystemMonitorMenuBarRingStrokeStyle.allCases {
                for indicator in SystemMonitorMenuBarIndicatorStyle.allCases {
                    for flags in 0..<16 {
                        for textScale in [1.62, 1.8, 1.98] {
                            for wifiScale in [1.0, 1.4, 1.8] {
                                try #require(checked < budget)
                                settings.systemMonitorMenuBarCombinedIconAppearance = SystemMonitorCombinedIconAppearance(
                                    iconSize: size,
                                    ringStrokeStyle: stroke,
                                    indicatorStyle: indicator,
                                    showsBatteryPercentage: flags & 1 != 0,
                                    showsChargingIndicator: flags & 2 != 0,
                                    showsPercentageWhenConnected: flags & 4 != 0,
                                    usesStatusColors: flags & 8 != 0,
                                    batteryTextScale: textScale,
                                    wifiScale: wifiScale
                                )
                                let decoded = try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(settings))
                                #expect(decoded == settings)
                                checked += 1
                            }
                        }
                    }
                }
            }
        }
        #expect(checked == 2_592)
    }

    @Test
    func requestedAppearanceDefaultsApplyToFreshMissingAndNullSettings() throws {
        let appearance = SystemMonitorCombinedIconAppearance()
        #expect(appearance.iconSize == 22)
        #expect(appearance.ringStrokeStyle == .bold)
        #expect(appearance.indicatorStyle == .dots)
        #expect(appearance.showsBatteryPercentage)
        #expect(appearance.showsChargingIndicator)
        #expect(appearance.showsPercentageWhenConnected)
        #expect(appearance.usesStatusColors)
        #expect(appearance.wifiScale == 1)
        #expect(appearance.batteryTextScale == 1.8)
        let expected = SystemMonitorCombinedIconAppearance(
            ringStrokeStyle: .bold,
            showsBatteryPercentage: true,
            showsChargingIndicator: true,
            showsPercentageWhenConnected: true
        )
        for payload in [
            "{}",
            #"{"systemMonitorMenuBarCombinedIconMetric":null,"systemMonitorMenuBarCombinedIconAppearance":null}"#,
            #"{"systemMonitorMenuBarCombinedIconAppearance":{}}"#,
            #"{"systemMonitorMenuBarCombinedIconAppearance":{"ringStrokeStyle":null,"indicatorStyle":null,"showsBatteryPercentage":null,"showsChargingIndicator":null,"showsPercentageWhenConnected":null}}"#,
        ] {
            let settings = try JSONDecoder().decode(FeatureSettings.self, from: Data(payload.utf8))
            #expect(settings.systemMonitorMenuBarCombinedIconMetric == .memory)
            #expect(settings.systemMonitorMenuBarCombinedIconAppearance == expected)
            #expect(settings.systemMonitorMenuBarLayout == .individual)
            #expect(settings.systemMonitorMenuBarTopRow == [.cpu])
            #expect(settings.systemMonitorMenuBarBottomRow == [.gpu])
            #expect(!settings.systemMonitorMenuBarCombinedIconEnabled)
        }
    }

    @Test
    func explicitLegacyAppearanceAndCpuSelectionDoNotAdoptNewDefaults() throws {
        let payload = Data(#"{"systemMonitorMenuBarLayout":"stacked","systemMonitorMenuBarCombinedIconMetric":"cpu","systemMonitorMenuBarCombinedIconAppearance":{"ringStrokeStyle":"regular","indicatorStyle":"arc","showsBatteryPercentage":false,"showsChargingIndicator":false,"showsPercentageWhenConnected":false,"usesStatusColors":false}}"#.utf8)
        let settings = try JSONDecoder().decode(FeatureSettings.self, from: payload)
        #expect(settings.systemMonitorMenuBarCombinedIconMetric == .cpu)
        #expect(settings.systemMonitorMenuBarCombinedIconAppearance == SystemMonitorCombinedIconAppearance(
            ringStrokeStyle: .regular,
            indicatorStyle: .arc,
            showsBatteryPercentage: false,
            showsChargingIndicator: false,
            showsPercentageWhenConnected: false,
            usesStatusColors: false
        ))
        #expect(settings.systemMonitorMenuBarLayout == .stacked)
        let restored = try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(settings))
        #expect(restored == settings)
    }

    private static let appearanceKey = "systemMonitorMenuBarCombinedIconAppearance"

    private static func object(_ value: some Encodable) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
    }
}
