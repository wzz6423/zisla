import Foundation
import Testing
import ZislaCore

@testable import Zisla

struct SystemAutoCleanupLocalizationTests {
    private static let keys = [
        "自动清理系统垃圾", "按所选间隔移入废纸篓；清空废纸篓后将永久删除", "清理范围",
    ] + SystemCleanupScope.allCases.map(\.menuTitle) + VoiceRecordingCleanupPolicy.allCases.map(\.menuTitle)

    @Test(arguments: AppLanguage.allCases)
    func everyLanguageContainsAndRendersTheActualCleanupOptions(language: AppLanguage) throws {
        #expect(AppLanguage.allCases.count == 17)
        let table = try Self.table(language)
        let english = try Self.table(.english)
        for key in Self.keys {
            let value = try #require(table[key], "Missing \(language.rawValue) translation for \(key)")
            #expect(!value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(!value.contains("%"), "Cleanup copy must not introduce placeholders: \(key)")
            #expect(AppLocalization.string(key, locale: language.locale) == value)
            if language != .simplifiedChinese && language != .traditionalChinese {
                #expect(value != key, "Untranslated Chinese in \(language.rawValue): \(key)")
            }
            if language != .english && language != .simplifiedChinese && language != .traditionalChinese {
                #expect(value != english[key], "Copied English in \(language.rawValue): \(key)")
            }
        }
    }

    @Test
    func scheduledCleanupPageUsesLocalizedOptionsAndScopeSearchAnchors() throws {
        let source = try String(contentsOf: Self.packageRoot.appendingPathComponent("Sources/Zisla/SettingsView.swift"), encoding: .utf8)
        let start = try #require(source.range(of: "settingsGroup(\"清理\")"))
        let end = try #require(source.range(of: "title: \"定时倾倒废纸篓\"", range: start.upperBound..<source.endIndex))
        let rows = String(source[start.lowerBound..<end.lowerBound])
        let titles = try NSRegularExpression(pattern: #"(?:title|detail): "([^"]+)""#)
            .matches(in: rows, range: NSRange(rows.startIndex..., in: rows))
            .compactMap { match -> String? in
                guard let range = Range(match.range(at: 1), in: rows) else { return nil }
                return String(rows[range])
            }
        #expect(Set(titles).isSubset(of: Set(Self.keys)))
        #expect(rows.components(separatedBy: "isNested: true").count == 2)
        #expect(rows.contains("VoiceRecordingCleanupPolicy.allCases"))
        #expect(rows.contains("SystemCleanupScope.allCases"))
        #expect(rows.contains("AppLocalizedText(policy.menuTitle)"))
        #expect(rows.contains("AppLocalizedText(scope.menuTitle)"))
        #expect(AppLocalization.string("自动清理系统垃圾", language: .english) == "Automatically clean system junk")
        #expect(AppLocalization.string("按所选间隔移入废纸篓；清空废纸篓后将永久删除", language: .english)
            == "Move items to the Trash at the selected interval; emptying the Trash permanently deletes them")
        #expect(AppLocalization.string("仅可信", language: .arabic) == "العناصر الموثوقة فقط")
        #expect(AppLocalization.string("全部（包含需人工复核）", language: .traditionalChinese) == "全部（包含需人工複核）")
        #expect(AppLanguage.allCases.filter(\.isRightToLeft) == [.arabic])
    }

    @Test(arguments: AppLanguage.allCases, [false, true])
    func localizedCleanupSearchReachesOnlyVisibleNestedRows(language: AppLanguage, enabled: Bool) {
        let settings = FeatureSettings(systemMonitorEnabled: enabled)
        for key in ["自动清理系统垃圾", "清理范围"] {
            let matches = SettingsSearchIndex.results(for: AppLocalization.string(key, locale: language.locale),
                settings: settings, locale: language.locale)
            #expect(matches.contains { $0.section == .scheduledCleanup && $0.title == key && $0.anchor == .row(key) } == enabled)
        }
        let scopeMatches = SettingsSearchIndex.results(for: AppLocalization.string("仅可信", locale: language.locale),
            settings: settings, locale: language.locale)
        #expect(scopeMatches.contains { $0.anchor == .row("清理范围") } == enabled)
    }

    private static var packageRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    private static func table(_ language: AppLanguage) throws -> [String: String] {
        try #require(NSDictionary(contentsOf: packageRoot.appendingPathComponent(
            "Resources/Localization/\(language.rawValue).lproj/Localizable.strings"
        )) as? [String: String])
    }
}
