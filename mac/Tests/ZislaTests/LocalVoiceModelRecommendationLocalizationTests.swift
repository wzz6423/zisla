import Foundation
import Testing
import ZislaCore

struct LocalVoiceModelRecommendationLocalizationTests {
    @Test
    func everyLanguageTranslatesTheRecommendationActuallyShownInSettings() throws {
        let source = try String(
            contentsOf: Self.packageRoot.appendingPathComponent("Sources/Zisla/SettingsView.swift"),
            encoding: .utf8
        )
        let start = try #require(source.range(of: "private func voiceLocalModelRecommendation("))
        let end = try #require(source.range(of: "private var voiceHistoryContent:", range: start.upperBound..<source.endIndex))
        let recommendation = String(source[start.lowerBound..<end.lowerBound])
        let regex = try NSRegularExpression(pattern: #"AppLocalization\.text\(\s*"([^"]+)""#)
        let keys = try Set(regex.matches(in: recommendation, range: NSRange(recommendation.startIndex..., in: recommendation)).map {
            String(recommendation[try #require(Range($0.range(at: 1), in: recommendation))])
        })
        #expect(keys.count == 11)
        #expect(AppLanguage.allCases.count == 17)

        for language in AppLanguage.allCases {
            let url = Self.packageRoot.appendingPathComponent("Resources/Localization/\(language.rawValue).lproj/Localizable.strings")
            let table = try #require(NSDictionary(contentsOf: url) as? [String: String])
            for key in keys {
                let translation = try #require(table[key], "Missing \(language.rawValue) recommendation: \(key)")
                #expect(!translation.isEmpty)
                #expect(Self.placeholders(in: translation) == Self.placeholders(in: key))
                #expect(AppLocalization.string(key, language: language) == translation)
                if language != .simplifiedChinese {
                    #expect(translation != key)
                }
                if language != .english, language != .simplifiedChinese {
                    #expect(translation != AppLocalization.string(key, language: .english))
                }
            }
        }
    }

    @Test
    func recommendationTitleUsesTheRequestedLanguage() {
        #expect(AppLocalization.string("本机模型建议", language: .english) == "Model suggestion for this Mac")
        #expect(AppLocalization.string("本机模型建议", language: .traditionalChinese) == "本機模型建議")
        #expect(AppLocalization.string("本机模型建议", language: .arabic) == "اقتراح نموذج لهذا الـ Mac")
    }

    private static func placeholders(in text: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: #"%(?:@|\d*\.?\d*f)"#)
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        }
    }

    private static var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }
}
