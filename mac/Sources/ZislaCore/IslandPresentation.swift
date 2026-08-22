import Foundation

/// Island presentation state machine: folds pointer, drag, and pin interactions into predictable
/// visibility states and side effects.
public struct IslandPresentationReducer {
    public enum Visibility: Equatable, Sendable {
        /// Fully hidden (no panel). Occurs when hover-to-activate is off and the island is not pinned.
        case hidden
        /// Collapsed to a thin strip at the top. The panel stays rendered for lightweight persistent content such as the pet.
        case collapsed
        /// Expanded to the full-featured panel.
        case expanded
        /// Pinned, staying expanded.
        case pinned
    }

    public enum Action: Equatable, Sendable {
        case pointerEntered
        case pointerExited
        case collapseDelayElapsed
        case collapseImmediately
        case setPinned(Bool)
        case setDragging(Bool)
    }

    public enum Effect: Equatable, Sendable {
        case show
        case collapse
        case hide
        case scheduleCollapse
        case cancelScheduledCollapse
    }

    public struct State: Equatable, Sendable {
        var pointerInside = false
        var pinned = false
        var dragging = false
        public internal(set) var visibility: Visibility = .hidden

        /// Whether a panel is currently rendered (collapsed or expanded).
        public var isVisible: Bool { visibility != .hidden }
    }

    public private(set) var state = State()

    public init() {}

    /// Suppresses any collapse while the pointer is inside, the island is pinned, or a drag is in progress.
    private var isHeldOpen: Bool {
        state.pointerInside || state.pinned || state.dragging
    }

    /// Re-evaluates after a release action (pointer exit, drag end, etc.): schedules a collapse if nothing else holds the island open.
    private mutating func reevaluateAfterRelease() -> [Effect] {
        isHeldOpen ? [] : [.scheduleCollapse]
    }

    @discardableResult
    public mutating func send(_ action: Action) -> [Effect] {
        switch action {
        case .pointerEntered:
            state.pointerInside = true
            state.visibility = .expanded
            return [.cancelScheduledCollapse, .show]

        case .pointerExited:
            state.pointerInside = false
            return reevaluateAfterRelease()

        case .collapseDelayElapsed:
            guard !isHeldOpen else { return [] }
            state.visibility = .collapsed
            return [.collapse]

        case .collapseImmediately:
            state.pinned = false
            state.visibility = .collapsed
            return [.cancelScheduledCollapse, .collapse]

        case let .setPinned(pinned):
            state.pinned = pinned
            if pinned {
                state.visibility = .pinned
                return [.cancelScheduledCollapse, .show]
            }
            return reevaluateAfterRelease()

        case let .setDragging(dragging):
            state.dragging = dragging
            if dragging {
                state.visibility = .expanded
                return [.cancelScheduledCollapse, .show]
            }
            return reevaluateAfterRelease()
        }
    }

    /// On startup, enters the collapsed state by default so persistent content (e.g. the pet) remains visible.
    public mutating func start() -> [Effect] {
        guard state.visibility == .hidden else { return [] }
        state.visibility = .collapsed
        return [.collapse]
    }
}
