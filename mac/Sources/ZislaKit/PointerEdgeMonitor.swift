import AppKit

struct PointerEdgeEventThrottle: Equatable, Sendable {
    let minimumMoveInterval: TimeInterval
    private var lastMoveTimestamp: TimeInterval?

    init(minimumMoveInterval: TimeInterval = 1.0 / 30.0) {
        self.minimumMoveInterval = max(0, minimumMoveInterval)
    }

    mutating func shouldEmit(eventType: NSEvent.EventType, timestamp: TimeInterval) -> Bool {
        guard eventType == .mouseMoved else {
            lastMoveTimestamp = nil
            return true
        }
        guard let lastMoveTimestamp,
              timestamp >= lastMoveTimestamp,
              timestamp - lastMoveTimestamp < minimumMoveInterval else {
            self.lastMoveTimestamp = timestamp
            return true
        }
        return false
    }
}

@MainActor
public final class PointerEdgeMonitor {
    public enum Interaction: Equatable, Sendable {
        case moved
        case dragging(hasSupportedPayload: Bool)
        case dragEnded
    }

    public typealias Handler = @MainActor @Sendable (CGPoint, Interaction) -> Void

    private let handler: Handler
    private let dragPasteboard: NSPasteboard
    private var payloadClassifier: DragPayloadSessionClassifier
    private var cachedDragResult: (changeCount: Int, hasSupportedPayload: Bool)?
    private var eventThrottle = PointerEdgeEventThrottle()
    private var globalMonitor: Any?
    private var localMonitor: Any?

    public var isRunning: Bool {
        globalMonitor != nil || localMonitor != nil
    }

    public init(
        dragPasteboard: NSPasteboard = NSPasteboard(name: .drag),
        handler: @escaping Handler
    ) {
        self.dragPasteboard = dragPasteboard
        payloadClassifier = DragPayloadSessionClassifier(
            initialChangeCount: dragPasteboard.changeCount
        )
        self.handler = handler
    }

    public func start() {
        guard !isRunning else { return }

        let mask: NSEvent.EventTypeMask = [
            .mouseMoved,
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown,
            .leftMouseDragged,
            .rightMouseDragged,
            .otherMouseDragged,
            .leftMouseUp,
            .rightMouseUp,
            .otherMouseUp,
        ]
        payloadClassifier.reset(initialChangeCount: dragPasteboard.changeCount)
        cachedDragResult = nil
        eventThrottle = PointerEdgeEventThrottle()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.emit(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.emit(event)
            return event
        }
    }

    public func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        globalMonitor = nil
        localMonitor = nil
    }

    isolated deinit {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
    }

    private nonisolated func emit(_ event: NSEvent) {
        let eventType = event.type
        let timestamp = event.timestamp
        // AppKit guarantees event monitor callbacks run on the main thread, avoiding a Task per mouse event.
        MainActor.assumeIsolated {
            guard eventThrottle.shouldEmit(
                eventType: eventType,
                timestamp: timestamp
            ) else { return }
            let interaction: Interaction
            switch PointerEdgeEventAction(eventType: eventType) {
            case .dragging:
                let changeCount = dragPasteboard.changeCount
                let hasSupportedPayload: Bool
                if let cachedDragResult, cachedDragResult.changeCount == changeCount {
                    hasSupportedPayload = cachedDragResult.hasSupportedPayload
                } else {
                    let snapshot = DragPayloadSnapshot(pasteboard: dragPasteboard)
                    hasSupportedPayload = payloadClassifier.inspect(snapshot)
                    cachedDragResult = (snapshot.changeCount, hasSupportedPayload)
                }
                interaction = .dragging(hasSupportedPayload: hasSupportedPayload)
            case .dragEnded:
                payloadClassifier.finish(changeCount: dragPasteboard.changeCount)
                cachedDragResult = nil
                interaction = .dragEnded
            case .pointerDown:
                payloadClassifier.prepareForPointerDrag()
                cachedDragResult = nil
                interaction = .moved
            case .moved:
                interaction = .moved
            }
            handler(NSEvent.mouseLocation, interaction)
        }
    }
}

enum PointerEdgeEventAction: Equatable, Sendable {
    case moved
    case pointerDown
    case dragging
    case dragEnded

    init(eventType: NSEvent.EventType) {
        switch eventType {
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            self = .dragging
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            self = .dragEnded
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            self = .pointerDown
        default:
            self = .moved
        }
    }
}
