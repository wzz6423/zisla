import Foundation
import Testing

@testable import ZislaCore
@testable import ZislaKit

struct AIQuotaRequestTests {
    @Test(arguments: AIQuotaProvider.allCases.filter { !$0.requiresLocalClient })
    func requestBoundaryUsesTheDocumentedEndpointAndCredentialType(_ provider: AIQuotaProvider) async throws {
        let configuration = AIQuotaFixtures.configuration(provider)
        let credential = AIQuotaFixtures.credential(configuration)
        let credentials = AIQuotaMemoryCredentials()
        try credentials.write(credential, id: configuration.id)
        let replies = AIQuotaFixtures.replies(provider)
        let order: [String]
        switch provider {
        case .volcengine: order = ["coding", "agent"]
        case .commandCode: order = ["whoami", "main"]
        case .xiaomiMiMo: order = ["main", "detail", "balance"]
        case .newAPI: order = ["main", "usage", "status"]
        default: order = ["main"]
        }
        let http = AIQuotaMockHTTP(order.map { .success(replies[$0]!) })
        let reader = AIQuotaProviderReader(configuration: configuration, credentials: credentials, http: http,
                                          clock: { AIQuotaFixtures.now }, localLogin: AIQuotaLocalLogin(home: URL(fileURLWithPath: "/nonexistent-aiquota-test")))
        let accounts = try await reader.read()
        #expect(accounts.count == 1)
        #expect(accounts.first?.id == configuration.id)
        #expect(accounts.first?.observedAt == AIQuotaFixtures.now)
        let requests = await http.requests
        #expect(requests.map { $0.url!.absoluteString } == endpoints(provider))
        #expect(await http.trustedLoopback.allSatisfy { !$0 })
        for (index, request) in requests.enumerated() {
            if provider == .volcengine {
                #expect(request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("HMAC-SHA256 Credential=") == true)
                #expect(request.value(forHTTPHeaderField: "X-Content-Sha256") == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
            } else if provider == .newAPI && index == 2 {
                #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            } else if provider.usesCookie {
                #expect(request.value(forHTTPHeaderField: "Cookie") == credential.token)
                #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            } else {
                #expect(request.value(forHTTPHeaderField: "Authorization") == "\(provider == .copilot ? "token" : "Bearer") fictional-token")
            }
            #expect(request.httpMethod == (provider == .grokBot ? "POST" : "GET"))
            if provider == .grokBot { #expect(request.httpBody == Data("{}".utf8)) }
        }
        if provider == .codex { #expect(requests[0].value(forHTTPHeaderField: "ChatGPT-Account-Id") == "acct-test") }
        if provider == .claudeCode { #expect(requests[0].value(forHTTPHeaderField: "anthropic-beta") == "oauth-2025-04-20") }
        if provider == .copilot { #expect(requests[0].value(forHTTPHeaderField: "X-Github-Api-Version") == "2025-04-01") }
        if provider == .ollamaCloud { #expect(requests[0].value(forHTTPHeaderField: "Accept") == "text/html") }
    }

    @Test
    func cookiesRetainRequiredLoginFieldsAndDropUnrelatedTrackingFields() throws {
        #expect(try AIQuotaRequestBuilder.cookie("Cookie: _ga=tracking; WorkosCursorSessionToken=test", provider: .cursor) == "WorkosCursorSessionToken=test")
        #expect(throws: AIQuotaError.credentialInvalid) { try AIQuotaRequestBuilder.cookie("_ga=tracking", provider: .cursor) }
        #expect(throws: AIQuotaError.credentialInvalid) { try AIQuotaRequestBuilder.cookie("api-platform_serviceToken=test", provider: .xiaomiMiMo) }
        #expect(try AIQuotaRequestBuilder.cookie("wos-session.0=one; wos-session.1=two; _ga=tracking", provider: .ollamaCloud) == "wos-session.0=one; wos-session.1=two")
        #expect(try AIQuotaRequestBuilder.cookie("_ga=tracking; qoder_session=test; _gid=tracking", provider: .qoder) == "qoder_session=test")
    }

    @Test
    func gatewayRetainsDeploymentPrefixAndRejectsCredentialLeaks() throws {
        #expect(try AIQuotaRequestBuilder.gateway("https://example.test/custom/v1/", path: "/api/status").absoluteString == "https://example.test/custom/api/status")
        for input in ["http://example.test", "https://user:pass@example.test", "https://example.test?token=leak", "https://example.test#leak", "https://example.test/%2e%2e/", "https://example.test/a%5cb"] {
            #expect(throws: AIQuotaError.invalidAddress) { try AIQuotaRequestBuilder.gateway(input, path: "/v1/usage") }
        }
    }

    @Test
    func devinAcceptsOrganizationIDsSlugsAndPageURLsWithoutPathInjection() throws {
        #expect(try AIQuotaRequestBuilder.devinOrganization("org_123") == "organizations/org_123")
        #expect(try AIQuotaRequestBuilder.devinOrganization("example") == "org/example")
        #expect(try AIQuotaRequestBuilder.devinOrganization("https://app.devin.ai/org/example/settings") == "org/example")
        for input in ["org/../billing", "org/evil?token=1", "https://unrelated.test/org/example"] {
            var configuration = AIQuotaFixtures.configuration(.devin)
            configuration.organization = input
            #expect(throws: AIQuotaError.self) { try AIQuotaRequestBuilder.validate(configuration) }
        }
    }

    @Test(arguments: [AIQuotaError.credentialRejected, .rateLimited, .network])
    func failuresPropagateWithoutExposingResponseOrCredential(_ failure: AIQuotaError) async throws {
        let configuration = AIQuotaFixtures.configuration(.codex)
        let credentials = AIQuotaMemoryCredentials()
        try credentials.write(AIQuotaFixtures.credential(configuration), id: configuration.id)
        let reader = AIQuotaProviderReader(configuration: configuration, credentials: credentials, http: AIQuotaMockHTTP([.failure(failure)]))
        await #expect(throws: failure) { try await reader.read() }
        #expect(!failure.localizedDescription.contains("fictional"))
    }

    @Test
    func minimaxFallsBackOnlyAfterANotFoundResponse() async throws {
        let configuration = AIQuotaFixtures.configuration(.minimax)
        let credentials = AIQuotaMemoryCredentials()
        try credentials.write(AIQuotaFixtures.credential(configuration), id: configuration.id)
        let fixture = AIQuotaFixtures.replies(.minimax)["main"]!
        let http = AIQuotaMockHTTP([.failure(.noQuota), .success(fixture)])
        let reader = AIQuotaProviderReader(configuration: configuration, credentials: credentials, http: http,
                                          clock: { AIQuotaFixtures.now }, localLogin: AIQuotaLocalLogin())
        #expect(try await reader.read().first?.windows.count == 2)
        #expect(await http.requests.last?.url?.path == "/v1/api/openplatform/coding_plan/remains")
        let rejected = AIQuotaMockHTTP([.failure(.credentialRejected), .success(fixture)])
        let denied = AIQuotaProviderReader(configuration: configuration, credentials: credentials, http: rejected)
        await #expect(throws: AIQuotaError.credentialRejected) { try await denied.read() }
        #expect(await rejected.requests.count == 1)
    }

    @Test
    func independentVolcenginePlansAndXiaomiBalanceSurvivePartialFailure() async throws {
        for provider in [AIQuotaProvider.volcengine, .xiaomiMiMo] {
            let configuration = AIQuotaFixtures.configuration(provider)
            let credentials = AIQuotaMemoryCredentials()
            try credentials.write(AIQuotaFixtures.credential(configuration), id: configuration.id)
            let responses: [Result<Data, AIQuotaError>] = provider == .volcengine
                ? [.failure(.server), .success(AIQuotaFixtures.reference["volcengine-agent-plan"]!)]
                : [.failure(.server), .failure(.network), .success(AIQuotaFixtures.reference["xiaomi-balance"]!)]
            let http = AIQuotaMockHTTP(responses)
            let reader = AIQuotaProviderReader(configuration: configuration, credentials: credentials, http: http,
                                              clock: { AIQuotaFixtures.now }, localLogin: AIQuotaLocalLogin())
            let account = try #require(try await reader.read().first)
            if provider == .volcengine { #expect(account.windows.count == 2) }
            else { #expect(account.balanceText?.hasPrefix("CNY ") == true) }
        }
    }

    @Test
    func signerMatchesIndependentReferenceAndCanonicalizesQueryOrder() throws {
        func sign(_ url: String) -> [String: String] {
            AIQuotaVolcengineSigner.headers(method: "GET", url: URL(string: url)!, body: Data(), contentType: "application/x-www-form-urlencoded; charset=utf-8",
                credentials: .init(accessKeyID: "AKLTTestAccessKeyId", secretAccessKey: "dGVzdC1zZWNyZXQtYWNjZXNzLWtleQ=="), date: Date(timeIntervalSince1970: 1_788_773_400))
        }
        let headers = sign("https://open.volcengineapi.com/?Action=GetCodingPlanUsage&Version=2024-01-01")
        #expect(headers["X-Date"] == "20260907T093000Z")
        #expect(headers["Authorization"] == "HMAC-SHA256 Credential=AKLTTestAccessKeyId/20260907/cn-beijing/ark/request, SignedHeaders=content-type;host;x-content-sha256;x-date, Signature=3bc6ebb4fd6da065cae0c05dbfc35285cdced26090d7c0aea87b2f2330cd031d")
        #expect(headers == sign("https://open.volcengineapi.com/?Version=2024-01-01&Action=GetCodingPlanUsage"))
    }

    private func endpoints(_ provider: AIQuotaProvider) -> [String] {
        switch provider {
        case .claudeCode: ["https://api.anthropic.com/api/oauth/usage"]
        case .codex: ["https://chatgpt.com/backend-api/wham/usage"]
        case .cursor: ["https://cursor.com/api/usage-summary"]
        case .openCodeGo: ["https://opencode.ai/zen/go/v1/usage"]
        case .kimiCode: ["https://api.kimi.com/coding/v1/usages"]
        case .ollamaCloud: ["https://ollama.com/settings"]
        case .zai: ["https://api.z.ai/api/monitor/usage/quota/limit"]
        case .glmCoding: ["https://open.bigmodel.cn/api/monitor/usage/quota/limit"]
        case .minimax: ["https://api.minimax.io/v1/token_plan/remains"]
        case .minimaxCN: ["https://api.minimaxi.com/v1/token_plan/remains"]
        case .copilot: ["https://api.github.com/copilot_internal/user"]
        case .grok: ["https://cli-chat-proxy.grok.com/v1/billing?format=credits"]
        case .grokBot: ["https://cursor.com/api/dashboard/get-sand-usage-status"]
        case .deepSeek: ["https://api.deepseek.com/user/balance"]
        case .v2ex: ["https://edge.v2ex.com/api/v2/chat/quota"]
        case .qoder: ["https://qoder.com/api/v2/me/usages/big_model_credits"]
        case .devin: ["https://app.devin.ai/api/org/example/billing/quota/usage"]
        case .sub2api: ["https://quota.example.test/prefix/v1/usage"]
        case .newAPI: ["https://quota.example.test/prefix/v1/dashboard/billing/subscription", "https://quota.example.test/prefix/v1/dashboard/billing/usage", "https://quota.example.test/prefix/api/status"]
        case .commandCode: ["https://api.commandcode.ai/alpha/whoami?limits=1", "https://api.commandcode.ai/alpha/billing/credits?orgId=org_2b91"]
        case .xiaomiMiMo: ["https://platform.xiaomimimo.com/api/v1/tokenPlan/usage", "https://platform.xiaomimimo.com/api/v1/tokenPlan/detail", "https://platform.xiaomimimo.com/api/v1/balance"]
        case .volcengine: ["https://open.volcengineapi.com/?Action=GetCodingPlanUsage&Version=2024-01-01", "https://open.volcengineapi.com/?Action=GetAFPUsage&Version=2024-01-01"]
        case .kiro, .antigravity: []
        }
    }
}
