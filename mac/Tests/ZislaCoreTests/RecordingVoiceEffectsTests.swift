import Foundation
import Testing
@testable import ZislaCore

struct RecordingVoiceEffectsTests {
    @Test func effectsDefaultToOriginalAndZeroStrengthDisablesEveryPreset() {
        #expect(RecordingVoiceEffects() == .init(preset: .original, amount: 0.5))
        #expect(!RecordingVoiceEffects().isEnabled)
        for preset in RecordingVoicePreset.allCases {
            #expect(!RecordingVoiceEffects(preset: preset, amount: 0).isEnabled)
        }
    }

    @Test(arguments: RecordingVoicePreset.allCases, [0.0, 0.25, 0.5, 1.0])
    func presetsAndStrengthRoundTripWithoutChangingValues(_ preset: RecordingVoicePreset, _ amount: Double) throws {
        let effects = RecordingVoiceEffects(preset: preset, amount: amount)
        #expect(effects.isValid)
        #expect(effects.isEnabled == (preset != .original && amount > 0))
        #expect(try JSONDecoder().decode(RecordingVoiceEffects.self, from: JSONEncoder().encode(effects)) == effects)
    }

    @Test(arguments: [-0.001, 1.001, Double.nan, .infinity, -.infinity])
    func invalidStrengthIsRejected(_ amount: Double) {
        #expect(!RecordingVoiceEffects(preset: .warm, amount: amount).isValid)
    }
}
