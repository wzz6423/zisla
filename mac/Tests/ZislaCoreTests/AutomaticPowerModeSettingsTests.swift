import Foundation
import Testing

@testable import ZislaCore

struct AutomaticPowerModeSettingsTests {
    @Test(arguments: [
        "{}",
        #"{"automaticPowerModeEnabled":null,"powerAdapterDefaultMode":null,"batteryDefaultMode":null,"lowBatteryPowerModeEnabled":null}"#,
        #"{"systemMonitorEnabled":false,"systemCleanupPolicy":"sevenDays","trashCleanupPolicy":"thirtyDays"}"#,
    ])
    func legacySettingsKeepAutomaticPowerSwitchingDisabled(payload: String) throws {
        let settings = try JSONDecoder().decode(FeatureSettings.self, from: Data(payload.utf8))
        #expect(!settings.automaticPowerModeEnabled)
        #expect(settings.powerAdapterDefaultMode == .automatic)
        #expect(settings.batteryDefaultMode == .lowPower)
        #expect(settings.lowBatteryPowerModeEnabled)
        #expect(!FeatureSettings.default.automaticPowerModeEnabled)
        #expect(FeatureSettings.default.powerAdapterDefaultMode == .automatic)
        #expect(FeatureSettings.default.batteryDefaultMode == .lowPower)
        #expect(FeatureSettings.default.lowBatteryPowerModeEnabled)
        if payload.contains("sevenDays") {
            #expect(!settings.systemMonitorEnabled)
            #expect(settings.systemCleanupPolicy == .sevenDays)
            #expect(settings.trashCleanupPolicy == .thirtyDays)
        }
    }

    @Test(arguments: BatteryPowerMode.allCases, BatteryPowerMode.allCases)
    func powerSourceChoicesRoundTripWithoutChangingIndependentCleanupPolicies(
        adapter: BatteryPowerMode, battery: BatteryPowerMode
    ) throws {
        var settings = FeatureSettings(systemMonitorEnabled: false, systemCleanupPolicy: .sevenDays,
            systemCleanupScope: .all, trashCleanupPolicy: .fifteenDays,
            automaticPowerModeEnabled: true, powerAdapterDefaultMode: adapter,
            batteryDefaultMode: battery, lowBatteryPowerModeEnabled: false)
        settings.clipboardHistoryCleanupPolicy = .thirtyDays
        let restored = try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(settings))
        #expect(restored == settings)
        #expect(restored.automaticPowerModeEnabled)
        #expect(restored.powerAdapterDefaultMode == adapter)
        #expect(restored.batteryDefaultMode == battery)
        #expect(!restored.lowBatteryPowerModeEnabled)
        #expect(restored.systemCleanupPolicy == .sevenDays)
        #expect(restored.trashCleanupPolicy == .fifteenDays)
        #expect(restored.clipboardHistoryCleanupPolicy == .thirtyDays)
    }

    @Test(arguments: [false, true], [false, true])
    func disabledAutomationStillPreservesEachPowerPreference(enabled: Bool, lowBatteryEnabled: Bool) throws {
        let settings = FeatureSettings(automaticPowerModeEnabled: enabled,
            powerAdapterDefaultMode: .highPower, batteryDefaultMode: .automatic,
            lowBatteryPowerModeEnabled: lowBatteryEnabled)
        let restored = try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(settings))
        #expect(restored == settings)
        #expect(restored.automaticPowerModeEnabled == enabled)
        #expect(restored.lowBatteryPowerModeEnabled == lowBatteryEnabled)
        #expect(restored.powerAdapterDefaultMode == .highPower)
        #expect(restored.batteryDefaultMode == .automatic)
    }

    @Test(arguments: [
        #"{"automaticPowerModeEnabled":1}"#,
        #"{"automaticPowerModeEnabled":"true"}"#,
        #"{"powerAdapterDefaultMode":-1}"#,
        #"{"powerAdapterDefaultMode":3}"#,
        #"{"powerAdapterDefaultMode":"automatic"}"#,
        #"{"powerAdapterDefaultMode":true}"#,
        #"{"batteryDefaultMode":-1}"#,
        #"{"batteryDefaultMode":3}"#,
        #"{"batteryDefaultMode":"lowPower"}"#,
        #"{"batteryDefaultMode":1.5}"#,
        #"{"lowBatteryPowerModeEnabled":1}"#,
        #"{"lowBatteryPowerModeEnabled":"false"}"#,
    ])
    func invalidPowerSettingsAreRejected(payload: String) {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(FeatureSettings.self, from: Data(payload.utf8))
        }
    }

    @Test(arguments: BatteryPowerMode.allCases)
    func sharedPowerModesKeepTheExistingSystemRawValues(mode: BatteryPowerMode) throws {
        let expectedValue: Int
        let expectedTitle: String
        switch mode {
        case .automatic: expectedValue = 0; expectedTitle = "自动"
        case .lowPower: expectedValue = 1; expectedTitle = "省电"
        case .highPower: expectedValue = 2; expectedTitle = "高性能"
        }
        #expect(mode.rawValue == expectedValue)
        #expect(mode.menuTitle == expectedTitle)
        let data = try JSONEncoder().encode(mode)
        #expect(String(decoding: data, as: UTF8.self) == String(expectedValue))
        #expect(try JSONDecoder().decode(BatteryPowerMode.self, from: data) == mode)
    }
}
