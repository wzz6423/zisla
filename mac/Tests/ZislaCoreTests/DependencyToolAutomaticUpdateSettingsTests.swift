import Foundation
import Testing
@testable import ZislaCore

struct DependencyToolAutomaticUpdateSettingsTests {
    @Test(arguments: [
        "{}",
        #"{"dependencyToolsAutomaticUpdatesEnabled":null}"#,
        #"{"recommendedToolsEnabled":false,"recommendedToolsAutomaticUpdatesEnabled":true}"#,
    ])
    func dependencyUpdatesRequireOptInForNewAndLegacySettings(json: String) throws {
        #expect(!FeatureSettings.default.dependencyToolsAutomaticUpdatesEnabled)
        let settings = try JSONDecoder().decode(FeatureSettings.self, from: Data(json.utf8))
        #expect(!settings.dependencyToolsAutomaticUpdatesEnabled)
        if json.contains("recommendedToolsEnabled") {
            #expect(!settings.recommendedToolsEnabled)
            #expect(settings.recommendedToolsAutomaticUpdatesEnabled)
        }
    }

    @Test(arguments: [
        (false, false, false), (false, false, true), (false, true, false), (false, true, true),
        (true, false, false), (true, false, true), (true, true, false), (true, true, true),
    ])
    func updateChoicesRoundTripIndependently(enabled: (Bool, Bool, Bool)) throws {
        let settings = FeatureSettings(
            mediaEnabled: false,
            recommendedToolsEnabled: enabled.0,
            recommendedToolsAutomaticUpdatesEnabled: enabled.1,
            dependencyToolsAutomaticUpdatesEnabled: enabled.2
        )
        let encoded = try JSONEncoder().encode(settings)
        let payload = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(payload["dependencyToolsAutomaticUpdatesEnabled"] as? Bool == enabled.2)
        let restored = try JSONDecoder().decode(FeatureSettings.self, from: encoded)
        #expect(restored == settings)
        #expect(restored.recommendedToolsEnabled == enabled.0)
        #expect(restored.recommendedToolsAutomaticUpdatesEnabled == enabled.1)
        #expect(restored.dependencyToolsAutomaticUpdatesEnabled == enabled.2)
        #expect(!restored.mediaEnabled)
    }

    @Test(arguments: [#""true""#, "1", "[]", "{}"])
    func dependencyUpdatesRejectInvalidTypes(value: String) {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(FeatureSettings.self,
                from: Data("{\"dependencyToolsAutomaticUpdatesEnabled\":\(value)}".utf8))
        }
    }
}
