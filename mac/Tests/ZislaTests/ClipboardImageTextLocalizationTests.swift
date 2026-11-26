import Foundation
import Testing
import ZislaCore

struct ClipboardImageTextLocalizationTests {
    @Test(arguments: AppLanguage.allCases)
    func imageTextActionsAndStatesResolveFromEveryLanguageResource(language: AppLanguage) throws {
        let source = try String(contentsOf: Self.packageRoot.appendingPathComponent("Sources/Zisla/ClipboardHistoryModuleView.swift"), encoding: .utf8)
        let expression = try NSRegularExpression(pattern: #""([^"]*图片文字[^"]*)""#)
        let range = NSRange(source.startIndex..., in: source)
        let keys = Set(expression.matches(in: source, range: range).compactMap { match in
            Range(match.range(at: 1), in: source).map { String(source[$0]) }
        }).union(["识别失败：%@", "未识别到文字", "识图完成", "无法写入剪贴板", "已复制到剪贴板"])
        #expect(keys.count == 10)
        let table = try #require(NSDictionary(contentsOf: Self.packageRoot.appendingPathComponent(
            "Resources/Localization/\(language.rawValue).lproj/Localizable.strings"
        )) as? [String: String])
        let english = try #require(NSDictionary(contentsOf: Self.packageRoot.appendingPathComponent(
            "Resources/Localization/en.lproj/Localizable.strings"
        )) as? [String: String])
        for key in keys {
            let value = try #require(table[key], "\(language.rawValue) is missing \(key)")
            #expect(!value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(Self.placeholders(in: value) == Self.placeholders(in: key))
            #expect(AppLocalization.string(key, locale: language.locale) == value)
            if language != .simplifiedChinese {
                #expect(value != key, "\(language.rawValue) must author its translation")
                if language != .english { #expect(value != english[key], "\(language.rawValue) must not silently fall back to English") }
            }
        }
        #expect(AppLanguage.allCases.count == 17)
        #expect(language.isRightToLeft == (language == .arabic))
    }

    @Test
    func imageTextActionsUseTheRequestedLocale() {
        #expect(AppLocalization.string("识别图片文字", language: .english) == "Recognize image text")
        #expect(AppLocalization.string("复制图片文字", language: .traditionalChinese) == "複製圖片文字")
        #expect(AppLocalization.string("取消图片文字识别", language: .arabic) == "إلغاء التعرّف على نص الصورة")
    }

    private static func placeholders(in text: String) -> [String] {
        let expression = try! NSRegularExpression(pattern: #"%(?:\d+\$)?[-+0 #]*(?:\d+|\*)?(?:\.(?:\d+|\*))?(?:hh|h|ll|l|q|z|t|j)?[@diuoxXfFeEgGaAcCsSp%]"#)
        return expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).map {
            String(text[Range($0.range, in: text)!])
        }
    }

    private static var packageRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }
}
