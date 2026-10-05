import Foundation
import Testing
import ZislaCore

struct SettingsSearchLocalizationTests {
    @Test(arguments: AppLanguage.allCases)
    func searchStringsArePresentInEveryLanguage(language: AppLanguage) throws {
        let keys = try runtimeSearchKeys()
        #expect(keys == ["搜索设置", "搜索结果", "未找到设置项"])
        let tableURL = Self.packageRoot.appendingPathComponent(
            "Resources/Localization/\(language.rawValue).lproj/Localizable.strings"
        )
        let table = try #require(NSDictionary(contentsOf: tableURL) as? [String: String])

        for key in keys {
            let value = try #require(table[key], "\(language.rawValue) is missing \(key)")
            #expect(!value.isEmpty)
            #expect(!value.contains("%"), "Search labels must not introduce format placeholders")
            #expect(AppLocalization.string(key, language: language) == value)
            if language != .simplifiedChinese {
                #expect(value != key, "\(language.rawValue) did not translate \(key)")
            }
        }
    }

    @Test
    func searchStringsUseRequestedLocale() {
        #expect(AppLanguage.allCases.count == 17)
        #expect(AppLocalization.string("搜索设置", language: .english) == "Search Settings")
        #expect(AppLocalization.string("未找到设置项", language: .english) == "No Settings Found")
        #expect(AppLocalization.string("搜索设置", language: .arabic) == "البحث في الإعدادات")
        #expect(AppLocalization.string("搜索结果", language: .traditionalChinese) == "搜尋結果")
    }

    private func runtimeSearchKeys() throws -> Set<String> {
        let source = try String(
            contentsOf: Self.packageRoot.appendingPathComponent("Sources/Zisla/SettingsView.swift"),
            encoding: .utf8
        )
        let expression = try NSRegularExpression(
            pattern: #"AppLocal(?:ization\.text|izedText)\("(搜索设置|搜索结果|未找到设置项)""#
        )
        return Set(expression.matches(in: source, range: NSRange(source.startIndex..., in: source)).map {
            String(source[Range($0.range(at: 1), in: source)!])
        })
    }

    private static var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
