import Foundation
import Testing
import ZislaCore

struct MailMarkAllReadLocalizationTests {
    @Test
    func everyLanguageTranslatesTheBulkReadActionAndSuccessMessage() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = try ["Zisla/MailModuleView.swift", "Zisla/AppModel.swift"]
            .map { try String(contentsOf: root.appendingPathComponent("Sources/" + $0), encoding: .utf8) }
            .joined(separator: "\n")
        let regex = try NSRegularExpression(pattern: #"AppLocalization\.(?:text|string)\("([^"\n]*全部[^"\n]*已读)""#)
        let keys = Set(regex.matches(in: source, range: NSRange(source.startIndex..., in: source)).map {
            String(source[Range($0.range(at: 1), in: source)!])
        })
        #expect(keys == ["全部标记为已读", "已将全部邮件标记为已读"])
        #expect(AppLanguage.allCases.count == 17)
        for language in AppLanguage.allCases {
            let table = try #require(NSDictionary(contentsOf: root.appendingPathComponent(
                "Resources/Localization/\(language.rawValue).lproj/Localizable.strings"
            )) as? [String: String])
            for key in keys {
                let translation = try #require(table[key], "Missing \(language.rawValue): \(key)")
                #expect(!translation.isEmpty)
                #expect(AppLocalization.string(key, language: language) == translation)
                if language != .simplifiedChinese { #expect(translation != key) }
                if language != .simplifiedChinese && language != .english {
                    #expect(translation != AppLocalization.string(key, language: .english))
                }
            }
        }
        #expect(AppLocalization.string("全部标记为已读", language: .english) == "Mark all as read")
        #expect(AppLocalization.string("全部标记为已读", language: .arabic) == "وضع علامة مقروء على الكل")
    }
}
