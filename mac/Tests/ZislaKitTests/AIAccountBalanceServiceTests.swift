import Foundation
import Testing
@testable import ZislaCore
@testable import ZislaKit

@Suite(.serialized)
struct AIAccountBalanceServiceTests {
    private let now = Date(timeIntervalSince1970: 1_910_000_000)

    @Test(arguments: [AIProvider?.none, .codex, .gpt])
    func sharedAliasesUseInstalledBrandWithoutChangingQuotaOrExplicitSelections(installedProvider: AIProvider?) async throws {
        BalanceURLProtocol.configure(["/backend-api/wham/usage": (0..<3).map { _ in
            .json(#"{"rate_limit":{"primary_window":{"used_percent":90,"limit_window_seconds":18000}}}"#)
        }])
        let service = makeService(openAIProvider: { installedProvider })
        let shared = try #require(try await service.accountBalances(for: [.codex, .gpt]).first)
        let expected: AIProvider = installedProvider == .gpt ? .gpt : .codex
        #expect(shared.displayProvider == expected)
        #expect(Set(shared.providers) == [.codex, .gpt], "Both aliases must remain selectable on the shared account")
        #expect(shared.providerTitle(language: .english) == (expected == .gpt ? "ChatGPT" : "Codex"))
        for provider in [AIProvider.codex, .gpt] {
            let selected = try #require(try await service.accountBalances(for: [provider]).first)
            #expect(selected.providers == [provider] && selected.displayProvider == provider)
            #expect(selected.id == shared.id && selected.windows == shared.windows)
        }
        #expect(BalanceURLProtocol.requests.count == 3, "Each selection must still query the shared account only once")
    }

    @Test func installedOpenAIBrandDoesNotRelabelOtherSharedAccounts() async throws {
        BalanceURLProtocol.configure(["/api/usage-summary": [.json(#"{"individualUsage":{"plan":{"used":900,"limit":1000}}}"#)]])
        let rows = try await makeService(openAIProvider: { .gpt }).accountBalances(for: [.cursor, .grokBot])
        #expect(rows.count == 1 && rows.first?.providers == [.cursor, .grokBot])
        #expect(rows.first?.providerTitle(language: .english) == "Cursor / Grok Bot")
        #expect(BalanceURLProtocol.requests.filter { $0.url?.path == "/api/usage-summary" }.count == 1)
    }

    #if DEBUG
        @Test(arguments: [Set<AIProvider>(), [.codex]])
        func explicitFixtureOverridesSelectionAndNeverReadsAccounts(providers: Set<AIProvider>) async throws {
            BalanceURLProtocol.configure([:])
            let environment = ["ZISLA_DEBUG_AI_ACCOUNT_BALANCE": "claude:10:70,gpt:0,cursor:20"]
            let service = makeService(credentials: { _, _, _ in
                Issue.record("An explicit fixture must never read account credentials")
                return nil
            }, debug: { AIAccountBalanceDebug.balances(environment: environment, now: now) })
            let rows = try await service.accountBalances(for: providers)
            #expect(rows.map(\.providers) == [[.claude], [.gpt], [.cursor]],
                    "The requested fixture must replace real monitor selections and preserve its explicit aliases")
            #expect(rows.map { $0.windows.map(\.remainingPercent) } == [[10, 70], [0], [20]])
            #expect(rows.allSatisfy { $0.isDebug && $0.updatedAt == now && $0.severity != nil })
            #expect(BalanceURLProtocol.requests.isEmpty)
        }

        @Test func environmentFixtureUsesTheDefaultServiceInitializer() async throws {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-balance-environment-\(UUID())")
            defer { try? FileManager.default.removeItem(at: root) }
            let service = AIAccountBalanceService(home: root,
                                                  environment: ["ZISLA_DEBUG_AI_ACCOUNT_BALANCE": "claude:10:70,gpt:0,cursor:20"], now: { now })
            let rows = try await service.accountBalances(for: [.codex])
            #expect(rows.map(\.providers) == [[.claude], [.gpt], [.cursor]])
            #expect(rows.map { $0.windows.map(\.remainingPercent) } == [[10, 70], [0], [20]])
            #expect(rows.allSatisfy { $0.isDebug })
            #expect(!FileManager.default.fileExists(atPath: root.path), "Debug fixtures must not create account files")
        }

        @Test func emptyOrRemovedFixtureRestoresTheSelectedAccountPath() async throws {
            BalanceURLProtocol.configure([:])
            for environment in [[:], ["ZISLA_DEBUG_AI_ACCOUNT_BALANCE": ""]] {
                let service = makeService(credentials: { _, _, _ in nil },
                                          debug: { AIAccountBalanceDebug.balances(environment: environment, now: now) })
                let rows = try await service.accountBalances(for: [.codex])
                #expect(rows.map(\.providers) == [[.codex]] && rows.map(\.status) == [.notSignedIn])
                #expect(rows.allSatisfy { !$0.isDebug }, "Clearing a fixture must restore the regular selected-account path")
            }
            #expect(BalanceURLProtocol.requests.isEmpty)
        }

        @Test(arguments: [" ", "claude:nan", "codex:101", "claude:10,claude:20", "cursor:20,"])
        func malformedFixtureCannotFallBackToCredentialedSources(raw: String) async throws {
            BalanceURLProtocol.configure([:])
            let service = makeService(credentials: { _, _, _ in
                Issue.record("A malformed explicit fixture must not fall back to an account")
                return nil
            }, debug: { AIAccountBalanceDebug.balances(environment: ["ZISLA_DEBUG_AI_ACCOUNT_BALANCE": raw], now: now) })
            #expect(try await service.accountBalances(for: [.claude, .codex, .cursor]).isEmpty)
            #expect(BalanceURLProtocol.requests.isEmpty)
        }

        @Test func seededFixtureAliasesKeepExactPercentagesAndRejectTruncation() throws {
            var seed: UInt64 = 0x283_2026
            let aliases: [AIProvider] = [.codex, .gpt, .cursor, .grokBot]
            for index in 0..<128 {
                seed = seed &* 6_364_136_223_846_793_005 &+ 1
                let percent = Double(seed % 101), provider = aliases[index % aliases.count]
                let raw = "\(provider.rawValue):\(percent):\(100 - percent)"
                let rows = try #require(AIAccountBalanceDebug.balances(environment: ["ZISLA_DEBUG_AI_ACCOUNT_BALANCE": raw], now: now))
                #expect(rows.map(\.providers) == [[provider]], "Seed 0x2832026 sample \(index) must preserve its selected alias")
                #expect(rows.first?.windows.map(\.remainingPercent) == [percent, 100 - percent])
                #expect(rows.allSatisfy { $0.isDebug && $0.windows.allSatisfy { $0.isValid } })
                #expect(AIAccountBalanceDebug.balances(environment: ["ZISLA_DEBUG_AI_ACCOUNT_BALANCE": raw + ","], now: now) == [],
                        "Seed 0x2832026 sample \(index) must reject an incomplete fixture without live fallback")
            }
        }
    #endif

    /// Recorded requests prove shared-account deduplication, selected alias output, and secret-free public rows.
    @Test func sharedAliasesFetchOnceAndPublishOnlySelectedNamesWithoutSecrets() async throws {
        BalanceURLProtocol.configure(["/backend-api/wham/usage": [.json(#"{"rate_limit":{"primary_window":{"used_percent":90,"limit_window_seconds":18000}}}"#)],
                                      "/api/usage-summary": [.json(#"{"individualUsage":{"plan":{"used":900,"limit":1000}}}"#)]])
        let service = makeService()
        let rows = try await service.accountBalances(for: [.gpt, .grokBot])
        #expect(rows.map(\.providers) == [[.gpt], [.grokBot]])
        #expect(rows.allSatisfy { $0.status == .available && $0.updatedAt == now })
        #expect(BalanceURLProtocol.requests.filter { $0.url?.path == "/backend-api/wham/usage" }.count == 1)
        #expect(BalanceURLProtocol.requests.filter { $0.url?.path == "/api/usage-summary" }.count == 1)
        #expect(BalanceURLProtocol.requests.first { $0.url?.host == "chatgpt.com" }?.value(forHTTPHeaderField: "ChatGPT-Account-Id") == "fixture-account")
        #expect(!String(describing: rows).contains("fixture-secret"))
        let both = try await service.accountBalances(for: [.codex, .gpt])
        #expect(both.count == 1 && both[0].providers == [.codex, .gpt])
        #expect(BalanceURLProtocol.requests.filter { $0.url?.path == "/backend-api/wham/usage" }.count == 2)
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
            for raw in ["claude:0:70,gpt:10", "claude:nan", "codex:101", "claude:10,claude:20", "codex:10,gpt:20"] {
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
        #expect(try await service.accountBalances(for: [.coder], qoderRegions: [.china]).first?.status == .available)
        #expect(try await service.accountBalances(for: [.coder], qoderRegions: [.global]).first?.status == .available)
        #expect(BalanceURLProtocol.requests.filter { $0.url?.path == "/api/v2/me/usages/big_model_credits" }.map { $0.url?.host } == ["qoder.com.cn", "qoder.com"])
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

    @Test func bothQoderRegionsQueryIndependentHostsAndKeepStableDistinctResults() async throws {
        let (events, continuation) = AsyncStream<Int>.makeStream()
        let global = #"{"data":{"totalQuota":{"quotaSummary":{"limitValue":100,"usedValue":90}}}}"#
        let china = #"{"data":{"totalQuota":{"quotaSummary":{"limitValue":100,"usedValue":30}}}}"#
        let path = "/api/v2/me/usages/big_model_credits"
        BalanceURLProtocol.configure(["https://qoder.com" + path: [.json(global)],
                                      "https://qoder.com.cn" + path: [.json(china)]], held: true, event: { continuation.yield($0) })
        defer { BalanceURLProtocol.release(); continuation.finish() }
        let service = makeService(credentials: { provider, _, region in
            #expect(provider == .coder)
            var credential = AIAccountBalanceCredential(token: "session=fixture-" + region.rawValue,
                                                        region: region == .china ? "cn" : "global")
            credential.isWebsiteCookie = true
            return credential
        })
        let task = Task {
            defer { continuation.yield(-1) }
            return try await service.accountBalances(for: [.coder], qoderRegions: [.global, .china])
        }
        var iterator = events.makeAsyncIterator()
        for _ in 0..<2 {
            guard let event = await iterator.next(), event > 0 else { break }
        }
        #expect(BalanceURLProtocol.requests.count == 2, "Both Qoder region requests must start independently")
        #expect(Set(BalanceURLProtocol.requests.compactMap { $0.url?.host }) == ["qoder.com", "qoder.com.cn"])
        for request in BalanceURLProtocol.requests {
            let region = request.url?.host == "qoder.com.cn" ? "china" : "global"
            #expect(request.value(forHTTPHeaderField: "Cookie") == "session=fixture-" + region)
        }
        BalanceURLProtocol.release()
        let rows = try await task.value
        #expect(rows.map(\.qoderRegion) == [.global, .china], "Completion order must not change the region ordering")
        #expect(rows.map { $0.windows.first?.remainingPercent } == [10, 70])
        #expect(rows.allSatisfy { $0.status == .available && $0.updatedAt == now })
        #expect(Set(rows.map(\.id)).count == 2 && Set(rows.map(\.noticeID)).count == 2)
        #expect(rows.map { $0.providerTitle(language: .english) } == ["Qoder · Global", "Qoder · China"])
        #expect(!String(describing: rows).contains("session=fixture-"))
    }

    @Test func qoderRegionFailureAndRecoveryDoNotReplaceTheOtherRegion() async throws {
        let path = "/api/v2/me/usages/big_model_credits"
        let quota = #"{"data":{"totalQuota":{"quotaSummary":{"limitValue":100,"usedValue":90}}}}"#
        BalanceURLProtocol.configure(["https://qoder.com" + path: [.init(status: 401)],
                                      "https://qoder.com.cn" + path: [.json(quota)]])
        let service = makeService(credentials: { _, _, region in
            AIAccountBalanceCredential(token: "session=fixture-secret", region: region == .china ? "cn" : "global")
        })
        let failed = try await service.accountBalances(for: [.coder], qoderRegions: [.global, .china])
        #expect(failed.map(\.qoderRegion) == [.global, .china])
        #expect(failed.map(\.status) == [.credentialsExpired, .available])
        #expect(failed[0].windows.isEmpty && failed[1].windows.first?.remainingPercent == 10)
        BalanceURLProtocol.configure(["https://qoder.com" + path: [.json(quota)],
                                      "https://qoder.com.cn" + path: [.json(quota)]])
        let recovered = try await service.accountBalances(for: [.coder], qoderRegions: [.global, .china])
        #expect(recovered.map(\.id) == failed.map(\.id))
        #expect(recovered.allSatisfy { $0.status == .available })
    }

    @Test func emptyQoderRegionsReadNoQoderCredentialsAndLeaveOtherProvidersSelected() async throws {
        BalanceURLProtocol.configure([:])
        let service = makeService(credentials: { provider, _, region in
            #expect(provider != .coder, "No Qoder region selection must prevent every Qoder credential read")
            #expect(region == .global, "Qoder region choices must not route TRAE or Zed credentials")
            return nil
        })
        #expect(try await service.accountBalances(for: [.coder], qoderRegions: []).isEmpty)
        for regions in [Set<AIAccountBalanceQoderRegion>(), [.china], [.global, .china]] {
            let rows = try await service.accountBalances(for: [.trae, .zed], qoderRegions: regions)
            #expect(Set(rows.flatMap(\.providers)) == [.trae, .zed])
            #expect(rows.allSatisfy { $0.qoderRegion == nil })
        }
        let rows = try await service.accountBalances(for: [.coder, .trae, .zed], qoderRegions: [])
        #expect(Set(rows.flatMap(\.providers)) == [.trae, .zed])
        #expect(BalanceURLProtocol.requests.isEmpty)
    }

    @Test func missingQoderCredentialsKeepSeparateRegionPlaceholders() async throws {
        BalanceURLProtocol.configure([:])
        let rows = try await makeService(credentials: { _, _, _ in nil })
            .accountBalances(for: [.coder], qoderRegions: [.global, .china])
        #expect(rows.map(\.id) == ["coder:global", "coder:china"])
        #expect(rows.map(\.qoderRegion) == [.global, .china])
        #expect(rows.allSatisfy { $0.status == .additionalCredentialsRequired && $0.windows.isEmpty })
        #expect(BalanceURLProtocol.requests.isEmpty)
    }

    /// Unified Cursor uses current dashboard/Connect endpoints; WorkBuddy's version fallback must not retry authentication failure.
    @Test func cursorUnifiedRequestsUseCurrentWindowsAndWorkBuddyFallbackRequires404() async throws {
        BalanceURLProtocol.configure([
            "/api/usage-summary": [.json(#"{"membershipType":"plus","individualUsage":{"plan":{"used":0,"limit":1000}}}"#)],
            "/api/dashboard/get-plan-info": [.json(#"{"isMerged":true,"planInfo":{"includedUsagePeriod":"INCLUDED_USAGE_PERIOD_WEEKLY","includedUsageResetsAt":"1910500000000"}}"#)],
            "/api/dashboard/get-sand-usage-status": [.json(#"{"usagePercent":90,"isUnified":true,"hasNonZeroIncludedLimit":true}"#)],
            "/aiserver.v1.DashboardService/GetCurrentPeriodUsage": [.json(#"{"planUsage":{"totalPercentUsed":80}}"#)],
            "/api/dashboard/get-user-prepaid-billing": [.json(#"{"availableCents":"1500"}"#)],
            "/billing/meter/get-user-resource": [.init(status: 404)],
            "/v2/billing/meter/get-user-resource": [.json(#"{"data":{"Accounts":[{"Status":0,"CycleCapacitySizePrecise":100,"CycleCapacityRemainPrecise":20}]}}"#)],
        ])
        let service = makeService(credentials: { provider, _, _ in
            if provider == .cursor {
                return AIAccountBalanceCredential(token: "WorkosCursorSessionToken=user_1%3A%3Aaaa.bbb.ccc", accountID: "user_1")
            }
            return AIAccountBalanceCredential(token: "fixture-secret", accountID: "fixture-account")
        })
        let rows = try await service.accountBalances(for: [.cursor, .workbuddyAI])
        #expect(rows.allSatisfy { $0.status == .available })
        let cursor = try #require(rows.first { $0.providers == [.cursor] })
        #expect(cursor.windows.map(\.id) == ["included", "prepaid"])
        #expect(cursor.windows[0].remainingPercent == 20 && cursor.windows[1].remaining == 15)
        let periodReq = try #require(BalanceURLProtocol.requests.first { $0.url?.host == "api2.cursor.sh" })
        #expect(periodReq.value(forHTTPHeaderField: "Authorization") == "Bearer aaa.bbb.ccc")
        #expect(periodReq.value(forHTTPHeaderField: "Connect-Protocol-Version") == "1")
        BalanceURLProtocol.configure(["/billing/meter/get-user-resource": [.init(status: 401)]])
        #expect(try await makeService().accountBalances(for: [.workbuddyAI]).first?.status == .credentialsExpired)
        #expect(BalanceURLProtocol.requests.count == 1)
    }

    @Test func antigravityAndGeminiDesktopFallbackRespectAccountIsolation() async throws {
        BalanceURLProtocol.configure([:])
        let snapshot = AIAccountAntigravitySnapshot(
            windows: [
                .init(id: "additional:gemini:five_hour", kind: .fiveHours, remainingPercent: 80, durationSeconds: 18_000, name: "Gemini"),
                .init(id: "additional:claude-gpt:weekly", kind: .weekly, remainingPercent: 60, durationSeconds: 604_800, name: "Claude/GPT"),
            ],
            accountID: "dev@example.test",
            accountName: "dev@example.test",
            sourceDetail: .app
        )
        let service = makeService(credentials: { _, _, _ in nil }, antigravity: { snapshot })
        let rows = try await service.accountBalances(for: [.antigravity, .gemini])
        let ag = try #require(rows.first { $0.providers == [.antigravity] })
        let gem = try #require(rows.first { $0.providers == [.gemini] })
        #expect(ag.status == .available && ag.windows.count == 2)
        #expect(gem.status == .available && gem.windows.map(\.name) == ["Gemini"])

        // Expired Gemini CLI credentials must fail without falling back to the local Antigravity daemon.
        let expiredCLI = makeService(credentials: { _, _, _ in throw AIAccountBalanceError.credentialsExpired }, antigravity: {
            Issue.record("Expired Gemini CLI credentials must not fall back to Antigravity probe")
            return snapshot
        })
        let expiredRow = try #require(try await expiredCLI.accountBalances(for: [.gemini]).first)
        #expect(expiredRow.status == .credentialsExpired && expiredRow.windows.isEmpty)

        // A snapshot without Gemini windows must not leak non-Gemini quota onto the Gemini row.
        let nonGeminiOnly = AIAccountAntigravitySnapshot(
            windows: [.init(id: "additional:claude-gpt:weekly", kind: .weekly, remainingPercent: 60, durationSeconds: 604_800, name: "Claude/GPT")],
            accountID: "dev@example.test",
            accountName: "dev@example.test",
            sourceDetail: .app
        )
        let missingGemini = try #require(try await makeService(credentials: { _, _, _ in nil }, antigravity: { nonGeminiOnly })
            .accountBalances(for: [.gemini]).first)
        #expect(missingGemini.status == .unavailable && missingGemini.windows.isEmpty)
    }

    @Test func qoderSharedCreditsZcodeStartPlanZedSubscriptionAndGeminiObjectProjectAreFetched() async throws {
        BalanceURLProtocol.configure([
            "/api/v2/me/usages/big_model_credits": [.json(#"{"data":{"totalQuota":{"quotaSummary":{"limitValue":100,"usedValue":25}}}}"#)],
            "/api/v1/me/organization-shared-usages/big_model_credits": [.json(#"{"data":{"sharedQuota":{"quotaSummary":{"limitValue":200,"usedValue":50}}}}"#)],
            "/api/v1/zcode-plan/billing/balance": [.json(#"{"code":200,"data":{"balances":[{"show_name":"Start Credits","total_units":100,"remaining_units":25,"period":"daily"}]}}"#)],
            "/frontend/billing/usage": [.json(#"{"current_usage":{"token_spend":{"limit_in_cents":2000,"spend_in_cents":500}}}"#)],
            "/frontend/billing/subscriptions/current": [.json(#"{"subscription":{"period":{"end_at":"2026-06-01T00:00:00Z"}}}"#)],
            "/v1internal:loadCodeAssist": [.json(#"{"response":{"cloudaicompanionProject":{"id":"proj-obj-9"}}}"#)],
            "/v1internal:retrieveUserQuota": [.json(#"{"buckets":[{"modelId":"gemini-2.5-pro","remainingFraction":0.7}]}"#)],
        ])
        let service = makeService(credentials: { provider, _, _ in
            switch provider {
            case .coder:
                var cred = AIAccountBalanceCredential(token: "session=qoder", region: "global")
                cred.isWebsiteCookie = true
                return cred
            case .zcode:
                return AIAccountBalanceCredential(token: "start-jwt", region: "start-plan", headers: ["X-Device-Mid": "mid-1"])
            case .zed:
                var cred = AIAccountBalanceCredential(token: "zed=cookie")
                cred.isWebsiteCookie = true
                return cred
            default:
                return AIAccountBalanceCredential(token: "fixture-secret", accountID: "fixture-account")
            }
        })
        let rows = try await service.accountBalances(for: [.coder, .zcode, .zed, .gemini])
        let qoder = try #require(rows.first { $0.providers == [.coder] })
        let zcode = try #require(rows.first { $0.providers == [.zcode] })
        let zed = try #require(rows.first { $0.providers == [.zed] })
        let gemini = try #require(rows.first { $0.providers == [.gemini] })
        #expect(qoder.windows.map(\.id) == ["credits", "team_credits"])
        #expect(zcode.windows.first?.remainingPercent == 25)
        #expect(zed.windows.first?.resetsAt != nil)
        #expect(gemini.windows.first?.remainingPercent == 70)
        let retrieveReq = try #require(BalanceURLProtocol.requests.first { $0.url?.path == "/v1internal:retrieveUserQuota" })
        let retrieveBody = try #require(retrieveReq.httpBody.flatMap { String(data: $0, encoding: .utf8) })
        #expect(retrieveBody.contains("proj-obj-9"))
        let zcodeReq = try #require(BalanceURLProtocol.requests.first { $0.url?.host == "zcode.z.ai" })
        #expect(zcodeReq.value(forHTTPHeaderField: "X-Device-Mid") == "mid-1")
    }

    @Test func grokHeadersAndStatusAndOpenCodeEntitlementAreClassifiedAccurately() async throws {
        BalanceURLProtocol.configure([
            "/grok_api_v2.GrokBuildBilling/GetGrokCreditsConfig": [
                .init(status: 200, data: Data(), headers: ["grpc-status": "16", "grpc-message": "unauthenticated"]),
            ],
            "/zen/go/v1/usage": [
                .init(status: 403, data: Data(#"{"error":{"type":"EntitlementError","message":"No Go subscription"}}"#.utf8)),
            ],
        ])
        let rows = try await makeService().accountBalances(for: [.grok, .opencode])
        let grok = try #require(rows.first { $0.providers == [.grok] })
        let opencode = try #require(rows.first { $0.providers == [.opencode] })
        #expect(grok.status == .credentialsExpired)
        #expect(opencode.status == .unavailable, "OpenCode EntitlementError must not be classified as expired credentials")
        let grokReq = try #require(BalanceURLProtocol.requests.first { $0.url?.host == "grok.com" })
        #expect(grokReq.value(forHTTPHeaderField: "X-XAI-Token-Auth") == "xai-grok-cli")
        #expect(grokReq.value(forHTTPHeaderField: "User-Agent") == "Grok Build")
        #expect(grokReq.value(forHTTPHeaderField: "Referer") == "https://grok.com/?_s=usage")
        #expect(grokReq.value(forHTTPHeaderField: "x-user-agent") == "connect-es/2.1.1")
        #expect(grokReq.value(forHTTPHeaderField: "Accept") == "*/*")
        #expect(grokReq.httpBody == Data([0, 0, 0, 0, 0]))
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
    muse: @escaping @Sendable () async throws -> Data? = { nil },
    antigravity: @escaping @Sendable () async throws -> AIAccountAntigravitySnapshot? = { nil },
    openAIProvider: @escaping @Sendable () -> AIProvider? = { nil }) -> AIAccountBalanceService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BalanceURLProtocol.self]
        return .init(credentials: credentials, configuration: configuration, now: { now }, museUsage: muse,
                     antigravityProbe: antigravity, debugBalances: debug, preferredOpenAIProvider: openAIProvider)
    }
}

private final class BalanceURLProtocol: URLProtocol, @unchecked Sendable {
    struct Response {
        var status = 200
        var data = Data("{}".utf8)
        var error: URLError.Code?
        var url: String?
        var contentLength: Int?
        var headers: [String: String] = [:]
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
            let responseKey = Self.responses[request.url!.absoluteString] == nil ? request.url!.path : request.url!.absoluteString
            var queue = Self.responses[responseKey] ?? []
            response = queue.isEmpty ? .init(error: .unsupportedURL) : queue.removeFirst()
            Self.responses[responseKey] = queue
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
        var headers = ["Content-Type": "application/json"].merging(response.headers, uniquingKeysWith: { _, new in new })
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
