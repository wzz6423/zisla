import Foundation
import Testing
import ZislaCore

struct KeepDisplayAwakeLocalizationTests {
    @Test
    func everyLanguageTranslatesTheManualKeepAwakeMessages() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = try ["Zisla/ToolboxModuleView.swift", "ZislaKit/PowerAssertionController.swift"]
            .map { try String(contentsOf: root.appendingPathComponent("Sources/" + $0), encoding: .utf8) }
            .joined(separator: "\n")
        let regex = try NSRegularExpression(pattern: #""([^"\n]*(?:合盖时保持亮屏|无法开启合盖亮屏|无法恢复休眠设置)[^"\n]*)""#)
        let keys = Set(regex.matches(in: source, range: NSRange(source.startIndex..., in: source)).map {
            String(source[Range($0.range(at: 1), in: source)!])
        })
        #expect(keys.count == 3)
        for language in AppLanguage.allCases {
            let table = try #require(NSDictionary(contentsOf: root.appendingPathComponent(
                "Resources/Localization/\(language.rawValue).lproj/Localizable.strings"
            )) as? [String: String])
            for key in keys {
                let translation = try #require(table[key], "Missing \(language.rawValue): \(key)")
                #expect(!translation.isEmpty)
                #expect(AppLocalization.string(key, language: language) == translation)
                if language != .simplifiedChinese { #expect(translation != key) }
                if language != .english && language != .simplifiedChinese {
                    #expect(translation != AppLocalization.string(key, language: .english))
                }
            }
        }
    }
}
