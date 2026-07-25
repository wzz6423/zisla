import Combine
import Foundation
import ZislaCore

@MainActor
public final class SideNoticeQueue: ObservableObject {
    @Published public private(set) var left: [IslandNotice] = []
    @Published public private(set) var right: [IslandNotice] = []

    private var expiryTasks: [String: Task<Void, Never>] = [:]
    private var persistentIDs: Set<String> = []
    private let capacityPerSide: Int
    private let expirySleeper: @Sendable (Duration) async throws -> Void

    public convenience init(capacityPerSide: Int = 3) {
        self.init(
            capacityPerSide: capacityPerSide,
            expirySleeper: { try await Task.sleep(for: $0) }
        )
    }

    init(
        capacityPerSide: Int,
        expirySleeper: @escaping @Sendable (Duration) async throws -> Void
    ) {
        self.capacityPerSide = max(1, capacityPerSide)
        self.expirySleeper = expirySleeper
    }

    public func enqueue(_ notice: IslandNotice, expiresAfter seconds: Double? = 6) {
        remove(id: notice.id)
        switch notice.side {
        case .left:
            left.append(notice)
            trimOrdinaryOverflow(on: .left)
        case .right:
            right.append(notice)
            trimOrdinaryOverflow(on: .right)
        }
        if let seconds {
            scheduleExpiry(for: notice.id, after: seconds)
        } else {
            persistentIDs.insert(notice.id)
        }
    }

    /// 仅刷新已在队列中的通知内容；不新增、不取消或重启到期任务。
    @discardableResult
    public func updateIfPresent(_ notice: IslandNotice) -> Bool {
        if let index = left.firstIndex(where: { $0.id == notice.id }) {
            left[index] = notice
            return true
        }
        if let index = right.firstIndex(where: { $0.id == notice.id }) {
            right[index] = notice
            return true
        }
        return false
    }

    public func setHovered(_ hovered: Bool, id: String) {
        guard !persistentIDs.contains(id) else { return }
        expiryTasks[id]?.cancel()
        expiryTasks[id] = nil
        if !hovered {
            scheduleExpiry(for: id, after: 3)
        }
    }

    public func remove(id: String) {
        expiryTasks[id]?.cancel()
        expiryTasks[id] = nil
        persistentIDs.remove(id)
        left.removeAll { $0.id == id }
        right.removeAll { $0.id == id }
    }

    public func removeAll() {
        for task in expiryTasks.values { task.cancel() }
        expiryTasks.removeAll()
        persistentIDs.removeAll()
        left.removeAll()
        right.removeAll()
    }

    private func trimOrdinaryOverflow(on side: NoticeSide) {
        let notices: [IslandNotice]
        switch side {
        case .left: notices = left
        case .right: notices = right
        }
        let ordinaryIDs = notices
            .filter { !Self.isCompactCollapsedNotice($0) }
            .map(\.id)
        guard ordinaryIDs.count > capacityPerSide else { return }
        let overflow = ordinaryIDs.count - capacityPerSide
        for id in ordinaryIDs.prefix(overflow) {
            remove(id: id)
        }
    }

    /// 与 SideNoticeLayoutEngine 一致：折叠展示的活动项不占普通侧容量。
    private static func isCompactCollapsedNotice(_ notice: IslandNotice) -> Bool {
        notice.id.hasPrefix("ai-active-")
            || notice.id.hasPrefix("media-active-")
            || notice.id.hasPrefix("focus-countdown-")
            || notice.id.hasPrefix("toolbox-reminder-")
    }

    private func scheduleExpiry(for id: String, after seconds: Double) {
        guard contains(id: id) else { return }
        let sleeper = expirySleeper
        expiryTasks[id] = Task { [weak self, sleeper] in
            do {
                try await sleeper(.seconds(seconds))
            } catch {
                return
            }
            self?.remove(id: id)
        }
    }

    private func contains(id: String) -> Bool {
        left.contains { $0.id == id } || right.contains { $0.id == id }
    }
}
