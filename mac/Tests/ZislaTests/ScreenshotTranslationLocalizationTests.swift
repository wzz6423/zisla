import Foundation
import Testing
import ZislaCore

@testable import Zisla

struct ScreenshotTranslationLocalizationTests {
    @Test(arguments: AppLanguage.allCases)
    func translationControlsAndStatusesRenderInEveryLanguage(language: AppLanguage) throws {
        let resource = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Localization/\(language.rawValue).lproj/Localizable.strings")
        let table = try #require(try PropertyListSerialization.propertyList(
            from: Data(contentsOf: resource), format: nil
        ) as? [String: String])
        for key in [
            "翻译并复制", ScreenshotRecognitionMode.translate.title, "正在翻译…",
            "翻译失败，请重试或使用浏览器翻译", "%@，结果已复制", "无法写入剪贴板",
        ] {
            let value = try #require(table[key], "Missing \(language.rawValue) translation for \(key)")
            #expect(!value.isEmpty)
            #expect(AppLocalization.string(key, language: language) == value)
            if language != .simplifiedChinese && language != .traditionalChinese { #expect(value != key) }
            #expect(value.components(separatedBy: "%@").count == key.components(separatedBy: "%@").count)
        }
        #expect(AppLocalization.string("翻译并复制", language: .english) == "Translate and Copy")
        #expect(AppLocalization.string("翻译完成", language: .arabic) == "اكتملت الترجمة")
    }
}
