import Foundation
import Testing
@testable import ZislaCore

struct AudioToolsSettingsTests {
    @Test(arguments: ["{}", #"{"pdfToolsEnabled":false}"#, #"{"audioToolsEnabled":null}"#])
    func enablesAudioToolsForNewAndLegacySettings(json: String) throws {
        #expect(FeatureSettings.default.audioToolsEnabled)
        let settings = try JSONDecoder().decode(FeatureSettings.self, from: Data(json.utf8))
        #expect(settings.audioToolsEnabled)
    }

    @Test(arguments: [false, true], [false, true])
    func audioAndPDFSwitchesRoundTripIndependently(audio: Bool, pdf: Bool) throws {
        let settings = FeatureSettings(pdfToolsEnabled: pdf, audioToolsEnabled: audio)
        let restored = try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(settings))
        #expect(restored.audioToolsEnabled == audio)
        #expect(restored.pdfToolsEnabled == pdf)
    }

    @Test(arguments: ["1", "\"true\"", "[]"])
    func rejectsInvalidSwitchTypes(value: String) {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(FeatureSettings.self, from: Data("{\"audioToolsEnabled\":\(value)}".utf8))
        }
    }
}
