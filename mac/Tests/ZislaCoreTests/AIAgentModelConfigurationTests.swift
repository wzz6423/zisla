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

    @Test
    func chatThreadLocalModelSelectionRoundTrips() throws {
        let localModelID = UUID()
        let thread = AgentChatThread(localModelID: localModelID)

        let decoded = try JSONDecoder().decode(
            AgentChatThread.self,
            from: JSONEncoder().encode(thread)
        )

        #expect(decoded.localModelID == localModelID)
    }
}
