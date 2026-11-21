import Foundation
import SwiftUI
import Testing
import ZislaCore
import ZislaKit
@testable import Zisla

@MainActor
struct AIAccountBalanceRegionSettingsTests {
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
