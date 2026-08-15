import Foundation
import Testing

@testable import ZislaKit

struct AppleMobileDeviceBatteryReaderTests {
    @Test
    func parsesDirectBatteryDomainAcrossNumberAndStringValues() throws {
        let device = try #require(AppleMobileDeviceBatteryParser.device(
            identifier: "opaque-id",
            name: "Work iPhone",
            productType: "iPhone17,1",
            deviceClass: "iPhone",
            connectionType: "Wi-Fi",
            battery: [
                "BatteryCurrentCapacity": "81",
                "BatteryIsCharging": "yes",
            ],
            now: Date(timeIntervalSince1970: 100)
        ))

        #expect(device.identifier == "idevice:opaque-id")
        #expect(device.deviceType == .iPhone)
        #expect(device.batteryPercentInt == 81)
        #expect(device.isCharging)
        #expect(device.connectionDetail == "Wi-Fi")
        #expect(device.source == .iDevice)
    }

    @Test
    func derivesBatteryLevelFromRawCapacities() throws {
        let device = try #require(AppleMobileDeviceBatteryParser.device(
            identifier: "tablet",
            name: "",
            productType: "iPad16,3",
            deviceClass: "Tablet",
            connectionType: "USB",
            battery: [
                "AppleRawCurrentCapacity": 2_250,
                "AppleRawMaxCapacity": 3_000,
                "IsCharging": false,
            ]
        ))

        #expect(device.name == "iPad")
        #expect(device.deviceType == .iPad)
        #expect(device.batteryPercentInt == 75)
        #expect(!device.isCharging)
    }

    @Test
    func preservesWatchParentAndRejectsMissingBatteryData() throws {
        let watch = try #require(AppleMobileDeviceBatteryParser.device(
            identifier: "watch",
            name: "Apple Watch",
            productType: "Watch7,5",
            deviceClass: "Watch",
            connectionType: "Wi-Fi",
            parentName: "Work iPhone",
            battery: ["BatteryCurrentCapacity": 56]
        ))

        #expect(watch.deviceType == .appleWatch)
        #expect(watch.parentName == "Work iPhone")
        #expect(AppleMobileDeviceBatteryParser.device(
            identifier: "missing",
            name: "iPhone",
            productType: "iPhone17,1",
            deviceClass: "iPhone",
            connectionType: "USB",
            battery: [:]
        ) == nil)
    }
}
