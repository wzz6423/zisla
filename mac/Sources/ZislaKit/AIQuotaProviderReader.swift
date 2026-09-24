// Adapted from upstream provider request protocols; modified for independent Zisla configuration.
// See Resources/ThirdPartyLicenses/AIQuota-LICENSE.txt.
import Foundation
import ZislaCore

public struct AIQuotaProviderReader: AIQuotaReading {
    public var providerID: String { configuration.provider.rawValue }
    public var id: String { configuration.id }
    let configuration: AIQuotaConfiguration
    private let credentials: any AIQuotaCredentialStoring
    private let http: any AIQuotaHTTPClient
    private let clock: @Sendable () -> Date
    private let localLogin: AIQuotaLocalLogin
    private let processEnvironment: [String: String]?

    public init(configuration: AIQuotaConfiguration, credentials: any AIQuotaCredentialStoring,
                http: any AIQuotaHTTPClient = AIQuotaURLSessionClient(), processEnvironment: [String: String]? = nil) {
        self.init(configuration: configuration, credentials: credentials, http: http,
                  clock: { Date() }, localLogin: AIQuotaLocalLogin(), processEnvironment: processEnvironment)
    }

    init(configuration: AIQuotaConfiguration, credentials: any AIQuotaCredentialStoring,
         http: any AIQuotaHTTPClient, clock: @escaping @Sendable () -> Date, localLogin: AIQuotaLocalLogin,
         processEnvironment: [String: String]? = nil) {
        self.configuration = configuration
        self.credentials = credentials
        self.http = http
        self.clock = clock
        self.localLogin = localLogin
        self.processEnvironment = processEnvironment
    }

    public func read() async throws -> [AIQuotaAccount] {
        guard configuration.isEnabled else { return [] }
        try AIQuotaRequestBuilder.validate(configuration)
        try Task.checkCancellation()
        var resolved = configuration
        if resolved.provider == .devin {
            resolved.organization = try AIQuotaRequestBuilder.devinOrganization(resolved.organization)
        }
        let replies: [String: Data]
        if configuration.provider == .kiro {
            let executable = configuration.localPath.isEmpty ? nil
                : URL(fileURLWithPath: (configuration.localPath as NSString).expandingTildeInPath)
            do { replies = ["main": try await AIQuotaKiroClient(executable: executable, environment: processEnvironment).usage()] }
            catch is CancellationError { throw CancellationError() }
            catch let failure as AIQuotaKiroClient.Failure {
                if Task.isCancelled { throw CancellationError() }
                switch failure {
                case .executableNotFound, .startFailed: throw AIQuotaError.clientUnavailable
                case .timedOut: throw AIQuotaError.network
                case .closed: throw AIQuotaError.invalidResponse
                case .server: throw AIQuotaError.server
                }
            }
            catch {
                if Task.isCancelled { throw CancellationError() }
                throw AIQuotaError.clientUnavailable
            }
        } else if configuration.provider == .antigravity {
            replies = ["main": try await AIQuotaAntigravityClient(http: http, clock: clock).read()]
        } else {
            let credential: AIQuotaCredential
            if configuration.source == .localLogin {
                let local = try localLogin.read(configuration, now: clock())
                credential = local.0
                if resolved.organization.isEmpty { resolved.organization = local.1 ?? "" }
            } else {
                guard let saved = try credentials.read(id: configuration.id) else { throw AIQuotaError.credentialMissing }
                guard saved.scope == AIQuotaRequestBuilder.credentialScope(configuration) else { throw AIQuotaError.credentialMissing }
                credential = saved
            }
            replies = try await fetch(configuration: resolved, credential: credential)
        }
        try Task.checkCancellation()
        let now = clock()
        let parsed = try AIQuotaResponseParser.parse(configuration.provider, replies: replies, now: now)
        return [AIQuotaAccount(id: configuration.id, providerID: providerID, label: configuration.label,
                               balanceText: parsed.balance, windows: parsed.windows, observedAt: now)]
    }

    private func get(_ address: String, configuration: AIQuotaConfiguration, credential: AIQuotaCredential?, post: Bool = false) async throws -> Data {
        guard let url = URL(string: address) else { throw AIQuotaError.invalidAddress }
        let request = try AIQuotaRequestBuilder.request(url, credential: credential,
                provider: configuration.provider, configuration: configuration, post: post)
        return try await http.data(for: request, trustLoopback: false)
    }

    private func fetch(configuration: AIQuotaConfiguration, credential: AIQuotaCredential) async throws -> [String: Data] {
        let provider = configuration.provider
        let credential = try AIQuotaRequestBuilder.validatedCredential(credential, provider: provider)
        let endpoint: String
        switch provider {
        case .claudeCode: endpoint = "https://api.anthropic.com/api/oauth/usage"
        case .codex: endpoint = "https://chatgpt.com/backend-api/wham/usage"
        case .cursor: endpoint = "https://cursor.com/api/usage-summary"
        case .openCodeGo: endpoint = "https://opencode.ai/zen/go/v1/usage"
        case .kimiCode: endpoint = "https://api.kimi.com/coding/v1/usages"
        case .ollamaCloud: endpoint = "https://ollama.com/settings"
        case .zai: endpoint = "https://api.z.ai/api/monitor/usage/quota/limit"
        case .glmCoding: endpoint = "https://open.bigmodel.cn/api/monitor/usage/quota/limit"
        case .minimax, .minimaxCN:
            let host = provider == .minimax ? "https://api.minimax.io" : "https://api.minimaxi.com"
            do { return ["main": try await get(host + "/v1/token_plan/remains", configuration: configuration, credential: credential)] }
            catch AIQuotaError.noQuota {
                return ["main": try await get(host + "/v1/api/openplatform/coding_plan/remains", configuration: configuration, credential: credential)]
            }
        case .copilot: endpoint = "https://api.github.com/copilot_internal/user"
        case .grok: endpoint = "https://cli-chat-proxy.grok.com/v1/billing?format=credits"
        case .grokBot: endpoint = "https://cursor.com/api/dashboard/get-sand-usage-status"
        case .deepSeek: endpoint = "https://api.deepseek.com/user/balance"
        case .v2ex: endpoint = "https://edge.v2ex.com/api/v2/chat/quota"
        case .qoder:
            endpoint = "https://\(configuration.chinaSite ? "qoder.com.cn" : "qoder.com")/api/v2/me/usages/big_model_credits"
        case .devin:
            let organization = configuration.organization
            var paths = [organization]
            if organization.hasPrefix("organizations/") { paths.insert(String(organization.dropFirst(14)), at: 0) }
            if organization.hasPrefix("org/") { paths.append(String(organization.dropFirst(4))) }
            for path in paths {
                do { return ["main": try await get("https://app.devin.ai/api/\(path)/billing/quota/usage", configuration: configuration, credential: credential)] }
                catch AIQuotaError.noQuota { continue }
            }
            throw AIQuotaError.noQuota
        case .sub2api:
            endpoint = try AIQuotaRequestBuilder.gateway(configuration.baseURL, path: "/v1/usage").absoluteString
        case .newAPI:
            var replies: [String: Data] = [:]
            for (name, path) in [("main", "/v1/dashboard/billing/subscription"), ("usage", "/v1/dashboard/billing/usage"), ("status", "/api/status")] {
                let url = try AIQuotaRequestBuilder.gateway(configuration.baseURL, path: path)
                replies[name] = try await get(url.absoluteString, configuration: configuration, credential: name == "status" ? nil : credential)
            }
            return replies
        case .commandCode:
            let whoami = try await get("https://api.commandcode.ai/alpha/whoami?limits=1", configuration: configuration, credential: credential)
            let root = try AIQuotaResponseParser.object(whoami)
            var components = URLComponents(string: "https://api.commandcode.ai/alpha/billing/credits")!
            if let org = (root["org"] as? [String: Any])?["id"] as? String {
                components.queryItems = [URLQueryItem(name: "orgId", value: org)]
            }
            guard let url = components.url else { throw AIQuotaError.invalidAddress }
            return ["whoami": whoami, "main": try await get(url.absoluteString, configuration: configuration, credential: credential)]
        case .xiaomiMiMo:
            var replies: [String: Data] = [:]
            var failures: [AIQuotaError] = []
            for (name, path) in [("main", "tokenPlan/usage"), ("detail", "tokenPlan/detail"), ("balance", "balance")] {
                do { replies[name] = try await get("https://platform.xiaomimimo.com/api/v1/" + path, configuration: configuration, credential: credential) }
                catch let error as AIQuotaError {
                    if error == .credentialRejected { throw error }
                    failures.append(error)
                }
            }
            guard !replies.isEmpty else { throw failures.first ?? AIQuotaError.network }
            return replies
        case .volcengine:
            var replies: [String: Data] = [:]
            var failures: [AIQuotaError] = []
            for (name, action) in [("coding", "GetCodingPlanUsage"), ("agent", "GetAFPUsage")] {
                let url = URL(string: "https://open.volcengineapi.com/?Action=\(action)&Version=2024-01-01")!
                var request = URLRequest(url: url)
                request.timeoutInterval = 15
                request.allHTTPHeaderFields = AIQuotaVolcengineSigner.headers(method: "GET", url: url, body: Data(),
                    contentType: "application/x-www-form-urlencoded; charset=utf-8",
                    credentials: .init(accessKeyID: credential.token, secretAccessKey: credential.secret), date: clock())
                do { replies[name] = try await http.data(for: request, trustLoopback: false) }
                catch let error as AIQuotaError { failures.append(error) }
            }
            guard !replies.isEmpty else { throw failures.first(where: { $0 == .credentialRejected || $0 == .rateLimited }) ?? failures.first ?? AIQuotaError.network }
            return replies
        case .kiro, .antigravity: throw AIQuotaError.invalidConfiguration
        }
        return ["main": try await get(endpoint, configuration: configuration, credential: credential, post: provider == .grokBot)]
    }
}
