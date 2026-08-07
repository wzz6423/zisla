import AppKit
import Testing

@testable import ZislaKit

struct PointerEdgeMonitorTests {
    @Test
    func mouseMovesAreCoalescedButInteractionsStayImmediate() {
        var throttle = PointerEdgeEventThrottle(minimumMoveInterval: 0.05)

        let firstMove = throttle.shouldEmit(eventType: .mouseMoved, timestamp: 1.00)
        let coalescedMove = throttle.shouldEmit(eventType: .mouseMoved, timestamp: 1.02)
        let pointerDown = throttle.shouldEmit(eventType: .leftMouseDown, timestamp: 1.03)
        let moveAfterInteraction = throttle.shouldEmit(eventType: .mouseMoved, timestamp: 1.04)
        let laterMove = throttle.shouldEmit(eventType: .mouseMoved, timestamp: 1.10)

        #expect(firstMove)
        #expect(!coalescedMove)
        #expect(pointerDown)
        #expect(moveAfterInteraction)
        #expect(laterMove)
    }
}
