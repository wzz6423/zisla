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

    public typealias KeyboardHandler = @MainActor @Sendable (NSEvent.EventType, Bool) -> Void

    private let handler: Handler
    private let onKeyboardEvent: KeyboardHandler?
    private let dragPasteboard: NSPasteboard
    private var payloadClassifier: DragPayloadSessionClassifier
    private var cachedDragResult: (changeCount: Int, hasSupportedPayload: Bool)?
    private var eventThrottle = PointerEdgeEventThrottle()
    private var cancelTrailingMove: (@MainActor () -> Void)?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    internal var pointerLocationProvider: @MainActor () -> CGPoint = { NSEvent.mouseLocation }
    internal var trailingMoveScheduler: @MainActor (TimeInterval, @escaping @MainActor () -> Void) -> @MainActor () -> Void = { delay, action in
        let timer = Timer(timeInterval: delay, repeats: false) { _ in
            MainActor.assumeIsolated { action() }
        }
        RunLoop.main.add(timer, forMode: .common)
        return { timer.invalidate() }
    }

    public var isRunning: Bool {
        globalMonitor != nil || localMonitor != nil
    }

    public init(
        dragPasteboard: NSPasteboard = NSPasteboard(name: .drag),
        onKeyboardEvent: KeyboardHandler? = nil,
        handler: @escaping Handler
    ) {
        self.dragPasteboard = dragPasteboard
        payloadClassifier = DragPayloadSessionClassifier(
            initialChangeCount: dragPasteboard.changeCount
        )
        self.handler = handler
        self.onKeyboardEvent = onKeyboardEvent
    }

    public func start() {
        guard !isRunning else { return }

        var mask: NSEvent.EventTypeMask = [
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
        if onKeyboardEvent != nil {
            mask.formUnion([.flagsChanged, .keyDown, .keyUp])
        }
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
        cancelTrailingMove?()
        cancelTrailingMove = nil
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
        cancelTrailingMove?()
        cancelTrailingMove = nil
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
    }

    nonisolated func emit(_ event: NSEvent) {
        let eventType = event.type
        let timestamp = event.timestamp
        let isRepeat = eventType == .keyDown && event.isARepeat
        // AppKit guarantees event monitor callbacks run on the main thread, avoiding a Task per mouse event.
        MainActor.assumeIsolated {
            if eventType == .flagsChanged || eventType == .keyDown || eventType == .keyUp {
                onKeyboardEvent?(eventType, isRepeat)
                return
            }
            guard eventThrottle.shouldEmit(
                eventType: eventType,
                timestamp: timestamp
            ) else {
                // Schedule one trailing emit so a fast flick that stops inside a display's trigger
                // during the throttle window is delivered promptly instead of waiting for recovery polling.
                if cancelTrailingMove == nil {
                    cancelTrailingMove = trailingMoveScheduler(eventThrottle.minimumMoveInterval) { [weak self] in
                        guard let self else { return }
                        self.cancelTrailingMove = nil
                        self.handler(self.pointerLocationProvider(), .moved)
                    }
                }
                return
            }
            cancelTrailingMove?()
            cancelTrailingMove = nil
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
            handler(pointerLocationProvider(), interaction)
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
