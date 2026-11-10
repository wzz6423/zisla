import Foundation
import Testing
@testable import ZislaCore

struct AIAccountBalanceTests {
    /// Boundary pairs distinguish inclusive remaining-quota thresholds from consumed-percentage thresholds.
    @Test(arguments: [(100.0, AIAccountQuotaSeverity.normal), (20.1, .normal), (20, .warning), (10.1, .warning),
                       (10, .critical), (0.1, .critical), (0, .exhausted)])
    func thresholdsUseRemainingQuota(percent: Double, expected: AIAccountQuotaSeverity) {
        #expect(AIAccountQuotaWindow(id: "quota", kind: .all, remainingPercent: percent).severity == expected)
    }

    /// Invalid and unavailable observations must suppress both alert severity and the compact summary.
    @Test func unavailableAndMalformedReadingsCannotTriggerLowOrZeroAlerts() {
        for status in AIAccountBalanceStatus.allFixtureCases {
            let balance = AIAccountBalance(id: "fixture", providers: [.claude], status: status,
                windows: [.init(id: "quota", kind: .all, remainingPercent: 0)])
            #expect(balance.severity == nil)
            #expect(balance.compactLines(language: .english).isEmpty)
        }
        for window in [AIAccountQuotaWindow(id: "empty", kind: .all), .init(id: "bad", kind: .all, remainingPercent: .nan),
                       .init(id: "bad", kind: .all, remainingPercent: -1), .init(id: "bad", kind: .all, remainingPercent: 101),
                       .init(id: "bad", kind: .all, remaining: 2, limit: 1), .init(id: "bad", kind: .fiveHours, remainingPercent: 10),
                       .init(id: "bad", kind: .all, remainingPercent: 10, durationSeconds: 0)] {
            #expect(!window.isValid)
            #expect(AIAccountBalance(id: "fixture", providers: [.claude], status: .available, windows: [window]).severity == nil)
        }
        #expect(AIAccountQuotaWindow(id: "unknown", kind: .all).value(language: .english) == "—")
    }

    /// Summary text must retain real window kinds and include extra quota without fabricating a 5h window.
    @Test func compactUsesOnlyRealWindowsAndAtMostTwoLines() {
        let all = AIAccountQuotaWindow(id: "weekly", kind: .weekly, remainingPercent: 70, durationSeconds: 604_800)
        var balance = AIAccountBalance(id: "fixture", providers: [.claude], status: .available, windows: [all])
        #expect(balance.compactLines(language: .simplifiedChinese) == ["全部 每周额度 70%"])
        balance.windows.insert(.init(id: "5h", kind: .fiveHours, remainingPercent: 10, durationSeconds: 18_000), at: 0)
        #expect(balance.compactLines(language: .simplifiedChinese) == ["5h 10%", "全部 每周额度 70%"])
        balance.windows[0] = .init(id: "rolling", kind: .rolling, remainingPercent: 10)
        #expect(balance.compactLines(language: .simplifiedChinese) == ["滚动额度 10%", "全部 每周额度 70%"])
        #expect(!balance.compactLines(language: .english).joined().contains("5h"))
        balance.windows.append(.init(id: "monthly", kind: .monthly, remainingPercent: 50))
        #expect(balance.compactLines(language: .simplifiedChinese).count == 2)
        #expect(balance.compactLines(language: .simplifiedChinese).last?.contains("50%") == true)
    }

    @Test func allProvidersHaveOneAccountGroupAndSharedAccountsCollapse() {
        let groups = AIAccountBalanceCatalog.groups
        #expect(groups.count == AIProvider.allCases.count - 2)
        #expect(Set(groups.flatMap { $0 }) == Set(AIProvider.allCases))
        #expect(groups.flatMap { $0 }.count == AIProvider.allCases.count)
        #expect(groups.contains([.codex, .gpt]))
        #expect(groups.contains([.cursor, .grokBot]))
        #expect(AIAccountBalanceCatalog.placeholder(for: [.pi]).status == .connectedAccount)
        #expect(AIAccountQuotaWindow(id: "unlimited", kind: .all, unlimited: true).severity == .normal)
    }

    /// Legacy defaults, forward provider IDs, explicit empty display selection, and region choice have distinct meanings.
    @Test func settingsDefaultsUnknownProvidersAndChosenRegionRoundTrip() throws {
        let old = try JSONDecoder().decode(FeatureSettings.self, from: Data("{}".utf8))
        #expect(old.aiAccountBalanceMonitoredProviders == Set(AIProvider.allCases))
        #expect(old.aiAccountBalanceDisplayedProviders == Set(AIProvider.allCases))
        #expect(old.aiAccountBalanceNoticeEnabled && !old.aiAccountBalancePinnedInCustomIsland)
        #expect(old.aiAccountBalanceQoderRegion == .global)
        let future = try JSONDecoder().decode(FeatureSettings.self, from: Data(#"{"aiAccountBalanceMonitoredProviders":["claude","future"],"aiAccountBalanceDisplayedProviders":[],"aiAccountBalanceQoderRegion":"future"}"#.utf8))
        #expect(future.aiAccountBalanceMonitoredProviders == [.claude] && future.aiAccountBalanceDisplayedProviders.isEmpty)
        #expect(future.aiAccountBalanceQoderRegion == .global)
        let settings = FeatureSettings(aiAccountBalanceNoticeEnabled: false, aiAccountBalanceCompactStyle: .detailed,
            aiAccountBalancePinnedInCustomIsland: true, aiAccountBalanceMonitoredProviders: [.gpt],
            aiAccountBalanceDisplayedProviders: [.codex], aiAccountBalanceQoderRegion: .china)
        #expect(try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(settings)) == settings)
    }
}

private extension AIAccountBalanceStatus {
    static let allFixtureCases: [Self] = [.notSignedIn, .credentialsUnavailable, .credentialsExpired,
        .additionalCredentialsRequired, .queryUnsupported, .connectedAccount, .unavailable, .rateLimited, .invalidResponse]
}
