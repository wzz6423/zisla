import Foundation
import Testing

@testable import ZislaKit

struct BluetoothBatteryScannerTests {
    @Test
    func parsesOpenCaseAppleHeadphoneAdvertisement() throws {
        var bytes = Array(repeating: UInt8(0), count: 29)
        bytes[0] = 0x4C
        bytes[1] = 0x00
        bytes[2] = 0x07
        bytes[7] = 0x00
        bytes[14] = 64
        bytes[15] = 82
        bytes[16] = 203

        let readings = AppleHeadphoneAdvertisementParser.readings(from: Data(bytes))
        let byComponent = Dictionary(uniqueKeysWithValues: readings.map { ($0.component, $0) })

        #expect(byComponent[.left]?.level == 82)
        #expect(byComponent[.right]?.level == 64)
        #expect(byComponent[.caseBattery]?.level == 75)
        #expect(byComponent[.caseBattery]?.isCharging == true)
    }

    @Test
    func parsesClosedCaseAdvertisementAndIgnoresUnavailableComponents() {
        var bytes = Array(repeating: UInt8(0), count: 25)
        bytes[0] = 0x4C
        bytes[1] = 0x00
        bytes[2] = 0x12
        bytes[12] = 45
        bytes[13] = 0xFF
        bytes[14] = 61

        let readings = AppleHeadphoneAdvertisementParser.readings(from: Data(bytes))

        #expect(readings.map(\.component) == [.caseBattery, .right])
        #expect(readings.map(\.level) == [45, 61])
    }

    @Test
    func rejectsUnknownManufacturerAndPayloadShape() {
        #expect(AppleHeadphoneAdvertisementParser.readings(from: Data([0x00, 0x00])).isEmpty)
        #expect(AppleHeadphoneAdvertisementParser.readings(
            from: Data([0x4C, 0x00, 0x07, 0x19])
        ).isEmpty)
    }
}
