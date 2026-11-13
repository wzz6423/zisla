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
    private var pinnedAccountID: String?
    private var pinnedReadingStart: Date?
    private var pinnedReadingLines: [String] = []

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
        let monitored = balances.compactMap { balance -> AIAccountBalance? in
            var row = balance
            row.providers = row.providers.filter {
                balance.isDebug || (AIAccountBalanceCatalog.supportsBalanceQuery($0)
                    && settings.aiAccountBalanceMonitoredProviders.contains($0))
            }
            return row.providers.isEmpty ? nil : row
        }
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
            let previous = notified[balance.noticeID]
            let escalates = previous.map { severity > $0.0 } ?? true
            let createdAt = escalates ? date : previous!.1
            let notice = Self.notice(balance, id: balance.noticeID, style: settings.aiAccountBalanceCompactStyle,
                language: language, createdAt: createdAt)
            if escalates {
                notified[balance.noticeID] = (severity, createdAt)
                queue.enqueue(notice, expiresAfter: max(6, readingSeconds(for: notice)))
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
        return AIAccountBalanceCatalog.displayedBalances(balances,
            monitoredProviders: settings.aiAccountBalanceMonitoredProviders,
            displayedProviders: settings.aiAccountBalanceDisplayedProviders).sorted { $0.id < $1.id }
    }

    /// Polling retains the current account's reading; a changed summary gets time to reach its new tail.
    func updatePinned(at date: Date) {
        let rows = pinnedBalances
        guard !rows.isEmpty else {
            pinnedAccountID = nil
            pinnedReadingStart = nil
            pinnedReadingLines = []
            queue.remove(id: Self.pinnedID)
            return
        }
        let currentIndex = rows.firstIndex { $0.id == pinnedAccountID }
        var index = currentIndex ?? 0
        var notice = Self.notice(rows[index], id: Self.pinnedID, style: settings.aiAccountBalanceCompactStyle,
            language: language, createdAt: date)
        let lines = CompactPillStatusPresentation(priority: .aiAccountBalance, notice: notice, text: "").accountBalanceLines
        let candidates = (queue.left + queue.right).filter { $0.id != Self.pinnedID } + [notice]
        let isSelected = SideNoticeLayoutEngine.selectedCompactStatusPriority(for: candidates, settings: settings) == .aiAccountBalance
            && !candidates.contains { $0.id.hasPrefix("voice-processing-") }
            && SideNoticeLayoutEngine.screenRecordingOperationNotice(for: candidates, settings: settings) == nil
        if !isSelected {
            pinnedReadingStart = nil
        } else if currentIndex == nil || pinnedReadingStart == nil || pinnedReadingLines != lines {
            pinnedReadingStart = date
        } else if let start = pinnedReadingStart, date.timeIntervalSince(start) >= max(5, readingSeconds(for: notice)) {
            index = (index + 1) % rows.count
            notice = Self.notice(rows[index], id: Self.pinnedID, style: settings.aiAccountBalanceCompactStyle,
                language: language, createdAt: date)
            pinnedReadingStart = date
        }
        pinnedAccountID = rows[index].id
        pinnedReadingLines = CompactPillStatusPresentation(priority: .aiAccountBalance, notice: notice, text: "").accountBalanceLines
        if !queue.updateIfPresent(notice) { queue.enqueue(notice, expiresAfter: nil) }
    }

    /// Includes persistent quota for layout without treating it as a new transient low-balance episode.
    public nonisolated static func isBalanceNotice(_ notice: IslandNotice) -> Bool {
        AIAccountBalance.isLowBalanceNotice(notice) || notice.id == pinnedID
    }

    private func readingSeconds(for notice: IslandNotice) -> Double {
        let presentation = CompactPillStatusPresentation(priority: .aiAccountBalance, notice: notice, text: "")
        return presentation.accountBalanceReadingSeconds(thickness: max(32, CGFloat(settings.islandPillHeight)),
            edge: settings.islandPlacement.edge)
    }

    /// Both styles retain canonical quota rows; compact mode singles out a limiting extra allowance.
    private nonisolated static func notice(_ balance: AIAccountBalance, id: String, style: MediaCompactStyle,
                                          language: AppLanguage, createdAt: Date) -> IslandNotice {
        let provider = balance.providerTitle(language: language)
        let summary = balance.compactLines(language: language)
        let short = balance.fiveHourWindow
            ?? balance.windows.first(where: { $0.kind == .rolling && !$0.id.hasPrefix("additional:") })
        let usesSummary = style == .detailed || balance.limitingWindow?.id == short?.id
            || balance.limitingWindow?.id == balance.weeklyWindow?.id
        let lines: [String]
        if usesSummary { lines = summary }
        else if let limiting = balance.limitingWindow {
            lines = [limiting.label(language: language) + " " + limiting.value(language: language)]
        } else { lines = [] }
        var metadata = ["quotaProvider": provider, "quotaSeverity": String(balance.severity?.rawValue ?? 0)]
        metadata["quotaAccountID"] = balance.id
        metadata["quotaProviderID"] = balance.displayProvider?.rawValue
        if let fraction = balance.limitingWindow?.remainingFraction { metadata["quotaRemainingFraction"] = String(fraction) }
        for (key, window) in [("5h", balance.fiveHourWindow), ("7d", balance.weeklyWindow)] {
            if let window {
                metadata["quota\(key)Severity"] = String(window.severity.rawValue)
                metadata["quota\(key)Fraction"] = window.remainingFraction.map { String($0) }
            }
        }
        for (index, line) in lines.enumerated() {
            metadata["quotaLine\(index)"] = line
            let lineSeverity: AIAccountQuotaSeverity
            if !usesSummary { lineSeverity = balance.limitingWindow?.severity ?? .normal }
            else if index == 0, let short { lineSeverity = short.severity }
            else if index == 0, let weekly = balance.weeklyWindow { lineSeverity = weekly.severity }
            else {
                let remaining = balance.windows.filter { $0.id != short?.id
                    && (short != nil || $0.id != balance.weeklyWindow?.id) }
                lineSeverity = remaining.map(\.severity).max() ?? .normal
            }
            metadata["quotaLineSeverity\(index)"] = String(lineSeverity.rawValue)
        }
        return IslandNotice(id: id, title: provider, detail: lines.joined(separator: " · "),
            kind: balance.severity == .normal ? .info : .warning, side: .left, createdAt: createdAt,
            style: .status, symbolName: "gauge.with.dots.needle.67percent", metadata: metadata)
    }
}
