import Foundation
import Testing
import ZislaCore
@testable import Zisla

struct ShelfContextActionLocalizationTests {
    @Test func newRuntimeKeysArePresentAndPreservePlaceholderOrderInEveryLanguage() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let keys = Set(["多选", "取消选择", "操作", "已选择 %ld 个项目", "选择顺序 %ld", "识图并发送到随记",
            "在录屏工作室中编辑", "所选项目不支持此操作", "文件已失效或无法读取：%@",
            "无法写入随记，请检查备忘录权限后重试", "录屏工作室当前不可用，请稍后重试", "已发送到录屏工作室", "已取消操作"])
        let sources = try ["ShelfModuleView.swift", "ShelfContextActions.swift"].map {
            try String(contentsOf: root.appendingPathComponent("Sources/Zisla/" + $0), encoding: .utf8)
        }.joined(separator: "\n")
        let literal = try NSRegularExpression(pattern: #""((?:[^"\\\n]|\\.)*)""#)
        let runtimeKeys = Set(literal.matches(in: sources, range: NSRange(sources.startIndex..., in: sources)).compactMap {
            Range($0.range(at: 1), in: sources).map { String(sources[$0]) }
        })
        #expect(keys.isSubset(of: runtimeKeys), "Every asserted key must be used by the shipping action or view")
        #expect(AppLanguage.allCases.count == 17)
        for language in AppLanguage.allCases {
            let url = root.appendingPathComponent("Resources/Localization/\(language.rawValue).lproj/Localizable.strings")
            let table = try #require(try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: String])
            for key in keys {
                let value = try #require(table[key], "Missing \(language.rawValue) translation: \(key)")
                #expect(!value.isEmpty && !value.contains("TODO"))
                #expect(try placeholders(value) == placeholders(key), "Incorrect placeholders in \(language.rawValue): \(key)")
                #expect(AppLocalization.string(key, language: language) == value)
            }
            if language != .simplifiedChinese && language != .traditionalChinese {
                #expect(table["识图并发送到随记"] != "识图并发送到随记")
                if language != .english {
                    #expect(table["识图并发送到随记"] != "Recognize Text and Send to Quick Notes")
                }
            }
        }
    }

    @Test func requestedLanguageRendersSelectionCountAndContextActions() {
        #expect(AppLocalization.format("已选择 %ld 个项目", locale: AppLanguage.english.locale, [2]) == "2 items selected")
        #expect(AppLocalization.string(ShelfContextAction.recognizeToQuickNote.title, language: .english)
            == "Recognize Text and Send to Quick Notes")
        #expect(AppLocalization.string(ShelfContextAction.editVideo.title, language: .arabic) == "التحرير في استوديو التسجيل")
        #expect(AppLanguage.arabic.isRightToLeft)
    }

    private func placeholders(_ text: String) throws -> [String] {
        let pattern = try NSRegularExpression(pattern: #"%(?:ld|@|\d*\.?\d*[fd])"#)
        return pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        }
    }
}
