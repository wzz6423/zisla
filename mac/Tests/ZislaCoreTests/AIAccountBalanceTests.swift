import Foundation
import Testing
@testable import ZislaCore

struct AIAccountBalanceTests {
    @Test func geminiSourcesKeepIndependentIdentityFiltersAndDefaultUpgradeSelection() throws {
        let window = AIAccountQuotaWindow(id: "weekly", kind: .weekly, remainingPercent: 10)
        let cli = AIAccountBalance(id: "gemini:cli", providers: [.gemini], status: .available, windows: [window], quotaGroup: "cli")
        let app = AIAccountBalance(id: "gemini:app", providers: [.gemini], status: .available, windows: [window], quotaGroup: "app")
        #expect(cli.providerTitle(language: .english) == "Gemini CLI" && app.providerTitle(language: .english) == "Gemini App")
        #expect(cli.noticeID != app.noticeID)
        let rows = AIAccountBalanceCatalog.displayedBalances([cli, app], monitoredProviders: [.gemini], displayedProviders: [.gemini],
                                                            monitoredGeminiSources: [.app], displayedGeminiSources: [.app])
        #expect(rows == [app])
        #expect(AIAccountBalanceCatalog.displayedBalances([cli, app], monitoredProviders: [.gemini], displayedProviders: [.gemini],
                                                         monitoredGeminiSources: [.app], displayedGeminiSources: [.cli]).isEmpty)
        let legacy = try JSONDecoder().decode(FeatureSettings.self, from: Data(#"{"aiAccountBalanceMonitoredProviders":["gemini"],"aiAccountBalanceDisplayedProviders":["gemini"]}"#.utf8))
        #expect(legacy.aiAccountBalanceMonitoredProviders == [.gemini])
        #expect(legacy.aiAccountBalanceMonitoredGeminiSources == [.cli, .app] && legacy.aiAccountBalanceDisplayedGeminiSources == [.cli, .app])
        var disabled = legacy
        disabled.aiAccountBalanceMonitoredGeminiSources = []
        disabled.aiAccountBalanceDisplayedGeminiSources = [.app]
        let decoded = try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(disabled))
        #expect(decoded.aiAccountBalanceMonitoredGeminiSources.isEmpty && decoded.aiAccountBalanceDisplayedGeminiSources == [.app])
        let unknown = try JSONDecoder().decode(FeatureSettings.self, from: Data(#"{"aiAccountBalanceMonitoredGeminiSources":["app","unknown"]}"#.utf8))
        #expect(unknown.aiAccountBalanceMonitoredGeminiSources == [.app])
    }

    @Test(arguments: [([AIProvider.codex], "Codex"), ([.gpt], "ChatGPT"),
                      ([.codex, .gpt], "Codex"), ([.gpt, .codex], "ChatGPT")], AppLanguage.allCases)
    func sharedAccountKeepsSelectedProviderBrandsAndTwoRealDurationReadings(selection: ([AIProvider], String), language: AppLanguage) {
        let (providers, title) = selection
        let reading = AIAccountBalance(id: "shared", providers: providers, status: .available,
                                       windows: [.init(id: "5h", kind: .fiveHours, remainingPercent: 10, durationSeconds: 18_000),
                                                 .init(id: "weekly", kind: .weekly, remainingPercent: 51, durationSeconds: 604_800)])
        #expect(reading.displayProvider == providers.first)
        #expect(reading.providerTitle(language: language) == title)
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
        #expect(selected.first?.displayProvider == .gpt)
        let codex = AIAccountBalanceCatalog.displayedBalances([reading], monitoredProviders: [.codex],
                                                              displayedProviders: [.codex])
        #expect(codex.count == 1 && codex.first?.providers == [.codex])
        #expect(codex.first?.displayProvider == .codex)
        #expect(AIAccountBalanceCatalog.displayedBalances([reading], monitoredProviders: [],
                                                          displayedProviders: [.gpt]).isEmpty)
    }

    @Test func emptyAndOtherSharedProviderIdentitiesKeepTheirExistingMeaning() {
        let empty = AIAccountBalance(id: "empty", providers: [], status: .notSignedIn)
        #expect(empty.displayProvider == nil && empty.providerTitle(language: .english).isEmpty)
        let cursor = AIAccountBalance(id: "cursor", providers: [.cursor, .grokBot], status: .notSignedIn)
        #expect(cursor.displayProvider == .cursor)
        #expect(cursor.providerTitle(language: .english) == "Cursor / Grok Bot")
    }

    @Test func debugBalancesOverrideRealProviderSelectionsAndKeepExplicitAliases() {
        let rows = [AIProvider.claude, .gpt, .cursor].map {
            AIAccountBalance(id: "debug:" + $0.rawValue, providers: [$0], status: .available,
                             windows: [.init(id: "quota", kind: .all, remainingPercent: 10)], isDebug: true)
        }
        for selection in [Set<AIProvider>(), [.codex]] {
            #expect(AIAccountBalanceCatalog.displayedBalances(rows, monitoredProviders: selection,
                                                              displayedProviders: selection) == rows)
        }
        var live = rows
        for index in live.indices { live[index].isDebug = false }
        #expect(AIAccountBalanceCatalog.displayedBalances(live, monitoredProviders: [], displayedProviders: []).isEmpty)
        var invalid = rows
        invalid[0].status = .unavailable
        invalid[1].windows = []
        invalid[2].windows = [.init(id: "quota", kind: .all, remainingPercent: .nan)]
        #expect(AIAccountBalanceCatalog.displayedBalances(invalid, monitoredProviders: [], displayedProviders: []).isEmpty)
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

    /// Defaults avoid account reads; unknown IDs are ignored without reviving an explicit empty selection.
    @Test func settingsDefaultsUnknownProvidersAndChosenRegionRoundTrip() throws {
        let old = try JSONDecoder().decode(FeatureSettings.self, from: Data("{}".utf8))
        #expect(old.aiAccountBalanceMonitoredProviders.isEmpty)
        #expect(old.aiAccountBalanceDisplayedProviders.isEmpty)
        #expect(FeatureSettings.default.aiAccountBalanceMonitoredProviders.isEmpty)
        #expect(FeatureSettings.default.aiAccountBalanceDisplayedProviders.isEmpty)
        #expect(old.aiAccountBalanceNoticeEnabled && !old.aiAccountBalancePinnedInCustomIsland)
        #expect(old.aiAccountBalanceQoderRegions == [.global])
        let future = try JSONDecoder().decode(FeatureSettings.self, from: Data(#"{"aiAccountBalanceMonitoredProviders":["claude","future"],"aiAccountBalanceDisplayedProviders":[],"aiAccountBalanceQoderRegion":"future"}"#.utf8))
        #expect(future.aiAccountBalanceMonitoredProviders == [.claude] && future.aiAccountBalanceDisplayedProviders.isEmpty)
        #expect(future.aiAccountBalanceQoderRegions.isEmpty)
        let settings = FeatureSettings(aiAccountBalanceNoticeEnabled: false, aiAccountBalanceCompactStyle: .detailed,
                                       aiAccountBalancePinnedInCustomIsland: true, aiAccountBalanceMonitoredProviders: [.gpt],
                                       aiAccountBalanceDisplayedProviders: [.codex], aiAccountBalanceQoderRegions: [.china])
        #expect(try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(settings)) == settings)
    }

    @Test(arguments: [Set<AIAccountBalanceQoderRegion>(), [.global], [.china], [.global, .china]])
    func qoderRegionSelectionsRoundTripWithoutChangingOtherProviders(regions: Set<AIAccountBalanceQoderRegion>) throws {
        let settings = FeatureSettings(aiAccountBalanceMonitoredProviders: [.coder, .trae, .zed],
                                       aiAccountBalanceDisplayedProviders: [.coder, .zed], aiAccountBalanceQoderRegions: regions)
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(FeatureSettings.self, from: data) == settings)
        let payload = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(try #require(payload["aiAccountBalanceQoderRegions"] as? [String])) == Set(regions.map(\.rawValue)))
        #expect(payload["aiAccountBalanceQoderRegion"] == nil, "New settings must persist the independent region selection")
    }

    @Test(arguments: AIAccountBalanceQoderRegion.allCases)
    func legacySingleQoderRegionMigratesAndPreservesExplicitProviders(region: AIAccountBalanceQoderRegion) throws {
        let data = try JSONSerialization.data(withJSONObject: ["aiAccountBalanceMonitoredProviders": ["coder", "trae", "zed"],
                                                               "aiAccountBalanceDisplayedProviders": ["coder"], "aiAccountBalanceQoderRegion": region.rawValue])
        let settings = try JSONDecoder().decode(FeatureSettings.self, from: data)
        #expect(settings.aiAccountBalanceQoderRegions == [region])
        #expect(settings.aiAccountBalanceMonitoredProviders == [.coder, .trae, .zed])
        #expect(settings.aiAccountBalanceDisplayedProviders == [.coder])
        #expect(try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(settings)) == settings)
    }

    @Test(arguments: ["future", "GLOBAL", "cn", ""])
    func invalidLegacyQoderRegionDoesNotSelectAnotherRegion(raw: String) throws {
        let data = try JSONSerialization.data(withJSONObject: ["aiAccountBalanceQoderRegion": raw])
        let settings = try JSONDecoder().decode(FeatureSettings.self, from: data)
        #expect(settings.aiAccountBalanceQoderRegions.isEmpty, "An unknown saved region must not access a different account")
        #expect(try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(settings)) == settings)
    }

    @Test(arguments: [([String](), Set<AIAccountBalanceQoderRegion>()), (["future"], Set<AIAccountBalanceQoderRegion>()),
                      (["china", "future", "china"], Set<AIAccountBalanceQoderRegion>([.china])),
                      (["global", "china", "future"], Set<AIAccountBalanceQoderRegion>([.global, .china]))])
    func currentQoderRegionsSupersedeLegacyValueAndIgnoreUnknownRegions(selection: ([String], Set<AIAccountBalanceQoderRegion>)) throws {
        let data = try JSONSerialization.data(withJSONObject: ["aiAccountBalanceQoderRegions": selection.0,
                                                               "aiAccountBalanceQoderRegion": "global"])
        let settings = try JSONDecoder().decode(FeatureSettings.self, from: data)
        #expect(settings.aiAccountBalanceQoderRegions == selection.1,
                "A new empty or unknown selection must not fall back to the old region")
    }

    @Test(arguments: AppLanguage.allCases)
    func qoderRegionsKeepDistinctTitlesAndNoticeIdentities(language: AppLanguage) throws {
        let rows = AIAccountBalanceQoderRegion.allCases.map { AIAccountBalanceCatalog.placeholder(for: [.coder], qoderRegion: $0) }
        #expect(Set(rows.map(\.id)).count == 2)
        #expect(Set(rows.map(\.noticeID)).count == 2)
        #expect(Set(rows.map { $0.providerTitle(language: language) }).count == 2)
        for row in rows {
            let region = try #require(row.qoderRegion)
            #expect(row.providerTitle(language: language) == "Qoder · " + AppLocalization.string(region.title, language: language))
            #expect(try JSONDecoder().decode(AIAccountBalance.self, from: JSONEncoder().encode(row)) == row)
        }
        #expect(AIAccountBalanceCatalog.placeholder(for: [.trae], qoderRegion: .china).providerTitle(language: language) == "TRAE")
        #expect(AIAccountBalanceCatalog.placeholder(for: [.zed], qoderRegion: .china).qoderRegion == nil)
    }

    @Test func legacyBalanceWithoutRegionStillDecodes() throws {
        let row = AIAccountBalance(id: "legacy", providers: [.coder], status: .notSignedIn)
        let payload = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(row)) as? [String: Any])
        #expect(payload["qoderRegion"] == nil)
        #expect(try JSONDecoder().decode(AIAccountBalance.self, from: JSONSerialization.data(withJSONObject: payload)) == row)
    }

    @Test func antigravityPoolsHaveIndependentLimitsResetsAndIdentities() throws {
        let geminiReset = Date(timeIntervalSince1970: 2_000_000_000)
        let claudeReset = geminiReset.addingTimeInterval(3_600)
        let sample = AIAccountBalance(id: "antigravity:account", providers: [.antigravity], status: .available, windows: [
            .init(id: "additional:gemini:five_hour", kind: .fiveHours, remainingPercent: 80,
                  resetsAt: geminiReset, durationSeconds: 18_000, name: "Gemini"),
            .init(id: "additional:gemini:weekly", kind: .weekly, remainingPercent: 70, durationSeconds: 604_800, name: "Gemini"),
            .init(id: "additional:argon:five_hour", kind: .fiveHours, remainingPercent: 60, durationSeconds: 18_000, name: "Gemini 4 Argon"),
            .init(id: "additional:claude-gpt:five_hour", kind: .fiveHours, remainingPercent: 10,
                  resetsAt: claudeReset, durationSeconds: 18_000, name: "Claude/GPT"),
            .init(id: "additional:claude-gpt:weekly", kind: .weekly, remainingPercent: 0, durationSeconds: 604_800, name: "Claude/GPT"),
            .init(id: "additional:custom:weekly", kind: .weekly, remainingPercent: 50, durationSeconds: 604_800, name: "Future Models"),
        ], accountName: "fixture@example.test")
        let rows = AIAccountBalanceCatalog.antigravityBalances(sample)
        #expect(rows.map(\.quotaGroup) == ["gemini", "claudeGPT", "custom:Future Models"])
        #expect(Set(rows.map(\.noticeID)).count == 3)
        let gemini = rows[0], claude = rows[1], custom = rows[2]
        #expect(gemini.severity == .normal && claude.severity == .exhausted && custom.severity == .normal)
        #expect(gemini.fiveHourWindow?.resetsAt == geminiReset && claude.fiveHourWindow?.resetsAt == claudeReset)
        #expect(gemini.windows.count == 3 && gemini.windows.last?.name == "Gemini 4 Argon")
        #expect(gemini.compactLines(language: .english).first == "5h 80%")
        #expect(claude.compactLines(language: .english) == ["5h 10%", "7d 0%"])
        #expect(custom.providerTitle(language: .english) == "Antigravity · Future Models")
        #expect(rows.allSatisfy { $0.accountName == sample.accountName })
        for row in rows {
            #expect(AIAccountBalanceCatalog.antigravityBalances(row) == [row])
            #expect(try JSONDecoder().decode(AIAccountBalance.self, from: JSONEncoder().encode(row)) == row)
        }
    }

    @Test func argonOnlyQuotaKeepsItsFeatureNameAndCannotBecomeCanonicalGeminiAllowance() {
        let window = AIAccountQuotaWindow(id: "additional:argon:five_hour", kind: .fiveHours,
                                          remainingPercent: 60, durationSeconds: 18_000, name: "Gemini 4 Argon")
        let rows = AIAccountBalanceCatalog.antigravityBalances(.init(id: "antigravity", providers: [.antigravity],
                                                                    status: .available, windows: [window]))
        #expect(rows[0].quotaGroup == "gemini" && rows[0].windows == [window])
        #expect(rows[0].fiveHourWindow == nil && rows[0].weeklyWindow == nil)
        #expect(rows[0].compactLines(language: .english).joined().contains("Gemini 4 Argon"))
        #expect(rows[1].status == .unavailable && rows[1].windows.isEmpty)
    }

    @Test func missingAntigravityPoolCannotBorrowOtherQuotaOrStatus() {
        let sample = AIAccountBalance(id: "antigravity", providers: [.antigravity], status: .available,
                                      windows: [.init(id: "additional:claude-gpt:weekly", kind: .weekly,
                                                      remainingPercent: 0, durationSeconds: 604_800, name: "Claude/GPT")])
        let rows = AIAccountBalanceCatalog.antigravityBalances(sample)
        #expect(rows.count == 2)
        #expect(rows[0].quotaGroup == "gemini" && rows[0].status == .unavailable && rows[0].severity == nil)
        #expect(rows[1].quotaGroup == "claudeGPT" && rows[1].status == .available && rows[1].severity == .exhausted)
        for status in AIAccountBalanceStatus.allFixtureCases {
            var failure = sample
            failure.status = status
            failure.windows = []
            let failedRows = AIAccountBalanceCatalog.antigravityBalances(failure)
            #expect(failedRows.map(\.status) == [status, status])
            #expect(failedRows.allSatisfy { $0.windows.isEmpty && $0.severity == nil })
        }
        let other = AIAccountBalance(id: "gemini", providers: [.gemini], status: .notSignedIn)
        #expect(AIAccountBalanceCatalog.antigravityBalances(other) == [other])
        var debug = sample
        debug.isDebug = true
        #expect(AIAccountBalanceCatalog.antigravityBalances(debug) == [debug])
        #expect(debug.matchesAntigravityGroups([]))
    }

    @Test func antigravityDisplayAndMonitoringSelectionsAreIndependent() {
        let sample = AIAccountBalance(id: "antigravity", providers: [.antigravity], status: .available, windows: [
            .init(id: "additional:gemini:weekly", kind: .weekly, remainingPercent: 60, durationSeconds: 604_800, name: "Gemini"),
            .init(id: "additional:claude-gpt:weekly", kind: .weekly, remainingPercent: 10, durationSeconds: 604_800, name: "Claude/GPT"),
        ])
        let rows = AIAccountBalanceCatalog.antigravityBalances(sample)
        let shown = AIAccountBalanceCatalog.displayedBalances(rows, monitoredProviders: [.antigravity], displayedProviders: [.antigravity],
                                                             monitoredAntigravityGroups: [.gemini, .claudeGPT], displayedAntigravityGroups: [.gemini])
        #expect(shown.map(\.quotaGroup) == ["gemini"])
        #expect(rows[1].matchesAntigravityGroups([.claudeGPT]))
        #expect(!rows[1].matchesAntigravityGroups([.gemini]))
        #expect(AIAccountBalanceCatalog.displayedBalances(rows, monitoredProviders: [.antigravity], displayedProviders: [.antigravity],
                                                         monitoredAntigravityGroups: [.claudeGPT], displayedAntigravityGroups: [.gemini]).isEmpty)
        #expect(AIAccountBalanceCatalog.displayedBalances(rows, monitoredProviders: [.antigravity], displayedProviders: [.antigravity],
                                                         displayedAntigravityGroups: []).isEmpty)
    }

    @Test func antigravitySettingsMigrateDefaultsAndPreserveEmptyOrUnknownSelections() throws {
        let old = try JSONDecoder().decode(FeatureSettings.self, from: Data(#"{"aiAccountBalanceMonitoredProviders":["antigravity"],"aiAccountBalanceDisplayedProviders":["antigravity"]}"#.utf8))
        #expect(old.aiAccountBalanceMonitoredAntigravityGroups == Set(AIAccountBalanceAntigravityGroup.allCases))
        #expect(old.aiAccountBalanceDisplayedAntigravityGroups == Set(AIAccountBalanceAntigravityGroup.allCases))
        let selected = try JSONDecoder().decode(FeatureSettings.self, from: Data(#"{"aiAccountBalanceMonitoredAntigravityGroups":["claudeGPT","future","claudeGPT"],"aiAccountBalanceDisplayedAntigravityGroups":[]}"#.utf8))
        #expect(selected.aiAccountBalanceMonitoredAntigravityGroups == [.claudeGPT])
        #expect(selected.aiAccountBalanceDisplayedAntigravityGroups.isEmpty)
        #expect(try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(selected)) == selected)
        let unknown = try JSONDecoder().decode(FeatureSettings.self, from: Data(#"{"aiAccountBalanceMonitoredAntigravityGroups":["future"]}"#.utf8))
        #expect(unknown.aiAccountBalanceMonitoredAntigravityGroups.isEmpty)
        #expect(unknown.aiAccountBalanceMonitoredProviders.isEmpty)
    }
}

private extension AIAccountBalanceStatus {
    static let allFixtureCases: [Self] = [.notSignedIn, .credentialsUnavailable, .credentialsExpired,
                                          .additionalCredentialsRequired, .queryUnsupported, .connectedAccount, .unavailable, .rateLimited, .invalidResponse]
}
