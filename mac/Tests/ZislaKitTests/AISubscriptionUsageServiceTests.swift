import Foundation
import Testing
@testable import ZislaCore
@testable import ZislaKit

@Suite(.serialized)
struct AISubscriptionUsageServiceTests {
    private let now = Date(timeIntervalSince1970: 1_910_000_000)
    private let summary = #"{"individualUsage":{"plan":{"totalPercentUsed":0.36}},"billingCycleEnd":"2031-01-01T00:00:00Z"}"#
    private let sand = #"{"usagePercent":25,"includedLimitZero":false,"nextResetTimestampUtc":"2031-01-01T00:00:00Z"}"#
    private let muse = #"{"is_subs_active":true,"require_payment":false,"subs_usage":{"window":{"window_duration_mins":300,"used_percent":40,"resets_at":2000000000},"weekly":{"used_percent":12.5,"resets_at":2000000010}}}"#

    @Test func refreshUsesVendorContractsAndKeepsCredentialsOutOfResults() async throws {
        SubscriptionURLProtocol.configure(responses: [
            "/api/usage-summary": [.json(summary)],
            "/api/dashboard/get-sand-usage-status": [.json(sand)],
            "/api/dashboard/get-filtered-usage-events": [.json(history([event(input: 10, output: 20)], count: 1))],
            "/muse-code/key": [.json(muse)],
        ])
        let service = makeService()
        let result = await service.subscriptionUsage()
        #expect(result.failedProviders.isEmpty && result.failedUsageProviders.isEmpty)
        #expect(result.quotas.count == 4)
        #expect(result.quotas.first { $0.provider == .cursor }?.usedPercent == 0.36)
        #expect(result.quotas.first { $0.provider == .grokBot }?.remainingPercent == 75)
        let sample = try #require(result.usageSamples.first)
        #expect(sample.inputTokens == 17 && sample.outputTokens == 20 && sample.totalTokens == 37)
        #expect(sample.timestamp == Date(timeIntervalSince1970: 1_909_999_990))
        #expect(!(sample.sourceID ?? "").contains("fixture-cookie"))
        let requests = SubscriptionURLProtocol.requests
        #expect(requests.count == 4)
        for request in requests where request.url?.host == "cursor.com" {
            #expect(request.value(forHTTPHeaderField: "Cookie") == "fixture-cookie")
            #expect(request.value(forHTTPHeaderField: "Origin") == "https://cursor.com")
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        }
        let key = try #require(requests.first { $0.url?.path == "/muse-code/key" })
        #expect(key.httpMethod == "POST")
        #expect(key.value(forHTTPHeaderField: "Authorization") == "Bearer dca:fixture-token")
        #expect(key.value(forHTTPHeaderField: "x-api-version") == "1.0.0")
        #expect(key.value(forHTTPHeaderField: "Cookie") == nil)
        let historyRequest = try #require(requests.first { $0.url?.path.contains("get-filtered") == true })
        let bodyData = try #require(historyRequest.httpBody)
        let bodyObject = try JSONSerialization.jsonObject(with: bodyData)
        let body = try #require(bodyObject as? [String: Any])
        #expect(body["page"] as? Int == 1 && body["pageSize"] as? Int == 1_000)
        #expect(body["startDate"] as? String == "1895484800000")
    }

    @Test func missingCredentialsCauseNoNetworkAndInvalidCredentialsAreIsolated() async {
        SubscriptionURLProtocol.configure(responses: [:])
        let absent = await makeService(cursor: { nil }, muse: { nil }).subscriptionUsage()
        #expect(absent.quotas.isEmpty && absent.failedProviders.isEmpty)
        #expect(SubscriptionURLProtocol.requests.isEmpty)
        let invalid = await makeService(cursor: { throw AISubscriptionUsageError.invalidCredentials }, muse: { nil }).subscriptionUsage()
        #expect(invalid.failedProviders == [.cursor, .grokBot])
        #expect(invalid.failedUsageProviders == [.cursor])
        #expect(SubscriptionURLProtocol.requests.isEmpty)
    }

    @Test(arguments: [401, 429, 503])
    func independentEndpointFailureDoesNotDiscardHealthySources(status: Int) async {
        SubscriptionURLProtocol.configure(responses: [
            "/api/usage-summary": [.json(summary)],
            "/api/dashboard/get-sand-usage-status": [.init(status: status, body: "private-server-body")],
            "/api/dashboard/get-filtered-usage-events": [.json("{}")],
            "/muse-code/key": [.json(muse)],
        ])
        let result = await makeService().subscriptionUsage()
        #expect(result.failedProviders == [.grokBot])
        #expect(result.quotas.count == 3 && result.failedUsageProviders.isEmpty)
        #expect(!String(describing: result).contains("private-server-body"))
        #expect(!String(describing: result).contains("fixture-token"))
    }

    @Test func timeoutAndIncompleteHistoryAreVisibleWithoutFailingQuota() async {
        SubscriptionURLProtocol.configure(responses: [
            "/api/usage-summary": [.json(summary)],
            "/api/dashboard/get-sand-usage-status": [.json(sand)],
            "/api/dashboard/get-filtered-usage-events": [.json(history([event(input: 1, output: 2)], count: 2))],
            "/muse-code/key": [.init(error: .timedOut)],
        ])
        let result = await makeService().subscriptionUsage()
        #expect(result.failedProviders == [.muse])
        #expect(result.failedUsageProviders == [.cursor])
        #expect(result.usageSamples.isEmpty && result.quotas.count == 2)
    }

    @Test func paginationRequiresTerminalPageAndStableAuthoritativeCount() async {
        let first = event(input: 1, output: 2)
        let second = event(input: 3, output: 4, timestamp: 1_909_999_980_000)
        for pages in [
            [history([first], count: 2), history([second], count: 2), history([], count: 2)],
            [history([first], count: 2), history([second], count: 3)],
            [history([first], count: 2), history([first], count: 2)],
            [history([first], count: 2), #"{"error":"private-response"}"#],
        ] {
            SubscriptionURLProtocol.configure(responses: [
                "/api/usage-summary": [.json(summary)],
                "/api/dashboard/get-sand-usage-status": [.json(sand)],
                "/api/dashboard/get-filtered-usage-events": pages.map { .json($0) },
            ])
            let result = await makeService(muse: { nil }, maximumPages: 3, pageSize: 1).subscriptionUsage()
            if pages.count == 3 {
                #expect(result.failedUsageProviders.isEmpty && result.usageSamples.count == 2)
            } else {
                #expect(result.failedUsageProviders == [.cursor] && result.usageSamples.isEmpty)
            }
        }
        SubscriptionURLProtocol.configure(responses: [
            "/api/usage-summary": [.json(summary)], "/api/dashboard/get-sand-usage-status": [.json(sand)],
            "/api/dashboard/get-filtered-usage-events": [.json(history([first], count: 1))],
        ])
        let capped = await makeService(muse: { nil }, maximumPages: 1, pageSize: 1).subscriptionUsage()
        #expect(capped.failedUsageProviders == [.cursor] && capped.usageSamples.isEmpty)
    }

    @Test func unexpectedResponseURLCannotPublishCredentialedData() async {
        SubscriptionURLProtocol.configure(responses: [
            "/api/usage-summary": [.init(body: summary, responseURL: "https://untrusted.example/api/usage-summary")],
            "/api/dashboard/get-sand-usage-status": [.json(sand)],
            "/api/dashboard/get-filtered-usage-events": [.json("{}")],
        ])
        let result = await makeService(muse: { nil }).subscriptionUsage()
        #expect(result.failedProviders == [.cursor])
        #expect(result.quotas.map(\.provider) == [.grokBot])
    }

    @Test func cursorAllowanceFallbacksAndStaleResponsesAreValidated() throws {
        for (text, expected) in [
            (summary, 0.36),
            (#"{"individualUsage":{"plan":{"used":20,"limit":80}}}"#, 25.0),
            (#"{"individualUsage":{"plan":{"limit":0},"overall":{"used":15,"limit":50}}}"#, 30.0),
            (#"{"teamUsage":{"pooled":{"used":25,"limit":50}}}"#, 50.0),
            (#"{"individualUsage":{"plan":{"totalPercentUsed":"125"}}}"#, 100.0),
        ] {
            #expect(try AISubscriptionUsageService.cursorQuotas(data: Data(text.utf8), now: now).first?.usedPercent == expected)
        }
        #expect(try AISubscriptionUsageService.cursorQuotas(data: Data(#"{"isUnlimited":true}"#.utf8), now: now).isEmpty)
        for invalid in [#"{"error":"unavailable"}"#, #"{"individualUsage":{"plan":{"totalPercentUsed":true}}}"#,
                        #"{"individualUsage":{"plan":{"totalPercentUsed":-1}}}"#,
                        #"{"individualUsage":{"plan":{"totalPercentUsed":10}},"billingCycleEnd":"2020-01-01T00:00:00Z"}"#] {
            #expect(throws: AISubscriptionUsageError.invalidResponse) {
                try AISubscriptionUsageService.cursorQuotas(data: Data(invalid.utf8), now: now)
            }
        }
    }

    @Test func museWindowsKeepIdleResponsesUnknownAndRejectIncorrectDurationOrSubscription() throws {
        let quotas = try AISubscriptionUsageService.museQuotas(data: Data(muse.utf8), now: now)
        #expect(quotas.map(\.window) == [.fiveHours, .weekly])
        #expect(quotas.map(\.remainingPercent) == [60, 87.5])
        #expect(try AISubscriptionUsageService.museQuotas(data: Data(#"{"is_subs_active":true}"#.utf8), now: now).isEmpty)
        for invalid in [
            muse.replacingOccurrences(of: ":300", with: ":60"),
            muse.replacingOccurrences(of: ":40", with: ":true"),
            muse.replacingOccurrences(of: ":2000000000", with: ":1800000000"),
            muse.replacingOccurrences(of: "\"require_payment\":false", with: "\"require_payment\":true"),
            muse.replacingOccurrences(of: "\"is_subs_active\":true", with: "\"is_subs_active\":false"),
        ] {
            #expect(throws: AISubscriptionUsageError.invalidResponse) {
                try AISubscriptionUsageService.museQuotas(data: Data(invalid.utf8), now: now)
            }
        }
    }

    @Test func sandTrialIsNotAWeeklyRenewalAndExplicitZeroLimitWins() throws {
        let trial = try JSONDecoder().decode(CursorSandUsageStatus.self, from: Data(
            #"{"usagePercent":25,"includedLimitZero":true,"hasNonZeroIncludedLimit":true,"sandTrialExpiresAt":"2031-01-01T00:00:00Z","nextResetTimestampUtc":"2031-01-01T00:00:00Z"}"#.utf8))
        #expect(trial.quota(now: now)?.resetsAt == nil)
        #expect(trial.quota(now: now)?.window == .trial)
        #expect(trial.quota(now: Date(timeIntervalSince1970: 2_000_000_000)) == nil)
        let unavailable = try JSONDecoder().decode(CursorSandUsageStatus.self, from: Data(
            #"{"usagePercent":0,"includedLimitZero":true,"hasAvailableUsage":true}"#.utf8))
        #expect(unavailable.quota(now: now) == nil)
    }

    @Test func cursorSamplesKeepAccountTimeAndStableIdentityAndRejectOverflow() throws {
        let row = event(input: 10, output: 20)
        let samples = try AISubscriptionUsageService.cursorSamples([row, row], startingAt: .distantPast, endingAt: now, accountID: "one")
        #expect(samples.count == 1 && samples.first?.inputTokens == 34 && samples.first?.outputTokens == 40)
        let other = try AISubscriptionUsageService.cursorSamples([row], startingAt: .distantPast, endingAt: now, accountID: "two")
        #expect(samples.first?.sourceID != other.first?.sourceID)
        for invalid in [event(input: -1, output: 2), event(input: Int.max, output: 1)] {
            #expect(throws: AISubscriptionUsageError.invalidResponse) {
                try AISubscriptionUsageService.cursorSamples([invalid], startingAt: .distantPast, endingAt: now)
            }
        }
        #expect(try AISubscriptionUsageService.cursorSamples([row], startingAt: now, endingAt: now).isEmpty)
    }

    @Test func authoritativeCountReconcilesOnlyAdjacentOverlapAndRetainsLegitimateEqualEvents() throws {
        let first = event(input: 1, output: 2)
        let second = event(input: 3, output: 4)
        let third = event(input: 5, output: 6)
        let reconciled = try AISubscriptionUsageService.reconcileCursorPages([[first, second], [second, third], []], expectedCount: 3)
        #expect(reconciled.count == 3)
        #expect(reconciled[2]["tokenUsage"] as? [String: Int] == third["tokenUsage"] as? [String: Int])
        #expect(try AISubscriptionUsageService.reconcileCursorPages([[first], [first], []], expectedCount: 2).count == 2)
        #expect(try AISubscriptionUsageService.reconcileCursorPages([[first], [first], []], expectedCount: 1).count == 1)
        #expect(throws: AISubscriptionUsageError.invalidResponse) {
            try AISubscriptionUsageService.reconcileCursorPages([[first], [third]], expectedCount: 1)
        }
        #expect(throws: AISubscriptionUsageError.invalidResponse) {
            try AISubscriptionUsageService.reconcileCursorPages([[first]], expectedCount: 2)
        }
    }

    @Test func credentialedRequestsNeverFollowRedirects() throws {
        let blocker = SubscriptionRedirectBlocker()
        let configuration = URLSessionConfiguration.ephemeral
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let url = try #require(URL(string: "https://cursor.com/api/usage-summary"))
        let response = try #require(HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil,
            headerFields: ["Location": "https://untrusted.example/"]))
        let task = session.dataTask(with: url)
        blocker.urlSession(session, task: task, willPerformHTTPRedirection: response,
            newRequest: URLRequest(url: URL(string: "https://untrusted.example/")!)) { request in
                #expect(request == nil)
            }
    }

    @Test func exhaustedHistoryBudgetAndCancelledRefreshDoNotIssueHistoryRequests() async {
        SubscriptionURLProtocol.configure(responses: [
            "/api/usage-summary": [.json(summary)],
            "/api/dashboard/get-sand-usage-status": [.json(sand)],
        ])
        let exhausted = await makeService(muse: { nil }, historyDuration: .zero).subscriptionUsage()
        #expect(exhausted.failedUsageProviders == [.cursor] && exhausted.usageSamples.isEmpty)
        #expect(SubscriptionURLProtocol.requests.count == 2)
        #expect(SubscriptionURLProtocol.requests.allSatisfy { $0.url?.path.contains("get-filtered") != true })
        SubscriptionURLProtocol.configure(responses: [:])
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await makeService().subscriptionUsage()
        }
        let cancelled = await task.value
        #expect(cancelled.quotas.isEmpty && cancelled.usageSamples.isEmpty)
        #expect(SubscriptionURLProtocol.requests.isEmpty)
    }

    private func makeService(cursor: @escaping @Sendable () throws -> String? = { "fixture-cookie" },
        muse: @escaping @Sendable () throws -> String? = { "dca:fixture-token" },
        maximumPages: Int = 200, pageSize: Int = 1_000, historyDuration: Duration = .seconds(60)) -> AISubscriptionUsageService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SubscriptionURLProtocol.self]
        return AISubscriptionUsageService(cursorCookie: cursor, museToken: muse, configuration: configuration,
            maximumHistoryPages: maximumPages, pageSize: pageSize, maximumHistoryDuration: historyDuration, now: { now })
    }

    private func event(input: Int, output: Int, timestamp: Int = 1_909_999_990_000) -> [String: Any] {
        ["timestamp": String(timestamp), "model": "fixture-model", "tokenUsage": [
            "inputTokens": input, "outputTokens": output, "cacheReadTokens": 3, "cacheWriteTokens": 4]]
    }

    private func history(_ rows: [[String: Any]], count: Int) -> String {
        String(decoding: try! JSONSerialization.data(withJSONObject: ["totalUsageEventsCount": count, "usageEventsDisplay": rows]), as: UTF8.self)
    }
}

private final class SubscriptionURLProtocol: URLProtocol, @unchecked Sendable {
    struct Response {
        var status: Int = 200
        var body: String = "{}"
        var error: URLError.Code?
        var responseURL: String?
        static func json(_ body: String) -> Self { .init(body: body) }
    }
    private static let lock = NSLock()
    nonisolated(unsafe) private static var responses: [String: [Response]] = [:]
    nonisolated(unsafe) private static var recorded: [URLRequest] = []

    static var requests: [URLRequest] { lock.withLock { recorded } }
    static func configure(responses: [String: [Response]]) {
        lock.withLock { Self.responses = responses; recorded = [] }
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var recordedRequest = request
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 1_024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                data.append(contentsOf: buffer.prefix(count))
            }
            recordedRequest.httpBody = data
        }
        let value: Response = Self.lock.withLock {
            Self.recorded.append(recordedRequest)
            let path = request.url!.path
            guard var queue = Self.responses[path], !queue.isEmpty else { return .init(error: .unsupportedURL) }
            let value = queue.removeFirst()
            Self.responses[path] = queue
            return value
        }
        if let error = value.error { client?.urlProtocol(self, didFailWithError: URLError(error)); return }
        let response = HTTPURLResponse(url: value.responseURL.flatMap(URL.init(string:)) ?? request.url!,
            statusCode: value.status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(value.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
