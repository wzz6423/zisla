import Foundation

/// 灵动岛展示状态机：把指针、拖拽、固定等交互折叠成可预测的可见性状态与副作用。
public struct IslandPresentationReducer {
    public enum Visibility: Equatable, Sendable {
        /// 完全隐藏（无面板）。通常在「悬停激活」关闭且未固定时出现。
        case hidden
        /// 收起为顶部细条。面板保持渲染，用来展示常驻宠物等轻量内容。
        case collapsed
        /// 展开为完整功能面板。
        case expanded
        /// 被固定，保持展开。
        case pinned
    }

    public enum Action: Equatable, Sendable {
        case pointerEntered
        case pointerExited
        case collapseDelayElapsed
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

        /// 是否有渲染中的面板（收起或展开）。
        public var isVisible: Bool { visibility != .hidden }
    }

    public private(set) var state = State()

    public init() {}

    /// 只要指针在内、被固定或正在拖拽，任何折叠都应被抑制。
    private var isHeldOpen: Bool {
        state.pointerInside || state.pinned || state.dragging
    }

    /// 收到抬手/移出等释放动作后重新评估：不再被任何理由留存则安排折叠。
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

    /// 启动后默认进入收起态，让常驻内容（如宠物）保持可见。
    public mutating func start() -> [Effect] {
        guard state.visibility == .hidden else { return [] }
        state.visibility = .collapsed
        return [.collapse]
    }
}
