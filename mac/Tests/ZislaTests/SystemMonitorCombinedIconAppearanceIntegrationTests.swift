import AppKit
import Foundation
import SwiftUI
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

struct SystemMonitorCombinedIconAppearanceIntegrationTests {
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
        binding.systemMonitorMenuBarLayout.individualEnabled.wrappedValue = false
        binding.systemMonitorMenuBarLayout.stackedEnabled.wrappedValue = false
        binding.systemMonitorMenuBarCombinedIconEnabled.wrappedValue = false
        #expect(settings.systemMonitorMenuBarCombinedIconAppearance == configured.systemMonitorMenuBarCombinedIconAppearance)
        binding.systemMonitorMenuBarLayout.individualEnabled.wrappedValue = true
        binding.systemMonitorMenuBarLayout.stackedEnabled.wrappedValue = true
        binding.systemMonitorMenuBarCombinedIconEnabled.wrappedValue = true
        #expect(settings == configured)
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
    func settingsStorePersistsAppearanceWithExistingStorage() throws {
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
