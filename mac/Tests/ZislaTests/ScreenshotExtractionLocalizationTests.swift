import Foundation
import Testing
import ZislaCore

struct ScreenshotExtractionLocalizationTests {
    @Test(arguments: AppLanguage.allCases)
    func extractionControlsAndStatusesExistAndRenderInEveryLanguage(language: AppLanguage) throws {
        let resource = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Localization/\(language.rawValue).lproj/Localizable.strings")
        let table = try #require(try PropertyListSerialization.propertyList(from: Data(contentsOf: resource), format: nil) as? [String: String])
        for key in [
            "提取", "提取主体", "提取背景", "自由圈选", "提取方式", "提取所选区域",
            "拖动圈选任意区域，可连续圈选多处", "已圈选 %ld 个区域", "正在提取...", "提取完成",
            "未找到可提取区域", "提取失败：%@", "圈选区域无效", "提取蒙版尺寸不匹配", "无法生成提取图片",
        ] {
            let value = try #require(table[key], "Missing \(language.rawValue) translation for \(key)")
            #expect(!value.isEmpty)
            #expect(AppLocalization.string(key, language: language) == value)
            if language != .simplifiedChinese && language != .traditionalChinese { #expect(value != key) }
            for token in ["%@", "%ld"] {
                #expect(value.components(separatedBy: token).count == key.components(separatedBy: token).count,
                    "Placeholder count differs for \(language.rawValue): \(key)")
            }
        }
        let selectedFormat = try #require(table["已圈选 %ld 个区域"])
        let failureFormat = try #require(table["提取失败：%@"])
        #expect(AppLocalization.format("已圈选 %ld 个区域", locale: language.locale, [3])
            == String(format: selectedFormat, locale: language.locale, 3))
        #expect(AppLocalization.format("提取失败：%@", locale: language.locale, ["test"])
            == String(format: failureFormat, locale: language.locale, "test"))
    }
}
