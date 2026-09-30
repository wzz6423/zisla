import Foundation
import SwiftUI
import Testing
import ZislaCore

struct SystemMonitorMenuBarModeIntegrationTests {
    @Test
    func configurationExposesTwoIndependentSwitches() throws {
        let source = try Self.source("SystemMonitorMenuBarSettingsView.swift")
        #expect(source.contains("Toggle(isOn: $settingsStore.settings.systemMonitorMenuBarLayout.individualEnabled)"))
        #expect(source.contains("Toggle(isOn: $settingsStore.settings.systemMonitorMenuBarLayout.stackedEnabled)"))
        #expect(!source.contains("Picker(AppLocalization.text(\"菜单栏布局\")"))
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
