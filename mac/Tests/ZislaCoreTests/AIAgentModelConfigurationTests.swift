import Foundation
import Testing
@testable import ZislaCore

struct AIAgentModelConfigurationTests {
    @Test
    func voiceModelConfigurationReferenceRoundTripsInSettings() throws {
        let reference = AIModelConfigurationReference.channel(UUID())
        var settings = FeatureSettings.default
        settings.voiceModelConfiguration = reference

        let decoded = try JSONDecoder().decode(
            FeatureSettings.self,
            from: JSONEncoder().encode(settings)
        )

        #expect(decoded.voiceModelConfiguration == reference)
    }
}
