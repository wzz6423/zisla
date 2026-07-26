import Foundation
import Testing
@testable import ZislaKit

struct AudioOutputDeviceServiceTests {
    @Test
    func recognizesCommonHeadphoneNames() {
        #expect(AudioOutputDevice(id: 1, name: "AirPods Pro").isHeadphones)
        #expect(AudioOutputDevice(id: 2, name: "Beats Studio Buds").isHeadphones)
        #expect(!AudioOutputDevice(id: 3, name: "MacBook Pro Speakers").isHeadphones)
    }

    @Test
    func parsesConnectedAirPodsBatteryLevelsFromBluetoothProfile() throws {
        let data = try #require(
            """
            {
              "SPBluetoothDataType": [
                {
                  "device_connected": [
                    {
                      "AirPods Pro": {
                        "device_minorType": "Headphones",
                        "device_batteryLevelLeft": "91%",
                        "device_batteryLevelRight": "83%",
                        "device_batteryLevelCase": "62%"
                      }
                    }
                  ]
                }
              ]
            }
            """.data(using: .utf8)
        )

        let snapshot = HeadphoneBatterySnapshot.fromBluetoothProfile(data, deviceName: "AirPods Pro")

        #expect(snapshot == HeadphoneBatterySnapshot(leftLevel: 91, rightLevel: 83, caseLevel: 62))
        #expect(snapshot?.noticeLevels.map(\.level) == [91, 83, 62])
    }
}
