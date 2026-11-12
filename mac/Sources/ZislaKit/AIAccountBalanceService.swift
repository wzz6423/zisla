import Foundation
import ZislaCore

public protocol AIAccountBalanceDetecting: Sendable {
    func accountBalances(for providers: Set<AIProvider>, qoderRegion: AIAccountBalanceQoderRegion) async throws -> [AIAccountBalance]
}

public final class AIAccountBalanceService: AIAccountBalanceDetecting, @unchecked Sendable {
    private let credentials: @Sendable (AIProvider, Date, AIAccountBalanceQoderRegion) throws -> AIAccountBalanceCredential?
    private let session: URLSession
    private let now: @Sendable () -> Date
    private let museUsage: @Sendable () async throws -> Data?
    private let debugBalances: @Sendable () -> [AIAccountBalance]?

    /// Uses read-only login sources and a bounded Muse usage command with automatic updates disabled.
    /// An explicit debug fixture isolates all account reads, including when the fixture is malformed.
    public convenience init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                            environment: [String: String] = ProcessInfo.processInfo.environment,
                            now: @escaping @Sendable () -> Date = Date.init) {
        let source = AIAccountBalanceCredentials(home: home, environment: environment)
        self.init(credentials: { try source.load(for: $0, at: $1, qoderRegion: $2) }, now: now, museUsage: {
            let cli = AIAgentCLIService(environment: environment, homeDirectory: home)
            guard let executable = cli.executable(named: "muse") else { return nil }
            var processEnvironment = environment
            processEnvironment["MUSE_NO_AUTO_UPDATE"] = "1"
            let output = try await AIAgentProcessRunner.run(executableURL: executable, arguments: ["usage", "--json"],
                environment: processEnvironment, workingDirectoryURL: FileManager.default.temporaryDirectory,
                timeout: 15, maximumOutputBytes: 256 * 1_024, maximumErrorBytes: 16 * 1_024)
            guard !output.didTimeout, output.status == 0 else { throw AIAccountBalanceError.noQuota }
            return output.standardOutput
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
         debugBalances: @escaping @Sendable () -> [AIAccountBalance]? = { nil }) {
        self.credentials = credentials
        self.now = now
        self.museUsage = museUsage
        self.debugBalances = debugBalances
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
    public func accountBalances(for providers: Set<AIProvider>, qoderRegion: AIAccountBalanceQoderRegion = .global) async throws -> [AIAccountBalance] {
        try Task.checkCancellation()
        if let fixtures = debugBalances() {
            return fixtures
        }
        let groups = AIAccountBalanceCatalog.groups.filter { !$0.allSatisfy { !providers.contains($0) } }
        return try await withThrowingTaskGroup(of: (Int, AIAccountBalance).self) { group in
            var next = 0, results: [Int: AIAccountBalance] = [:]
            for _ in 0..<min(3, groups.count) {
                let index = next
                next += 1
                group.addTask { (index, try await self.refresh(groups[index], selected: providers, qoderRegion: qoderRegion)) }
            }
            while let (index, balance) = try await group.next() {
                results[index] = balance
                if next < groups.count {
                    let index = next
                    next += 1
                    group.addTask { (index, try await self.refresh(groups[index], selected: providers, qoderRegion: qoderRegion)) }
                }
            }
            try Task.checkCancellation()
            return groups.indices.compactMap { results[$0] }
        }
    }

    /// Publishes a complete validated reading or a sanitized status, never partial windows or raw error text.
    /// A cancelled query must escape the provider failure path instead of appearing as an unavailable balance.
    private func refresh(_ group: [AIProvider], selected: Set<AIProvider>, qoderRegion: AIAccountBalanceQoderRegion) async throws -> AIAccountBalance {
        let provider = group[0]
        var row = AIAccountBalanceCatalog.placeholder(for: group.filter { selected.contains($0) })
        guard row.status == .notSignedIn || row.status == .additionalCredentialsRequired else { return row }
        let time = now()
        do {
            try Task.checkCancellation()
            if provider == .muse {
                guard let data = try await museUsage() else { return row }
                row.windows = try AIAccountBalanceParser.parse(data, provider: provider, now: time)
            } else {
                guard let credential = try credentials(provider, time, qoderRegion) else { return row }
                row.id = provider.rawValue + ":" + credential.identity(provider: provider)
                row.accountName = credential.accountName
                row.windows = try await fetch(provider, credential: credential, now: time)
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

    /// Uses fixed provider endpoints and the chosen realm; website authentication never falls back to native login.
    /// WorkBuddy AI retries the same host's versioned endpoint only for its known 404 compatibility response.
    private func fetch(_ provider: AIProvider, credential: AIAccountBalanceCredential, now: Date) async throws -> [AIAccountQuotaWindow] {
        let data: Data
        switch provider {
        case .copilot:
            data = try await request("https://api.github.com/copilot_internal/user", credential: credential,
                headers: ["Authorization": "token " + credential.token, "Editor-Version": "vscode/1.96.2",
                          "Editor-Plugin-Version": "copilot-chat/0.26.7", "Copilot-Integration-Id": "vscode-chat"])
        case .coder:
            let base = credential.region == "cn" ? "https://qoder.com.cn" : "https://qoder.com"
            data = try await request(base + "/api/v2/me/usages/big_model_credits", credential: credential, cookie: true,
                headers: ["Origin": base, "Referer": base + "/account/usage", "X-Requested-With": "XMLHttpRequest", "Bx-V": "2.5.35"])
        case .trae:
            let headers = ["Origin": "https://www.trae.cn", "Referer": "https://www.trae.cn/"]
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
                headers: ["anthropic-beta": "oauth-2025-04-20"])
        case .codex, .gpt:
            var headers: [String: String] = [:]
            if let accountID = credential.accountID { headers["ChatGPT-Account-Id"] = accountID }
            data = try await request("https://chatgpt.com/backend-api/wham/usage", credential: credential, headers: headers)
        case .gemini:
            let setup = try await request("https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist", credential: credential,
                body: ["metadata": ["ideType": "GEMINI_CLI", "pluginType": "GEMINI"]])
            let root = try AIAccountBalanceCredentials.object(setup)
            let project = root["cloudaicompanionProject"] as? String ?? (root["cloudaicompanionProject"] as? [String: Any])?["id"] as? String
            let body: [String: Any] = project.map { ["project": $0] } ?? [:]
            data = try await request("https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota", credential: credential, body: body)
        case .grok:
            data = try await request("https://grok.com/grok_api_v2.GrokBuildBilling/GetGrokCreditsConfig", credential: credential,
                headers: ["Content-Type": "application/grpc-web+proto", "Accept": "application/grpc-web+proto",
                          "Origin": "https://grok.com", "x-grpc-web": "1"], rawBody: Data([0, 0, 0, 0, 2, 8, 0]))
        case .kimi:
            data = try await request("https://api.kimi.com/coding/v1/usages", credential: credential)
        case .cursor, .grokBot:
            let summary = try await request("https://cursor.com/api/usage-summary", credential: credential, cookie: true)
            let root = try AIAccountBalanceCredentials.object(summary)
            let isUnified = (root["membershipType"] as? String)?.lowercased().hasPrefix("unified_") == true
                && (root["limitType"] as? String)?.lowercased() == "user"
            if isUnified {
                let sand = try await request("https://cursor.com/api/dashboard/get-sand-usage-status", credential: credential, cookie: true, body: [:])
                let monthly = try await request("https://cursor.com/api/dashboard/v2/usage-status", credential: credential, cookie: true)
                let windows = try AIAccountBalanceParser.cursor(root, now: now,
                    sand: AIAccountBalanceCredentials.object(sand), unified: AIAccountBalanceCredentials.object(monthly))
                guard !windows.isEmpty, windows.allSatisfy(\.isValid) else { throw AIAccountBalanceError.noQuota }
                return windows
            }
            data = summary
        case .zcode:
            let base = credential.region == "bigmodel" ? "https://open.bigmodel.cn" : "https://api.z.ai"
            data = try await request(base + "/api/monitor/usage/quota/limit", credential: credential)
        case .zed:
            if credential.isWebsiteCookie {
                data = try await request("https://cloud.zed.dev/frontend/billing/usage", credential: credential,
                    cookie: true, headers: ["Origin": "https://dashboard.zed.dev", "Referer": "https://dashboard.zed.dev/"])
                break
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
            data = try await request("https://opencode.ai/zen/go/v1/usage", credential: credential)
        default: throw AIAccountBalanceError.noQuota
        }
        return try AIAccountBalanceParser.parse(data, provider: provider, now: now)
    }

    /// Sends credentials only to an internal fixed endpoint with a 15-second timeout and a 1 MiB streaming limit.
    /// The session blocks redirects, and an unexpected response URL or status invalidates the entire reading.
    private func request(_ endpoint: String, credential: AIAccountBalanceCredential, cookie: Bool = false,
                         headers: [String: String] = [:], body: [String: Any]? = nil, rawBody: Data? = nil) async throws -> Data {
        try Task.checkCancellation()
        var request = URLRequest(url: URL(string: endpoint)!)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(cookie ? credential.token : "Bearer " + credential.token, forHTTPHeaderField: cookie ? "Cookie" : "Authorization")
        for (key, value) in credential.headers.merging(headers, uniquingKeysWith: { _, new in new }) {
            request.setValue(value, forHTTPHeaderField: key)
        }
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } else if let rawBody { request.httpMethod = "POST"; request.httpBody = rawBody }
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse, response.url == request.url else { throw AIAccountBalanceError.invalidResponse }
        guard response.statusCode == 200 else { throw AIAccountBalanceError.httpStatus(response.statusCode) }
        guard response.expectedContentLength <= 1_024 * 1_024 else { throw AIAccountBalanceError.invalidResponse }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < 1_024 * 1_024 else { throw AIAccountBalanceError.invalidResponse }
            data.append(byte)
        }
        return data
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
