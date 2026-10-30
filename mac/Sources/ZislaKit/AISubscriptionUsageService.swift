import CoreFoundation
import Foundation
import ZislaCore

public struct AISubscriptionUsageRefresh: Sendable {
    public var quotas: [AIQuotaSnapshot]
    public var usageSamples: [AIUsageSample]
    public var failedProviders: Set<AIProvider>
    public var failedUsageProviders: Set<AIProvider>

    public init(quotas: [AIQuotaSnapshot] = [], usageSamples: [AIUsageSample] = [],
                failedProviders: Set<AIProvider> = [], failedUsageProviders: Set<AIProvider> = []) {
        self.quotas = quotas
        self.usageSamples = usageSamples
        self.failedProviders = failedProviders
        self.failedUsageProviders = failedUsageProviders
    }
}

public protocol AISubscriptionUsageDetecting: Sendable {
    func subscriptionUsage() async -> AISubscriptionUsageRefresh
}

enum AISubscriptionUsageError: Error, Equatable {
    case invalidCredentials
    case invalidResponse
    case httpStatus(Int)
    case historyLimitExceeded
}

/// Native adaptation of CodexBar's Cursor usage fetcher, Sand status and Muse plugin (MIT).
public final class AISubscriptionUsageService: AISubscriptionUsageDetecting {
    private let cursorCookie: @Sendable () throws -> String?
    private let museToken: @Sendable () throws -> String?
    private let session: URLSession
    private let now: @Sendable () -> Date
    private let maximumHistoryPages: Int
    private let pageSize: Int
    private let maximumHistoryDuration: Duration

    public convenience init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        configuration: URLSessionConfiguration = .ephemeral,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        let credentials = AISubscriptionCredentials(home: home)
        self.init(
            cursorCookie: { try credentials.cursorCookie(now: now()) },
            museToken: { try credentials.museToken() }, configuration: configuration, now: now
        )
    }

    init(
        cursorCookie: @escaping @Sendable () throws -> String?,
        museToken: @escaping @Sendable () throws -> String?,
        configuration: URLSessionConfiguration = .ephemeral,
        maximumHistoryPages: Int = 200,
        pageSize: Int = 1_000,
        maximumHistoryDuration: Duration = .seconds(60),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.cursorCookie = cursorCookie
        self.museToken = museToken
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 15
        session = URLSession(configuration: configuration, delegate: SubscriptionRedirectBlocker(), delegateQueue: nil)
        self.maximumHistoryPages = maximumHistoryPages
        self.pageSize = pageSize
        self.maximumHistoryDuration = maximumHistoryDuration
        self.now = now
    }

    deinit { session.invalidateAndCancel() }

    public func subscriptionUsage() async -> AISubscriptionUsageRefresh {
        await withTaskGroup(of: AISubscriptionUsageRefresh.self) { group in
            group.addTask { await self.cursorUsage() }
            group.addTask { await self.museUsage() }
            var result = AISubscriptionUsageRefresh()
            for await update in group {
                result.quotas += update.quotas
                result.usageSamples += update.usageSamples
                result.failedProviders.formUnion(update.failedProviders)
                result.failedUsageProviders.formUnion(update.failedUsageProviders)
            }
            return result
        }
    }

    private func cursorUsage() async -> AISubscriptionUsageRefresh {
        let cookie: String
        do {
            guard let credential = try cursorCookie() else { return .init() }
            cookie = credential
        } catch { return .init(failedProviders: [.cursor, .grokBot], failedUsageProviders: [.cursor]) }
        return await withTaskGroup(of: AISubscriptionUsageRefresh.self) { group in
            group.addTask {
                do {
                    let data = try await self.request("https://cursor.com/api/usage-summary", cookie: cookie)
                    return .init(quotas: try Self.cursorQuotas(data: data, now: self.now()))
                } catch { return .init(failedProviders: [.cursor]) }
            }
            group.addTask {
                do {
                    let data = try await self.request("https://cursor.com/api/dashboard/get-sand-usage-status", cookie: cookie, body: [:])
                    let status = try JSONDecoder().decode(CursorSandUsageStatus.self, from: data)
                    return .init(quotas: status.quota(now: self.now()).map { [$0] } ?? [])
                } catch { return .init(failedProviders: [.grokBot]) }
            }
            group.addTask {
                do { return .init(usageSamples: try await self.cursorHistory(cookie: cookie)) }
                catch { return .init(failedUsageProviders: [.cursor]) }
            }
            var result = AISubscriptionUsageRefresh()
            for await update in group {
                result.quotas += update.quotas
                result.usageSamples += update.usageSamples
                result.failedProviders.formUnion(update.failedProviders)
                result.failedUsageProviders.formUnion(update.failedUsageProviders)
            }
            return result
        }
    }

    private func museUsage() async -> AISubscriptionUsageRefresh {
        do {
            guard let token = try museToken() else { return .init() }
            let data = try await request("https://api.meta.ai/muse-code/key", bearer: token, body: [:])
            return .init(quotas: try Self.museQuotas(data: data, now: now()))
        } catch { return .init(failedProviders: [.muse]) }
    }

    private func request(_ endpoint: String, cookie: String? = nil, bearer: String? = nil, body: [String: Any]? = nil) async throws -> Data {
        try Task.checkCancellation()
        var request = URLRequest(url: URL(string: endpoint)!)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let cookie {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
            request.setValue("https://cursor.com", forHTTPHeaderField: "Origin")
            request.setValue("https://cursor.com/dashboard", forHTTPHeaderField: "Referer")
        }
        if let bearer {
            request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
            request.setValue("1.0.0", forHTTPHeaderField: "x-api-version")
        }
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse, response.url == request.url else {
            throw AISubscriptionUsageError.invalidResponse
        }
        guard response.statusCode == 200 else { throw AISubscriptionUsageError.httpStatus(response.statusCode) }
        return data
    }

    private func cursorHistory(cookie: String) async throws -> [AIUsageSample] {
        let end = now()
        let start = end.addingTimeInterval(-168 * 86_400)
        let deadline = ContinuousClock.now.advanced(by: maximumHistoryDuration)
        var pages: [[[String: Any]]] = []
        var expectedCount: Int?
        for page in 1...maximumHistoryPages {
            guard ContinuousClock.now < deadline else { throw AISubscriptionUsageError.historyLimitExceeded }
            let data = try await request("https://cursor.com/api/dashboard/get-filtered-usage-events", cookie: cookie, body: [
                "startDate": String(Int64(start.timeIntervalSince1970 * 1_000)),
                "endDate": String(Int64(end.timeIntervalSince1970 * 1_000)), "page": page, "pageSize": pageSize,
            ])
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw AISubscriptionUsageError.invalidResponse
            }
            let count = Self.integer(root["totalUsageEventsCount"])
            guard root["totalUsageEventsCount"] == nil || count != nil else {
                throw AISubscriptionUsageError.invalidResponse
            }
            if let count {
                guard expectedCount == nil || expectedCount == count else { throw AISubscriptionUsageError.invalidResponse }
                expectedCount = count
            }
            let rows: [[String: Any]]
            if let values = root["usageEventsDisplay"] as? [[String: Any]] { rows = values }
            else if root.isEmpty || (root.count == 1 && count != nil) { rows = [] }
            else { throw AISubscriptionUsageError.invalidResponse }
            pages.append(rows)
            if rows.count < pageSize {
                let records = try Self.reconcileCursorPages(pages, expectedCount: expectedCount)
                let accountID = cookie.components(separatedBy: "%3A%3A")[0]
                return try Self.cursorSamples(records, startingAt: start, endingAt: end, accountID: accountID)
            }
        }
        throw AISubscriptionUsageError.historyLimitExceeded
    }

    static func reconcileCursorPages(_ pages: [[[String: Any]]], expectedCount: Int?) throws -> [[String: Any]] {
        let records = pages.flatMap { $0 }
        guard let expectedCount else { return records }
        guard records.count >= expectedCount else { throw AISubscriptionUsageError.invalidResponse }
        guard records.count > expectedCount else { return records }
        // The API has no event ID. Remove only boundary overlap proven by its authoritative count.
        let fingerprints = try pages.map { page in
            try page.map { try JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys]) }
        }
        var excess = records.count - expectedCount
        var reconciled = pages[0]
        for index in pages.indices.dropFirst() {
            let previous = fingerprints[index - 1]
            let current = fingerprints[index]
            let limit = min(previous.count, current.count)
            let overlap = stride(from: limit, through: 1, by: -1).first { count in
                previous.suffix(count).elementsEqual(current.prefix(count))
            } ?? 0
            let removed = min(overlap, excess)
            reconciled += pages[index].dropFirst(removed)
            excess -= removed
        }
        guard excess == 0 else { throw AISubscriptionUsageError.invalidResponse }
        return reconciled
    }

    static func cursorSamples(_ rows: [[String: Any]], startingAt start: Date, endingAt end: Date,
                              accountID: String = "") throws -> [AIUsageSample] {
        var samples: [String: AIUsageSample] = [:]
        for row in rows {
            guard let timestamp = integer(row["timestamp"]), timestamp > 0, timestamp < 253_402_300_800_000,
                  let usage = row["tokenUsage"] as? [String: Any],
                  let input = integer(usage["inputTokens"]), let output = integer(usage["outputTokens"]),
                  let read = usage["cacheReadTokens"] == nil ? 0 : integer(usage["cacheReadTokens"]),
                  let write = usage["cacheWriteTokens"] == nil ? 0 : integer(usage["cacheWriteTokens"]) else {
                throw AISubscriptionUsageError.invalidResponse
            }
            let inputWithRead = input.addingReportingOverflow(read)
            let inputWithCache = inputWithRead.partialValue.addingReportingOverflow(write)
            let total = inputWithCache.partialValue.addingReportingOverflow(output)
            guard !inputWithRead.overflow, !inputWithCache.overflow, !total.overflow else { throw AISubscriptionUsageError.invalidResponse }
            let date = Date(timeIntervalSince1970: Double(timestamp) / 1_000)
            guard date >= start, date <= end else { continue }
            let model = row["model"] as? String
            let key = "cursor-usage-" + DesktopAIStorage.identity([accountID, String(timestamp), model ?? ""])
            if var sample = samples[key] {
                sample.inputTokens = AIUsageTokenMath.adding(sample.inputTokens, inputWithCache.partialValue)
                sample.outputTokens = AIUsageTokenMath.adding(sample.outputTokens, output)
                samples[key] = sample
            } else {
                samples[key] = AIUsageSample(sourceID: key, provider: .cursor,
                    timestamp: date,
                    inputTokens: inputWithCache.partialValue, outputTokens: output, model: model)
            }
        }
        return samples.values.sorted { ($0.sourceID ?? "") < ($1.sourceID ?? "") }
    }

    static func cursorQuotas(data: Data, now: Date) throws -> [AIQuotaSnapshot] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AISubscriptionUsageError.invalidResponse
        }
        let individual = root["individualUsage"] as? [String: Any]
        let plan = individual?["plan"] as? [String: Any]
        let overall = individual?["overall"] as? [String: Any]
        let pooled = (root["teamUsage"] as? [String: Any])?["pooled"] as? [String: Any]
        let percent = number(plan?["totalPercentUsed"]) ?? {
            for allowance in [plan, overall, pooled] {
                if let used = number(allowance?["used"]), let limit = number(allowance?["limit"]), limit > 0 {
                    return used / limit * 100
                }
            }
            return nil
        }()
        guard let percent else {
            if root["isUnlimited"] as? Bool == true { return [] }
            throw AISubscriptionUsageError.invalidResponse
        }
        let reset = date(root["billingCycleEnd"] as? String)
        if let reset, reset <= now { throw AISubscriptionUsageError.invalidResponse }
        return [.init(provider: .cursor, window: .plan, usedPercent: min(100, percent),
            resetsAt: reset, checkedAt: now)]
    }

    static func museQuotas(data: Data, now: Date) throws -> [AIQuotaSnapshot] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["is_subs_active"] as? Bool == true,
              root["require_payment"] == nil || root["require_payment"] as? Bool == false else {
            throw AISubscriptionUsageError.invalidResponse
        }
        guard let usage = root["subs_usage"] as? [String: Any] else { return [] }
        guard let window = usage["window"] as? [String: Any], integer(window["window_duration_mins"]) == 300 else {
            throw AISubscriptionUsageError.invalidResponse
        }
        return try [("window", AIQuotaWindow.fiveHours), ("weekly", .weekly)].map { key, window in
            guard let value = usage[key] as? [String: Any], let percent = number(value["used_percent"]) else {
                throw AISubscriptionUsageError.invalidResponse
            }
            let resetsAt = number(value["resets_at"]).flatMap { $0 > 0 && $0 < 253_402_300_800 ? Date(timeIntervalSince1970: $0) : nil }
            if let resetsAt, resetsAt <= now { throw AISubscriptionUsageError.invalidResponse }
            return .init(provider: .muse, window: window, usedPercent: min(100, percent), resetsAt: resetsAt, checkedAt: now)
        }
    }

    static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            return number.doubleValue.isFinite && number.doubleValue >= 0 ? number.doubleValue : nil
        }
        if let value = value as? String, let number = Double(value), number.isFinite, number >= 0 { return number }
        return nil
    }

    private static func integer(_ value: Any?) -> Int? {
        number(value).flatMap { $0 < Double(Int.max) ? Int(exactly: $0) : nil }
    }
}

/// Retains CodexBar's verified Sand response fields; an expired trial is not a paid allowance.
struct CursorSandUsageStatus: Decodable, Sendable {
    let nextResetTimestampUtc: String?
    let usagePercent: Double?
    let hasNonZeroIncludedLimit: Bool?
    let includedLimitZero: Bool?
    let sandTrialExpiresAt: String?

    func quota(now: Date) -> AIQuotaSnapshot? {
        let hasLimit = includedLimitZero.map { !$0 } ?? hasNonZeroIncludedLimit
        let hasTrial = hasLimit != true && AISubscriptionUsageService.date(sandTrialExpiresAt).map { $0 > now } == true
        guard hasLimit == true || hasTrial, let usagePercent, usagePercent.isFinite, usagePercent >= 0 else { return nil }
        let resetsAt = hasTrial ? nil : AISubscriptionUsageService.date(nextResetTimestampUtc)
        if let resetsAt, resetsAt <= now { return nil }
        return .init(provider: .grokBot, window: hasTrial ? .trial : .weekly, usedPercent: min(100, usagePercent),
            resetsAt: resetsAt, checkedAt: now)
    }
}

final class SubscriptionRedirectBlocker: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
