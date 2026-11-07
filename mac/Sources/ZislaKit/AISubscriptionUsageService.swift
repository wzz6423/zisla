import CoreFoundation
import Foundation
import ZislaCore

public struct AISubscriptionUsageRefresh: Sendable {
    public var usageSamples: [AIUsageSample]
    public var failedUsageProviders: Set<AIProvider>

    public init(usageSamples: [AIUsageSample] = [], failedUsageProviders: Set<AIProvider> = []) {
        self.usageSamples = usageSamples
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

/// Native adaptation of CodexBar's Cursor usage fetcher (MIT).
public final class AISubscriptionUsageService: AISubscriptionUsageDetecting {
    private let cursorCookie: @Sendable () throws -> String?
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
            configuration: configuration, now: now
        )
    }

    init(
        cursorCookie: @escaping @Sendable () throws -> String?,
        configuration: URLSessionConfiguration = .ephemeral,
        maximumHistoryPages: Int = 200,
        pageSize: Int = 1_000,
        maximumHistoryDuration: Duration = .seconds(60),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.cursorCookie = cursorCookie
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
        do {
            guard let cookie = try cursorCookie() else { return .init() }
            return .init(usageSamples: try await cursorHistory(cookie: cookie))
        } catch { return .init(failedUsageProviders: [.cursor]) }
    }

    private func request(_ endpoint: String, cookie: String, body: [String: Any]) async throws -> Data {
        try Task.checkCancellation()
        var request = URLRequest(url: URL(string: endpoint)!)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue("https://cursor.com", forHTTPHeaderField: "Origin")
        request.setValue("https://cursor.com/dashboard", forHTTPHeaderField: "Referer")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
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

final class SubscriptionRedirectBlocker: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
