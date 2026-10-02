import AppKit
import Foundation
import SwiftUI
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

struct SystemMonitorMenuBarModeIntegrationTests {
    @Test
    func configurationExposesTwoIndependentSwitches() throws {
        let settings = try Self.source("SettingsView.swift")
        let merged = try Self.source("SystemMonitorMenuBarSettingsView.swift")
        let individualOrder = try [
            "Toggle(isOn: $settingsStore.settings.systemMonitorMenuBarLayout.individualEnabled)",
            "if model.settingsStore.settings.systemMonitorMenuBarLayout.individualEnabled {",
            "title: \"监控样式\"",
            "ForEach(SystemMonitorMenuBarMetric.allCases, id: \\.self)",
            "SystemMonitorMenuBarSettingsView(settingsStore: model.settingsStore)",
        ].map { try #require(settings.range(of: $0), "Missing settings control: \($0)").lowerBound }
        #expect(individualOrder == individualOrder.sorted())
        let mergedOrder = try [
            "Toggle(isOn: $settingsStore.settings.systemMonitorMenuBarLayout.stackedEnabled)",
            "if settingsStore.settings.systemMonitorMenuBarLayout.stackedEnabled {",
            "Toggle(isOn: $settingsStore.settings.systemMonitorMenuBarCombinedIconEnabled)",
        ].map { try #require(merged.range(of: $0), "Missing settings control: \($0)").lowerBound }
        #expect(mergedOrder == mergedOrder.sorted())
        #expect(!merged.contains("Picker(AppLocalization.text(\"菜单栏布局\")"))
    }

    @Test
    func controllersUseIndependentModeGates() throws {
        let source = try Self.source("ZislaApp.swift")
        #expect(source.contains("let selected = settings.systemMonitorEnabled && settings.systemMonitorMenuBarLayout.individualEnabled\n            ? settings.systemMonitorMenuBarMetrics : []"))
        #expect(source.contains("guard settings.systemMonitorEnabled, settings.systemMonitorMenuBarLayout.stackedEnabled else {"))
    }

    @Test
    func bothModeExposesBothConfigurationSections() throws {
        let merged = try Self.source("SystemMonitorMenuBarSettingsView.swift")
        let individual = try Self.source("SettingsView.swift")
        #expect(merged.contains("if settingsStore.settings.systemMonitorMenuBarLayout.stackedEnabled {"))
        #expect(individual.contains("if model.settingsStore.settings.systemMonitorMenuBarLayout.individualEnabled {"))
        #expect(!merged.contains("systemMonitorMenuBarLayout == .stacked"))
        #expect(!individual.contains("systemMonitorMenuBarLayout == .individual"))
    }

    @Test
    func masterSwitchStillGatesAllItemsAndCombinedIconStaysIndependent() throws {
        let source = try Self.source("ZislaApp.swift")
        let individual = try Self.section(source, from: "    private func syncMonitorStatusItems(", to: "    private func syncMergedMonitorStatusItem(")
        let merged = try Self.section(source, from: "    private func syncMergedMonitorStatusItem(", to: "    private func syncCombinedMonitorStatusItem(")
        let icon = try Self.section(source, from: "    private func syncCombinedMonitorStatusItem(", to: "    private func updateCombinedMonitorStatusImage(")
        #expect(individual.contains("settings.systemMonitorEnabled && settings.systemMonitorMenuBarLayout.individualEnabled"))
        #expect(individual.contains("syncMergedMonitorStatusItem(settings: settings)"))
        #expect(individual.contains("syncCombinedMonitorStatusItem(settings: settings)"))
        #expect(merged.contains("guard settings.systemMonitorEnabled, settings.systemMonitorMenuBarLayout.stackedEnabled else {"))
        #expect(icon.contains("guard settings.systemMonitorEnabled, settings.systemMonitorMenuBarCombinedIconEnabled else {"))
        #expect(!icon.contains("systemMonitorMenuBarLayout"))
    }

    @Test
    func settingsChangesReuseExistingRefreshAndRemovalLifecycle() throws {
        let source = try Self.source("ZislaApp.swift")
        let subscription = try Self.section(
            source,
            from: "        model.settingsStore.$settings\n            .sink { [weak self] settings in",
            to: "            .store(in: &cancellables)"
        )
        let individual = try Self.section(source, from: "    private func syncMonitorStatusItems(", to: "    private func syncMergedMonitorStatusItem(")
        let merged = try Self.section(source, from: "    private func syncMergedMonitorStatusItem(", to: "    private func syncCombinedMonitorStatusItem(")
        #expect(subscription.contains("syncMonitorStatusItems(force: true)"))
        #expect(individual.contains("for metric in monitorStatusItems.keys.filter({ !selected.contains($0) })"))
        #expect(individual.contains("NSStatusBar.system.removeStatusItem(item)"))
        #expect(merged.contains("NSStatusBar.system.removeStatusItem(item)"))
        #expect(merged.contains("mergedMonitorStatusItem = nil"))
        #expect(!individual.contains("settings.systemMonitorMenuBarMetrics ="))
        #expect(!merged.contains("settings.systemMonitorMenuBarTopRow ="))
        #expect(!merged.contains("settings.systemMonitorMenuBarBottomRow ="))
    }

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

    private static func section(_ source: String, from startMarker: String, to endMarker: String) throws -> String {
        let start = try #require(source.range(of: startMarker))
        let end = try #require(source.range(of: endMarker, range: start.upperBound..<source.endIndex))
        return String(source[start.lowerBound..<end.lowerBound])
    }

    private static func source(_ filename: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Zisla/\(filename)")
        return try String(contentsOf: url, encoding: .utf8)
    }
}
