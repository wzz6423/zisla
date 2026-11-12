import Foundation
import Testing
@testable import ZislaCore

struct AIAccountBalanceTests {
    @Test(arguments: [[AIProvider.codex], [.gpt], [.codex, .gpt]], AppLanguage.allCases)
    func sharedChatGPTBalanceHasOneBrandAndTwoRealDurationReadings(providers: [AIProvider], language: AppLanguage) {
        let reading = AIAccountBalance(id: "shared", providers: providers, status: .available,
            windows: [.init(id: "5h", kind: .fiveHours, remainingPercent: 10, durationSeconds: 18_000),
                .init(id: "weekly", kind: .weekly, remainingPercent: 51, durationSeconds: 604_800)])
        #expect(reading.providerTitle(language: language) == "ChatGPT")
        #expect(reading.compactLines(language: language) == ["5h 10%", "7d 51%"])
        let weeklyOnly = AIAccountBalance(id: "weekly", providers: providers, status: .available,
            windows: [reading.windows[1]])
        #expect(weeklyOnly.compactLines(language: language) == ["7d 51%"])
    }

    @Test func additionalAndNamedWindowsKeepTheirLabelsBesideTheRealCanonicalDurations() {
        let extras = [AIAccountQuotaWindow(id: "additional:spark:primary_window", kind: .fiveHours,
            remainingPercent: 20, durationSeconds: 18_000, name: "Codex Spark"),
            .init(id: "additional:spark:secondary_window", kind: .weekly, remainingPercent: 70,
                durationSeconds: 604_800, name: "Codex Spark"),
            .init(id: "named-weekly", kind: .weekly, remainingPercent: 30, durationSeconds: 604_800, name: "Sonnet"),
            .init(id: "localized-weekly", kind: .weekly, remainingPercent: 40, nameKey: "模型额度")]
        var reading = AIAccountBalance(id: "shared", providers: [.codex], status: .available, windows: extras)
        let all = "全部 Codex Spark · 5h 20% · Codex Spark · 每周额度 70% · Sonnet · 每周额度 30% · 模型额度 40%"
        #expect(reading.compactLines(language: .simplifiedChinese) == [all])
        reading.windows += [.init(id: "primary_window", kind: .fiveHours, remainingPercent: 10, durationSeconds: 18_000),
            .init(id: "secondary_window", kind: .weekly, remainingPercent: 51, durationSeconds: 604_800)]
        #expect(reading.compactLines(language: .simplifiedChinese) == ["5h 10%", "7d 51% · " + all])
        reading.windows = [reading.windows[4]]
        #expect(reading.compactLines(language: .simplifiedChinese) == ["5h 10%"])
    }

    @Test func detailedSummaryKeepsRealFiveHoursAndPutsExhaustionFirstInAllWindows() {
        let reading = AIAccountBalance(id: "claude", providers: [.claude], status: .available,
            windows: [.init(id: "5h", kind: .fiveHours, remainingPercent: 70, durationSeconds: 18_000),
                .init(id: "weekly", kind: .weekly, remainingPercent: 90),
                .init(id: "extra", kind: .budget, remaining: 0, unit: .usd)])
        #expect(reading.compactLines(language: .simplifiedChinese) == ["5h 70%", "7d 90% · 全部 可用预算 $0"])
    }

    @Test func ringFractionRequiresARealFiniteDenominator() {
        let percent = AIAccountQuotaWindow(id: "percent", kind: .all, remainingPercent: 10)
        let amount = AIAccountQuotaWindow(id: "credits", kind: .credits, remaining: 25, limit: 100, unit: .credits)
        #expect(percent.remainingFraction == 0.1)
        #expect(amount.remainingFraction == 0.25)
        #expect(amount.severity == .normal, "Amount-only visualization must preserve the existing alert semantics")
        for window in [AIAccountQuotaWindow(id: "unknown", kind: .credits, remaining: 20, unit: .credits),
            .init(id: "zero", kind: .credits, remaining: 0, limit: 0, unit: .credits),
            .init(id: "unlimited", kind: .all, remainingPercent: 100, unlimited: true),
            .init(id: "invalid", kind: .all, remainingPercent: .nan)] {
            #expect(window.remainingFraction == nil)
        }
    }

    @Test func visibleSharedAccountRequiresTheSameMonitoredAndDisplayedAlias() {
        let reading = AIAccountBalance(id: "shared", providers: [.codex, .gpt], status: .available,
            windows: [.init(id: "quota", kind: .all, remainingPercent: 70)])
        #expect(AIAccountBalanceCatalog.displayedBalances([reading], monitoredProviders: [.codex],
            displayedProviders: [.gpt]).isEmpty)
        let selected = AIAccountBalanceCatalog.displayedBalances([reading], monitoredProviders: [.gpt],
            displayedProviders: [.gpt])
        #expect(selected.count == 1 && selected.first?.providers == [.gpt])
        #expect(AIAccountBalanceCatalog.displayedBalances([reading], monitoredProviders: [],
            displayedProviders: [.gpt]).isEmpty)
    }

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
        #expect(balance.compactLines(language: .simplifiedChinese) == ["7d 70%"])
        balance.windows.insert(.init(id: "5h", kind: .fiveHours, remainingPercent: 10, durationSeconds: 18_000), at: 0)
        #expect(balance.compactLines(language: .simplifiedChinese) == ["5h 10%", "7d 70%"])
        balance.windows[0] = .init(id: "rolling", kind: .rolling, remainingPercent: 10)
        #expect(balance.compactLines(language: .simplifiedChinese) == ["滚动额度 10%", "7d 70%"])
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
