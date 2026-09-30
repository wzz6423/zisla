import Foundation
import SwiftUI
import Testing
import ZislaCore
import ZislaKit

struct SystemMonitorHeadphoneOptionsIntegrationTests {
    @Test
    func headphoneControlsUsePersistedOptionsInsideCombinedIconSettings() throws {
        let source = try Self.source()
        let combined = try Self.section(source, from: "            if settingsStore.settings.systemMonitorMenuBarCombinedIconEnabled {", to: "\n        }\n        .font")
        for property in ["replacesNetworkIcon", "prioritizesNetworkErrors", "usesVolumeColor", "symbolScale"] {
            #expect(combined.contains("$settingsStore.settings.systemMonitorMenuBarHeadphoneOptions.\(property)"), "Missing binding for \(property)")
        }
        #expect(combined.contains("in: SystemMonitorHeadphoneOptions.symbolScaleRange"))
    }

    @Test
    func replacementGatesPriorityAndSizeWithoutMisrepresentingBatteryOrVolume() throws {
        let source = try Self.source()
        #expect(source.contains("AppLocalizedText(\"仅底部指标选择音量时生效\")"))
        #expect(!source.contains("showsBatteryLevels"))
        #expect(!source.contains("点击图标后在系统监控页查看耳机电量"))
        let replacement = try Self.section(
            source,
            from: "                if settingsStore.settings.systemMonitorMenuBarHeadphoneOptions.replacesNetworkIcon {",
            to: "                Toggle(isOn: $settingsStore.settings.systemMonitorMenuBarHeadphoneOptions.usesVolumeColor)"
        )
        #expect(replacement.contains("$settingsStore.settings.systemMonitorMenuBarHeadphoneOptions.prioritizesNetworkErrors"))
        #expect(replacement.contains("$settingsStore.settings.systemMonitorMenuBarHeadphoneOptions.symbolScale"))
        #expect(!replacement.contains("showsBatteryLevels"))
        #expect(!source.contains("外环显示耳机电量"))
    }

    @Test
    func everyLanguageTranslatesHeadphoneControlsAndUsageHints() throws {
        let source = try Self.source()
        let expression = try NSRegularExpression(pattern: #"(?:AppLocalizedText|AppLocalization\.text)\("([^"]+)"\)"#)
        let keys = Set(expression.matches(in: source, range: NSRange(source.startIndex..., in: source)).compactMap { match in
            Range(match.range(at: 1), in: source).map { String(source[$0]) }
        })
        #expect(keys.isSuperset(of: Self.keys))
        #expect(AppLanguage.allCases.count == 17)
        for language in AppLanguage.allCases {
            let url = Self.packageRoot.appendingPathComponent("Resources/Localization/\(language.rawValue).lproj/Localizable.strings")
            let table = try #require(NSDictionary(contentsOf: url) as? [String: String])
            for key in Self.keys.sorted() {
                let value = try #require(table[key], "\(language.rawValue) missing \(key)")
                #expect(!value.isEmpty)
                #expect(AppLocalization.string(key, locale: language.locale) == value)
                #expect(!value.contains("%"))
            }
            for key in ["耳机电量", "显示耳机电量", "点击图标后在系统监控页查看耳机电量"] {
                #expect(table[key] == nil, "\(language.rawValue) retains removed control text: \(key)")
            }
        }
        #expect(AppLocalization.string("耳机图标大小", locale: Locale(identifier: "en")) == "Headphone Icon Size")
    }

    private static let keys: Set<String> = [
        "连接时短暂显示耳机图标", "优先显示网络错误", "蓝牙音量颜色", "耳机图标大小",
        "仅底部指标选择音量时生效",
    ]

    private static func section(_ source: String, from startMarker: String, to endMarker: String) throws -> String {
        let start = try #require(source.range(of: startMarker))
        let end = try #require(source.range(of: endMarker, range: start.upperBound..<source.endIndex))
        return String(source[start.lowerBound..<end.lowerBound])
    }

    private static func source() throws -> String {
        try String(contentsOf: packageRoot.appendingPathComponent("Sources/Zisla/SystemMonitorMenuBarSettingsView.swift"), encoding: .utf8)
    }

    private static var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
