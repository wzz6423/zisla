import Combine
import Foundation
import ZislaCore

@MainActor
public final class SideNoticeQueue: ObservableObject {
    public nonisolated static let defaultCapacityPerSide = 3
    @Published public private(set) var left: [IslandNotice] = []
    @Published public private(set) var right: [IslandNotice] = []
    @Published public private(set) var activeNotificationScenarios: Set<NotificationScenario> = []
    @Published private var scenarioRevision = 0

    private var expiryTasks: [String: Task<Void, Never>] = [:]
    private var persistentIDs: Set<String> = []
    private let capacityPerSide: Int
    private let expirySleeper: @Sendable (Duration) async throws -> Void
    private let now: () -> Date
    private var scenarioBuffer = ScenarioNotificationBuffer()
    private var nextNoticeRevision: UInt64 = 0
    private var noticeRevisions: [String: UInt64] = [:]
    private var externalEventIDs: [String] = []

    public convenience init(capacityPerSide: Int = SideNoticeQueue.defaultCapacityPerSide,
                            now: @escaping () -> Date = Date.init) {
        self.init(
            capacityPerSide: capacityPerSide,
            expirySleeper: { try await Task.sleep(for: $0) },
            now: now
        )
    }

    init(
        capacityPerSide: Int,
        expirySleeper: @escaping @Sendable (Duration) async throws -> Void,
        now: @escaping () -> Date = Date.init
    ) {
        self.capacityPerSide = max(1, capacityPerSide)
        self.expirySleeper = expirySleeper
        self.now = now
    }

    public func enqueue(_ notice: IslandNotice, expiresAfter seconds: Double? = 6) {
        removeVisible(id: notice.id)
        recordScenarioEvent(notice)
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

    /// Updates the content of a notice already in the queue; does not add, cancel, or restart its expiry task.
    @discardableResult
    public func updateIfPresent(_ notice: IslandNotice) -> Bool {
        if let index = left.firstIndex(where: { $0.id == notice.id }) {
            left[index] = notice
            recordScenarioEvent(notice)
            return true
        }
        if let index = right.firstIndex(where: { $0.id == notice.id }) {
            right[index] = notice
            recordScenarioEvent(notice)
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
        scenarioBuffer.remove(id: id)
        scenarioRevision &+= 1
        removeVisible(id: id)
    }

    private func removeVisible(id: String) {
        noticeRevisions[id] = nil
        externalEventIDs.removeAll { $0 == id }
        expiryTasks[id]?.cancel()
        expiryTasks[id] = nil
        persistentIDs.remove(id)
        left.removeAll { $0.id == id }
        right.removeAll { $0.id == id }
    }

    public func removeVisible(withIDPrefix prefix: String) {
        let ids = (left + right).lazy.map(\.id).filter { $0.hasPrefix(prefix) }
        for id in Array(ids) { removeVisible(id: id) }
    }

    public func removeAll() {
        scenarioBuffer.removeAll()
        noticeRevisions.removeAll()
        externalEventIDs.removeAll()
        scenarioRevision &+= 1
        for task in expiryTasks.values { task.cancel() }
        expiryTasks.removeAll()
        persistentIDs.removeAll()
        left.removeAll()
        right.removeAll()
    }

    public func removeAll(withIDPrefix prefix: String) {
        scenarioBuffer.removeAll(withIDPrefix: prefix)
        scenarioRevision &+= 1
        let ids = (left + right)
            .lazy
            .map(\.id)
            .filter { $0.hasPrefix(prefix) }
        for id in Array(ids) { remove(id: id) }
    }

    public func removeAll(withIDPrefix prefix: String, except ids: Set<String>) {
        scenarioBuffer.removeAll(withIDPrefix: prefix, except: ids)
        scenarioRevision &+= 1
        let staleIDs = (left + right)
            .lazy
            .map(\.id)
            .filter { $0.hasPrefix(prefix) && !ids.contains($0) }
        for id in Array(staleIDs) { remove(id: id) }
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
            removeVisible(id: id)
        }
    }

    /// Consistent with SideNoticeLayoutEngine: collapsed active items do not consume ordinary side capacity.
    private static func isCompactCollapsedNotice(_ notice: IslandNotice) -> Bool {
        notice.id.hasPrefix("ai-active-")
            || notice.id.hasPrefix("media-active-")
            || notice.id.hasPrefix("focus-countdown-")
            || notice.id.hasPrefix("focus-mode-")
            || notice.id.hasPrefix("focus-transition")
            || LowBatteryNoticeController.isLowBatteryNotice(notice)
            || notice.id.hasPrefix("mail-notification-")
            || notice.id.hasPrefix("toolbox-reminder-")
            || notice.id.hasPrefix("browser-download-")
            || notice.id.hasPrefix("video-download-")
            || notice.id.hasPrefix("voice-processing-")
            || notice.id.hasPrefix("screen-recording-operation-")
            || notice.style == .headphone
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
            guard !Task.isCancelled else { return }
            self?.removeVisible(id: id)
        }
    }

    private func contains(id: String) -> Bool {
        left.contains { $0.id == id } || right.contains { $0.id == id }
    }

    public func configureNotificationScenarios(_ settings: NotificationScenarioSettings,
                                               displayIdentifiers: Set<String>? = nil) {
        let displays = displayIdentifiers ?? scenarioBuffer.displayIdentifiers
        guard scenarioBuffer.settings != settings || scenarioBuffer.displayIdentifiers != displays else { return }
        scenarioBuffer.configure(settings, displays: displays,
            notices: scenarioNotices, latestRevision: nextNoticeRevision, at: now())
        scenarioRevision &+= 1
    }

    public func setNotificationScenarios(_ scenarios: Set<NotificationScenario>) {
        guard activeNotificationScenarios != scenarios else { return }
        activeNotificationScenarios = scenarios
        scenarioBuffer.setScenarios(scenarios, notices: scenarioNotices, latestRevision: nextNoticeRevision, at: now())
        scenarioRevision &+= 1
    }

    public func setNotificationScenario(_ scenario: NotificationScenario, active: Bool) {
        var scenarios = activeNotificationScenarios
        if active { scenarios.insert(scenario) } else { scenarios.remove(scenario) }
        setNotificationScenarios(scenarios)
    }

    public func notificationBehavior(for importance: ScenarioNoticeImportance,
                                     displayIdentifier: String? = nil) -> ScenarioNotificationBehavior {
        scenarioBuffer.settings.behavior(for: importance, scenarios: activeNotificationScenarios,
            displayIdentifier: displayIdentifier)
    }

    public func recordScenarioEvent(_ notice: IslandNotice) {
        nextNoticeRevision &+= 1
        noticeRevisions[notice.id] = nextNoticeRevision
        if !contains(id: notice.id) {
            externalEventIDs.removeAll { $0 == notice.id }
            externalEventIDs.append(notice.id)
            if externalEventIDs.count > ScenarioNotificationBuffer.capacityPerDisplay {
                let expired = externalEventIDs.removeFirst()
                if !contains(id: expired) { noticeRevisions[expired] = nil }
            }
        }
        scenarioBuffer.receive(notice, revision: nextNoticeRevision, at: now())
        scenarioRevision &+= 1
    }

    public func suppressScenarioFeedback(_ notice: IslandNotice, displayIdentifier: String?) -> Bool {
        guard notificationBehavior(for: ScenarioNoticeImportance(notice: notice),
            displayIdentifier: displayIdentifier) != .show else { return false }
        recordScenarioEvent(notice)
        releaseScenarioEventVisibility(id: notice.id)
        return true
    }

    public func releaseScenarioEventVisibility(id: String) {
        noticeRevisions[id] = nil
        externalEventIDs.removeAll { $0 == id }
        scenarioRevision &+= 1
    }

    public func isScenarioNoticeVisible(_ notice: IslandNotice, displayIdentifier: String) -> Bool {
        scenarioBuffer.isVisible(notice, revision: noticeRevisions[notice.id] ?? 0, on: displayIdentifier)
    }

    public func presentationNotices(_ notices: [IslandNotice], displayIdentifier: String) -> [IslandNotice] {
        notices.filter { isScenarioNoticeVisible($0, displayIdentifier: displayIdentifier) }
    }

    public func scenarioReview(displayIdentifier: String) -> [ScenarioNotificationReviewItem] {
        scenarioBuffer.review(on: displayIdentifier, at: now())
    }

    public func dismissScenarioReview(displayIdentifier: String) {
        scenarioBuffer.dismissReview(on: displayIdentifier)
        scenarioRevision &+= 1
    }

    public func scenarioReviewNotice(displayIdentifier: String) -> IslandNotice? {
        let items = scenarioReview(displayIdentifier: displayIdentifier)
        guard !items.isEmpty else { return nil }
        return IslandNotice(id: "scenario-review-" + displayIdentifier,
            title: AppLocalization.text("已延后 %ld 条提示", items.count),
            detail: AppLocalization.text("点击回顾"), side: .right, symbolName: "bell.badge")
    }

    private var scenarioNotices: [(IslandNotice, UInt64)] {
        (left + right).map { ($0, noticeRevisions[$0.id] ?? 0) }
    }
}
