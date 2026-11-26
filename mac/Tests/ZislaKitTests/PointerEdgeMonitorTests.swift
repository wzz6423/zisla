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

    @MainActor
    private final class PointerBox {
        var location = CGPoint(x: 100, y: 500)
        var emittedLocations: [CGPoint] = []
        var scheduledAction: (@MainActor () -> Void)?
        var cancelCount = 0
        var scheduleCount = 0
    }

    @Test @MainActor
    func coalescedMouseMoveSchedulesOneTrailingEmitAndCancelsOnNextEmitOrStop() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let box = PointerBox()

        let monitor = PointerEdgeMonitor(dragPasteboard: pasteboard) { point, interaction in
            #expect(interaction == .moved)
            box.emittedLocations.append(point)
        }
        monitor.pointerLocationProvider = { box.location }
        monitor.trailingMoveScheduler = { _, action in
            box.scheduleCount += 1
            box.scheduledAction = action
            return {
                box.cancelCount += 1
                box.scheduledAction = nil
            }
        }

        func makeMove(timestamp: TimeInterval) throws -> NSEvent {
            try #require(NSEvent.mouseEvent(
                with: .mouseMoved,
                location: .zero,
                modifierFlags: [],
                timestamp: timestamp,
                windowNumber: 0,
                context: nil,
                eventNumber: 0,
                clickCount: 0,
                pressure: 0
            ))
        }

        // First move emits immediately.
        monitor.emit(try makeMove(timestamp: 1.00))
        #expect(box.emittedLocations == [CGPoint(x: 100, y: 500)])
        #expect(box.scheduleCount == 0)

        // Rapid moves inside the 33ms window coalesce into one trailing emit.
        box.location = CGPoint(x: 2_000, y: 1_430)
        monitor.emit(try makeMove(timestamp: 1.01))
        box.location = CGPoint(x: 2_000, y: 1_440)
        monitor.emit(try makeMove(timestamp: 1.02))
        #expect(box.emittedLocations.count == 1)
        #expect(box.scheduleCount == 1)

        // Firing the trailing callback emits the final resting pointer coordinates.
        box.scheduledAction?()
        #expect(box.emittedLocations == [CGPoint(x: 100, y: 500), CGPoint(x: 2_000, y: 1_440)])

        // A later immediate event supersedes a pending trailing callback.
        box.location = CGPoint(x: 2_100, y: 1_440)
        monitor.emit(try makeMove(timestamp: 1.025))
        #expect(box.scheduleCount == 2)
        box.location = CGPoint(x: 2_200, y: 1_440)
        monitor.emit(try makeMove(timestamp: 1.10))
        #expect(box.cancelCount == 1)
        #expect(box.scheduledAction == nil)
        #expect(box.emittedLocations.last == CGPoint(x: 2_200, y: 1_440))

        // Stopping cancels any pending trailing callback.
        box.location = CGPoint(x: 2_250, y: 1_440)
        monitor.emit(try makeMove(timestamp: 1.11))
        #expect(box.scheduleCount == 3)
        monitor.stop()
        #expect(box.cancelCount == 2)
        #expect(box.scheduledAction == nil)

        // Deinitialization cancels any pending trailing callback without leaking the monitor.
        var temporaryMonitor: PointerEdgeMonitor? = PointerEdgeMonitor(dragPasteboard: pasteboard) { _, _ in }
        temporaryMonitor?.pointerLocationProvider = { box.location }
        temporaryMonitor?.trailingMoveScheduler = { _, action in
            box.scheduleCount += 1
            box.scheduledAction = action
            return {
                box.cancelCount += 1
                box.scheduledAction = nil
            }
        }
        temporaryMonitor?.emit(try makeMove(timestamp: 2.00))
        temporaryMonitor?.emit(try makeMove(timestamp: 2.01))
        #expect(box.scheduleCount == 4)
        weak let weakMonitor = temporaryMonitor
        temporaryMonitor = nil
        #expect(weakMonitor == nil)
        #expect(box.cancelCount == 3)
        #expect(box.scheduledAction == nil)
    }
}
