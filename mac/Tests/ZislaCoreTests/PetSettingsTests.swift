import Foundation
import Testing
@testable import ZislaCore

struct PetSettingsTests {
    private static let retiredIDs = [
        "cow", "dog", "duck", "frog", "horse", "monkey", "owl",
        "panda", "parrot", "penguin", "pig", "rabbit", "sloth", "whale",
    ]

    @Test
    func newAndMissingSettingsSelectChiikawa() throws {
        #expect(FeatureSettings.default.petID == "chiikawa")
        for json in ["{}", #"{"petID":null}"#] {
            let settings = try JSONDecoder().decode(FeatureSettings.self, from: Data(json.utf8))
            #expect(settings.petID == "chiikawa")
            #expect(settings.petEnabled)
            #expect(settings.petSide == .left)
        }
    }

    @Test(arguments: retiredIDs, [false, true])
    func retiredSelectionMigratesWithoutChangingPetOptions(id: String, enabled: Bool) throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "petID": id, "petEnabled": enabled, "petSide": "right",
        ])
        let settings = try JSONDecoder().decode(FeatureSettings.self, from: data)
        #expect(settings.petID == "chiikawa")
        #expect(settings.petEnabled == enabled)
        #expect(settings.petSide == .right)

        let restored = try JSONDecoder().decode(
            FeatureSettings.self, from: JSONEncoder().encode(settings)
        )
        #expect(restored.petID == "chiikawa")
        #expect(restored.petEnabled == enabled)
        #expect(restored.petSide == .right)
    }

    @Test(arguments: ["bear", "chick", "chiikawa", "kirby", "pikachu", "toothless", "boba"])
    func retainedAndNewSelectionsRoundTrip(id: String) throws {
        let settings = FeatureSettings(petEnabled: false, petID: id, petSide: .right)
        let restored = try JSONDecoder().decode(
            FeatureSettings.self, from: JSONEncoder().encode(settings)
        )
        #expect(restored.petID == id)
        #expect(!restored.petEnabled)
        #expect(restored.petSide == .right)
    }

    @Test(arguments: ["", "custom-pet", "future-pet"])
    func unrelatedIdentifiersAreNotRewritten(id: String) throws {
        let data = try JSONSerialization.data(withJSONObject: ["petID": id])
        let settings = try JSONDecoder().decode(FeatureSettings.self, from: data)
        #expect(settings.petID == id)
    }

    @Test(arguments: [#"{"petID":42}"#, #"{"petID":false}"#, #"{"petID":[]}"#])
    func invalidSelectionTypesStillFailDecoding(json: String) {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(FeatureSettings.self, from: Data(json.utf8))
        }
    }
}
