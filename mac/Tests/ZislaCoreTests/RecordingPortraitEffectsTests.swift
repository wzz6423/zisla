import Foundation
import Testing
@testable import ZislaCore

struct RecordingPortraitEffectsTests {
    @Test func defaultsPreserveTheOriginalPortrait() {
        let effects = RecordingPortraitEffects()
        #expect(effects.isValid)
        #expect(!effects.isEnabled)
        #expect(effects.smoothing == 0 && effects.brightening == 0 && effects.faceSlimming == 0 && effects.bodySlimming == 0)
    }

    @Test(arguments: [0.0, 0.25, 1.0])
    func eachEffectRoundTripsItsStrength(_ strength: Double) throws {
        for path in [\RecordingPortraitEffects.smoothing, \.brightening, \.faceSlimming, \.bodySlimming] {
            var effects = RecordingPortraitEffects()
            effects[keyPath: path] = strength
            let decoded = try JSONDecoder().decode(RecordingPortraitEffects.self, from: JSONEncoder().encode(effects))
            #expect(decoded == effects)
            #expect(decoded.isEnabled == (strength > 0))
            #expect(decoded.isValid)
        }
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity, -0.01, 1.000_001])
    func invalidStrengthsAreRejectedForEveryEffect(_ strength: Double) {
        for path in [\RecordingPortraitEffects.smoothing, \.brightening, \.faceSlimming, \.bodySlimming] {
            var effects = RecordingPortraitEffects()
            effects[keyPath: path] = strength
            #expect(!effects.isValid)
        }
    }
}
