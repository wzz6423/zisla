import Foundation
import SwiftUI
import Testing
import ZislaCore
import ZislaKit
@testable import Zisla

@MainActor
struct AIAccountBalanceRegionSettingsTests {
    @Test func geminiSourceBindingsSeparateMonitoringFromDisplayWithoutChangingProviderSelection() {
        var settings = FeatureSettings(aiAccountBalanceMonitoredProviders: [.gemini, .claude],
                                       aiAccountBalanceDisplayedProviders: [.gemini],
                                       aiAccountBalanceMonitoredGeminiSources: [], aiAccountBalanceDisplayedGeminiSources: [.cli])
        let binding = Binding(get: { settings }, set: { settings = $0 })
        let cli = SettingsView.geminiSourceBinding(.cli, monitored: true, settings: binding)
        let app = SettingsView.geminiSourceBinding(.app, monitored: true, settings: binding)
        let displayed = SettingsView.geminiSourceBinding(.app, monitored: false, settings: binding)
        cli.wrappedValue = true
        app.wrappedValue = true
        cli.wrappedValue = false
        displayed.wrappedValue = true
        #expect(settings.aiAccountBalanceMonitoredGeminiSources == [.app])
        #expect(settings.aiAccountBalanceDisplayedGeminiSources == [.cli, .app])
        #expect(settings.aiAccountBalanceMonitoredProviders == [.gemini, .claude])
        #expect(settings.aiAccountBalanceDisplayedProviders == [.gemini])
        app.wrappedValue = false
        #expect(settings.aiAccountBalanceMonitoredGeminiSources.isEmpty)
    }

    @Test func geminiSourceStatusAndCardsNeverBorrowTheOtherSourcesAllowance() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-gemini-status-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let monitor = AIStateMonitor(directoryURL: root, activityDetectors: [], accountBalanceDetector: GeminiStatusDetector(),
                                     accountBalanceNotificationCenter: NotificationCenter(), detectorRefreshInterval: 3_600)
        defer { monitor.stop() }
        let cli = AIAccountBalanceProviderStatus(monitor: monitor, provider: .gemini, language: .english, geminiSource: .cli)
        let app = AIAccountBalanceProviderStatus(monitor: monitor, provider: .gemini, language: .english, geminiSource: .app)
        #expect(cli.status == .notSignedIn && app.status == .additionalCredentialsRequired)
        monitor.configureAccountBalanceProviders([.gemini])
        monitor.start()
        try #require(await waitFor { monitor.accountBalances.count == 2 })
        #expect(cli.status == .credentialsExpired && app.status == .available)
        #expect(cli.title == "Gemini CLI" && app.title == "Gemini App")
        let section = AIAccountBalanceSection(balances: monitor.accountBalances, displayedProviders: [.gemini],
                                              monitoredProviders: [.gemini], language: .english, displayedGeminiSources: [.cli])
        #expect(section.displayedBalances.isEmpty)
        monitor.configureAccountBalanceProviders([.gemini], geminiSources: [.cli])
        #expect(app.status == .additionalCredentialsRequired)
        try #require(await waitFor { !monitor.isRefreshingAccountBalances })
    }

    @Test func antigravityGroupBindingsDoNotChangeProviderOrOtherGroupSelections() {
        var settings = FeatureSettings(aiAccountBalanceMonitoredProviders: [.antigravity, .claude],
                                       aiAccountBalanceDisplayedProviders: [.antigravity],
                                       aiAccountBalanceMonitoredAntigravityGroups: [], aiAccountBalanceDisplayedAntigravityGroups: [.gemini])
        let binding = Binding(get: { settings }, set: { settings = $0 })
        let gemini = SettingsView.antigravityGroupBinding(.gemini, monitored: true, settings: binding)
        let claude = SettingsView.antigravityGroupBinding(.claudeGPT, monitored: true, settings: binding)
        let shownClaude = SettingsView.antigravityGroupBinding(.claudeGPT, monitored: false, settings: binding)
        gemini.wrappedValue = true
        claude.wrappedValue = true
        gemini.wrappedValue = false
        shownClaude.wrappedValue = true
        #expect(settings.aiAccountBalanceMonitoredAntigravityGroups == [.claudeGPT])
        #expect(settings.aiAccountBalanceDisplayedAntigravityGroups == [.gemini, .claudeGPT])
        #expect(settings.aiAccountBalanceMonitoredProviders == [.antigravity, .claude])
        #expect(settings.aiAccountBalanceDisplayedProviders == [.antigravity])
    }

    @Test func qoderRegionBindingsAllowBothOrNeitherWithoutChangingProviderSelection() {
        var settings = FeatureSettings(aiAccountBalanceMonitoredProviders: [.coder, .trae, .zed],
                                       aiAccountBalanceDisplayedProviders: [.trae, .zed], aiAccountBalanceQoderRegions: [])
        let binding = Binding(get: { settings }, set: { settings = $0 })
        let global = SettingsView.qoderRegionBinding(.global, settings: binding)
        let china = SettingsView.qoderRegionBinding(.china, settings: binding)
        #expect(!global.wrappedValue && !china.wrappedValue)
        global.wrappedValue = true
        #expect(global.wrappedValue && !china.wrappedValue)
        china.wrappedValue = true
        #expect(global.wrappedValue && china.wrappedValue)
        global.wrappedValue = false
        #expect(!global.wrappedValue && china.wrappedValue)
        china.wrappedValue = false
        #expect(!global.wrappedValue && !china.wrappedValue)
        #expect(settings.aiAccountBalanceQoderRegions.isEmpty)
        #expect(settings.aiAccountBalanceMonitoredProviders == [.coder, .trae, .zed])
        #expect(settings.aiAccountBalanceDisplayedProviders == [.trae, .zed])
    }

    @Test func antigravityStatusesAndCardsUseTheirOwnPoolSelection() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-antigravity-status-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let monitor = AIStateMonitor(directoryURL: root, activityDetectors: [], accountBalanceDetector: AntigravityStatusDetector(),
                                     accountBalanceNotificationCenter: NotificationCenter(), detectorRefreshInterval: 3_600)
        defer { monitor.stop() }
        let gemini = AIAccountBalanceProviderStatus(monitor: monitor, provider: .antigravity, language: .english, antigravityGroup: .gemini)
        let claude = AIAccountBalanceProviderStatus(monitor: monitor, provider: .antigravity, language: .english, antigravityGroup: .claudeGPT)
        monitor.configureAccountBalanceProviders([.antigravity])
        monitor.start()
        try #require(await waitFor { monitor.accountBalances.count == 2 })
        #expect(gemini.status == .unavailable && claude.status == .available)
        #expect(gemini.title == "Gemini")
        #expect(claude.title == AppLocalization.string("Claude 与 GPT 模型", language: .english))
        let section = AIAccountBalanceSection(balances: monitor.accountBalances, displayedProviders: [.antigravity],
                                              monitoredProviders: [.antigravity], language: .english,
                                              displayedAntigravityGroups: [.gemini])
        #expect(section.displayedBalances.isEmpty, "An unavailable Gemini pool cannot show the available Claude/GPT balance")
        monitor.configureAccountBalanceProviders([.antigravity], antigravityGroups: [.gemini])
        #expect(claude.status == .notSignedIn, "A removed pool must not borrow the remaining pool's status")
        try #require(await waitFor { !monitor.isRefreshingAccountBalances })
    }

    @Test(arguments: AppLanguage.allCases)
    func qoderRegionStatusUsesTheMatchingRegionAndCannotBorrowTheOtherStatus(language: AppLanguage) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-qoder-status-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let detector = RegionStatusDetector()
        let monitor = AIStateMonitor(directoryURL: root, activityDetectors: [], accountBalanceDetector: detector,
                                     accountBalanceNotificationCenter: NotificationCenter(), detectorRefreshInterval: 3_600)
        defer { monitor.stop() }
        let global = AIAccountBalanceProviderStatus(monitor: monitor, provider: .coder, language: language, qoderRegion: .global)
        let china = AIAccountBalanceProviderStatus(monitor: monitor, provider: .coder, language: language, qoderRegion: .china)
        #expect(global.status == .additionalCredentialsRequired && china.status == .additionalCredentialsRequired)
        #expect(global.title == AppLocalization.string("国际区", language: language))
        #expect(china.title == AppLocalization.string("中国区", language: language))
        monitor.configureAccountBalanceProviders([.coder], qoderRegions: [.global, .china])
        monitor.start()
        try #require(await waitFor { monitor.accountBalances.count == 2 })
        #expect(global.status == .credentialsExpired, "The global status must ignore the earlier China balance")
        #expect(china.status == .available)
        monitor.configureAccountBalanceProviders([.coder], qoderRegions: [.china])
        #expect(global.status == .additionalCredentialsRequired, "A removed region must not borrow the remaining region's available status")
        #expect(china.status == .available)
        try #require(await waitFor { !monitor.isRefreshingAccountBalances })
    }

    private func waitFor(_ condition: () -> Bool) async throws -> Bool {
        let deadline = ContinuousClock.now + .seconds(2)
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }
}

private struct AntigravityStatusDetector: AIAccountBalanceDetecting {
    func accountBalances(for providers: Set<AIProvider>, qoderRegions: Set<AIAccountBalanceQoderRegion>) async throws -> [AIAccountBalance] {
        AIAccountBalanceCatalog.antigravityBalances(.init(id: "antigravity", providers: [.antigravity], status: .available,
                                                        windows: [.init(id: "additional:claude-gpt:weekly", kind: .weekly,
                                                                        remainingPercent: 80, durationSeconds: 604_800, name: "Claude/GPT")])).reversed()
    }
}

private struct RegionStatusDetector: AIAccountBalanceDetecting {
    func accountBalances(for providers: Set<AIProvider>, qoderRegions: Set<AIAccountBalanceQoderRegion>) async throws -> [AIAccountBalance] {
        AIAccountBalanceQoderRegion.allCases.reversed().filter { qoderRegions.contains($0) }.map { region in
            var row = AIAccountBalanceCatalog.placeholder(for: [.coder], qoderRegion: region)
            row.status = region == .china ? .available : .credentialsExpired
            if region == .china { row.windows = [.init(id: "credits", kind: .all, remainingPercent: 70)] }
            return row
        }
    }
}

private struct GeminiStatusDetector: AIAccountBalanceDetecting {
    func accountBalances(for providers: Set<AIProvider>, qoderRegions: Set<AIAccountBalanceQoderRegion>) async throws -> [AIAccountBalance] {
        [.init(id: "gemini:app", providers: [.gemini], status: .available,
               windows: [.init(id: "weekly", kind: .weekly, remainingPercent: 80)], quotaGroup: "app"),
         .init(id: "gemini:cli", providers: [.gemini], status: .credentialsExpired, quotaGroup: "cli")]
    }
}
