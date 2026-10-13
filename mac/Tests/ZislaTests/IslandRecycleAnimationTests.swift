import Foundation
import SwiftUI
import Testing
@testable import Zisla

/// The island used to blink out of existence: the reveal mask animated back into the pill while the
/// surface's opacity snapped to zero in the same frame, so nobody ever saw the fold. These tests pin
/// the two halves of the recycle to the same clock.
struct IslandRecycleAnimationTests {
    @Test
    func theFoldAndTheDissolveShareOneClock() {
        // Equal durations are the whole point: a dissolve that outruns the fold reads as a blink,
        // one that lags leaves a ghost pill sitting on the notch. The expand reveal shares the
        // same duration as the fold so growing and shrinking feel symmetric; only the fold keeps
        // its bounce-free ease.
        #expect(ZislaMotion.islandRecycle == .smooth(duration: 0.22))
        #expect(ZislaMotion.islandRecycleFade == .easeIn(duration: 0.22))
        #expect(ZislaMotion.islandReveal == .snappy(duration: 0.22, extraBounce: 0.05))
    }

    @Test
    func quickNoteClipboardAssistantWaitsUntilTheFoldSettles() {
        #expect(ZislaMotion.islandRecycleSettleDelay == .milliseconds(280))
    }

}
