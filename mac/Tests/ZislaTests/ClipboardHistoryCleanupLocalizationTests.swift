import Foundation
import Testing
import ZislaCore

struct ClipboardHistoryCleanupLocalizationTests {
    @Test(arguments: AppLanguage.allCases)
    func clipboardCleanupLabelsAndPeriodsResolveInEveryLanguage(language: AppLanguage) throws {
        let source = try String(
            contentsOf: Self.packageRoot.appendingPathComponent("Sources/Zisla/SettingsView.swift"),
            encoding: .utf8
        )
        let expression = try NSRegularExpression(
            pattern: #"title: "(自动删除剪贴板历史)",\s*detail: "([^"]*)""#
        )
        let match = try #require(expression.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)))
        let title = String(source[try #require(Range(match.range(at: 1), in: source))])
        let detail = String(source[try #require(Range(match.range(at: 2), in: source))])
        let keys = [title, detail] + VoiceRecordingCleanupPolicy.allCases.map(\.menuTitle)
        let tableURL = Self.packageRoot.appendingPathComponent(
            "Resources/Localization/\(language.rawValue).lproj/Localizable.strings"
        )
        let table = try #require(NSDictionary(contentsOf: tableURL) as? [String: String])

        for key in keys {
            let value = try #require(table[key], "\(language.rawValue) is missing \(key)")
            #expect(!value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(!value.contains("%"), "Cleanup labels must not introduce format placeholders")
            #expect(AppLocalization.string(key, locale: language.locale) == value)
            if language != .simplifiedChinese, [title, detail].contains(key) {
                #expect(value != key, "\(language.rawValue) did not translate \(key)")
                if language != .english {
                    #expect(value != AppLocalization.string(key, language: .english), "\(language.rawValue) copied the English translation")
                }
            }
        }
        #expect(AppLanguage.allCases.count == 17)
    }

    @Test
    func cleanupLabelsUseTheRequestedLocale() {
        #expect(AppLocalization.string("自动删除剪贴板历史", language: .english) == "Auto-delete clipboard history")
        #expect(AppLocalization.string("自动删除剪贴板历史", language: .traditionalChinese) == "自動刪除剪貼簿歷史記錄")
        #expect(AppLocalization.string("自动删除剪贴板历史", language: .arabic) == "حذف سجل الحافظة تلقائيًا")
    }

    private static var packageRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }
}
