import Foundation
import Testing
import ZislaCore

@testable import Zisla

/// Missing emoji-recognition keys silently fall back to Chinese in any language,
/// so each language's resources are checked to catch missing translations.
struct ClipboardAssistantEmojiLocalizationTests {
    private static let keys = ["Emoji 名称", "复制 Emoji"]

    @Test
    func everyLanguageTranslatesEmojiKeys() throws {
        for language in AppLanguage.allCases {
            let table = try #require(
                Self.stringsTable(for: language),
                "无法解析 \(language.rawValue) 的 Localizable.strings"
            )
            for key in Self.keys {
                _ = try #require(table[key], "\(language.rawValue) 缺少「\(key)」")
            }
        }
    }

    @Test
    func simplifiedChineseUsesKeysVerbatim() throws {
        for language in AppLanguage.allCases where language.rawValue == "zh-Hans" {
            let table = try #require(Self.stringsTable(for: language))
            for key in Self.keys {
                #expect(table[key] == key, "zh-Hans 的「\(key)」应与 key 一致")
            }
        }
    }

    private static func stringsTable(for language: AppLanguage) -> [String: String]? {
        let url = Self.localizationURL
            .appendingPathComponent("\(language.rawValue).lproj", isDirectory: true)
            .appendingPathComponent("Localizable.strings")
        return NSDictionary(contentsOf: url) as? [String: String]
    }

    private static var localizationURL: URL {
        Self.packageRootURL
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("Localization", isDirectory: true)
    }

    private static var packageRootURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
