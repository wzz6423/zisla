import Foundation
import Testing
import ZislaCore

struct FileShelfShakeLocalizationTests {
    @Test(arguments: AppLanguage.allCases)
    func dropInstructionsAndSettingsExistAndRenderInEveryLanguage(language: AppLanguage) throws {
        let resource = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Localization/\(language.rawValue).lproj/Localizable.strings")
        let table = try #require(try PropertyListSerialization.propertyList(from: Data(contentsOf: resource), format: nil) as? [String: String])
        for key in [
            "中转站", "拖入文件，暂存到中转站", "松开以添加到中转站",
            "晃动唤出中转窗口", "拖拽文件时晃动鼠标，在旁边显示中转窗口",
        ] {
            let value = try #require(table[key], "Missing \(language.rawValue) translation for \(key)")
            #expect(!value.isEmpty)
            #expect(AppLocalization.string(key, language: language) == value)
            if language != .simplifiedChinese && language != .traditionalChinese {
                #expect(value != key)
            }
        }
    }
}
