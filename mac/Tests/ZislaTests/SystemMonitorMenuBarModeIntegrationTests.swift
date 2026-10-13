import AppKit
import Foundation
import SwiftUI
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

struct SystemMonitorMenuBarModeIntegrationTests {
    @Test @MainActor
    func nestedToggleBindingsAllowAllModesAndPreserveSelections() {
        var settings = FeatureSettings.default
        settings.systemMonitorEnabled = true
        settings.systemMonitorMenuBarMetrics = [.memory, .fan]
        settings.systemMonitorMenuBarTopRow = [.network, .cpu]
        settings.systemMonitorMenuBarBottomRow = [.fan, .gpu]
        settings.systemMonitorMenuBarCombinedIconEnabled = true
        let original = settings
        let binding = Binding(get: { settings }, set: { settings = $0 })
        binding.systemMonitorMenuBarLayout.stackedEnabled.wrappedValue = true
        #expect(settings.systemMonitorMenuBarLayout == .both)
        #expect(settings.systemMonitorMenuBarLayout.individualEnabled)
        #expect(settings.systemMonitorMenuBarLayout.stackedEnabled)
        #expect(settings.systemMonitorMenuBarCombinedIconEnabled)
        binding.systemMonitorMenuBarLayout.individualEnabled.wrappedValue = false
        #expect(settings.systemMonitorMenuBarLayout == .stacked)
        binding.systemMonitorMenuBarLayout.stackedEnabled.wrappedValue = false
        #expect(settings.systemMonitorMenuBarLayout == .none)
        #expect(settings.systemMonitorMenuBarCombinedIconEnabled)
        binding.systemMonitorMenuBarLayout.individualEnabled.wrappedValue = true
        #expect(settings.systemMonitorMenuBarLayout == .individual)
        #expect(settings == original)
    }

    @Test(.serialized, arguments: AppLanguage.allCases) @MainActor
    func metricPickerColumnsAlignAcrossLanguages(language: AppLanguage) async throws {
        let suite = "SystemMonitorMenuBarModeIntegrationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FeatureSettingsStore(defaults: defaults, persistenceDelay: .seconds(60), defaultUpdateChannel: .release)
        defer { store.flushPendingChanges() }
        store.settings.systemMonitorMenuBarLayout = .stacked
        store.settings.systemMonitorMenuBarTopRow = [.cpu, .gpu]
        store.settings.systemMonitorMenuBarBottomRow = [.disk, .memory]

        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
        let host = NSHostingView(rootView: SystemMonitorMenuBarSettingsView(settingsStore: store)
            .environment(\.locale, language.locale)
            .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight)
        )
        host.sizingOptions = []
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 360),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.alphaValue = 0
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }

        var frames = [String: NSRect]()
        for child in host.accessibilityChildren() ?? [] {
            guard let element = child as? any NSAccessibilityElementProtocol,
                  let identifier = element.accessibilityIdentifier?(),
                  identifier.hasPrefix("system-monitor-row-") else { continue }
            frames[identifier] = element.accessibilityFrame()
        }
        try #require(frames.count == 4)
        for slot in 0..<2 {
            let top = try #require(frames["system-monitor-row-0-metric-\(slot)"])
            let bottom = try #require(frames["system-monitor-row-1-metric-\(slot)"])
            #expect(top.width > 0)
            #expect(abs(top.minX - bottom.minX) < 0.5)
            #expect(abs(top.maxX - bottom.maxX) < 0.5)
            #expect(top.midY != bottom.midY)
        }
        #expect(window.alphaValue == 0)
    }

}
