import Foundation
import Testing
@testable import ZislaCore
@testable import ZislaKit

@Suite(.serialized)
struct AISubscriptionUsageServiceTests {
    private let now = Date(timeIntervalSince1970: 1_910_000_000)

    @Test func refreshFetchesOnlyTokenHistoryAndKeepsCredentialsOutOfResults() async throws {
        SubscriptionURLProtocol.configure(responses: [
            "/api/dashboard/get-filtered-usage-events": [.json(history([event(input: 10, output: 20)], count: 1))],
        ])
        let service = makeService()
        let result = await service.subscriptionUsage()
        #expect(result.failedUsageProviders.isEmpty)
        #expect(result.usageSamples.count == 1)
        #expect(result.usageSamples.allSatisfy { $0.provider == .cursor })
        let sample = try #require(result.usageSamples.first)
        #expect(sample.inputTokens == 17 && sample.outputTokens == 20 && sample.totalTokens == 37)
        #expect(sample.timestamp == Date(timeIntervalSince1970: 1_909_999_990))
        #expect(!(sample.sourceID ?? "").contains("fixture-cookie"))
        let requests = SubscriptionURLProtocol.requests
        #expect(requests.count == 1)
        for request in requests {
            #expect(request.url?.absoluteString == "https://cursor.com/api/dashboard/get-filtered-usage-events")
            #expect(request.value(forHTTPHeaderField: "Cookie") == "fixture-cookie")
            #expect(request.value(forHTTPHeaderField: "Origin") == "https://cursor.com")
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        }
        let historyRequest = try #require(requests.first { $0.url?.path.contains("get-filtered") == true })
        #expect(historyRequest.httpMethod == "POST")
        let bodyData = try #require(historyRequest.httpBody)
        let bodyObject = try JSONSerialization.jsonObject(with: bodyData)
        let body = try #require(bodyObject as? [String: Any])
        #expect(body["page"] as? Int == 1 && body["pageSize"] as? Int == 1_000)
        #expect(body["startDate"] as? String == "1895484800000")
    }

    @Test func missingCredentialsCauseNoNetworkAndInvalidCredentialsAreIsolated() async {
        SubscriptionURLProtocol.configure(responses: [:])
        let absent = await makeService(cursor: { nil }).subscriptionUsage()
        #expect(absent.usageSamples.isEmpty && absent.failedUsageProviders.isEmpty)
        #expect(SubscriptionURLProtocol.requests.isEmpty)
        let invalid = await makeService(cursor: { throw AISubscriptionUsageError.invalidCredentials }).subscriptionUsage()
        #expect(invalid.usageSamples.isEmpty)
        #expect(invalid.failedUsageProviders == [.cursor])
        #expect(SubscriptionURLProtocol.requests.isEmpty)
    }

    @Test(arguments: ["{}", #"{"totalUsageEventsCount":0,"usageEventsDisplay":[]}"#])
    func emptyHistorySucceedsWithoutTokenSamples(response: String) async {
        SubscriptionURLProtocol.configure(responses: [
            "/api/dashboard/get-filtered-usage-events": [.json(response)],
        ])
        let result = await makeService().subscriptionUsage()
        #expect(result.usageSamples.isEmpty && result.failedUsageProviders.isEmpty)
        #expect(SubscriptionURLProtocol.requests.count == 1)
    }

    @Test(arguments: [401, 429, 503])
    func historyFailureIsSanitizedAndRecovers(status: Int) async {
        SubscriptionURLProtocol.configure(responses: [
            "/api/dashboard/get-filtered-usage-events": [.init(status: status, body: "private-server-body")],
        ])
        let result = await makeService().subscriptionUsage()
        #expect(result.failedUsageProviders == [.cursor] && result.usageSamples.isEmpty)
        #expect(!String(describing: result).contains("private-server-body"))
        #expect(!String(describing: result).contains("fixture-cookie"))
        SubscriptionURLProtocol.configure(responses: [
            "/api/dashboard/get-filtered-usage-events": [.json(history([event(input: 1, output: 2)], count: 1))],
        ])
        let recovered = await makeService().subscriptionUsage()
        #expect(recovered.failedUsageProviders.isEmpty && recovered.usageSamples.count == 1)
    }

    @Test func incompleteHistoryDoesNotPublishPartialTokenSamples() async {
        SubscriptionURLProtocol.configure(responses: [
            "/api/dashboard/get-filtered-usage-events": [.json(history([event(input: 1, output: 2)], count: 2))],
        ])
        let result = await makeService().subscriptionUsage()
        #expect(result.failedUsageProviders == [.cursor])
        #expect(result.usageSamples.isEmpty)
    }

    @Test(arguments: [URLError.Code.timedOut, .cancelled])
    func failedHistoryRequestDoesNotPublishTokenSamples(error: URLError.Code) async {
        SubscriptionURLProtocol.configure(responses: [
            "/api/dashboard/get-filtered-usage-events": [.init(error: error)],
        ])
        let result = await makeService().subscriptionUsage()
        #expect(result.failedUsageProviders == [.cursor] && result.usageSamples.isEmpty)
        #expect(SubscriptionURLProtocol.requests.count == 1)
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
                "/api/dashboard/get-filtered-usage-events": pages.map { .json($0) },
            ])
            let result = await makeService(maximumPages: 3, pageSize: 1).subscriptionUsage()
            if pages.count == 3 {
                #expect(result.failedUsageProviders.isEmpty && result.usageSamples.count == 2)
            } else {
                #expect(result.failedUsageProviders == [.cursor] && result.usageSamples.isEmpty)
            }
        }
        SubscriptionURLProtocol.configure(responses: [
            "/api/dashboard/get-filtered-usage-events": [.json(history([first], count: 1))],
        ])
        let capped = await makeService(maximumPages: 1, pageSize: 1).subscriptionUsage()
        #expect(capped.failedUsageProviders == [.cursor] && capped.usageSamples.isEmpty)
    }

    @Test func unexpectedResponseURLCannotPublishCredentialedData() async {
        SubscriptionURLProtocol.configure(responses: [
            "/api/dashboard/get-filtered-usage-events": [.init(body: history([event(input: 10, output: 20)], count: 1),
                responseURL: "https://untrusted.example/api/dashboard/get-filtered-usage-events")],
        ])
        let result = await makeService().subscriptionUsage()
        #expect(result.failedUsageProviders == [.cursor] && result.usageSamples.isEmpty)
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
        let url = try #require(URL(string: "https://cursor.com/api/dashboard/get-filtered-usage-events"))
        let response = try #require(HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil,
            headerFields: ["Location": "https://untrusted.example/"]))
        let task = session.dataTask(with: url)
        blocker.urlSession(session, task: task, willPerformHTTPRedirection: response,
            newRequest: URLRequest(url: URL(string: "https://untrusted.example/")!)) { request in
                #expect(request == nil)
            }
    }

    @Test func exhaustedHistoryBudgetAndCancelledRefreshDoNotIssueHistoryRequests() async {
        SubscriptionURLProtocol.configure(responses: [:])
        let exhausted = await makeService(historyDuration: .zero).subscriptionUsage()
        #expect(exhausted.failedUsageProviders == [.cursor] && exhausted.usageSamples.isEmpty)
        #expect(SubscriptionURLProtocol.requests.isEmpty)
        SubscriptionURLProtocol.configure(responses: [:])
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await makeService().subscriptionUsage()
        }
        let cancelled = await task.value
        #expect(cancelled.usageSamples.isEmpty)
        #expect(SubscriptionURLProtocol.requests.isEmpty)
    }

    private func makeService(cursor: @escaping @Sendable () throws -> String? = { "fixture-cookie" },
        maximumPages: Int = 200, pageSize: Int = 1_000, historyDuration: Duration = .seconds(60)) -> AISubscriptionUsageService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SubscriptionURLProtocol.self]
        return AISubscriptionUsageService(cursorCookie: cursor, configuration: configuration,
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
