import Foundation
import Testing
import ZislaCore
import ZislaKit

/// Settings copy goes through `AppLocalizedText`, whose lookup key is the
/// Simplified Chinese original: a missing translation compiles and renders the
/// Chinese key silently. This scans `SettingsView` for the keys the lid-close
/// row really queries and checks them against every language table.
struct LidCloseAnimationLocalizationTests {
    @Test
    func everyLanguageTranslatesTheLidCloseAnimationKeys() throws {
        let keys = try Self.lidCloseAnimationKeys()
        #expect(keys.count == 2, "key 扫描失效，只找到 \(keys.count) 个")

        for language in AppLanguage.allCases {
            let table = try #require(
                Self.stringsTable(for: language),
                "无法解析 \(language.rawValue) 的 Localizable.strings"
            )
            for key in keys {
                #expect(table[key] != nil, "\(language.rawValue) 缺少「\(key)」")
            }
        }
    }

    @Test
    func nonChineseTablesTranslateInsteadOfRepeatingTheKey() throws {
        let keys = try Self.lidCloseAnimationKeys()

        for language in AppLanguage.allCases where language != .simplifiedChinese {
            let table = try #require(
                Self.stringsTable(for: language),
                "无法解析 \(language.rawValue) 的 Localizable.strings"
            )
            for key in keys {
                #expect(table[key] != key, "\(language.rawValue) 的「\(key)」没有译文")
            }
        }
    }

    @Test
    func settingsLookupResolvesTheLidCloseAnimationCopy() {
        #expect(AppLocalization.string("合盖动画", language: .english) == "Lid Close Animation")
        #expect(AppLocalization.string("合盖动画", language: .japanese) == "フタを閉じるアニメーション")
        #expect(AppLocalization.string("合盖动画", language: .traditionalChinese) == "闔蓋動畫")
        #expect(AppLocalization.string("合盖动画", language: .simplifiedChinese) == "合盖动画")
    }

    /// The keys the running settings row queries, read out of its source line so
    /// the test follows the view instead of restating it.
    private static func lidCloseAnimationKeys() throws -> [String] {
        let source = try String(contentsOf: settingsViewSourceURL, encoding: .utf8)
        let call = try NSRegularExpression(
            pattern: #"featureToggle\(\s*"([^"]*)"\s*,\s*detail:\s*"([^"]*)"\s*,\s*symbol:\s*"[^"]*"\s*,\s*keyPath:\s*\\\.lidCloseAnimationEnabled\s*\)"#
        )
        let match = try #require(
            call.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
            "SettingsView 中找不到 lidCloseAnimationEnabled 的 featureToggle 调用"
        )
        return [1, 2].compactMap { index in
            Range(match.range(at: index), in: source).map { String(source[$0]) }
        }
    }

    private static func stringsTable(for language: AppLanguage) -> [String: String]? {
        let url = packageRootURL
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("Localization", isDirectory: true)
            .appendingPathComponent("\(language.rawValue).lproj", isDirectory: true)
            .appendingPathComponent("Localizable.strings")
        return NSDictionary(contentsOf: url) as? [String: String]
    }

    private static var settingsViewSourceURL: URL {
        packageRootURL
            .appendingPathComponent("Sources", isDirectory: true)
            .appendingPathComponent("Zisla", isDirectory: true)
            .appendingPathComponent("SettingsView.swift")
    }

    private static var packageRootURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
