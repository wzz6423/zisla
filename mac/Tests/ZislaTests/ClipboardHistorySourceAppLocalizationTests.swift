import Foundation
import Testing
import ZislaCore
import ZislaKit

struct ClipboardHistorySourceAppLocalizationTests {
    @Test(arguments: AppLanguage.allCases)
    func clipboardSourceLabelsResolveInEveryLanguage(language: AppLanguage) throws {
        let source = try String(contentsOf: Self.packageRoot.appendingPathComponent(
            "Sources/Zisla/ClipboardHistoryModuleView.swift"), encoding: .utf8)
        let expression = try NSRegularExpression(pattern: #"AppLocalization\.text\("([^"]+)""#)
        let keys = Set(expression.matches(in: source, range: NSRange(source.startIndex..., in: source)).compactMap { match in
            Range(match.range(at: 1), in: source).map { String(source[$0]) }
        })
        let callKeys: Set<String> = ["按应用", "搜索内容或应用", "未知应用"]
        #expect(callKeys.isSubset(of: keys), "The checked labels must be used by the clipboard view")
        let groupingKeys = ClipboardHistoryGrouping.allCases.map(\.title)
        #expect(AppLanguage.allCases.count == 17)
        let table = try #require(NSDictionary(contentsOf: Self.packageRoot.appendingPathComponent(
            "Resources/Localization/\(language.rawValue).lproj/Localizable.strings")) as? [String: String])
        for key in callKeys.union(groupingKeys).union(["无符合条件的内容"]) {
            let value = try #require(table[key], "\(language.rawValue) is missing \(key)")
            #expect(!value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(!value.contains("%"), "Clipboard source labels must not add format placeholders")
            #expect(AppLocalization.string(key, locale: language.locale) == value)
            if language != .simplifiedChinese {
                #expect(value != key, "\(language.rawValue) did not translate \(key)")
            }
        }
        if language != .english, language != .simplifiedChinese {
            for key in ["按应用", "搜索内容或应用"] {
                #expect(table[key] != AppLocalization.string(key, language: .english),
                    "\(language.rawValue) copied the English translation for \(key)")
            }
        }
    }

    @Test
    func clipboardSourceLabelsUseTheRequestedLocale() {
        #expect(AppLocalization.string("按应用", language: .english) == "By app")
        #expect(AppLocalization.string("搜索内容或应用", language: .english) == "Search content or apps")
        #expect(AppLocalization.string("按应用", language: .arabic) == "حسب التطبيق")
        #expect(AppLocalization.string("搜索内容或应用", language: .arabic) == "البحث عن محتوى أو تطبيقات")
        #expect(AppLanguage.arabic.isRightToLeft)
    }

    private static var packageRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }
}
