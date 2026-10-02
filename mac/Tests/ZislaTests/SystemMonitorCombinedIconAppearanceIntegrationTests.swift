import AppKit
import Foundation
import SwiftUI
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

struct SystemMonitorCombinedIconAppearanceIntegrationTests {
    @Test
    func appearanceControlsAreBoundToPersistedSettingsInsideCombinedIconSection() throws {
        let source = try Self.source("SystemMonitorMenuBarSettingsView.swift")
        let section = try Self.section(
            source,
            from: "            if settingsStore.settings.systemMonitorMenuBarCombinedIconEnabled {",
            to: "\n        }\n        .font"
        )
        for property in [
            "showsBatteryPercentage", "showsChargingIndicator", "showsPercentageWhenConnected", "usesStatusColors",
            "indicatorStyle", "ringStrokeStyle", "iconSize", "wifiScale", "batteryTextScale",
        ] {
            #expect(section.contains("$settingsStore.settings.systemMonitorMenuBarCombinedIconAppearance.\(property)"), "Missing binding for \(property)")
        }
        for range in ["iconSizeRange", "wifiScaleRange", "batteryTextScaleRange"] {
            #expect(section.contains("in: SystemMonitorCombinedIconAppearance.\(range)"))
        }
        #expect(section.contains("SystemMonitorMenuBarIndicatorStyle.allCases"))
        #expect(section.contains("SystemMonitorMenuBarRingStrokeStyle.allCases"))
    }

    @Test
    func imageRefreshReadsCurrentSettingsAndUsesUpstreamSystemItemSizing() throws {
        let source = try Self.source("ZislaApp.swift")
        let section = try Self.section(
            source,
            from: "    private func updateCombinedMonitorStatusImage(",
            to: "    private func configureMonitorStatusItem("
        )
        #expect(section.contains("let settings = AppModel.shared.settingsStore.settings"))
        #expect(section.contains("configuration: settings.systemMonitorMenuBarCombinedIconAppearance"))
        #expect(!section.contains("combinedMonitorStatusItem?.length ="))
        let controller = try Self.section(source,
            from: "    private func syncCombinedMonitorStatusItem(",
            to: "    private func updateCombinedMonitorStatusImage(")
        #expect(controller.contains("item.button?.imagePosition = .imageOnly"))
        #expect(controller.contains("statusItem(withLength: NSStatusItem.variableLength)"))
        #expect(!controller.contains("item.button?.imageScaling = .scaleNone"))
    }

    @Test
    func imageRefreshLeavesDynamicColorsToRendererAndPreservesLiveInputs() throws {
        let source = try Self.source("ZislaApp.swift")
        let section = try Self.section(
            source,
            from: "    private func updateCombinedMonitorStatusImage(",
            to: "    private func configureMonitorStatusItem("
        )
        #expect(!section.contains("isDark"))
        #expect(!section.contains("foreground:"))
        #expect(!section.contains("effectiveAppearance"))
        #expect(section.contains("battery: battery, wifi: combinedIconLevels.wifi, level: level"))
        #expect(section.contains("button.toolTip = tooltip"))
        #expect(section.contains("button.image?.accessibilityDescription = tooltip"))
    }

    @Test
    func independentCompactRowsRemainCentered() throws {
        let source = try Self.source("ZislaApp.swift")
        let section = try Self.section(
            source,
            from: "    private func compactMonitorStatusImage(",
            to: "    private func "
        )
        #expect(section.contains("paragraph.alignment = .center"))
        #expect(!section.contains("paragraph.alignment = .left"))
        #expect(section.contains("let size = NSSize(width: itemWidth - 4, height: 22)"))
        #expect(section.contains("NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)"))
        #expect(section.contains("NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)"))
        #expect(section.contains("NSFont.systemFont(ofSize: 8, weight: .semibold)"))
    }

    @Test
    func everyLanguageTranslatesAppearanceLabelsAndEnumTitles() throws {
        let source = try Self.source("SystemMonitorMenuBarSettingsView.swift")
        let section = try Self.section(
            source,
            from: "            if settingsStore.settings.systemMonitorMenuBarCombinedIconEnabled {",
            to: "\n        }\n        .font"
        )
        let pattern = try NSRegularExpression(pattern: #"(?:AppLocalizedText|AppLocalization\.text)\("([^"]+)"\)"#)
        var keys = Set(pattern.matches(in: section, range: NSRange(section.startIndex..., in: section)).compactMap { match in
            Range(match.range(at: 1), in: section).map { String(section[$0]) }
        })
        keys.formUnion(SystemMonitorMenuBarIndicatorStyle.allCases.map(\.menuTitle))
        keys.formUnion(SystemMonitorMenuBarRingStrokeStyle.allCases.map(\.menuTitle))
        #expect(keys.isSuperset(of: Self.appearanceLabels))
        #expect(AppLanguage.allCases.count == 17)
        for language in AppLanguage.allCases {
            let url = Self.packageRoot
                .appendingPathComponent("Resources/Localization/\(language.rawValue).lproj/Localizable.strings")
            let table = try #require(NSDictionary(contentsOf: url) as? [String: String])
            for key in keys {
                let value = try #require(table[key], "\(language.rawValue) missing \(key)")
                #expect(!value.isEmpty)
                #expect(Self.placeholders(in: value) == Self.placeholders(in: key))
                #expect(AppLocalization.string(key, locale: language.locale) == value)
            }
        }
        #expect(AppLocalization.string("电量状态颜色", locale: Locale(identifier: "en")) == "Battery Status Colors")
        #expect(AppLocalization.string("电量状态颜色", locale: Locale(identifier: "ar")) == "ألوان حالة البطارية")
    }

    @Test @MainActor
    func nestedBindingsPreserveAppearanceWhenModesAndIconAreDisabled() {
        var settings = FeatureSettings.default
        settings.systemMonitorMenuBarLayout = .both
        settings.systemMonitorMenuBarCombinedIconEnabled = true
        settings.systemMonitorMenuBarMetrics = [.memory, .fan]
        settings.systemMonitorMenuBarTopRow = [.network, .cpu]
        settings.systemMonitorMenuBarBottomRow = [.fan]
        let original = settings
        let binding = Binding(get: { settings }, set: { settings = $0 })
        let appearance = binding.systemMonitorMenuBarCombinedIconAppearance
        appearance.showsBatteryPercentage.wrappedValue = true
        appearance.showsChargingIndicator.wrappedValue = true
        appearance.showsPercentageWhenConnected.wrappedValue = true
        appearance.usesStatusColors.wrappedValue = false
        appearance.indicatorStyle.wrappedValue = .arc
        appearance.ringStrokeStyle.wrappedValue = .light
        appearance.iconSize.wrappedValue = 36
        appearance.wifiScale.wrappedValue = 1.8
        appearance.batteryTextScale.wrappedValue = 1.98
        let configured = settings
        #expect(configured.systemMonitorMenuBarCombinedIconAppearance == SystemMonitorCombinedIconAppearance(
            iconSize: 36, ringStrokeStyle: .light, indicatorStyle: .arc,
            showsBatteryPercentage: true, showsChargingIndicator: true, showsPercentageWhenConnected: true,
            usesStatusColors: false, batteryTextScale: 1.98, wifiScale: 1.8
        ))
        for _ in 0..<16 {
            binding.systemMonitorMenuBarLayout.individualEnabled.wrappedValue = false
            binding.systemMonitorMenuBarLayout.stackedEnabled.wrappedValue = false
            binding.systemMonitorMenuBarCombinedIconEnabled.wrappedValue = false
            #expect(settings.systemMonitorMenuBarCombinedIconAppearance == configured.systemMonitorMenuBarCombinedIconAppearance)
            binding.systemMonitorMenuBarLayout.individualEnabled.wrappedValue = true
            binding.systemMonitorMenuBarLayout.stackedEnabled.wrappedValue = true
            binding.systemMonitorMenuBarCombinedIconEnabled.wrappedValue = true
            #expect(settings == configured)
        }
        settings.systemMonitorMenuBarCombinedIconAppearance = original.systemMonitorMenuBarCombinedIconAppearance
        #expect(settings == original)
    }

    @Test @MainActor
    func settingsAppearanceReachesRendererWithNormalizedDimensions() throws {
        for size in [0.0, 16, 22, 36, 100, .nan, .infinity] {
            var settings = FeatureSettings.default
            settings.systemMonitorMenuBarCombinedIconAppearance.iconSize = size
            let image = try #require(SystemMonitorMenuBarImageRenderer.combinedIcon(
                battery: nil, wifi: .off, level: 0.5,
                configuration: settings.systemMonitorMenuBarCombinedIconAppearance
            ))
            let expected = CGFloat(settings.systemMonitorMenuBarCombinedIconAppearance.normalized.iconSize)
            #expect(image.size.width == expected)
            #expect(image.size.height == expected)
            let cell = NSButtonCell(imageCell: image)
            cell.isBordered = false
            cell.imagePosition = .imageOnly
            let imageRect = cell.imageRect(forBounds: NSRect(x: 0, y: 0, width: expected, height: 22))
            #expect(imageRect.width > 0 && imageRect.width <= expected)
            #expect(imageRect.minX >= 0)
            #expect(imageRect.maxX <= expected)
        }
    }

    @Test @MainActor
    func settingsStorePersistsAppearanceWithExistingStorageAndRefreshLifecycle() throws {
        let suite = "SystemMonitorCombinedIconAppearanceIntegrationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FeatureSettingsStore(defaults: defaults, persistenceDelay: .seconds(60), defaultUpdateChannel: .release)
        defer { store.flushPendingChanges() }
        let binding = Binding(get: { store.settings }, set: { store.settings = $0 })
        #expect(binding.systemMonitorMenuBarCombinedIconMetric.wrappedValue == .memory)
        #expect(binding.systemMonitorMenuBarCombinedIconAppearance.ringStrokeStyle.wrappedValue == .bold)
        #expect(binding.systemMonitorMenuBarCombinedIconAppearance.indicatorStyle.wrappedValue == .dots)
        #expect(binding.systemMonitorMenuBarCombinedIconAppearance.showsBatteryPercentage.wrappedValue)
        #expect(binding.systemMonitorMenuBarCombinedIconAppearance.showsChargingIndicator.wrappedValue)
        #expect(binding.systemMonitorMenuBarCombinedIconAppearance.showsPercentageWhenConnected.wrappedValue)
        #expect(binding.systemMonitorMenuBarCombinedIconAppearance.iconSize.wrappedValue == 26)
        #expect(binding.systemMonitorMenuBarCombinedIconAppearance.wifiScale.wrappedValue == 1.55)
        #expect(binding.systemMonitorMenuBarCombinedIconAppearance.batteryTextScale.wrappedValue == SystemMonitorCombinedIconAppearance.batteryTextScaleRange.upperBound)
        binding.systemMonitorMenuBarCombinedIconAppearance.indicatorStyle.wrappedValue = .arc
        binding.systemMonitorMenuBarCombinedIconAppearance.ringStrokeStyle.wrappedValue = .regular
        binding.systemMonitorMenuBarCombinedIconAppearance.showsBatteryPercentage.wrappedValue = false
        binding.systemMonitorMenuBarCombinedIconAppearance.showsChargingIndicator.wrappedValue = false
        binding.systemMonitorMenuBarCombinedIconAppearance.showsPercentageWhenConnected.wrappedValue = false
        binding.systemMonitorMenuBarCombinedIconAppearance.usesStatusColors.wrappedValue = false
        binding.systemMonitorMenuBarCombinedIconAppearance.iconSize.wrappedValue = 32
        binding.systemMonitorMenuBarCombinedIconMetric.wrappedValue = .cpu
        binding.systemMonitorMenuBarLayout.stackedEnabled.wrappedValue = true
        store.flushPendingChanges()
        let data = try #require(defaults.data(forKey: "feature-settings-v1"))
        let persisted = try JSONDecoder().decode(FeatureSettings.self, from: data)
        #expect(persisted == store.settings)
        let reloaded = FeatureSettingsStore(defaults: defaults, defaultUpdateChannel: .release)
        #expect(reloaded.settings == store.settings)
        #expect(reloaded.settings.systemMonitorMenuBarCombinedIconMetric == .cpu)
        #expect(reloaded.settings.systemMonitorMenuBarCombinedIconAppearance.ringStrokeStyle == .regular)
        #expect(!reloaded.settings.systemMonitorMenuBarCombinedIconAppearance.showsBatteryPercentage)
        #expect(!reloaded.settings.systemMonitorMenuBarCombinedIconAppearance.showsChargingIndicator)
        #expect(!reloaded.settings.systemMonitorMenuBarCombinedIconAppearance.showsPercentageWhenConnected)
        let source = try Self.source("ZislaApp.swift")
        let subscription = try Self.section(
            source,
            from: "        model.settingsStore.$settings\n            .sink { [weak self] settings in",
            to: "            .store(in: &cancellables)"
        )
        #expect(subscription.contains("syncMonitorStatusItems(force: true)"))
        let controller = try Self.section(source, from: "    private func syncCombinedMonitorStatusItem(", to: "    private func updateCombinedMonitorStatusImage(")
        #expect(controller.contains("item.button?.action = #selector(showSystemMonitor)"))
        #expect(controller.contains("guard combinedIconReadTask == nil else { return }"))
        #expect(controller.contains("combinedIconReadTask?.cancel()"))
        #expect(controller.contains("self.updateCombinedMonitorStatusImage(metric: metric)"))
        #expect(!controller.contains("systemMonitorMenuBarCombinedIconAppearance ="))
    }

    private static let appearanceLabels: Set<String> = [
        "显示电池百分比", "显示充电标记", "接通电源时显示百分比", "底部指示样式",
        "电量环粗细", "图标大小", "Wi-Fi 大小", "电量文字大小", "电量状态颜色",
    ]

    private static func placeholders(in text: String) -> [String] {
        let expression = try! NSRegularExpression(pattern: #"%(?:ld|@|\d*\.?\d*[fd])"#)
        return expression.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap { Range($0.range, in: text).map { String(text[$0]) } }
            .sorted()
    }

    private static func section(_ source: String, from startMarker: String, to endMarker: String) throws -> String {
        let start = try #require(source.range(of: startMarker))
        let end = try #require(source.range(of: endMarker, range: start.upperBound..<source.endIndex))
        return String(source[start.lowerBound..<end.lowerBound])
    }

    private static func source(_ filename: String) throws -> String {
        try String(contentsOf: packageRoot.appendingPathComponent("Sources/Zisla/\(filename)"), encoding: .utf8)
    }

    private static var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
