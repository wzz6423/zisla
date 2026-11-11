import Foundation
import Testing
@testable import ZislaCore

struct ImageToolsSettingsTests {
    @Test(arguments: ["{}", #"{"pdfToolsEnabled":false}"#, #"{"imageToolsEnabled":null}"#])
    func legacySettingsEnableImageToolsIndependently(json: String) throws {
        let settings = try JSONDecoder().decode(FeatureSettings.self, from: Data(json.utf8))
        #expect(settings.imageToolsEnabled)
    }

    @Test(arguments: [false, true], [false, true])
    func imageAndPDFChoicesRoundTripIndependently(imageEnabled: Bool, pdfEnabled: Bool) throws {
        let settings = FeatureSettings(pdfToolsEnabled: pdfEnabled, imageToolsEnabled: imageEnabled)
        let restored = try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(settings))
        #expect(restored.imageToolsEnabled == imageEnabled)
        #expect(restored.pdfToolsEnabled == pdfEnabled)
    }

    @Test(arguments: [#""true""#, "1", "[]", "{}"])
    func invalidImageToolsChoicesFail(value: String) {
        let json = "{\"imageToolsEnabled\":\(value)}"
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(FeatureSettings.self, from: Data(json.utf8))
        }
    }
}
