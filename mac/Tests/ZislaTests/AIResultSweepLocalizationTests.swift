import Foundation
import Testing
import ZislaCore

struct AIResultSweepLocalizationTests {
    @Test
    func everyLanguageTranslatesTheActualSettingsRow() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Sources/Zisla/SettingsView.swift"), encoding: .utf8)
        let regex = try NSRegularExpression(
            pattern: #"featureToggle\("([^"]+)", detail: "([^"]+)", symbol: "[^"]+", keyPath: \\\.aiTaskResultSweepEnabled\)"#
        )
        let match = try #require(regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)))
        let keys = try [1, 2].map { String(source[try #require(Range(match.range(at: $0), in: source))]) }
        for language in AppLanguage.allCases {
            let url = root.appendingPathComponent("Resources/Localization/\(language.rawValue).lproj/Localizable.strings")
            let table = try #require(NSDictionary(contentsOf: url) as? [String: String])
            for key in keys {
                let translation = try #require(table[key], "\(language.rawValue) 缺少 \(key)")
                #expect(!translation.isEmpty)
                if language != .simplifiedChinese { #expect(translation != key) }
                #expect(AppLocalization.string(key, language: language) == translation)
            }
        }
        #expect(AppLocalization.string(keys[0], language: .english) == "AI Task Result Sweep")
        #expect(AppLocalization.string(keys[0], language: .traditionalChinese) == "AI 任務結果掃光")
    }
}
