import Foundation
import Testing

@testable import ZislaCore
@testable import ZislaKit

struct AIQuotaResponseParserTests {
    private let now = AIQuotaFixtures.now

    @Test(arguments: AIQuotaProvider.allCases)
    func allTwentyFourServicesProduceOnlyEvidencedQuota(_ provider: AIQuotaProvider) throws {
        let value = try AIQuotaResponseParser.parse(provider, replies: AIQuotaFixtures.replies(provider), now: now)
        let expected: [AIQuotaProvider: (Int, Double?)] = [
            .claudeCode: (2, 80), .codex: (2, 75), .kiro: (2, 93.8275), .antigravity: (4, 99.49068),
            .cursor: (2, 75), .openCodeGo: (3, 80), .kimiCode: (2, 75), .ollamaCloud: (2, 75),
            .zai: (2, 100), .glmCoding: (2, 100), .minimax: (2, 60), .minimaxCN: (2, 60),
            .copilot: (1, 75), .grok: (1, 75), .grokBot: (1, 75), .volcengine: (4, 58.5),
            .commandCode: (5, 75), .deepSeek: (0, nil), .devin: (2, 98), .xiaomiMiMo: (1, 62.5),
            .sub2api: (3, 9), .newAPI: (0, nil), .v2ex: (2, 75), .qoder: (1, 75),
        ]
        let contract = try #require(expected[provider])
        #expect(value.windows.count == contract.0)
        if let first = contract.1 {
            #expect(abs(try #require(value.windows.first?.remainingPercent) - first) < 0.000_01)
        }
        #expect(value.windows.allSatisfy { ($0.remainingPercent.map { $0.isFinite && (0...100).contains($0) }) == true })
        #expect(Set(value.windows.map(\.id)).count == value.windows.count)
        if [.deepSeek, .newAPI, .cursor, .commandCode, .devin, .xiaomiMiMo].contains(provider) {
            #expect(value.balance != nil)
        }
        if provider == .codex { #expect(value.windows.first?.label == "每日") }
    }

    @Test(arguments: AIQuotaProvider.allCases)
    func malformedRepliesDoNotProduceSuccessfulZeroUsage(_ provider: AIQuotaProvider) {
        #expect(throws: AIQuotaError.self) {
            try AIQuotaResponseParser.parse(provider, replies: ["main": Data("{\"broken\":".utf8)], now: now)
        }
    }

    @Test
    func monetaryBalancesNeverInventAQuotaDenominatorOrMergeCurrencies() throws {
        let wallet = try AIQuotaResponseParser.parse(.sub2api, replies: ["main": AIQuotaFixtures.reference["sub2api-wallet"]!], now: now)
        #expect(wallet.windows.isEmpty)
        #expect(wallet.balance?.hasPrefix("USD ") == true)
        let quota = try AIQuotaResponseParser.parse(.sub2api, replies: AIQuotaFixtures.replies(.sub2api), now: now)
        #expect(quota.balance == nil)
        let subscription = try AIQuotaResponseParser.parse(.sub2api, replies: ["main": AIQuotaFixtures.reference["sub2api-subscription"]!], now: now)
        #expect(subscription.windows.count == 2)
        #expect(subscription.balance == nil)
        let currencies = try AIQuotaResponseParser.parse(.deepSeek, replies: ["main": AIQuotaFixtures.reference["deepseek-two-currencies"]!], now: now)
        #expect(currencies.windows.isEmpty)
        #expect(currencies.balance?.contains("USD ") == true)
        #expect(currencies.balance?.contains("CNY ") == true)
        let rootRemaining = try AIQuotaResponseParser.parse(.sub2api, replies: ["main": Data(#"{"remaining":7.5}"#.utf8)], now: now)
        #expect(rootRemaining.balance?.hasPrefix("USD ") == true)
        #expect(throws: AIQuotaError.noQuota) {
            try AIQuotaResponseParser.parse(.sub2api, replies: ["main": Data(#"{"remaining":7.5,"unit":"points"}"#.utf8)], now: now)
        }
    }

    @Test(arguments: ["newapi-status-usd", "newapi-status-cny", "newapi-status-legacy"])
    func newAPISubtractsUsageInCentsAndUsesReportedCurrency(_ status: String) throws {
        var replies = AIQuotaFixtures.replies(.newAPI)
        replies["status"] = AIQuotaFixtures.reference[status]
        let value = try AIQuotaResponseParser.parse(.newAPI, replies: replies, now: now)
        let prefix = status == "newapi-status-cny" ? "CNY " : "USD "
        #expect(value.balance == prefix + 13.155.formatted(.number.precision(.fractionLength(2)).locale(AppLocalization.currentLanguage.locale)))
        #expect(value.windows.isEmpty)
    }

    @Test
    func newAPITokenUnitAndUnlimitedSentinelAreNotMoney() throws {
        var replies = AIQuotaFixtures.replies(.newAPI)
        replies["status"] = AIQuotaFixtures.reference["newapi-status-tokens"]
        #expect(throws: AIQuotaError.noQuota) { try AIQuotaResponseParser.parse(.newAPI, replies: replies, now: now) }
        replies = AIQuotaFixtures.replies(.newAPI)
        replies["main"] = AIQuotaFixtures.reference["newapi-unlimited"]
        #expect(throws: AIQuotaError.noQuota) { try AIQuotaResponseParser.parse(.newAPI, replies: replies, now: now) }
    }

    @Test
    func invalidNumbersAndOverflowCannotBecomeAHealthyBalance() {
        for input in [#"{"five_hour":{"utilization":true}}"#, #"{"five_hour":{"utilization":"NaN"}}"#, #"{"five_hour":{"utilization":-1}}"#] {
            #expect(throws: AIQuotaError.noQuota) {
                try AIQuotaResponseParser.parse(.claudeCode, replies: ["main": Data(input.utf8)], now: now)
            }
        }
        #expect(AIQuotaResponseParser.number(false) == nil)
        #expect(AIQuotaResponseParser.number("Infinity") == nil)
        #expect(AIQuotaResponseParser.percent(1, limit: 0) == nil)
        #expect(AIQuotaResponseParser.percent(-1, limit: 10) == nil)
        #expect(AIQuotaResponseParser.percent(12, limit: 10) == 0)
        #expect(throws: AIQuotaError.noQuota) {
            try AIQuotaResponseParser.parse(.commandCode, replies: ["main": Data(#"{"credits":{"monthlyCredits":1e308,"purchasedCredits":1e308}}"#.utf8)], now: now)
        }
    }

    @Test
    func expiredWindowsAreRemovedEvenWhenResponseJustArrived() throws {
        let input = Data(#"{"five_hour":{"utilization":90,"resets_at":"2020-01-01T00:00:00Z"},"seven_day":{"utilization":10,"resets_at":"2030-01-01T00:00:00Z"}}"#.utf8)
        let value = try AIQuotaResponseParser.parse(.claudeCode, replies: ["main": input], now: now)
        #expect(value.windows.map(\.id) == ["seven_day"])
        #expect(throws: AIQuotaError.noQuota) {
            try AIQuotaResponseParser.parse(.antigravity, replies: AIQuotaFixtures.replies(.antigravity), now: Date(timeIntervalSince1970: 2_000_000_000))
        }
    }

    @Test
    func unknownWindowsAndAmbiguousDuplicatePoolsAreExcluded() throws {
        let antigravity = Data(#"{"response":{"groups":[{"buckets":[{"bucketId":"unknown","window":"fortnightly","remainingFraction":0.8}]}]}}"#.utf8)
        #expect(throws: AIQuotaError.noQuota) { try AIQuotaResponseParser.parse(.antigravity, replies: ["main": antigravity], now: now) }
        let kimi = Data(#"{"limits":[{"window":{"duration":5,"timeUnit":"UNKNOWN"},"detail":{"limit":100,"used":20}}]}"#.utf8)
        #expect(throws: AIQuotaError.noQuota) { try AIQuotaResponseParser.parse(.kimiCode, replies: ["main": kimi], now: now) }
        let volcanic = try AIQuotaResponseParser.parse(.volcengine, replies: AIQuotaFixtures.replies(.volcengine), now: now)
        #expect(!volcanic.windows.contains { $0.id.contains("fortnightly") })
        let duplicate = Data(#"{"rate_limits":[{"window":"5h","used":1,"limit":100},{"window":"5h","used":90,"limit":100}]}"#.utf8)
        #expect(throws: AIQuotaError.noQuota) { try AIQuotaResponseParser.parse(.sub2api, replies: ["main": duplicate], now: now) }
    }

    @Test(arguments: [AIQuotaProvider.kimiCode, .glmCoding, .sub2api])
    func reorderingWindowsDoesNotMixThresholdBaselines(_ provider: AIQuotaProvider) throws {
        var root = try AIQuotaResponseParser.object(AIQuotaFixtures.replies(provider)["main"]!)
        if provider == .kimiCode {
            root["limits"] = [
                ["window": ["duration": 5, "timeUnit": "TIME_UNIT_HOUR"], "detail": ["used": 10, "limit": 100]],
                ["window": ["duration": 1, "timeUnit": "TIME_UNIT_DAY"], "detail": ["used": 70, "limit": 100]],
            ]
        } else if provider == .glmCoding {
            root["data"] = ["limits": [
                ["type": "CREDIT_LIMIT", "unit": 3, "number": 5, "currentValue": 10, "usage": 100],
                ["type": "CREDIT_LIMIT", "unit": 6, "number": 1, "currentValue": 70, "usage": 100],
            ]]
        }
        let first = try AIQuotaResponseParser.parse(provider, replies: ["main": AIQuotaFixtures.json(root)], now: now)
        if provider == .glmCoding {
            let data = root["data"] as! [String: Any]
            root["data"] = ["limits": Array((data["limits"] as! [[String: Any]]).reversed())]
        } else {
            let key = provider == .kimiCode ? "limits" : "rate_limits"
            root[key] = Array((root[key] as! [[String: Any]]).reversed())
        }
        let second = try AIQuotaResponseParser.parse(provider, replies: ["main": AIQuotaFixtures.json(root)], now: now)
        #expect(Dictionary(uniqueKeysWithValues: first.windows.map { ($0.id, $0.remainingPercent) }) == Dictionary(uniqueKeysWithValues: second.windows.map { ($0.id, $0.remainingPercent) }))
        func snapshot(_ windows: [AIQuotaWindow]) -> AIQuotaSnapshot {
            AIQuotaSnapshot(accounts: [.init(id: "same", providerID: provider.rawValue, label: "Test", windows: windows, observedAt: now)])
        }
        var tracker = AIQuotaThresholdTracker()
        #expect(tracker.consume(snapshot(first.windows), at: now).isEmpty)
        #expect(tracker.consume(snapshot(second.windows), at: now).isEmpty)
    }

    @Test
    func grokZeroDefaultRequiresACurrentPeriodAndGrokBotRequiresExplicitUsage() throws {
        let current = Data(#"{"config":{"currentPeriod":{"start":"2023-01-01T00:00:00Z","end":"2024-01-01T00:00:00Z"}}}"#.utf8)
        #expect(try AIQuotaResponseParser.parse(.grok, replies: ["main": current], now: now).windows.first?.remainingPercent == 100)
        #expect(throws: AIQuotaError.noQuota) { try AIQuotaResponseParser.parse(.grok, replies: ["main": current], now: Date(timeIntervalSince1970: 2_000_000_000)) }
        #expect(throws: AIQuotaError.noQuota) { try AIQuotaResponseParser.parse(.grokBot, replies: ["main": Data(#"{"hasNonZeroIncludedLimit":true}"#.utf8)], now: now) }
    }

    @Test(arguments: ["qoder-credits", "qoder-credits-snake", "qoder-credits-team"])
    func qoderSupportsPersonalTeamAndSnakeCaseResponses(_ fixture: String) throws {
        let value = try AIQuotaResponseParser.parse(.qoder, replies: ["main": AIQuotaFixtures.reference[fixture]!], now: now)
        #expect(!value.windows.isEmpty)
        #expect(value.windows.allSatisfy { $0.remainingPercent != nil })
    }

    @Test
    func htmlNeverTreatsScriptsLoginFormsOrExternalEntitiesAsUsage() throws {
        let good = String(decoding: AIQuotaFixtures.replies(.ollamaCloud)["main"]!, as: UTF8.self)
        let script = good.replacingOccurrences(of: "<body>", with: "<body><script>Session usage 99% used</script>")
        #expect(try AIQuotaResponseParser.parse(.ollamaCloud, replies: ["main": Data(script.utf8)], now: now).windows.first?.remainingPercent == 75)
        for page in ["<html><form action='/signin'></form></html>", "<!ENTITY x SYSTEM 'file:///etc/passwd'>" + good, "<html><span>Session usage</span><span>25% used</span></html>"] {
            #expect(throws: AIQuotaError.self) { try AIQuotaOllamaPage.parse(Data(page.utf8)) }
        }
    }

    @Test
    func responseByteAndWindowBudgetsAreEnforced() throws {
        #expect(throws: AIQuotaError.responseTooLarge) {
            try AIQuotaResponseParser.object(Data(repeating: 32, count: AIQuotaURLSessionClient.maximumResponseBytes + 1))
        }
        let groups: [[String: Any]] = (0...AIQuotaResponseParser.maximumWindows).map { index in
            ["kind": "weekly_scoped", "percent": 1, "scope": ["model": ["display_name": "model-\(index)"]]]
        }
        #expect(throws: AIQuotaError.responseTooLarge) {
            try AIQuotaResponseParser.parse(.claudeCode, replies: ["main": AIQuotaFixtures.json(["limits": groups])], now: now)
        }
    }

    @Test
    func deterministicNumericFuzzNeverEmitsNonFiniteOrOutOfRangePercentages() {
        var seed: UInt64 = 0xA11C0DE
        for _ in 0..<512 {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1
            let used = Double(Int64(bitPattern: seed)) / 1e13
            seed = seed &* 6_364_136_223_846_793_005 &+ 1
            let limit = Double(Int64(bitPattern: seed)) / 1e13
            if let percentage = AIQuotaResponseParser.percent(used, limit: limit) {
                #expect(used >= 0 && limit > 0)
                #expect(percentage.isFinite && (0...100).contains(percentage))
            } else {
                #expect(used < 0 || limit <= 0)
            }
        }
    }
}
