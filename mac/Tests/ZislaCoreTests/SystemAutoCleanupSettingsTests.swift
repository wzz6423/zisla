import Foundation
import Testing

@testable import ZislaCore

struct SystemAutoCleanupSettingsTests {
    @Test(arguments: ["{}", #"{"systemCleanupPolicy":null,"systemCleanupScope":null}"#,
                      #"{"systemMonitorEnabled":false,"voiceRecordingCleanupPolicy":"sevenDays"}"#])
    func legacySettingsKeepAutomaticSystemCleanupDisabled(payload: String) throws {
        let settings = try JSONDecoder().decode(FeatureSettings.self, from: Data(payload.utf8))
        #expect(settings.systemCleanupPolicy == .never)
        #expect(settings.systemCleanupScope == .trustedOnly)
        #expect(FeatureSettings.default.systemCleanupPolicy == .never)
        #expect(FeatureSettings.default.systemCleanupScope == .trustedOnly)
        if payload.contains("sevenDays") {
            #expect(settings.voiceRecordingCleanupPolicy == .sevenDays)
            #expect(!settings.systemMonitorEnabled)
        }
    }

    @Test(arguments: VoiceRecordingCleanupPolicy.allCases, SystemCleanupScope.allCases)
    func systemCleanupChoicesRoundTripIndependentlyOfVoiceCleanup(
        policy: VoiceRecordingCleanupPolicy, scope: SystemCleanupScope
    ) throws {
        var settings = FeatureSettings(systemCleanupPolicy: policy, systemCleanupScope: scope)
        settings.voiceRecordingCleanupPolicy = .fifteenDays
        settings.systemMonitorEnabled = false
        let restored = try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(settings))
        #expect(restored == settings)
        #expect(restored.systemCleanupPolicy == policy)
        #expect(restored.systemCleanupScope == scope)
        #expect(restored.voiceRecordingCleanupPolicy == .fifteenDays)
    }

    @Test(arguments: [
        #"{"systemCleanupPolicy":"daily"}"#,
        #"{"systemCleanupScope":"unknown"}"#,
        #"{"systemCleanupPolicy":7}"#,
        #"{"systemCleanupScope":true}"#,
    ])
    func invalidCleanupPreferencesAreRejected(payload: String) {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(FeatureSettings.self, from: Data(payload.utf8))
        }
    }
}
