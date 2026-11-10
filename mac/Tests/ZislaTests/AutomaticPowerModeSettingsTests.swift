import Foundation
import Testing
import ZislaCore

@testable import Zisla

struct AutomaticPowerModeSettingsTests {
    @Test
    func automaticPowerToggleIsNestedUnderTheSystemMonitorFeature() throws {
        let source = try Self.settingsSource()
        let start = try #require(source.range(of: #"featureToggle("系统状态与清理""#))
        let end = try #require(source.range(of: #"featureToggle("键盘音效""#, range: start.upperBound..<source.endIndex))
        let rows = String(source[start.lowerBound..<end.lowerBound])
        let expression = try NSRegularExpression(
            pattern: #"featureToggle\(\s*"自动切换电源模式",\s*detail: "",\s*symbol: "[^"]+",\s*keyPath: \\.automaticPowerModeEnabled,\s*isNested: true\s*\)\s*\.disabled\(!model.settingsStore.settings.systemMonitorEnabled\)"#
        )
        #expect(expression.numberOfMatches(in: rows, range: NSRange(rows.startIndex..., in: rows)) == 1)
        #expect(!rows.contains("插电默认模式"))
        #expect(!rows.contains("脱电默认模式"))
    }

    @Test
    func detailedSettingsUseAllExistingPowerModesAndKeepTheManualOverrideExplanation() throws {
        let source = try Self.settingsSource()
        let start = try #require(source.range(of: #"settingsGroup("电源模式")"#))
        let end = try #require(source.range(of: #"settingsGroup("清理")"#, range: start.upperBound..<source.endIndex))
        let rows = String(source[start.lowerBound..<end.lowerBound])
        #expect(rows.contains("settingsStore.settings.powerAdapterDefaultMode = $0"))
        #expect(rows.contains("settingsStore.settings.batteryDefaultMode = $0"))
        #expect(rows.components(separatedBy: "ForEach(BatteryPowerMode.allCases").count == 3)
        #expect(rows.contains("AppLocalizedText(mode.menuTitle).tag(mode)"))
        #expect(rows.contains("keyPath: \\.lowBatteryPowerModeEnabled"))
        #expect(rows.contains(".disabled(!settingsStore.settings.systemMonitorEnabled || !settingsStore.settings.automaticPowerModeEnabled)"))
        #expect(rows.contains("手动更改电源模式后暂停自动切换，下次插电或脱电时恢复"))
        #expect(rows.contains("电量不高于20%时保持省电，插电也不切换；超过20%后恢复对应默认模式"))
        #expect(BatteryPowerMode.allCases.map(\.menuTitle) == ["自动", "省电", "高性能"])
    }

    @Test(arguments: AppLanguage.allCases, [(false, false), (false, true), (true, false), (true, true)])
    func automaticPowerControlsRemainSearchableBeforeTheyAreEnabled(language: AppLanguage, enabled: (Bool, Bool)) {
        let settings = FeatureSettings(systemMonitorEnabled: enabled.0, automaticPowerModeEnabled: enabled.1)
        #expect(SettingsSection.scheduledCleanup.isVisible(settings: settings))
        for (key, section) in [("自动切换电源模式", SettingsSection.features),
                               ("插电默认模式", .scheduledCleanup), ("脱电默认模式", .scheduledCleanup),
                               ("20%及以下固定省电", .scheduledCleanup)] {
            let query = AppLocalization.string(key, locale: language.locale)
            let matches = SettingsSearchIndex.results(for: query, settings: settings, locale: language.locale)
            #expect(matches.first?.section == section)
            #expect(matches.first?.anchor == .row(key))
            #expect(SettingsSearchAnchor.row(key).localized(locale: language.locale) == .row(query))
        }
        for mode in BatteryPowerMode.allCases {
            let matches = SettingsSearchIndex.results(for: AppLocalization.string(mode.menuTitle, locale: language.locale),
                settings: settings, locale: language.locale)
            #expect(matches.contains { $0.section == .scheduledCleanup && $0.anchor == .row("插电默认模式") })
            #expect(matches.contains { $0.section == .scheduledCleanup && $0.anchor == .row("脱电默认模式") })
        }
    }

    @Test(arguments: AppLanguage.allCases)
    func powerSettingsRenderActualRuntimeKeysInEveryLanguage(language: AppLanguage) throws {
        let keys = try Self.runtimeKeys()
        let newKeys: Set<String> = [
            "自动切换电源模式", "插电默认模式", "脱电默认模式", "20%及以下固定省电",
            "电量不高于20%时保持省电，插电也不切换；超过20%后恢复对应默认模式",
            "手动更改电源模式后暂停自动切换，下次插电或脱电时恢复", "省电", "高性能",
        ]
        #expect(newKeys.isSubset(of: keys))
        #expect(AppLanguage.allCases.count == 17)
        let tableURL = Self.packageRoot.appendingPathComponent("Resources/Localization/\(language.rawValue).lproj/Localizable.strings")
        let table = try #require(NSDictionary(contentsOf: tableURL) as? [String: String])
        let source = try String(contentsOf: tableURL, encoding: .utf8)
        let placeholders = try NSRegularExpression(pattern: #"%(?:\d+\$)?(?:ld|lu|lld|llu|@|\d*\.?\d*[fd])"#)
        for key in keys {
            let value = try #require(table[key], "\(language.rawValue) is missing \(key)")
            #expect(!value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(AppLocalization.string(key, locale: language.locale) == value)
            #expect(placeholders.numberOfMatches(in: value, range: NSRange(value.startIndex..., in: value)) == 0,
                    "Power settings must not introduce format placeholders: \(key)")
            let declaration = try NSRegularExpression(pattern: "^\\s*\"" + NSRegularExpression.escapedPattern(for: key) + "\"\\s*=", options: .anchorsMatchLines)
            #expect(declaration.numberOfMatches(in: source, range: NSRange(source.startIndex..., in: source)) == 1)
            if newKeys.contains(key) && language != .simplifiedChinese {
                if language == .japanese && key == "高性能" {
                    #expect(value == "高性能")
                } else {
                    #expect(value != key, "\(language.rawValue) did not translate \(key)")
                }
                if language != .traditionalChinese && language != .english {
                    #expect(value != AppLocalization.string(key, language: .english), "\(language.rawValue) copied English for \(key)")
                }
            }
        }
        if language == .english {
            #expect(table["手动更改电源模式后暂停自动切换，下次插电或脱电时恢复"]
                == "Changing the power mode manually pauses automatic switching until the next plug-in or unplug event")
            #expect(BatteryPowerMode.allCases.map { AppLocalization.string($0.menuTitle, locale: language.locale) }
                == ["Automatic", "Low Power", "High Performance"])
        }
        if language == .arabic {
            #expect(table["自动切换电源模式"] == "تبديل أوضاع الطاقة تلقائيًا")
        }
        #expect(AppLanguage.allCases.filter(\.isRightToLeft) == [.arabic])
    }

    private static func runtimeKeys() throws -> Set<String> {
        let source = try settingsSource()
        let start = try #require(source.range(of: #"settingsGroup("电源模式")"#))
        let end = try #require(source.range(of: #"settingsGroup("清理")"#, range: start.upperBound..<source.endIndex))
        let toggle = try NSRegularExpression(pattern: #"featureToggle\(\s*"自动切换电源模式",[^)]*\)"#)
        let match = try #require(toggle.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)))
        let range = try #require(Range(match.range, in: source))
        let calls = String(source[start.lowerBound..<end.lowerBound]) + String(source[range])
        let literal = try NSRegularExpression(pattern: #""([^"\n]*[\u4E00-\u9FFF][^"\n]*)""#)
        var keys = Set(BatteryPowerMode.allCases.map(\.menuTitle))
        for match in literal.matches(in: calls, range: NSRange(calls.startIndex..., in: calls)) {
            keys.insert(String(calls[try #require(Range(match.range(at: 1), in: calls))]))
        }
        return keys
    }

    private static func settingsSource() throws -> String {
        try String(contentsOf: packageRoot.appendingPathComponent("Sources/Zisla/SettingsView.swift"), encoding: .utf8)
    }

    private static var packageRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }
}
