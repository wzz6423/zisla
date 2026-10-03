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

    @Test @MainActor
    func keyboardTransitionsReachTheHandlerWithoutBecomingPointerMoves() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        var keyboardEvents: [NSEvent.EventType] = []
        var pointerEvents = 0
        let monitor = PointerEdgeMonitor(dragPasteboard: pasteboard, onKeyboardEvent: { type, _ in
            keyboardEvents.append(type)
        }) { _, _ in pointerEvents += 1 }
        for type in [NSEvent.EventType.flagsChanged, .keyDown, .keyUp] {
            let event = try #require(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [],
                                                    timestamp: 0, windowNumber: 0, context: nil, characters: "",
                                                    charactersIgnoringModifiers: "", isARepeat: false, keyCode: 55))
            monitor.emit(event)
        }
        #expect(keyboardEvents == [.flagsChanged, .keyDown, .keyUp])
        #expect(pointerEvents == 0)
        #expect(!monitor.isRunning)
    }
}
