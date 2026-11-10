import Foundation
import Testing
@testable import ZislaCore
@testable import ZislaKit

struct AIAccountBalanceParserTests {
    let now = Date(timeIntervalSince1970: 1_910_000_000)

    @Test func publishedWindowsPercentagesAmountsAndZeroRemainDistinct() throws {
        let fixtures: [(AIProvider, String, [Double])] = [
            (.claude, #"{"five_hour":{"utilization":90},"seven_day":{"utilization":30}}"#, [10, 70]),
            (.codex, #"{"rate_limit":{"primary_window":{"used_percent":80,"limit_window_seconds":18000},"secondary_window":{"used_percent":30,"limit_window_seconds":604800}},"credits":{"has_credits":true,"balance":"10.5"}}"#, [20, 70]),
            (.gemini, #"{"buckets":[{"modelId":"gemini-fixture","remainingFraction":0.8},{"modelId":"gemini-fixture","remainingFraction":0.1}]}"#, [10]),
            (.kimi, #"{"usage":{"limit":"100","remaining":"70"},"limits":[{"window":{"duration":5,"timeUnit":"TIME_UNIT_HOUR"},"detail":{"limit":100,"used":90}}]}"#, [70, 10]),
            (.cursor, #"{"individualUsage":{"plan":{"used":800,"limit":1000,"breakdown":{"total":800}}}}"#, [20]),
            (.zcode, #"{"data":{"limits":[{"type":"CREDIT_LIMIT","unit":3,"number":5,"usage":100,"remaining":50,"currentValue":90}]}}"#, [10]),
            (.zed, #"{"plan":{"usage":{"edit_predictions":{"used":100,"limit":{"limited":100}}},"subscription_period":{"started_at":"2026-01-01T00:00:00Z","ended_at":"2027-01-01T00:00:00Z"}}}"#, [0]),
            (.workbuddy, #"{"data":{"Accounts":[{"Status":0,"CycleCapacitySizePrecise":100,"CycleCapacityRemainPrecise":20},{"Status":3,"CycleCapacitySizePrecise":1000,"CycleCapacityRemainPrecise":1000}]}}"#, [20]),
            (.opencode, #"{"usage":{"rolling":{"percent":90},"weekly":{"percent":50}}}"#, [10, 50]),
            (.muse, #"{"schemaVersion":1,"allowance":{"window":{"usedPercent":90,"windowDurationMins":300},"weekly":{"usedPercent":20}}}"#, [10, 80]),
        ]
        for (provider, response, expected) in fixtures {
            let windows = try parse(response, provider)
            #expect(windows.compactMap(\.remainingPercent) == expected, "\(provider.rawValue) must report exact remaining quota")
            #expect(windows.allSatisfy { $0.isValid })
            if provider == .zed { #expect(windows.count == 1 && windows.first?.kind == .predictions) }
            if provider == .opencode { #expect(windows.first?.kind == .rolling && windows.first?.durationSeconds == nil) }
            if provider == .cursor { #expect(windows.first?.remaining == 2 && windows.first?.limit == 10) }
        }
    }

    @Test func kimiRatioPoolsDoNotCountMonthlyCodeBreakdownAsIndependentQuota() throws {
        let windows = try parse(#"{"usages":{"limit_5h":{"used_ratio":0.9},"limit_7d":{"used_ratio":0.2},"limit_month_total":{"used_ratio":0.3},"limit_month_code":{"used_ratio":0.1}}}"#, .kimi)
        #expect(windows.map(\.remainingPercent) == [10, 80, 70])
        #expect(windows.first?.durationSeconds == 18_000)
    }

    @Test func codexNamedFeaturesKeepIndependentRealDurationsAndWorkWithoutPrimaryQuota() throws {
        let response = #"{"rate_limit":null,"additional_rate_limits":[{"metered_feature":"spark","limit_name":"Codex Spark","rate_limit":{"primary_window":{"used_percent":90,"limit_window_seconds":18000},"secondary_window":{"used_percent":30,"limit_window_seconds":604800}}},{"metered_feature":"review","limit_name":"Review","rate_limit":{"primary_window":{"used_percent":50,"limit_window_seconds":3600}}},{"metered_feature":"empty","limit_name":"Empty","rate_limit":null}]}"#
        let windows = try parse(response, .codex)
        #expect(windows.map(\.id) == ["additional:spark:primary_window", "additional:spark:secondary_window", "additional:review:primary_window"])
        #expect(windows.map(\.remainingPercent) == [10, 70, 50])
        #expect(windows.map(\.kind) == [.fiveHours, .weekly, .rolling])
        #expect(windows.map(\.durationSeconds) == [18_000, 604_800, 3_600])
        let balance = AIAccountBalance(id: "fixture", providers: [.codex], status: .available, windows: windows)
        #expect(balance.compactLines(language: .simplifiedChinese).count == 1, "Additional windows must not be promoted to the canonical short window")
        #expect(balance.compactLines(language: .simplifiedChinese).joined().contains("Codex Spark · 5h 10%"))
        #expect(!balance.compactLines(language: .simplifiedChinese).joined().contains("Review · 5h"))
    }

    @Test func codexAdditionalInvalidDuplicateMissingAndOverBudgetInputsFailClosed() throws {
        let rows = [#"{"metered_feature":"spark","limit_name":"Spark","rate_limit":{"primary_window":{"used_percent":"NaN","limit_window_seconds":18000}}}"#,
            #"{"limit_name":"Spark","rate_limit":{"primary_window":{"used_percent":1}}}"#,
            #"{"metered_feature":"codex","limit_name":"Main","rate_limit":null}"#,
            #"{"metered_feature":"spark","limit_name":"Spark","rate_limit":{"primary_window":{"limit_window_seconds":18000}}}"#]
        for row in rows {
            #expect(throws: AIAccountBalanceError.invalidResponse) { try parse("{\"additional_rate_limits\":[" + row + "]}", .codex) }
        }
        let duplicate = #"{"metered_feature":"spark","limit_name":"Spark","rate_limit":null}"#
        #expect(throws: AIAccountBalanceError.invalidResponse) { try parse("{\"additional_rate_limits\":[" + duplicate + "," + duplicate + "]}", .codex) }
        let entries = (0..<65).map { #"{"metered_feature":"feature"# + String($0) + #"","limit_name":"Fixture","rate_limit":null}"# }
        #expect(throws: AIAccountBalanceError.invalidResponse) { try parse("{\"additional_rate_limits\":[" + entries.joined(separator: ",") + "]}", .codex) }
        #expect(throws: AIAccountBalanceError.noQuota) { try parse(#"{"additional_rate_limits":[]}"#, .codex) }
    }

    @Test func codexSpendControlUsesCreditsAndNeverFabricatesAbsentUsage() throws {
        let windows = try parse(#"{"spend_control":{"individual_limit":{"limit":100,"used":90,"reset_at":1910001000}}}"#, .codex)
        #expect(windows.first?.remaining == 10 && windows.first?.remainingPercent == 10 && windows.first?.unit == .credits)
        let percent = try parse(#"{"spend_control":{"individual_limit":{"limit":100,"remaining_percent":0}}}"#, .codex)
        #expect(percent.first?.severity == .exhausted)
        #expect(throws: AIAccountBalanceError.invalidResponse) { try parse(#"{"spend_control":{"individual_limit":{"limit":100}}}"#, .codex) }
    }

    @Test func copilotCurrentAndLegacyQuotasRejectPlaceholdersAndKeepResetDate() throws {
        let windows = try parse(#"{"quota_snapshots":{"premium_interactions":{"entitlement":100,"remaining":10,"percent_remaining":10},"chat":{"entitlement":0,"remaining":0}},"monthly_quotas":{"chat":50,"completions":200},"limited_user_quotas":{"chat":25,"completions":100},"quota_reset_date":"2030-08-01"}"#, .copilot)
        #expect(windows.map(\.id) == ["premium_interactions", "chat"])
        #expect(windows.map(\.remainingPercent) == [10, 50])
        let reset = try AIAccountBalanceParser.date("2030-08-01T00:00:00Z")
        #expect(windows.allSatisfy { $0.resetsAt == reset })
        #expect(throws: AIAccountBalanceError.noQuota) { try parse(#"{"quota_snapshots":{"chat":{"entitlement":0,"remaining":0},"empty":{}}}"#, .copilot) }
        #expect(throws: AIAccountBalanceError.invalidResponse) { try parse(#"{"quota_snapshots":{"chat":{"percent_remaining":true}}}"#, .copilot) }
        #expect(throws: AIAccountBalanceError.invalidResponse) { try AIAccountBalanceParser.date("2030-02-30", acceptsDateOnly: true) }
    }

    @Test func websiteQoderTraeAndZedBudgetsUseActualUnitsAndPartialRowsFail() throws {
        let qoder = try parse(#"{"data":{"totalQuota":{"quotaSummary":{"limitValue":100,"usedValue":90,"remainingValue":10}},"sharedQuota":{"quotaSummary":{"limitValue":100,"usedValue":20,"remainingValue":80}}}}"#, .coder)
        #expect(qoder.first?.remaining == 90 && qoder.first?.remainingPercent == 45 && qoder.first?.unit == .credits)
        let trae = try parse(#"{"is_credits_billing":true,"usage_summary":{"total_amount":100,"consumed_amount":90}}"#, .trae)
        #expect(trae.first?.remaining == 10 && trae.first?.remainingPercent == 10)
        let zed = try parse(#"{"current_usage":{"token_spend_in_cents":900,"token_spend":{"limit_in_cents":1000},"edit_predictions":{"used":50,"limit":100}}}"#, .zed)
        #expect(zed.map(\.remainingPercent) == [10, 50])
        #expect(zed.first?.remaining == 1 && zed.first?.limit == 10 && zed.first?.unit == .usd)
        let free = try parse(#"{"current_usage":{"token_spend":{"limit_in_cents":0},"edit_predictions":{"used":0,"limit":100}}}"#, .zed)
        #expect(free.count == 1 && free.first?.kind == .predictions && free.first?.severity == .normal)
        for (provider, response) in [(AIProvider.coder, #"{"data":{"totalQuota":{"quotaSummary":{"limitValue":100}}}}"#),
            (.trae, #"{"is_credits_billing":true,"usage_summary":{"total_amount":100}}"#),
            (.zed, #"{"current_usage":{"token_spend":{"limit_in_cents":1000}}}"#)] {
            #expect(throws: AIAccountBalanceError.invalidResponse) { try parse(response, provider) }
        }
    }

    @Test func malformedUnknownPartialAndMissingQuotasNeverBecomeZero() throws {
        let fixtures: [(AIProvider, String)] = [(.claude, #"{"five_hour":{"utilization":true}}"#),
            (.codex, #"{"rate_limit":{"primary_window":{"used_percent":101}}}"#),
            (.gemini, #"{"buckets":[{"modelId":"fixture","remainingFraction":1.1}]}"#),
            (.kimi, #"{"usage":{"limit":100},"limits":[]}"#), (.cursor, #"{"individualUsage":{"plan":{"limit":1000,"breakdown":{"total":1000}}}}"#),
            (.zed, #"{"plan":{"usage":{"edit_predictions":{"used":1,"limit":null}}}}"#),
            (.workbuddy, #"{"data":{"Accounts":[{"Status":0,"CycleCapacitySizePrecise":100,"CycleCapacityRemainPrecise":20},{"Status":0,"CycleCapacitySizePrecise":100}]}}"#),
            (.opencode, #"{"usage":{"rolling":{"percent":0}}}"#), (.muse, #"{"schemaVersion":1,"allowance":null}"#)]
        for (provider, response) in fixtures { #expect(throws: (any Error).self) { try parse(response, provider) } }
        for provider in [AIProvider.claude, .codex, .gemini, .kimi, .cursor, .zcode, .zed, .workbuddy, .opencode, .muse] {
            for response in ["{}", "[]", "{", #"{"quota":0,"private":"fixture-secret"}"#] {
                #expect(throws: (any Error).self) { try parse(response, provider) }
            }
        }
    }

    @Test func unlimitedAndBudgetWithoutPercentageDoNotFabricatePercentages() throws {
        let credits = try parse(#"{"credits":{"unlimited":false,"has_credits":true,"balance":"0"}}"#, .codex)
        #expect(credits.first?.remaining == 0 && credits.first?.remainingPercent == nil)
        #expect(credits.first?.severity == .exhausted)
        let noBalance = #"{"credits":{"unlimited":false,"has_credits":true}}"#
        #expect(throws: AIAccountBalanceError.noQuota) { try parse(noBalance, .codex) }
        let unlimited = try parse(#"{"data":{"limitNum":-1,"credit":100}}"#, .workbuddy)
        #expect(unlimited.first?.unlimited == true && unlimited.first?.severity == .normal)
    }

    @Test func unifiedCursorUsesPublishedCurrentWindowsInsteadOfStaleLegacyZero() throws {
        let root: [String: Any] = ["membershipType": "unified_pro", "limitType": "user",
            "individualUsage": ["plan": ["used": 0, "limit": 2000]]]
        #expect(throws: AIAccountBalanceError.noQuota) { try AIAccountBalanceParser.cursor(root, now: now) }
        let windows = try AIAccountBalanceParser.cursor(root, now: now,
            sand: ["usagePercent": 90, "hasNonZeroIncludedLimit": true],
            unified: ["availability": "available", "monthlyUsage": ["usedCents": 800, "limitCents": 1000,
                "periodStart": "2030-01-01T00:00:00Z", "resetsAt": "2031-01-01T00:00:00Z"]])
        #expect(windows.map(\.remainingPercent) == [10, 20])
        #expect(!windows.contains { $0.id == "plan" })
    }

    @Test func boundedMalformedJSONAndGrokFramesFailClosedWithDeterministicCorpus() throws {
        var seed: UInt64 = 0x6a73756c61
        for _ in 0..<128 {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1
            let length = Int(seed % 64)
            let bytes = (0..<length).map { _ -> UInt8 in seed = seed &* 6_364_136_223_846_793_005 &+ 1; return UInt8(truncatingIfNeeded: seed >> 24) }
            let data = Data(bytes)
            #expect(throws: (any Error).self) { try AIAccountBalanceParser.parse(data, provider: .grok, now: now) }
            #expect(throws: (any Error).self) { try AIAccountBalanceParser.parse(data, provider: .claude, now: now) }
        }
        #expect(throws: AIAccountBalanceError.invalidResponse) {
            try AIAccountBalanceParser.parse(Data(repeating: 0, count: 1_024 * 1_024 + 1), provider: .codex, now: now)
        }
    }

    @Test func grokAcceptsOnlyDescriptorPercentageAndActiveImplicitZero() throws {
        let published = grpc(message(1, Data([13]) + floatBytes(90)))
        let windows = try AIAccountBalanceParser.parse(published, provider: .grok, now: now)
        #expect(windows.first?.remainingPercent == 10)
        let unrelated = grpc(message(1, message(12, Data([13]) + floatBytes(90))))
        #expect(throws: AIAccountBalanceError.noQuota) { try AIAccountBalanceParser.parse(unrelated, provider: .grok, now: now) }
        let reset = message(5, Data([8]) + varint(1_910_001_000))
        let period = message(8, Data([8, 1]) + message(2, Data([8]) + varint(1_909_983_000))
            + message(3, Data([8]) + varint(1_910_001_000)))
        let emptyActive = grpc(message(1, reset + period))
        #expect(try AIAccountBalanceParser.parse(emptyActive, provider: .grok, now: now).first?.remainingPercent == 100)
        #expect(throws: (any Error).self) { try AIAccountBalanceParser.parse(Data(published.dropLast()), provider: .grok, now: now) }
        #expect(throws: AIAccountBalanceError.invalidResponse) {
            try AIAccountBalanceParser.parse(grpc(message(1, Data([13]) + floatBytes(.nan))), provider: .grok, now: now)
        }
    }

    private func parse(_ text: String, _ provider: AIProvider) throws -> [AIAccountQuotaWindow] {
        try AIAccountBalanceParser.parse(Data(text.utf8), provider: provider, now: now)
    }
    private func floatBytes(_ value: Float) -> Data { var bits = value.bitPattern.littleEndian; return withUnsafeBytes(of: &bits) { Data($0) } }
    private func varint(_ value: UInt64) -> Data {
        var value = value, bytes: [UInt8] = []
        repeat { var byte = UInt8(value & 0x7f); value >>= 7; if value > 0 { byte |= 0x80 }; bytes.append(byte) } while value > 0
        return Data(bytes)
    }
    private func message(_ field: UInt64, _ body: Data) -> Data { varint(field * 8 + 2) + varint(UInt64(body.count)) + body }
    private func grpc(_ payload: Data) -> Data {
        let length = UInt32(payload.count)
        return Data([0, UInt8(truncatingIfNeeded: length >> 24), UInt8(truncatingIfNeeded: length >> 16),
                     UInt8(truncatingIfNeeded: length >> 8), UInt8(truncatingIfNeeded: length)]) + payload
    }
}
