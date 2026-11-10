import Foundation
import Testing
@testable import ZislaCore
@testable import ZislaKit

@Suite(.serialized)
struct AIAccountBalanceServiceTests {
    private let now = Date(timeIntervalSince1970: 1_910_000_000)

    /// Recorded requests prove shared-account deduplication, selected alias output, and secret-free public rows.
    @Test func sharedAliasesFetchOnceAndPublishOnlySelectedNamesWithoutSecrets() async throws {
        BalanceURLProtocol.configure(["/backend-api/wham/usage": [.json(#"{"rate_limit":{"primary_window":{"used_percent":90,"limit_window_seconds":18000}}}"#)],
            "/api/usage-summary": [.json(#"{"individualUsage":{"plan":{"used":900,"limit":1000}}}"#)]])
        let service = makeService()
        let rows = try await service.accountBalances(for: [.gpt, .grokBot])
        #expect(rows.map(\.providers) == [[.gpt], [.grokBot]])
        #expect(rows.allSatisfy { $0.status == .available && $0.updatedAt == now })
        #expect(BalanceURLProtocol.requests.count == 2)
        #expect(BalanceURLProtocol.requests.first { $0.url?.host == "chatgpt.com" }?.value(forHTTPHeaderField: "ChatGPT-Account-Id") == "fixture-account")
        #expect(!String(describing: rows).contains("fixture-secret"))
        let both = try await service.accountBalances(for: [.codex, .gpt])
        #expect(both.count == 1 && both[0].providers == [.codex, .gpt])
        #expect(BalanceURLProtocol.requests.count == 3)
    }

    /// Forbidden-read seams prove disabled and debug paths stay isolated even when a fixture is invalid.
    @Test func disabledMissingUnsupportedAndDebugSourcesDoNoCredentialedRequests() async throws {
        BalanceURLProtocol.configure([:])
        let service = makeService(credentials: { _, _, _ in Issue.record("Disabled providers must not read credentials"); return nil })
        #expect(try await service.accountBalances(for: []).isEmpty)
        let unsupported = try await service.accountBalances(for: [.qwen, .pi, .doubao, .delta, .harness, .orca])
        #expect(unsupported.count == 6 && unsupported.allSatisfy { $0.status == .queryUnsupported || $0.status == .connectedAccount })
        #expect(BalanceURLProtocol.requests.isEmpty)
        #if DEBUG
        for raw in ["claude:0:70,gpt:10", "", "claude:nan", "codex:101", "claude:10,claude:20", "codex:10,gpt:20"] {
            let service = makeService(credentials: { _, _, _ in Issue.record("Debug fixtures must not read credentials"); return nil },
                debug: { AIAccountBalanceDebug.balances(environment: ["ZISLA_DEBUG_AI_ACCOUNT_BALANCE": raw], now: now) })
            let result = try await service.accountBalances(for: Set(AIProvider.allCases))
            #expect(result.allSatisfy { $0.isDebug })
            #expect(BalanceURLProtocol.requests.isEmpty)
        }
        #endif
        let missing = try await makeService(credentials: { _, _, _ in nil }).accountBalances(for: [.claude, .coder])
        #expect(missing.map(\.status) == [.notSignedIn, .additionalCredentialsRequired])
        #expect(BalanceURLProtocol.requests.isEmpty)
    }

    /// One provider's HTTP failure must preserve another provider's reading without exposing body text or secrets.
    @Test(arguments: [(401, AIAccountBalanceStatus.credentialsExpired), (403, .credentialsExpired), (429, .rateLimited), (503, .unavailable)])
    func failuresStayIsolatedSanitizedAndRecover(scenario: (status: Int, expected: AIAccountBalanceStatus)) async throws {
        BalanceURLProtocol.configure(["/api/oauth/usage": [.init(status: scenario.status, data: Data("private-body".utf8))],
            "/backend-api/wham/usage": [.json(#"{"credits":{"has_credits":true,"balance":"10"}}"#)]])
        let service = makeService()
        let result = try await service.accountBalances(for: [.claude, .codex])
        #expect(result.first?.status == scenario.expected && result.first?.windows.isEmpty == true)
        #expect(result.last?.status == .available)
        #expect(!String(describing: result).contains("private-body") && !String(describing: result).contains("fixture-secret"))
        BalanceURLProtocol.configure(["/api/oauth/usage": [.json(#"{"five_hour":{"utilization":0}}"#)]])
        #expect(try await service.accountBalances(for: [.claude]).first?.windows.first?.remainingPercent == 100)
    }

    /// Body and declared size, unexpected URL, timeout, and redirect-like responses must all invalidate quota.
    @Test func responseSizeURLAndNetworkFailuresCannotPublishPartialQuota() async throws {
        for response in [BalanceURLProtocol.Response(data: Data(repeating: 32, count: 1_024 * 1_024 + 1)),
            .init(data: Data("{}".utf8), contentLength: 1_024 * 1_024 + 1),
            .init(data: Data(#"{"five_hour":{"utilization":0}}"#.utf8), url: "https://untrusted.example/"),
            .init(error: .timedOut), .init(status: 302)] {
            BalanceURLProtocol.configure(["/api/oauth/usage": [response]])
            let result = try await makeService().accountBalances(for: [.claude])
            #expect(result.first?.severity == nil && result.first?.windows.isEmpty == true)
            #expect(BalanceURLProtocol.requests.count == 1)
        }
    }

    /// Request host/header/body assertions prove selected-region authentication and prevent an expired website from changing accounts.
    @Test func websiteRegionsAndCookieAuthenticationUseOnlyFixedHostsAndNeverFallback() async throws {
        let qoder = #"{"data":{"totalQuota":{"quotaSummary":{"limitValue":100,"usedValue":90}}}}"#
        BalanceURLProtocol.configure(["/api/v2/me/usages/big_model_credits": [.json(qoder), .json(qoder)],
            "/cloudide/api/v3/common/GetUserToken": [.json(#"{"Result":{"Token":"fixture-exchanged-token"}}"#)],
            "/trae/api/v2/pay/user_current_entitlement_list": [.json(#"{"is_credits_billing":true,"usage_summary":{"total_amount":100,"consumed_amount":90}}"#)],
            "/frontend/billing/usage": [.init(status: 401)]])
        let service = makeService(credentials: { provider, _, region in
            var credential = AIAccountBalanceCredential(token: "session=fixture-secret", region: region == .china ? "cn" : "global")
            credential.isWebsiteCookie = [.coder, .trae, .zed].contains(provider)
            return credential
        })
        #expect(try await service.accountBalances(for: [.coder], qoderRegion: .china).first?.status == .available)
        #expect(try await service.accountBalances(for: [.coder], qoderRegion: .global).first?.status == .available)
        #expect(BalanceURLProtocol.requests.prefix(2).map { $0.url?.host } == ["qoder.com.cn", "qoder.com"])
        #expect(try await service.accountBalances(for: [.trae]).first?.status == .available)
        let entitlement = try #require(BalanceURLProtocol.requests.first { $0.url?.path.hasSuffix("user_current_entitlement_list") == true })
        #expect(entitlement.value(forHTTPHeaderField: "Authorization") == "Cloud-IDE-JWT fixture-exchanged-token")
        #expect(entitlement.value(forHTTPHeaderField: "Cookie") == "session=fixture-secret")
        let body = try JSONSerialization.jsonObject(with: try #require(entitlement.httpBody)) as? [String: Bool]
        #expect(body == ["require_usage": true, "full_data": true])
        let zed = try await service.accountBalances(for: [.zed])
        #expect(zed.first?.status == .credentialsExpired)
        #expect(!BalanceURLProtocol.requests.contains { $0.url?.path == "/client/users/me" }, "An expired website session must not fall back to another account")
    }

    /// Unified Cursor must use current endpoints; WorkBuddy's version fallback must not retry authentication failure.
    @Test func cursorUnifiedRequestsUseCurrentWindowsAndWorkBuddyFallbackRequires404() async throws {
        BalanceURLProtocol.configure(["/api/usage-summary": [.json(#"{"membershipType":"unified_pro","limitType":"user","individualUsage":{"plan":{"used":0,"limit":1000}}}"#)],
            "/api/dashboard/get-sand-usage-status": [.json(#"{"usagePercent":90,"hasNonZeroIncludedLimit":true}"#)],
            "/api/dashboard/v2/usage-status": [.json(#"{"availability":"available","monthlyUsage":{"usedCents":800,"limitCents":1000,"periodStart":"2030-01-01T00:00:00Z","resetsAt":"2031-01-01T00:00:00Z"}}"#)],
            "/billing/meter/get-user-resource": [.init(status: 404)],
            "/v2/billing/meter/get-user-resource": [.json(#"{"data":{"Accounts":[{"Status":0,"CycleCapacitySizePrecise":100,"CycleCapacityRemainPrecise":20}]}}"#)]])
        let rows = try await makeService().accountBalances(for: [.cursor, .workbuddyAI])
        #expect(rows.allSatisfy { $0.status == .available })
        #expect(rows.first { $0.providers == [.cursor] }?.windows.map(\.remainingPercent) == [10, 20])
        #expect(BalanceURLProtocol.requests.count == 5)
        BalanceURLProtocol.configure(["/billing/meter/get-user-resource": [.init(status: 401)]])
        #expect(try await makeService().accountBalances(for: [.workbuddyAI]).first?.status == .credentialsExpired)
        #expect(BalanceURLProtocol.requests.count == 1)
    }

    /// Held request events expose the concurrency bound and make in-flight versus pre-start cancellation observable.
    @Test func groupedParallelRequestsAreBoundedAndCancellationPropagates() async throws {
        let (events, continuation) = AsyncStream<Int>.makeStream()
        BalanceURLProtocol.configure(["/api/oauth/usage": [.json(#"{"five_hour":{"utilization":0}}"#)],
            "/backend-api/wham/usage": [.json(#"{"credits":{"has_credits":true,"balance":10}}"#)],
            "/copilot_internal/user": [.json(#"{"quota_snapshots":{"chat":{"percent_remaining":50}}}"#)],
            "/coding/v1/usages": [.json(#"{"usages":{"limit_5h":{"used_ratio":0.1}}}"#)],
            "/zen/go/v1/usage": [.json(#"{"usage":{"rolling":{"percent":10},"weekly":{"percent":20}}}"#)]],
            held: true, event: { continuation.yield($0) })
        defer { BalanceURLProtocol.release(); continuation.finish() }
        let service = makeService()
        let task = Task { try await service.accountBalances(for: [.claude, .codex, .copilot, .kimi, .opencode]) }
        var iterator = events.makeAsyncIterator()
        for _ in 0..<3 { _ = await iterator.next() }
        #expect(BalanceURLProtocol.requests.count == 3)
        BalanceURLProtocol.release()
        #expect(try await task.value.count == 5)
        #expect(BalanceURLProtocol.maximumActive <= 3)
        for _ in 3..<5 { _ = await iterator.next() }
        BalanceURLProtocol.configure([:], held: true, event: { continuation.yield($0) })
        let cancelled = Task { try await service.accountBalances(for: [.claude]) }
        _ = await iterator.next()
        cancelled.cancel()
        await #expect(throws: CancellationError.self) { try await cancelled.value }
        #expect(BalanceURLProtocol.requests.count == 1)
        let preCancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await service.accountBalances(for: [.claude])
        }
        await #expect(throws: CancellationError.self) { try await preCancelled.value }
        #expect(BalanceURLProtocol.requests.count == 1)
    }

    /// Injected CLI bytes distinguish no login, malformed schema, and valid quota without launching a real process.
    @Test func museFailureMissingAndSchemaUseOnlyInjectedProcessData() async throws {
        BalanceURLProtocol.configure([:])
        for data in [nil, Data("{}".utf8), Data(#"{"schemaVersion":1,"allowance":{"window":{"usedPercent":100,"windowDurationMins":300}}}"#.utf8)] {
            let result = try await makeService(muse: { data }).accountBalances(for: [.muse])
            #expect(result.first?.status == (data == nil ? .notSignedIn : data!.count == 2 ? .invalidResponse : .available))
        }
        #expect(BalanceURLProtocol.requests.isEmpty)
    }

    private func makeService(credentials: @escaping @Sendable (AIProvider, Date, AIAccountBalanceQoderRegion) throws -> AIAccountBalanceCredential? = { _, _, _ in
        AIAccountBalanceCredential(token: "fixture-secret", accountID: "fixture-account")
    }, debug: @escaping @Sendable () -> [AIAccountBalance]? = { nil },
        muse: @escaping @Sendable () async throws -> Data? = { nil }) -> AIAccountBalanceService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BalanceURLProtocol.self]
        return .init(credentials: credentials, configuration: configuration, now: { now }, museUsage: muse, debugBalances: debug)
    }
}

private final class BalanceURLProtocol: URLProtocol, @unchecked Sendable {
    struct Response {
        var status = 200
        var data = Data("{}".utf8)
        var error: URLError.Code?
        var url: String?
        var contentLength: Int?
        static func json(_ value: String) -> Self { .init(data: Data(value.utf8)) }
    }
    private static let lock = NSLock()
    nonisolated(unsafe) private static var responses: [String: [Response]] = [:]
    nonisolated(unsafe) private static var recorded: [URLRequest] = []
    nonisolated(unsafe) private static var pending: [BalanceURLProtocol] = []
    nonisolated(unsafe) private static var held = false
    nonisolated(unsafe) private static var event: @Sendable (Int) -> Void = { _ in }
    nonisolated(unsafe) private static var active = 0
    nonisolated(unsafe) private static var maximum = 0
    private var response = Response()
    private var finished = false
    static var requests: [URLRequest] { lock.withLock { recorded } }
    static var maximumActive: Int { lock.withLock { maximum } }
    static func configure(_ responses: [String: [Response]], held: Bool = false, event: @escaping @Sendable (Int) -> Void = { _ in }) {
        lock.withLock { Self.responses = responses; recorded = []; pending = []; Self.held = held; Self.event = event; active = 0; maximum = 0 }
    }
    static func release() {
        let items = lock.withLock { held = false; let items = pending; pending = []; return items }
        items.forEach { $0.finish() }
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    /// Captures body streams before publishing request events, so tests inspect actual authentication payloads.
    /// Held responses provide a deterministic seam for concurrency and cancellation instead of timing sleeps.
    override func startLoading() {
        var recordedRequest = request
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var data = Data(), bytes = [UInt8](repeating: 0, count: 1_024)
            while stream.hasBytesAvailable {
                let count = stream.read(&bytes, maxLength: bytes.count)
                guard count > 0 else { break }
                data.append(contentsOf: bytes.prefix(count))
            }
            recordedRequest.httpBody = data
        }
        let (hold, count, event) = Self.lock.withLock {
            Self.recorded.append(recordedRequest)
            Self.active += 1; Self.maximum = max(Self.maximum, Self.active)
            var queue = Self.responses[request.url!.path] ?? []
            response = queue.isEmpty ? .init(error: .unsupportedURL) : queue.removeFirst()
            Self.responses[request.url!.path] = queue
            if Self.held { Self.pending.append(self) }
            return (Self.held, Self.recorded.count, Self.event)
        }
        event(count)
        if !hold { finish() }
    }
    /// Completes each mock request once so cancellation cannot corrupt active-request bounds or deliver twice.
    private func finish() {
        guard Self.lock.withLock({ if finished { return false }; finished = true; Self.active -= 1; return true }) else { return }
        if let error = response.error { client?.urlProtocol(self, didFailWithError: URLError(error)); return }
        var headers = ["Content-Type": "application/json"]
        if let length = response.contentLength { headers["Content-Length"] = String(length) }
        let http = HTTPURLResponse(url: response.url.flatMap(URL.init(string:)) ?? request.url!, statusCode: response.status, httpVersion: nil, headerFields: headers)!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.data)
        client?.urlProtocolDidFinishLoading(self)
    }
    /// Removes cancelled held requests so later fixture release cannot deliver their response.
    override func stopLoading() {
        Self.lock.withLock { if !finished { finished = true; Self.active -= 1 }; Self.pending.removeAll { $0 === self } }
    }
}
