import Foundation
import Testing

@testable import ZislaCore

struct ApplicationVolumeMixerSettingsTests {
    @Test(arguments: ["{}", #"{"pdfToolsEnabled":false}"#, #"{"volumeMixerEnabled":null}"#])
    func newAndLegacySettingsEnableVolumeMixerWithoutReusingPDFToggle(json: String) throws {
        #expect(FeatureSettings.default.volumeMixerEnabled)
        let settings = try JSONDecoder().decode(FeatureSettings.self, from: Data(json.utf8))
        #expect(settings.volumeMixerEnabled)
    }

    @Test(arguments: [false, true], [false, true])
    func pdfAndVolumeSettingsRoundTripIndependently(pdfEnabled: Bool, volumeEnabled: Bool) throws {
        let settings = FeatureSettings(pdfToolsEnabled: pdfEnabled, volumeMixerEnabled: volumeEnabled)
        let restored = try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(settings))
        #expect(settings.pdfToolsEnabled == pdfEnabled)
        #expect(settings.volumeMixerEnabled == volumeEnabled)
        #expect(restored.pdfToolsEnabled == pdfEnabled)
        #expect(restored.volumeMixerEnabled == volumeEnabled)
    }

    @Test(arguments: [#""true""#, "1", "[]", "{}"])
    func volumeSettingRejectsInvalidValues(value: String) {
        let json = "{\"volumeMixerEnabled\":\(value)}"
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(FeatureSettings.self, from: Data(json.utf8))
        }
    }

    @Test
    func legacyPDFPositionMigratesToVolumeWithoutChangingOtherPositions() throws {
        let json = #"{"moduleOrder":["mail","pdf","battery","clipboard","pdf","unknown"]}"#
        let restored = try JSONDecoder().decode(FeatureSettings.self, from: Data(json.utf8))
        #expect(Array(restored.moduleOrder.prefix(4)) == [.mail, .volumeMixer, .system, .clipboard])
        #expect(restored.moduleOrder.filter { $0 == .volumeMixer }.count == 1)
        #expect(!restored.moduleOrder.contains(.pdf))
        let encoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(restored)) as? [String: Any])
        let order = try #require(encoded["moduleOrder"] as? [String])
        #expect(order[1] == "volumeMixer")
        #expect(!order.contains("pdf"))
    }

    @Test(arguments: [
        ["pdf", "mail", "volumeMixer", "pdf"],
        ["volumeMixer", "mail", "pdf", "volumeMixer"],
    ])
    func mixedLegacyAndNewValuesKeepFirstVolumePosition(rawValues: [String]) {
        let order = IslandModuleOrder.normalized(rawValues: rawValues)
        #expect(Array(order.prefix(2)) == [.volumeMixer, .mail])
        #expect(order.filter { $0 == .volumeMixer }.count == 1)
        #expect(!order.contains(.pdf))
        #expect(IslandModuleOrder.normalized(order) == order)
    }

    @Test(arguments: [[], ["unknown"], ["pdf"], ["volumeMixer"], ["pdf", "battery", "system"]])
    func normalizationAlwaysIncludesEachCurrentModuleOnce(rawValues: [String]) {
        let order = IslandModuleOrder.normalized(rawValues: rawValues)
        #expect(Set(order) == Set(IslandModuleOrder.defaultOrder))
        #expect(order.count == IslandModuleOrder.defaultOrder.count)
        #expect(IslandModuleOrder.normalized(order) == order)
        #expect(!order.contains(.pdf))
        #expect(!order.contains(.battery))
    }
}
