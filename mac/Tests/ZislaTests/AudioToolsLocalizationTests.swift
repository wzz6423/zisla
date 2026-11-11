import Foundation
import Testing
import ZislaCore
import ZislaKit
@testable import Zisla

struct AudioToolsLocalizationTests {
    @Test(arguments: AppLanguage.allCases)
    func runtimeAudioKeysHaveTranslationsAndMatchingPlaceholders(language: AppLanguage) throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        var keys = Set([SettingsSection.audioTools.title, SettingsSection.audioTools.subtitle, ManagedTool.ffmpeg.purpose])
        keys.formUnion(AudioToolOperation.allCases.flatMap { [$0.title, $0.detail] })
        keys.formUnion(AudioChannelMode.allCases.map(\.title))
        let token = try NSRegularExpression(pattern: #"//[^\n]*|/\*[\s\S]*?\*/|"(?:[^"\\]|\\.)*""#)
        for file in ["ZislaKit/AudioProcessingModels", "ZislaKit/AudioProcessingService", "Zisla/AudioToolsModuleView", "Zisla/AudioToolsController"] {
            let source = try String(contentsOf: root.appendingPathComponent("Sources/\(file).swift"), encoding: .utf8)
            for match in token.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
                let range = try #require(Range(match.range, in: source))
                let literal = String(source[range])
                if literal.first == "\"", literal.range(of: #"[\u4E00-\u9FFF]"#, options: .regularExpression) != nil {
                    keys.insert(String(literal.dropFirst().dropLast()))
                }
            }
        }
        #expect(keys.count >= 130)
        let tableURL = root.appendingPathComponent("Resources/Localization/\(language.rawValue).lproj/Localizable.strings")
        let table = try #require(NSDictionary(contentsOf: tableURL) as? [String: String])
        let placeholders = try NSRegularExpression(pattern: #"%(?:ld|@|\d*\.?\d*[fd])"#)
        func values(_ value: String) -> [String] {
            placeholders.matches(in: value, range: NSRange(value.startIndex..., in: value)).compactMap {
                Range($0.range, in: value).map { String(value[$0]) }
            }
        }
        for key in keys {
            let value = try #require(table[key], "\(language.rawValue) is missing \(key)")
            #expect(!value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(values(value) == values(key), "\(language.rawValue) has invalid placeholders for \(key)")
            #expect(AppLocalization.string(key, locale: language.locale) == value)
        }
        if language != .simplifiedChinese && language != .traditionalChinese {
            for key in AudioToolOperation.allCases.flatMap({ [$0.title, $0.detail] }) where key != "均衡器" {
                #expect(table[key] != key, "\(language.rawValue) left \(key) untranslated")
                if language != .english { #expect(table[key] != AppLocalization.string(key, language: .english)) }
            }
        }
    }

    @Test
    func representativeLabelsResolveByLocale() {
        #expect(AppLocalization.string("音频工具", language: .english) == "Audio tools")
        #expect(AppLocalization.string("音频工具", language: .arabic) == "أدوات الصوت")
        #expect(AppLocalization.string("音频工具", language: .traditionalChinese) == "音訊工具")
    }
}
