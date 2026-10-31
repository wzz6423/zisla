import Foundation
import Testing
import ZislaCore
@testable import Zisla

struct IslandAppearanceLocalizationTests {
    static let keys: Set<String> = [
        "灵动岛展开材质", "灵动岛收起材质", "选择贴边刘海或悬浮药丸", "刘海模式", "灵动岛模式", "灵动岛位置",
        "摄像头位置居中对齐菜单栏；其他位置可拖动到屏幕四边", "摄像头位置", "其他位置", "调整位置",
        "黑色", "收起时上侧黑色，下侧透明", "音乐动效", "音浪或随音乐节奏呼吸的专辑光晕", "音浪模式", "光晕模式",
        "拖动药丸到屏幕边缘，按回车完成，按 Esc 取消。", "Liquid Glass"
    ]

    @Test(arguments: AppLanguage.allCases)
    func everyNewAppearanceLabelUsesTheRequestedLanguageWithoutFallback(language: AppLanguage) throws {
        #expect(AppLanguage.allCases.count == 17)
        let localized = try table(for: language)
        let english = try table(for: .english)
        for key in Self.keys {
            let value = try #require(localized[key], "Missing \(language.rawValue): \(key)")
            #expect(!value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(!value.contains("%"), "Unexpected placeholder in \(key)")
            #expect(AppLocalization.string(key, language: language) == value,
                    "Requested locale must render its own table for \(key)")
            if ![AppLanguage.simplifiedChinese, .traditionalChinese, .japanese].contains(language) {
                #expect(value.range(of: #"[\u4E00-\u9FFF]"#, options: .regularExpression) == nil)
            }
            if language == .japanese, key != "Liquid Glass" {
                #expect(value != key, "Japanese must use its own translation even where it shares Han characters")
            }
            if ![AppLanguage.english, .simplifiedChinese, .traditionalChinese].contains(language),
               key != "Liquid Glass" {
                #expect(value != english[key], "Copied English in \(language.rawValue): \(key)")
            }
        }
    }

    @Test
    func settingsOfferTheSameAppearanceChoicesInEnglishAndArabic() {
        #expect(AppLocalization.string("刘海模式", language: .english) == "Notch Mode")
        #expect(AppLocalization.string("光晕模式", language: .english) == "Glow Mode")
        #expect(AppLocalization.string("摄像头位置", language: .arabic) != "摄像头位置")
        #expect(AppLanguage.arabic.isRightToLeft)
        let items = SettingsSearchIndex.items(settings: .default)
        for title in ["灵动岛样式", "灵动岛展开材质", "灵动岛收起材质", "音乐动效"] {
            #expect(items.contains { $0.title == title })
        }
    }

    private func table(for language: AppLanguage) throws -> [String: String] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Localization/\(language.rawValue).lproj/Localizable.strings")
        return try #require(NSDictionary(contentsOf: url) as? [String: String])
    }
}
