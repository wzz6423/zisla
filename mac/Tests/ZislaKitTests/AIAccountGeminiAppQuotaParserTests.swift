import Foundation
import Testing
import ZislaCore
@testable import ZislaKit

struct AIAccountGeminiAppQuotaParserTests {
    @Test func officialUsageAssetAndQuerySignatureFollowRotatingNamesWithoutAcceptingURLs() throws {
        let page = Data(#"{"@messages/assets/UsagePageSurface-new_123.js":"https://evil.test/stolen.js"}"#.utf8)
        #expect(try AIAccountGeminiAppQuotaParser.usageScriptURL(page).absoluteString
            == "https://www.gstatic.com/bg3/boq-bard-web/islands/assets/UsagePageSurface-new_123.js")
        for signature in ["2/old+sig=", "2/new/sig="] {
            let script = Data("params:{id:`\(signature)`,metadata:{},name:`UsagePageQuery`}".utf8)
            #expect(try AIAccountGeminiAppQuotaParser.querySignature(script) == signature)
        }
        for page in ["", "UsagePageSurface-bad.js", #"@messages/assets/UsagePageSurface-../../secret.js"#,
                     #"@messages/assets/UsagePageSurface-file.js?token=secret"#] {
            #expect(throws: AIAccountBalanceError.invalidResponse) {
                try AIAccountGeminiAppQuotaParser.usageScriptURL(Data(page.utf8))
            }
        }
        for script in ["", "id:`2/valid=`,metadata:{},name:`OtherQuery`", "id:`https://evil.test/`,metadata:{},name:`UsagePageQuery`"] {
            #expect(throws: AIAccountBalanceError.invalidResponse) {
                try AIAccountGeminiAppQuotaParser.querySignature(Data(script.utf8))
            }
        }
    }

    @Test func fractionsBecomeRemainingWindowsWithExplicitDurationsAndIndependentResets() throws {
        let windows = try AIAccountGeminiAppQuotaParser.parse(payload([
            pool("GXU_WEEKLY", 0.125, "2030-07-12T01:02:03.123456Z"),
            pool("GXU_FIVE_HOURLY", 0.8, "2030-07-11T01:02:03Z"),
        ]))
        #expect(windows.map(\.kind) == [.fiveHours, .weekly])
        #expect(abs((windows[0].remainingPercent ?? 0) - 20) < 0.0001)
        #expect(windows[1].remainingPercent == 87.5)
        #expect(windows.map(\.durationSeconds) == [18_000, 604_800])
        #expect(windows.allSatisfy(\.isValid) && windows[0].resetsAt != windows[1].resetsAt)
        #expect(windows[0].name == nil && windows[1].name == nil)
    }

    @Test func overageIsExhaustedAndMissingPoolsCannotBecomeHealthyAllowance() throws {
        for used in [0.0, 1.0, 1.5, 200.0] {
            let window = try #require(AIAccountGeminiAppQuotaParser.parse(payload([pool("GXU_WEEKLY", used)])).first)
            #expect(window.remainingPercent == max(0, 1 - used) * 100)
        }
        #expect(throws: AIAccountBalanceError.noQuota) { try AIAccountGeminiAppQuotaParser.parse(payload([])) }
        #expect(throws: AIAccountBalanceError.noQuota) {
            try AIAccountGeminiAppQuotaParser.parse(payload([pool("GXU_UNKNOWN", 0.0)]))
        }
        #expect(throws: AIAccountBalanceError.noQuota) {
            try AIAccountGeminiAppQuotaParser.parse(Data(#"{"data":{"viewer":{"rpcs":{}}}}"#.utf8))
        }
    }

    @Test func malformedPoolsErrorsAndDuplicateWindowsInvalidateTheCompleteReading() throws {
        var noRemaining = pool("GXU_WEEKLY", 0.2)
        noRemaining.removeValue(forKey: "percentageUsed")
        var noReset = pool("GXU_WEEKLY", 0.2)
        noReset.removeValue(forKey: "gxu")
        for invalid in [noRemaining, noReset, pool("GXU_WEEKLY", -0.1), pool("GXU_WEEKLY", true),
                        pool("GXU_WEEKLY", "0.5"), pool("GXU_WEEKLY", 0.5, "invalid")] {
            #expect(throws: AIAccountBalanceError.invalidResponse) {
                try AIAccountGeminiAppQuotaParser.parse(payload([pool("GXU_FIVE_HOURLY", 0.1), invalid]))
            }
        }
        #expect(throws: AIAccountBalanceError.invalidResponse) {
            try AIAccountGeminiAppQuotaParser.parse(payload([pool("GXU_WEEKLY", 0.1), pool("GXU_WEEKLY", 0.2)]))
        }
        #expect(throws: AIAccountBalanceError.invalidResponse) {
            try AIAccountGeminiAppQuotaParser.parse(payload(Array(repeating: pool("GXU_WEEKLY", 0.1), count: 65)))
        }
        #expect(throws: AIAccountBalanceError.invalidResponse) {
            try AIAccountGeminiAppQuotaParser.parse(Data(#"{"data":{"viewer":{"rpcs":{"getUsageInfo":{"pools":[]}}}},"errors":[{"message":"private"}]}"#.utf8))
        }
        for data in [Data("invalid".utf8), Data("[1]".utf8), Data([0xff])] {
            #expect(throws: AIAccountBalanceError.invalidResponse) { try AIAccountGeminiAppQuotaParser.parse(data) }
        }
    }

    @Test func fragmentPoolBudgetsAndMalformedErrorsRejectOtherwiseValidReadings() throws {
        let observation = try JSONSerialization.jsonObject(with: payload([pool("GXU_WEEKLY", 0.1)]))
        let fragments = Array(repeating: ["extensions": ["is_final": true]] as [String: Any], count: 64) + [observation as! [String: Any]]
        #expect(throws: AIAccountBalanceError.invalidResponse) {
            try AIAccountGeminiAppQuotaParser.parse(JSONSerialization.data(withJSONObject: fragments))
        }
        let pools = Array(repeating: ["poolType": "GXU_UNKNOWN"] as [String: Any], count: 64) + [pool("GXU_WEEKLY", 0.1)]
        #expect(throws: AIAccountBalanceError.invalidResponse) { try AIAccountGeminiAppQuotaParser.parse(payload(pools)) }
        var root = observation as! [String: Any]
        for errors: Any in [[["message": "private"]], "malformed", ["message": "private"], NSNull()] {
            root["errors"] = errors
            #expect(throws: AIAccountBalanceError.invalidResponse) {
                try AIAccountGeminiAppQuotaParser.parse(JSONSerialization.data(withJSONObject: root))
            }
        }
        root["errors"] = []
        #expect(try AIAccountGeminiAppQuotaParser.parse(JSONSerialization.data(withJSONObject: root)).count == 1)
    }

    @Test func splitGraphQLFragmentsKeepEachQuotaWindowAndIgnoreUnrelatedMetadata() throws {
        let first = try JSONSerialization.jsonObject(with: payload([pool("GXU_FIVE_HOURLY", 0.1)]))
        let second = try JSONSerialization.jsonObject(with: payload([pool("GXU_WEEKLY", 0.3)]))
        let data = try JSONSerialization.data(withJSONObject: [first, ["extensions": ["is_final": true]], second])
        #expect(try AIAccountGeminiAppQuotaParser.parse(data).map(\.id) == ["five_hour", "weekly"])
    }

    @Test func boundedProtocolMutationsNeverPublishInvalidWindows() throws {
        for index in 0..<64 {
            let candidate = pool(index.isMultiple(of: 3) ? "GXU_FIVE_HOURLY" : "GXU_WEEKLY", Double(index) / 20)
            let windows = try AIAccountGeminiAppQuotaParser.parse(payload([candidate]))
            #expect(windows.count == 1 && windows.allSatisfy(\.isValid))
            #expect(windows[0].remainingPercent.map { (0...100).contains($0) } == true)
        }
    }

    private func pool(_ type: String, _ used: Any, _ reset: String = "2030-07-12T01:02:03Z") -> [String: Any] {
        ["poolType": type, "percentageUsed": used, "gxu": ["windowRefreshesAt": reset]]
    }

    private func payload(_ pools: [[String: Any]]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["data": ["viewer": ["rpcs": ["getUsageInfo": ["pools": pools]]]]])
    }
}
