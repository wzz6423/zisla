import Foundation
import Testing
import ZislaCore

struct ClipboardLinkDetectionLocalizationTests {
    @Test
    func clipboardLinkDetectionSettingCopyIsTranslatedForEveryLanguage() throws {
        let keys = try Self.clipboardLinkDetectionKeys()
        #expect(keys == ["剪贴板链接检测", "发现链接时提示"])

        for language in AppLanguage.allCases {
            let table = try #require(
                Self.stringsTable(for: language),
                "无法解析 \(language.rawValue) 的 Localizable.strings"
            )
            for key in keys {
                let translation = try #require(table[key], "\(language.rawValue) 缺少「\(key)」")
                #expect(!translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if language != .simplifiedChinese {
                    #expect(translation != key, "\(language.rawValue) 的「\(key)」没有译文")
                }
            }
        }
    }

    private static func clipboardLinkDetectionKeys() throws -> [String] {
        let source = try String(contentsOf: settingsViewSourceURL, encoding: .utf8)
        let expression = try NSRegularExpression(
            pattern: #"featureToggle\(AppLocalization\.text\("([^"]*)"\), detail: "([^"]*)", symbol: "clipboard\.fill", keyPath: \\.clipboardDetectionEnabled\)"#
        )
        let matches = expression.matches(in: source, range: NSRange(source.startIndex..., in: source))
        let match = try #require(matches.first)
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
