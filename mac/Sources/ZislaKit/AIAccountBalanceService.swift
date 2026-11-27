import Foundation
import ZislaCore

public protocol AIAccountBalanceDetecting: Sendable {
    func accountBalances(for providers: Set<AIProvider>, qoderRegions: Set<AIAccountBalanceQoderRegion>) async throws -> [AIAccountBalance]
    func accountBalances(for providers: Set<AIProvider>, qoderRegions: Set<AIAccountBalanceQoderRegion>,
                         geminiSources: Set<AIAccountBalanceGeminiSource>) async throws -> [AIAccountBalance]
}

public extension AIAccountBalanceDetecting {
    func accountBalances(for providers: Set<AIProvider>, qoderRegions: Set<AIAccountBalanceQoderRegion>,
                         geminiSources: Set<AIAccountBalanceGeminiSource>) async throws -> [AIAccountBalance] {
        try await accountBalances(for: providers, qoderRegions: qoderRegions).filter { $0.matchesGeminiSources(geminiSources) }
    }
}

public final class AIAccountBalanceService: AIAccountBalanceDetecting, @unchecked Sendable {
    private static let browserUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36"

    private let credentials: @Sendable (AIProvider, Date, AIAccountBalanceQoderRegion) throws -> AIAccountBalanceCredential?
    private let session: URLSession
    private let now: @Sendable () -> Date
    private let museUsage: @Sendable () async throws -> Data?
    private let antigravityProbe: @Sendable () async throws -> AIAccountAntigravitySnapshot?
    private let geminiAppCookie: @Sendable () throws -> String?
    private let debugBalances: @Sendable () -> [AIAccountBalance]?
    private let preferredOpenAIProvider: @Sendable () -> AIProvider?

    /// Uses read-only login sources and a bounded Muse usage command with automatic updates disabled.
    /// An explicit debug fixture isolates all account reads, including when the fixture is malformed.
    public convenience init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                            environment: [String: String] = ProcessInfo.processInfo.environment,
                            now: @escaping @Sendable () -> Date = Date.init) {
        let source = AIAccountBalanceCredentials(home: home, environment: environment)
        let antigravity = AIAccountAntigravityProbe(home: home)
        self.init(credentials: { try source.load(for: $0, at: $1, qoderRegion: $2) }, now: now, museUsage: {
            let cli = AIAgentCLIService(environment: environment, homeDirectory: home)
            guard let executable = cli.executable(named: "muse") else { return nil }
            var processEnvironment = environment
            processEnvironment["MUSE_NO_AUTO_UPDATE"] = "1"
            let output = try await AIAgentProcessRunner.run(executableURL: executable, arguments: ["usage", "--json"],
                                                            environment: processEnvironment, workingDirectoryURL: FileManager.default.temporaryDirectory,
                                                            timeout: 15, maximumOutputBytes: 256 * 1_024, maximumErrorBytes: 16 * 1_024)
            guard !output.didTimeout else { throw AIAccountBalanceError.noQuota }
            if output.status != 0 {
                let stderr = output.standardError.lowercased()
                if stderr.contains("not logged in"), stderr.contains("muse login") { return nil }
                throw AIAccountBalanceError.noQuota
            }
            return output.standardOutput
        }, antigravityProbe: {
            try await antigravity.probe()
        }, geminiAppCookie: {
            try AIAccountBalanceCookieStore().cookie(for: .geminiApp)
        }, debugBalances: {
            #if DEBUG
                return AIAccountBalanceDebug.balances(environment: environment, now: now())
            #else
                nil
            #endif
        })
    }

    /// Isolates explicit authentication from ambient cookies and caches, and blocks redirects before credentials move.
    init(credentials: @escaping @Sendable (AIProvider, Date, AIAccountBalanceQoderRegion) throws -> AIAccountBalanceCredential?,
         configuration: URLSessionConfiguration = .ephemeral, now: @escaping @Sendable () -> Date = Date.init,
         museUsage: @escaping @Sendable () async throws -> Data? = { nil },
         antigravityProbe: @escaping @Sendable () async throws -> AIAccountAntigravitySnapshot? = { nil },
         geminiAppCookie: @escaping @Sendable () throws -> String? = { nil },
         debugBalances: @escaping @Sendable () -> [AIAccountBalance]? = { nil },
         preferredOpenAIProvider: @escaping @Sendable () -> AIProvider? = { AIMascotLibrary.installedOpenAIApplication()?.provider }) {
        self.credentials = credentials
        self.now = now
        self.museUsage = museUsage
        self.antigravityProbe = antigravityProbe
        self.geminiAppCookie = geminiAppCookie
        self.debugBalances = debugBalances
        self.preferredOpenAIProvider = preferredOpenAIProvider
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 15
        session = URLSession(configuration: configuration, delegate: SubscriptionRedirectBlocker(), delegateQueue: nil)
    }

    deinit { session.invalidateAndCancel() }

    /// Queries each selected shared account once with at most three groups in flight and stable result ordering.
    /// Unselected groups never read credentials; provider failures become rows while cancellation propagates.
    public func accountBalances(for providers: Set<AIProvider>, qoderRegions: Set<AIAccountBalanceQoderRegion> = [.global]) async throws -> [AIAccountBalance] {
        try await accountBalances(for: providers, qoderRegions: qoderRegions, geminiSources: Set(AIAccountBalanceGeminiSource.allCases))
    }

    public func accountBalances(for providers: Set<AIProvider>, qoderRegions: Set<AIAccountBalanceQoderRegion>,
                                geminiSources: Set<AIAccountBalanceGeminiSource>) async throws -> [AIAccountBalance] {
        try Task.checkCancellation()
        if let fixtures = debugBalances() {
            return fixtures
        }
        let groups = AIAccountBalanceCatalog.queryGroups(for: providers, qoderRegions: qoderRegions).flatMap { group in
            if group.providers == [.gemini] {
                return AIAccountBalanceGeminiSource.allCases.filter(geminiSources.contains).map {
                    (providers: group.providers, qoderRegion: group.qoderRegion, geminiSource: Optional($0))
                }
            }
            return [(providers: group.providers, qoderRegion: group.qoderRegion, geminiSource: Optional<AIAccountBalanceGeminiSource>.none)]
        }
        return try await withThrowingTaskGroup(of: (Int, AIAccountBalance).self) { group in
            var next = 0, results: [Int: AIAccountBalance] = [:]
            for _ in 0..<min(3, groups.count) {
                let index = next
                next += 1
                group.addTask { (index, try await self.refresh(groups[index].providers, selected: providers,
                                                               qoderRegion: groups[index].qoderRegion, geminiSource: groups[index].geminiSource)) }
            }
            while let (index, balance) = try await group.next() {
                results[index] = balance
                if next < groups.count {
                    let index = next
                    next += 1
                    group.addTask { (index, try await self.refresh(groups[index].providers, selected: providers,
                                                                   qoderRegion: groups[index].qoderRegion, geminiSource: groups[index].geminiSource)) }
                }
            }
            try Task.checkCancellation()
            return groups.indices.compactMap { results[$0] }.flatMap(AIAccountBalanceCatalog.antigravityBalances)
        }
    }

    /// Publishes a complete validated reading or a sanitized status, never partial windows or raw error text.
    /// A cancelled query must escape the provider failure path instead of appearing as an unavailable balance.
    private func refresh(_ group: [AIProvider], selected: Set<AIProvider>, qoderRegion: AIAccountBalanceQoderRegion?,
                         geminiSource: AIAccountBalanceGeminiSource?) async throws -> AIAccountBalance {
        let provider = group[0]
        var row = AIAccountBalanceCatalog.placeholder(for: group.filter { selected.contains($0) }, qoderRegion: qoderRegion)
        if let geminiSource {
            row.quotaGroup = geminiSource.rawValue
            row.id += ":" + geminiSource.rawValue
            if geminiSource == .app {
                row.status = .additionalCredentialsRequired
                row.detailKey = "Gemini App 使用同一账号的网页版额度，请添加网站额度凭据"
            }
        }
        if provider == .codex, row.providers.count > 1, preferredOpenAIProvider() == .gpt {
            row.providers = [.gpt, .codex]
        }
        guard row.status == .notSignedIn || row.status == .additionalCredentialsRequired else { return row }
        let time = now()
        do {
            try Task.checkCancellation()
            if geminiSource == .app {
                guard let cookie = try geminiAppCookie() else { return row }
                let token = try AIAccountBalanceCookieStore.normalizedCookie(cookie, website: .geminiApp)
                let credential = AIAccountBalanceCredential(token: token)
                row.id = "gemini:app:" + credential.identity(provider: .gemini)
                row.windows = try await fetchGeminiApp(credential: credential)
            } else if provider == .muse {
                guard let data = try await museUsage() else { return row }
                row.windows = try AIAccountBalanceParser.parse(data, provider: provider, now: time)
            } else if provider == .antigravity {
                guard let snapshot = try await antigravityProbe() else { return row }
                if let accountID = snapshot.accountID {
                    row.id = provider.rawValue + ":" + DesktopAIStorage.identity([provider.rawValue, "", accountID])
                }
                row.accountName = snapshot.accountName
                row.windows = snapshot.windows
            } else {
                if let credential = try credentials(provider, time, qoderRegion ?? .global) {
                    row.id = provider.rawValue + (geminiSource.map { ":" + $0.rawValue } ?? "") + ":" + credential.identity(provider: provider)
                    row.accountName = credential.accountName
                    row.windows = try await fetch(provider, credential: credential, now: time)
                } else {
                    return row
                }
            }
            try Task.checkCancellation()
            row.status = .available
            row.updatedAt = time
            if provider == .codex { row.detailKey = "Codex 账户额度" }
            else if provider == .zed, row.windows.allSatisfy({ $0.kind == .predictions }) { row.detailKey = "仅编辑预测额度，模型余额需要网站登录凭据" }
            else { row.detailKey = nil }
            return row
        } catch {
            try Task.checkCancellation()
            row.status = Self.status(error)
            row.windows = []
            return row
        }
    }

    private func fetchGeminiApp(credential: AIAccountBalanceCredential) async throws -> [AIAccountQuotaWindow] {
        let page = try await request("https://gemini.google.com/usage", headers: ["User-Agent": Self.browserUserAgent])
        let scriptURL = try AIAccountGeminiAppQuotaParser.usageScriptURL(page)
        let script = try await request(scriptURL.absoluteString)
        let signature = try AIAccountGeminiAppQuotaParser.querySignature(script)
        var endpoint = URLComponents(string: "https://gemini.google.com/_/BardChatUi/graphql/schemas/GEMINI_WEB_GRAPHQL/executeQuery")!
        endpoint.queryItems = [URLQueryItem(name: "query_signature", value: signature), URLQueryItem(name: "variables", value: "{}")]
        endpoint.percentEncodedQuery = endpoint.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        let data = try await request(endpoint.url!.absoluteString, credential: credential, cookie: true,
                                     headers: ["User-Agent": Self.browserUserAgent, "Referer": "https://gemini.google.com/usage"])
        return try AIAccountGeminiAppQuotaParser.parse(data)
    }

    /// Uses fixed provider endpoints and the chosen realm; website authentication never falls back to native login.
    /// WorkBuddy AI retries the same host's versioned endpoint only for its known 404 compatibility response.
    private func fetch(_ provider: AIProvider, credential: AIAccountBalanceCredential, now: Date) async throws -> [AIAccountQuotaWindow] {
        let data: Data
        switch provider {
        case .copilot:
            data = try await request("https://api.github.com/copilot_internal/user", credential: credential,
                                     headers: ["Authorization": "token " + credential.token,
                                               "User-Agent": "GitHubCopilotChat/0.26.7",
                                               "X-Github-Api-Version": "2025-04-01",
                                               "Editor-Version": "vscode/1.96.2",
                                               "Editor-Plugin-Version": "copilot-chat/0.26.7",
                                               "Copilot-Integration-Id": "vscode-chat"])
        case .coder:
            let base = credential.region == "cn" ? "https://qoder.com.cn" : "https://qoder.com"
            let headers = ["Accept": "application/json, text/plain, */*",
                           "Accept-Language": "en-US,en;q=0.9",
                           "User-Agent": Self.browserUserAgent,
                           "Origin": base,
                           "Referer": base + "/account/usage",
                           "X-Requested-With": "XMLHttpRequest",
                           "Bx-V": "2.5.35"]
            data = try await request(base + "/api/v2/me/usages/big_model_credits", credential: credential, cookie: true, headers: headers)
            let root = try AIAccountBalanceCredentials.object(data)
            let payload = root["data"] as? [String: Any] ?? root
            var sharedRoot: [String: Any]?
            if payload["sharedQuota"] == nil && payload["shared_quota"] == nil {
                if let sharedData = try? await request(base + "/api/v1/me/organization-shared-usages/big_model_credits",
                                                       credential: credential, cookie: true, headers: headers) {
                    sharedRoot = try? AIAccountBalanceCredentials.object(sharedData)
                }
            }
            let windows = try AIAccountBalanceParser.qoder(root, shared: sharedRoot)
            guard !windows.isEmpty, windows.allSatisfy(\.isValid) else { throw AIAccountBalanceError.noQuota }
            return windows
        case .trae:
            let headers = ["Origin": "https://www.trae.cn",
                           "Referer": "https://www.trae.cn/",
                           "User-Agent": Self.browserUserAgent]
            let exchange = try await request("https://api.trae.cn/cloudide/api/v3/common/GetUserToken", credential: credential,
                                             cookie: true, headers: headers, body: [:])
            let root = try AIAccountBalanceCredentials.object(exchange)
            guard AIAccountBalanceCredentials.number(root["code"]) != 1001,
                  let token = (root["Result"] as? [String: Any])?["Token"] as? String else { throw AIAccountBalanceError.credentialsExpired }
            data = try await request("https://api.trae.cn/trae/api/v2/pay/user_current_entitlement_list", credential: credential,
                                     cookie: true, headers: headers.merging(["Authorization": "Cloud-IDE-JWT " + (try AIAccountBalanceCredentials.header(token))],
                                                                            uniquingKeysWith: { _, new in new }), body: ["require_usage": true, "full_data": true])
        case .claude:
            data = try await request("https://api.anthropic.com/api/oauth/usage", credential: credential,
                                     headers: ["anthropic-beta": "oauth-2025-04-20",
                                               "User-Agent": "claude-cli/2.1.280 (external, cli)"])
        case .codex, .gpt:
            var headers: [String: String] = [:]
            if let accountID = credential.accountID { headers["ChatGPT-Account-Id"] = accountID }
            data = try await request("https://chatgpt.com/backend-api/wham/usage", credential: credential, headers: headers)
        case .gemini:
            let setup = try await request("https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist", credential: credential,
                                          body: ["metadata": ["ideType": "GEMINI_CLI", "pluginType": "GEMINI"]])
            let root = try AIAccountBalanceCredentials.object(setup)
            let project = Self.geminiProjectID(from: root)
            let body: [String: Any] = project.map { ["project": $0] } ?? [:]
            data = try await request("https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota", credential: credential, body: body)
        case .grok:
            let (body, response) = try await requestWithResponse(
                "https://grok.com/grok_api_v2.GrokBuildBilling/GetGrokCreditsConfig",
                credential: credential,
                headers: ["X-XAI-Token-Auth": "xai-grok-cli",
                          "Accept": "*/*",
                          "Content-Type": "application/grpc-web+proto",
                          "User-Agent": "Grok Build",
                          "Origin": "https://grok.com",
                          "Referer": "https://grok.com/?_s=usage",
                          "x-grpc-web": "1",
                          "x-user-agent": "connect-es/2.1.1"],
                rawBody: Data([0, 0, 0, 0, 0])
            )
            try AIAccountGrokQuotaParser.validateGRPCStatus(
                status: response.value(forHTTPHeaderField: "grpc-status"),
                message: response.value(forHTTPHeaderField: "grpc-message")
            )
            return try AIAccountGrokQuotaParser.parse(body, now: now)
        case .kimi:
            data = try await request("https://api.kimi.com/coding/v1/usages", credential: credential)
        case .cursor, .grokBot:
            return try await fetchCursor(credential: credential, now: now)
        case .zcode:
            if credential.region == "start-plan" {
                data = try await request("https://zcode.z.ai/api/v1/zcode-plan/billing/balance", credential: credential)
            } else {
                let base = credential.region == "bigmodel" ? "https://open.bigmodel.cn" : "https://api.z.ai"
                data = try await request(base + "/api/monitor/usage/quota/limit", credential: credential)
            }
        case .zed:
            if credential.isWebsiteCookie {
                let headers = ["Accept": "application/json, text/plain, */*",
                               "Accept-Language": "en-US,en;q=0.9",
                               "User-Agent": Self.browserUserAgent,
                               "Origin": "https://dashboard.zed.dev",
                               "Referer": "https://dashboard.zed.dev/"]
                data = try await request("https://cloud.zed.dev/frontend/billing/usage", credential: credential,
                                         cookie: true, headers: headers)
                let root = try AIAccountBalanceCredentials.object(data)
                let subscription = (try? await request("https://cloud.zed.dev/frontend/billing/subscriptions/current",
                                                       credential: credential, cookie: true, headers: headers))
                    .flatMap { try? AIAccountBalanceCredentials.object($0) }
                let windows = try AIAccountBalanceParser.zed(root, subscription: subscription)
                guard !windows.isEmpty, windows.allSatisfy(\.isValid) else { throw AIAccountBalanceError.noQuota }
                return windows
            }
            guard let accountID = credential.accountID else { throw AIAccountBalanceError.invalidCredentials }
            data = try await request("https://cloud.zed.dev/client/users/me", credential: credential,
                                     headers: ["Authorization": accountID + " " + credential.token])
        case .workbuddy, .workbuddyAI:
            let base = provider == .workbuddyAI ? "https://www.workbuddy.ai" : "https://copilot.tencent.com"
            let enterprise = credential.headers["X-Enterprise-Id"] != nil
            let path = "/billing/meter/" + (enterprise ? "get-enterprise-user-usage" : "get-user-resource")
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            let body: [String: Any] = enterprise ? [:] : ["PageNumber": 1, "PageSize": 100, "ProductCode": "p_tcaca", "Status": [0, 3],
                                                          "PackageEndTimeRangeBegin": formatter.string(from: now),
                                                          "PackageEndTimeRangeEnd": formatter.string(from: now.addingTimeInterval(101 * 365 * 86_400))]
            do { data = try await request(base + (provider == .workbuddyAI ? "" : "/v2") + path, credential: credential, body: body) }
            catch AIAccountBalanceError.httpStatus(404) where provider == .workbuddyAI {
                data = try await request(base + "/v2" + path, credential: credential, body: body)
            }
        case .opencode:
            let (body, response) = try await requestWithResponse(
                "https://opencode.ai/zen/go/v1/usage",
                credential: credential,
                allowErrorBodyStatuses: [403]
            )
            if response.statusCode == 403 {
                if let payload = try? AIAccountBalanceCredentials.object(body),
                   let error = payload["error"] as? [String: Any],
                   error["type"] as? String == "EntitlementError" {
                    throw AIAccountBalanceError.noQuota
                }
                throw AIAccountBalanceError.httpStatus(403)
            }
            data = body
        default: throw AIAccountBalanceError.noQuota
        }
        return try AIAccountBalanceParser.parse(data, provider: provider, now: now)
    }

    private func fetchCursor(credential: AIAccountBalanceCredential, now: Date) async throws -> [AIAccountQuotaWindow] {
        let getHeaders = ["Accept": "*/*",
                          "Accept-Language": "en-US,en;q=0.9",
                          "Referer": "https://cursor.com/dashboard",
                          "User-Agent": Self.browserUserAgent]
        let postHeaders = getHeaders.merging(["Accept": "application/json", "Origin": "https://cursor.com"], uniquingKeysWith: { _, new in new })
        let summary = try await request("https://cursor.com/api/usage-summary", credential: credential, cookie: true, headers: getHeaders)
        let root = try AIAccountBalanceCredentials.object(summary)
        let planInfo = (try? await request("https://cursor.com/api/dashboard/get-plan-info", credential: credential, cookie: true, headers: postHeaders, body: [:]))
            .flatMap { try? AIAccountBalanceCredentials.object($0) }
        let sand = (try? await request("https://cursor.com/api/dashboard/get-sand-usage-status", credential: credential, cookie: true, headers: postHeaders, body: [:]))
            .flatMap { try? AIAccountBalanceCredentials.object($0) }
        let isUnified = AIAccountBalanceParser.cursorIsUnified(root: root, sand: sand, planInfo: planInfo)
        var currentPeriod: [String: Any]?
        var prepaid: [String: Any]?
        var requestUsage: [String: Any]?
        if isUnified {
            if let bearer = Self.cursorAccessToken(from: credential.token),
               let safeBearer = try? AIAccountBalanceCredentials.header(bearer) {
                let bearerCredential = AIAccountBalanceCredential(token: safeBearer)
                currentPeriod = (try? await request(
                    "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage",
                    credential: bearerCredential,
                    headers: ["Accept": "application/json",
                              "Connect-Protocol-Version": "1",
                              "User-Agent": Self.browserUserAgent],
                    body: [:]
                )).flatMap { try? AIAccountBalanceCredentials.object($0) }
            }
            prepaid = (try? await request("https://cursor.com/api/dashboard/get-user-prepaid-billing",
                                          credential: credential, cookie: true, headers: postHeaders, body: [:]))
                .flatMap { try? AIAccountBalanceCredentials.object($0) }
        }
        var windows = try AIAccountBalanceParser.cursor(
            root,
            now: now,
            sand: sand,
            planInfo: planInfo,
            currentPeriod: currentPeriod,
            prepaid: prepaid,
            requestUsage: requestUsage
        )
        if !isUnified, windows.isEmpty, let userID = credential.accountID, !userID.isEmpty,
           let encoded = userID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            requestUsage = (try? await request("https://cursor.com/api/usage?user=" + encoded,
                                               credential: credential, cookie: true, headers: getHeaders))
                .flatMap { try? AIAccountBalanceCredentials.object($0) }
            if requestUsage != nil {
                windows = try AIAccountBalanceParser.cursor(root, now: now, sand: sand, planInfo: planInfo, requestUsage: requestUsage)
            }
        }
        guard !windows.isEmpty, windows.allSatisfy(\.isValid) else { throw AIAccountBalanceError.noQuota }
        return windows
    }

    private static func cursorAccessToken(from cookie: String) -> String? {
        var value = cookie
        if let range = value.range(of: "WorkosCursorSessionToken=") {
            value = String(value[range.upperBound...])
        }
        if let semicolon = value.firstIndex(of: ";") {
            value = String(value[..<semicolon])
        }
        let decoded = value.removingPercentEncoding ?? value
        guard let separator = decoded.range(of: "::") else { return nil }
        let token = String(decoded[separator.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return token.split(separator: ".", omittingEmptySubsequences: false).count == 3 ? token : nil
    }

    private static func geminiProjectID(from root: [String: Any]) -> String? {
        for container in [root, root["response"] as? [String: Any]].compactMap({ $0 }) {
            for key in ["cloudaicompanionProject", "projectId", "project"] {
                if let value = container[key] as? String, !value.isEmpty { return value }
                if let object = container[key] as? [String: Any] {
                    for nested in ["value", "id", "projectId"] {
                        if let value = object[nested] as? String, !value.isEmpty { return value }
                    }
                }
            }
        }
        return nil
    }

    /// Sends credentials only to an internal fixed endpoint with a 15-second timeout and a 1 MiB streaming limit.
    /// The session blocks redirects, and an unexpected response URL or status invalidates the entire reading.
    private func request(_ endpoint: String, credential: AIAccountBalanceCredential? = nil, cookie: Bool = false,
                         headers: [String: String] = [:], body: [String: Any]? = nil, rawBody: Data? = nil) async throws -> Data {
        try await requestWithResponse(endpoint, credential: credential, cookie: cookie, headers: headers, body: body, rawBody: rawBody).data
    }

    private func requestWithResponse(_ endpoint: String, credential: AIAccountBalanceCredential? = nil, cookie: Bool = false,
                                     headers: [String: String] = [:], body: [String: Any]? = nil, rawBody: Data? = nil,
                                     allowErrorBodyStatuses: Set<Int> = []) async throws -> (data: Data, response: HTTPURLResponse) {
        try Task.checkCancellation()
        var request = URLRequest(url: URL(string: endpoint)!)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let credential {
            request.setValue(cookie ? credential.token : "Bearer " + credential.token, forHTTPHeaderField: cookie ? "Cookie" : "Authorization")
        }
        for (key, value) in (credential?.headers ?? [:]).merging(headers, uniquingKeysWith: { _, new in new }) {
            request.setValue(value, forHTTPHeaderField: key)
        }
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } else if let rawBody { request.httpMethod = "POST"; request.httpBody = rawBody }
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse, response.url == request.url else { throw AIAccountBalanceError.invalidResponse }
        guard response.statusCode == 200 || allowErrorBodyStatuses.contains(response.statusCode) else {
            throw AIAccountBalanceError.httpStatus(response.statusCode)
        }
        guard response.expectedContentLength <= 1_024 * 1_024 else { throw AIAccountBalanceError.invalidResponse }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < 1_024 * 1_024 else { throw AIAccountBalanceError.invalidResponse }
            data.append(byte)
        }
        return (data, response)
    }

    /// Classifies expected failures without copying response bodies, credential paths, or secrets into UI text.
    private static func status(_ error: Error) -> AIAccountBalanceStatus {
        switch error {
        case AIAccountBalanceError.credentialsExpired, AIAccountBalanceError.httpStatus(401), AIAccountBalanceError.httpStatus(403): .credentialsExpired
        case AIAccountBalanceError.invalidCredentials, AIAccountBalanceError.credentialsUnavailable,
             is AISubscriptionCredentials.KeychainReadError, is AISubscriptionUsageError: .credentialsUnavailable
        case AIAccountBalanceError.unsupportedLogin: .additionalCredentialsRequired
        case AIAccountBalanceError.httpStatus(429): .rateLimited
        case AIAccountBalanceError.invalidResponse: .invalidResponse
        default: .unavailable
        }
    }
}
