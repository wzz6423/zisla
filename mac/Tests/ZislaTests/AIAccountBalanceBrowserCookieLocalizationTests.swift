import Foundation
import Testing
import ZislaCore
@testable import Zisla

struct AIAccountBalanceBrowserCookieLocalizationTests {
    static let keys = ["从默认浏览器导入", "正在读取默认浏览器 Cookie", "无法识别默认浏览器，请手动粘贴 Cookie",
        "默认浏览器暂不支持 Cookie 导入，请手动粘贴", "未找到当前网站的 Cookie，请在默认浏览器登录或手动粘贴",
        "无法读取默认浏览器 Cookie，请手动粘贴或检查访问权限"]

    @Test(arguments: AppLanguage.allCases)
    func cookieImportCopyHasExplicitTranslationsInEverySupportedLanguage(language: AppLanguage) throws {
        let table = try table(language)
        let english = try self.table(.english)
        for key in Self.keys {
            let translation = try #require(table[key], "Missing \(language.rawValue) cookie import key: \(key)")
            #expect(!translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(AppLocalization.string(key, language: language) == translation)
            if language != .simplifiedChinese { #expect(translation != key) }
            if language != .english && language != .simplifiedChinese { #expect(translation != english[key]) }
        }
        #expect(language.isRightToLeft == (language == .arabic))
    }

    @Test func allRuntimeImportLabelsAreCoveredAndEnglishAndTraditionalTextRemainExplicit() throws {
        let root = Self.root
        let paths = ["Sources/ZislaKit/AIAccountBalanceBrowserCookie.swift", "Sources/Zisla/AIAccountBalanceCookieInput.swift"]
        let expression = try NSRegularExpression(pattern: #""([^"\\\n]*[\u4e00-\u9fff][^"\\\n]*)""#)
        var discovered: Set<String> = []
        for path in paths {
            let text = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8) as NSString
            for match in expression.matches(in: text as String, range: NSRange(location: 0, length: text.length)) {
                discovered.insert(text.substring(with: match.range(at: 1)))
            }
        }
        let existing = Set(AIAccountBalanceLocalizationTests.keys + ["保存", "清除"])
        #expect(discovered.subtracting(existing).isSubset(of: Set(Self.keys)))
        #expect(Set(Self.keys).isSubset(of: discovered))
        #expect(AppLocalization.string("从默认浏览器导入", language: .english) == "Import from default browser")
        #expect(AppLocalization.string("从默认浏览器导入", language: .traditionalChinese) == "從預設瀏覽器匯入")
        #expect(AppLocalization.string("从默认浏览器导入", language: .arabic) == "استيراد من المتصفح الافتراضي")
    }

    private static var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func table(_ language: AppLanguage) throws -> [String: String] {
        try #require(NSDictionary(contentsOf: Self.root.appendingPathComponent(
            "Resources/Localization/\(language.rawValue).lproj/Localizable.strings")) as? [String: String])
    }
}
