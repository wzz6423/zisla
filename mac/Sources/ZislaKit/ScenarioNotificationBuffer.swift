import Foundation
import ZislaCore

public struct ScenarioNotificationReviewItem: Equatable, Identifiable, Sendable {
    public let id: String
    public var title: String
    public var detail: String?
    public var kind: NoticeKind
    public var recordedAt: Date
    var sourceIDs: Set<String>
    var hasLeftSource: Bool

    init(notice: IslandNotice, at date: Date) {
        id = Self.reviewID(for: notice.id)
        title = String(String.UnicodeScalarView(notice.title.unicodeScalars.prefix(160)))
        detail = notice.detail.map { String(String.UnicodeScalarView($0.unicodeScalars.prefix(320))) }
        kind = notice.kind
        recordedAt = date
        sourceIDs = [notice.id]
        hasLeftSource = notice.side == .left
    }

    mutating func update(with notice: IslandNotice, at date: Date) {
        sourceIDs.insert(notice.id)
        kind = notice.kind
        recordedAt = date
        if notice.side == .left || !hasLeftSource {
            title = String(String.UnicodeScalarView(notice.title.unicodeScalars.prefix(160)))
            detail = notice.detail.map { String(String.UnicodeScalarView($0.unicodeScalars.prefix(320))) }
        } else {
            detail = String(String.UnicodeScalarView((notice.detail ?? notice.title).unicodeScalars.prefix(320)))
        }
        hasLeftSource = hasLeftSource || notice.side == .left
    }

    static func reviewID(for id: String) -> String {
        for suffix in ["-left", "-right"] where id.hasSuffix(suffix) {
            return String(id.dropLast(suffix.count))
        }
        return id
    }
}

struct ScenarioNotificationBuffer {
    static let capacityPerDisplay = 50
    static let maximumAge: TimeInterval = 4 * 60 * 60
    private(set) var settings = NotificationScenarioSettings()
    private(set) var scenarios: Set<NotificationScenario> = []
    private(set) var displayIdentifiers: Set<String> = []
    private var deferred: [String: [ScenarioNotificationReviewItem]] = [:]
    private var reviews: [String: [ScenarioNotificationReviewItem]] = [:]
    private var suppressedRevisions: [String: [ScenarioNoticeImportance: UInt64]] = [:]

    mutating func configure(_ settings: NotificationScenarioSettings, displays: Set<String>,
                            notices: [(IslandNotice, UInt64)], latestRevision: UInt64, at date: Date) {
        let previous = self.settings
        let oldDisplays = displayIdentifiers
        self.settings = settings
        displayIdentifiers = displays
        deferred = deferred.filter { displays.contains($0.key) }
        reviews = reviews.filter { displays.contains($0.key) }
        suppressedRevisions = suppressedRevisions.filter { displays.contains($0.key) }
        guard settings.enabled else {
            deferred.removeAll()
            reviews.removeAll()
            suppressedRevisions.removeAll()
            return
        }
        prune(at: date)
        for display in displays {
            suppressEarlierEvents(on: display, through: latestRevision)
            if previous != settings {
                deferred[display] = deferred[display]?.filter {
                    settings.behavior(for: importance(of: $0), scenarios: scenarios, displayIdentifier: display) != .mute
                }
            }
            for (notice, revision) in notices {
                capture(notice, revision: revision, on: display, at: date, recordsEvent: false)
            }
            if oldDisplays.contains(display),
               previous.behavior(for: .ordinary, scenarios: scenarios, displayIdentifier: display) != .show,
               settings.behavior(for: .ordinary, scenarios: scenarios, displayIdentifier: display) == .show {
                finish(on: display, at: date)
            }
        }
    }

    mutating func setScenarios(_ scenarios: Set<NotificationScenario>, notices: [(IslandNotice, UInt64)],
                              latestRevision: UInt64, at date: Date) {
        let previous = self.scenarios
        self.scenarios = scenarios
        guard settings.enabled else { return }
        prune(at: date)
        for display in displayIdentifiers {
            suppressEarlierEvents(on: display, through: latestRevision)
            deferred[display] = deferred[display]?.filter {
                settings.behavior(for: importance(of: $0), scenarios: scenarios, displayIdentifier: display) != .mute
            }
            for (notice, revision) in notices {
                capture(notice, revision: revision, on: display, at: date, recordsEvent: false)
            }
            if settings.behavior(for: .ordinary, scenarios: previous, displayIdentifier: display) != .show,
               settings.behavior(for: .ordinary, scenarios: scenarios, displayIdentifier: display) == .show {
                finish(on: display, at: date)
            }
        }
    }

    mutating func receive(_ notice: IslandNotice, revision: UInt64, at date: Date) {
        guard settings.enabled else { return }
        prune(at: date)
        for display in displayIdentifiers { capture(notice, revision: revision, on: display, at: date, recordsEvent: true) }
    }

    func isVisible(_ notice: IslandNotice, revision: UInt64, on display: String) -> Bool {
        guard settings.enabled else { return true }
        let importance = ScenarioNoticeImportance(notice: notice)
        guard settings.behavior(for: importance, scenarios: scenarios, displayIdentifier: display) == .show else { return false }
        return Self.isLiveStatus(notice) || suppressedRevisions[display]?[importance].map { revision > $0 } != false
    }

    func review(on display: String, at date: Date) -> [ScenarioNotificationReviewItem] {
        guard settings.enabled,
              settings.behavior(for: .ordinary, scenarios: scenarios, displayIdentifier: display) == .show else { return [] }
        return (reviews[display] ?? []).filter { date.timeIntervalSince($0.recordedAt) < Self.maximumAge }
    }

    mutating func dismissReview(on display: String) {
        reviews[display] = nil
    }

    mutating func remove(id: String) {
        let reviewID = ScenarioNotificationReviewItem.reviewID(for: id)
        for display in displayIdentifiers {
            deferred[display]?.removeAll { $0.id == reviewID }
            reviews[display]?.removeAll { $0.id == reviewID }
        }
    }

    mutating func removeAll() {
        deferred.removeAll()
        reviews.removeAll()
        suppressedRevisions.removeAll()
    }

    mutating func removeAll(withIDPrefix prefix: String, except ids: Set<String> = []) {
        for display in displayIdentifiers {
            for item in (deferred[display] ?? []) + (reviews[display] ?? [])
            where item.sourceIDs.contains(where: { $0.hasPrefix(prefix) && !ids.contains($0) }) {
                remove(id: item.sourceIDs.first(where: { $0.hasPrefix(prefix) && !ids.contains($0) })!)
            }
        }
    }

    private mutating func capture(_ notice: IslandNotice, revision: UInt64, on display: String,
                                  at date: Date, recordsEvent: Bool) {
        let importance = ScenarioNoticeImportance(notice: notice)
        let behavior = settings.behavior(for: importance,
            scenarios: scenarios, displayIdentifier: display)
        if behavior != .show, !Self.isLiveStatus(notice) {
            suppressedRevisions[display, default: [:]][importance] = max(revision, suppressedRevisions[display]?[importance] ?? 0)
        }
        switch behavior {
        case .show:
            if importance != .ordinary {
                deferred[display]?.removeAll { $0.id == ScenarioNotificationReviewItem.reviewID(for: notice.id) }
            }
        case .mute:
            deferred[display]?.removeAll { $0.id == ScenarioNotificationReviewItem.reviewID(for: notice.id) }
        case .deferUntilEnd:
            // Ongoing display furniture has no event to review when the scene ends.
            guard recordsEvent, !Self.isRoutineStatus(notice) else { return }
            var items = deferred[display] ?? []
            let id = ScenarioNotificationReviewItem.reviewID(for: notice.id)
            if let index = items.firstIndex(where: { $0.id == id }) {
                var item = items.remove(at: index)
                item.update(with: notice, at: date)
                items.append(item)
            } else {
                items.append(ScenarioNotificationReviewItem(notice: notice, at: date))
            }
            deferred[display] = Array(items.suffix(Self.capacityPerDisplay))
            reviews[display]?.removeAll { $0.id == id }
            reviews[display] = reviews[display].map {
                Array($0.suffix(max(0, Self.capacityPerDisplay - min(items.count, Self.capacityPerDisplay))))
            }
        }
    }

    private mutating func suppressEarlierEvents(on display: String, through revision: UInt64) {
        for importance in [ScenarioNoticeImportance.ordinary, .waiting, .failure, .safety, .lowBattery]
        where settings.behavior(for: importance, scenarios: scenarios, displayIdentifier: display) != .show {
            suppressedRevisions[display, default: [:]][importance] = max(revision, suppressedRevisions[display]?[importance] ?? 0)
        }
    }

    private mutating func finish(on display: String, at date: Date) {
        var items = reviews[display] ?? []
        for item in deferred.removeValue(forKey: display) ?? [] {
            items.removeAll { $0.id == item.id }
            items.append(item)
        }
        reviews[display] = Array(items.filter { date.timeIntervalSince($0.recordedAt) < Self.maximumAge }
            .suffix(Self.capacityPerDisplay))
    }

    private mutating func prune(at date: Date) {
        for display in displayIdentifiers {
            deferred[display]?.removeAll { date.timeIntervalSince($0.recordedAt) >= Self.maximumAge }
            reviews[display]?.removeAll { date.timeIntervalSince($0.recordedAt) >= Self.maximumAge }
        }
    }

    private func importance(of item: ScenarioNotificationReviewItem) -> ScenarioNoticeImportance {
        ScenarioNoticeImportance(notice: IslandNotice(id: item.sourceIDs.sorted().first!,
            title: item.title, kind: item.kind))
    }

    private static func isRoutineStatus(_ notice: IslandNotice) -> Bool {
        isLiveStatus(notice) && notice.kind != .warning && notice.kind != .error
    }

    private static func isLiveStatus(_ notice: IslandNotice) -> Bool {
        if ["focus-mode-", "focus-countdown-", "meeting-countdown-"].contains(where: { notice.id.hasPrefix($0) }) {
            return true
        }
        return ["media-active-", "ai-active-",
         "background-sound-", "toolbox-reminder-", "browser-download-", "video-download-", "voice-processing-",
         "screen-recording-operation-"].contains { notice.id.hasPrefix($0) }
            && notice.kind != .success
    }
}
