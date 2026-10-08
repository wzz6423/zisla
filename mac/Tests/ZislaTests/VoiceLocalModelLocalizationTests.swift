import Foundation
import Testing
import ZislaCore
import ZislaKit

struct VoiceLocalModelLocalizationTests {
    @Test
    func localConfigurationKeysAreTranslatedAndRenderedInAllLanguages() throws {
        let source = try String(contentsOf: root.appendingPathComponent("Sources/Zisla/AIAgentModuleView.swift"), encoding: .utf8)
        let rowStart = try #require(source.range(of: "private struct AILocalModelConfigurationRow"))
        let row = String(source[rowStart.lowerBound...])
        let regex = try NSRegularExpression(pattern: #"AppLocalization\.text\("([^"]+)""#)
        let keys = Set(regex.matches(in: row, range: NSRange(row.startIndex..., in: row)).compactMap {
            Range($0.range(at: 1), in: row).map { String(row[$0]) }
        })
        #expect(keys.contains("API Key（可选）"))
        #expect(keys.contains("默认无需 API Key；仅在本地服务启用认证时填写。"))
        #expect(keys.contains("未发现模型，请先在本地服务中下载或加载模型。"))
        #expect(AppLanguage.allCases.count == 17)
        let english = try table(for: .english)

        for language in AppLanguage.allCases {
            let translations = try table(for: language)
            for key in keys {
                let value = try #require(translations[key], "Missing \(language.rawValue) translation for \(key)")
                #expect(!value.isEmpty)
                #expect(AppLocalization.string(key, locale: language.locale) == value)
                if newKeys.contains(key), language != .english, language != .simplifiedChinese {
                    #expect(value != english[key], "Translation must not silently copy English")
                }
            }
        }
        #expect(AppLocalization.string("获取模型", locale: Locale(identifier: "en")) == "Fetch models")
        #expect(AppLocalization.string("获取模型", locale: Locale(identifier: "ja")) == "モデルを取得")
        #expect(AppLocalization.string("获取模型", locale: Locale(identifier: "ar")) == "جلب النماذج")
    }

    private let newKeys: Set<String> = [
        "本地服务", "选择已发现的模型", "API Key（可选）", "获取模型",
        "默认无需 API Key；仅在本地服务启用认证时填写。",
        "未发现模型，请先在本地服务中下载或加载模型。",
    ]

    private func table(for language: AppLanguage) throws -> [String: String] {
        let path = root.appendingPathComponent("Resources/Localization/\(language.rawValue).lproj/Localizable.strings")
        return try #require(NSDictionary(contentsOf: path) as? [String: String])
    }

    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }
}
