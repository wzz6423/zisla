import Foundation
import ZislaCore

@MainActor
public final class AIQuotaNoticeController {
    static let maximumPending = 64
    private struct Pending {
        let alert: AIQuotaThresholdAlert
        let expiresAt: Date
    }

    private let queue: SideNoticeQueue
    private let sleeper: @Sendable (Duration) async throws -> Void
    private let clock: @Sendable () -> Date
    private var tracker = AIQuotaThresholdTracker()
    private var pending: [Pending] = []
    private var displayTask: Task<Void, Never>?
    private var activeIDs: [String] = []

    public convenience init(queue: SideNoticeQueue) {
        self.init(queue: queue, sleeper: { try await Task.sleep(for: $0) })
    }

    init(queue: SideNoticeQueue, sleeper: @escaping @Sendable (Duration) async throws -> Void,
         clock: @escaping @Sendable () -> Date = { Date() }) {
        self.queue = queue
        self.sleeper = sleeper
        self.clock = clock
    }

    deinit { displayTask?.cancel() }

    public func consume(_ snapshot: AIQuotaSnapshot, enabled: Bool, at now: Date = Date()) {
        let alerts = tracker.consume(snapshot, at: now)
        guard enabled else {
            stop()
            return
        }
        for alert in alerts {
            pending.removeAll { $0.alert.accountID == alert.accountID && $0.alert.windowID == alert.windowID }
            pending.append(Pending(alert: alert, expiresAt: now.addingTimeInterval(600)))
        }
        pending.sort { ($0.alert.threshold, $0.alert.accountID, $0.alert.windowID) < ($1.alert.threshold, $1.alert.accountID, $1.alert.windowID) }
        pending = Array(pending.prefix(Self.maximumPending))
        showNext()
    }

    public func stop() {
        tracker = AIQuotaThresholdTracker()
        displayTask?.cancel()
        displayTask = nil
        pending.removeAll()
        for id in activeIDs { queue.remove(id: id) }
        activeIDs.removeAll()
    }

    private func showNext() {
        pending.removeAll { $0.expiresAt <= clock() }
        guard displayTask == nil, !pending.isEmpty else { return }
        let alert = pending.removeFirst().alert
        let id = "ai-quota-\(UUID().uuidString)"
        let percent = "\(Int(alert.remainingPercent.rounded(.down)))%"
        let detail = "\(alert.accountLabel) · \(alert.windowLabel)"
        let metadata = ["providerID": alert.providerID, "windowID": alert.windowID, "remaining": percent]
        let left = IslandNotice(
            id: "\(id)-left",
            title: alert.accountLabel,
            detail: detail,
            kind: alert.threshold <= 10 ? .warning : .info,
            side: .left,
            metadata: metadata
        )
        let right = IslandNotice(
            id: "\(id)-right",
            title: percent,
            detail: detail,
            kind: alert.threshold <= 10 ? .warning : .info,
            side: .right,
            metadata: metadata
        )
        activeIDs = [left.id, right.id]
        queue.enqueue(left, expiresAfter: 5)
        queue.enqueue(right, expiresAfter: 5)

        let sleeper = sleeper
        displayTask = Task { [weak self, sleeper] in
            do { try await sleeper(.seconds(5)) }
            catch { return }
            guard !Task.isCancelled, let self else { return }
            for id in self.activeIDs { self.queue.remove(id: id) }
            self.activeIDs.removeAll()
            self.displayTask = nil
            self.showNext()
        }
    }
}
