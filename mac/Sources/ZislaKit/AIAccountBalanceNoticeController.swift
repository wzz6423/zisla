import Foundation
import ZislaCore

@MainActor
public final class AIAccountBalanceNoticeController {
    public nonisolated static let pinnedID = "ai-balance-pinned"
    private let queue: SideNoticeQueue
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (Duration) async throws -> Void
    private var notified: [String: (AIAccountQuotaSeverity, Date)] = [:]
    private var balances: [AIAccountBalance] = []
    private var settings = FeatureSettings()
    private var language = AppLanguage.simplifiedChinese
    private var rotationTask: Task<Void, Never>?

    public init(queue: SideNoticeQueue, now: @escaping @Sendable () -> Date = Date.init,
                sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.queue = queue
        self.now = now
        self.sleep = sleep
    }

    isolated deinit {
        rotationTask?.cancel()
        queue.remove(id: Self.pinnedID)
        queue.removeAll(withIDPrefix: "ai-balance-low-")
    }

    /// Notifies once per low-quota episode and reissues escalation; healthy readings rearm an enabled episode.
    /// Monitoring governs alerts independently of display selection; disabling alerts clears their episodes.
    public func update(balances: [AIAccountBalance], settings: FeatureSettings, language: AppLanguage,
                       at date: Date = Date()) {
        self.balances = balances
        self.settings = settings
        self.language = language
        let monitored = balances.filter { !$0.providers.allSatisfy { !settings.aiAccountBalanceMonitoredProviders.contains($0) } }
        let ids = Set(monitored.map(\.noticeID))
        notified = notified.filter { ids.contains($0.key) }
        if !settings.aiProgressEnabled || !settings.sideNoticesEnabled || !settings.aiAccountBalanceNoticeEnabled { notified.removeAll() }
        queue.removeAll(withIDPrefix: "ai-balance-low-", except: ids)
        for balance in monitored {
            guard settings.aiProgressEnabled, settings.sideNoticesEnabled, settings.aiAccountBalanceNoticeEnabled,
                  let severity = balance.severity, severity != .normal else {
                if balance.severity == .normal { notified[balance.noticeID] = nil }
                queue.remove(id: balance.noticeID)
                continue
            }
            var selectedBalance = balance
            selectedBalance.providers = balance.providers.filter { settings.aiAccountBalanceMonitoredProviders.contains($0) }
            let previous = notified[balance.noticeID]
            let escalates = previous.map { severity > $0.0 } ?? true
            let createdAt = escalates ? date : previous!.1
            let notice = Self.notice(selectedBalance, id: balance.noticeID, style: settings.aiAccountBalanceCompactStyle,
                language: language, createdAt: createdAt)
            if escalates {
                notified[balance.noticeID] = (severity, createdAt)
                queue.enqueue(notice)
            } else { queue.updateIfPresent(notice) }
        }
        updatePinned(at: date)
        if pinnedBalances.count > 1, rotationTask == nil {
            let sleep = sleep
            rotationTask = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await sleep(.seconds(5)) } catch { return }
                    guard !Task.isCancelled, let self else { return }
                    self.updatePinned(at: self.now())
                }
            }
        } else if pinnedBalances.count <= 1 {
            rotationTask?.cancel()
            rotationTask = nil
        }
    }

    /// Persistent quota requires custom placement and both monitoring and display selection for an alias.
    private var pinnedBalances: [AIAccountBalance] {
        guard settings.aiProgressEnabled, settings.sideNoticesEnabled, settings.islandPlacement.mode == .custom,
              settings.aiAccountBalancePinnedInCustomIsland else { return [] }
        return balances.filter { balance in
            balance.severity != nil && balance.providers.contains {
                settings.aiAccountBalanceMonitoredProviders.contains($0) && settings.aiAccountBalanceDisplayedProviders.contains($0)
            }
        }.sorted { $0.id < $1.id }
    }

    /// Rotates stable account IDs in five-second slots and removes the persistent notice when selection is empty.
    func updatePinned(at date: Date) {
        let rows = pinnedBalances
        guard !rows.isEmpty else { queue.remove(id: Self.pinnedID); return }
        let index = Int(max(0, date.timeIntervalSinceReferenceDate) / 5) % rows.count
        var balance = rows[index]
        balance.providers = balance.providers.filter {
            settings.aiAccountBalanceDisplayedProviders.contains($0) && settings.aiAccountBalanceMonitoredProviders.contains($0)
        }
        let notice = Self.notice(balance, id: Self.pinnedID, style: settings.aiAccountBalanceCompactStyle,
            language: language, createdAt: date)
        if !queue.updateIfPresent(notice) { queue.enqueue(notice, expiresAfter: nil) }
    }

    /// Includes persistent quota for layout without treating it as a new transient low-balance episode.
    public nonisolated static func isBalanceNotice(_ notice: IslandNotice) -> Bool {
        AIAccountBalance.isLowBalanceNotice(notice) || notice.id == pinnedID
    }

    /// Compact mode identifies the limiting window, including exhausted credits beside healthy percentages.
    /// Detailed mode carries the bounded summary in metadata so every compact shape renders the same reading.
    private nonisolated static func notice(_ balance: AIAccountBalance, id: String, style: MediaCompactStyle,
                                          language: AppLanguage, createdAt: Date) -> IslandNotice {
        let provider = balance.providerTitle(language: language)
        let summary = balance.compactLines(language: language)
        let lines: [String]
        if style == .detailed { lines = summary }
        else if let limiting = balance.windows.sorted(by: {
            $0.severity != $1.severity ? $0.severity > $1.severity : ($0.remainingPercent ?? 100) < ($1.remainingPercent ?? 100)
        }).first {
            lines = [limiting.label(language: language) + " " + limiting.value(language: language)]
        } else { lines = [] }
        var metadata = ["quotaProvider": provider, "quotaSeverity": String(balance.severity?.rawValue ?? 0)]
        for (index, line) in lines.enumerated() { metadata["quotaLine\(index)"] = line }
        return IslandNotice(id: id, title: provider, detail: lines.joined(separator: " · "),
            kind: balance.severity == .normal ? .info : .warning, side: .left, createdAt: createdAt,
            style: .status, symbolName: "gauge.with.dots.needle.67percent", metadata: metadata)
    }
}
