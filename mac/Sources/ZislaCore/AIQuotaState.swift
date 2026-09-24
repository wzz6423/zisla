import Foundation

public struct AIQuotaWindow: Equatable, Sendable, Identifiable {
    public let id: String
    public let label: String
    public let scope: String?
    /// A provider-reported percentage. Nil means the balance has no reliable denominator.
    public let remainingPercent: Double?
    public let resetsAt: Date?

    public init(id: String, label: String, remainingPercent: Double?, resetsAt: Date? = nil, scope: String? = nil) {
        self.id = id
        self.label = label
        self.remainingPercent = remainingPercent
        self.resetsAt = resetsAt
        self.scope = scope
    }

    public var displayLabel: String {
        let name = AppLocalization.text(label)
        return scope.map { "\(name) · \($0)" } ?? name
    }
}

public struct AIQuotaAccount: Equatable, Sendable, Identifiable {
    public let id: String
    public let providerID: String
    public let label: String
    public let balanceText: String?
    public let windows: [AIQuotaWindow]
    public let observedAt: Date

    public init(
        id: String,
        providerID: String,
        label: String,
        balanceText: String? = nil,
        windows: [AIQuotaWindow],
        observedAt: Date
    ) {
        self.id = id
        self.providerID = providerID
        self.label = label
        self.balanceText = balanceText
        self.windows = windows
        self.observedAt = observedAt
    }
}

public struct AIQuotaSnapshot: Equatable, Sendable {
    public let accounts: [AIQuotaAccount]

    public init(accounts: [AIQuotaAccount]) {
        self.accounts = accounts
    }
}

public struct AIQuotaThresholdAlert: Equatable, Sendable {
    public let accountID: String
    public let providerID: String
    public let accountLabel: String
    public let windowID: String
    public let windowLabel: String
    public let threshold: Int
    public let remainingPercent: Double

    public init(account: AIQuotaAccount, window: AIQuotaWindow, threshold: Int, remainingPercent: Double) {
        accountID = account.id
        providerID = account.providerID
        accountLabel = account.label
        windowID = window.id
        windowLabel = window.displayLabel
        self.threshold = threshold
        self.remainingPercent = remainingPercent
    }
}

public struct AIQuotaThresholdTracker: Sendable {
    public static let levels = [80, 60, 40, 20, 10, 5, 0]

    private struct Key: Hashable, Sendable {
        let accountID: String
        let windowID: String
    }

    private struct Reading: Sendable {
        var remainingPercent: Double
        var resetsAt: Date?
        var observedAt: Date
        var notifiedThresholds: Set<Int>
    }

    private var previous: [Key: Reading] = [:]
    private let maximumReadingAge: TimeInterval

    public init(maximumReadingAge: TimeInterval = 600) {
        self.maximumReadingAge = maximumReadingAge
    }

    public mutating func consume(_ snapshot: AIQuotaSnapshot, at now: Date = Date()) -> [AIQuotaThresholdAlert] {
        var alerts: [AIQuotaThresholdAlert] = []
        var liveKeys: Set<Key> = []

        for account in snapshot.accounts {
            for window in account.windows {
                let key = Key(accountID: account.id, windowID: window.id)
                liveKeys.insert(key)
                guard let remaining = window.remainingPercent,
                      remaining.isFinite,
                      (0...100).contains(remaining),
                      window.resetsAt.map({ $0 > now }) ?? true,
                      account.observedAt <= now,
                      now.timeIntervalSince(account.observedAt) <= maximumReadingAge
                else {
                    previous.removeValue(forKey: key)
                    continue
                }

                let last = previous[key]
                guard last.map({ account.observedAt >= $0.observedAt }) ?? true else { continue }
                let newCycle = last.map { previous in
                    account.observedAt.timeIntervalSince(previous.observedAt) > maximumReadingAge
                        || (window.resetsAt == nil && remaining == 100 && previous.remainingPercent < 100)
                        || (window.resetsAt.map { reset in
                            previous.resetsAt.map { reset.timeIntervalSince($0) > 60 } ?? true
                        } ?? false)
                } ?? true
                let notified = newCycle ? Set(Self.levels.filter { remaining <= Double($0) }) : (last?.notifiedThresholds ?? [])
                previous[key] = Reading(
                    remainingPercent: remaining,
                    resetsAt: window.resetsAt,
                    observedAt: account.observedAt,
                    notifiedThresholds: notified
                )

                guard let last,
                      !newCycle,
                      remaining < last.remainingPercent
                else { continue }

                let crossed = Self.levels.filter {
                    last.remainingPercent > Double($0) && remaining <= Double($0)
                }
                previous[key]?.notifiedThresholds.formUnion(crossed)
                if let threshold = crossed.filter({ !notified.contains($0) }).min() {
                    alerts.append(AIQuotaThresholdAlert(
                        account: account,
                        window: window,
                        threshold: threshold,
                        remainingPercent: remaining
                    ))
                }
            }
        }

        previous = previous.filter { liveKeys.contains($0.key) }
        return alerts
    }
}
