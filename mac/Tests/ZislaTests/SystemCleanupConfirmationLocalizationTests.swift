import Foundation
import Testing
import ZislaCore

struct SystemCleanupConfirmationLocalizationTests {
    @Test(arguments: AppLanguage.allCases)
    func cleanupConfirmationsExplainThatTrashCanLaterBeEmptied(language: AppLanguage) throws {
        let keys = try Self.runtimeKeys()
        #expect(keys == [
            "本次操作将项目移入废纸篓；废纸篓之后可能被清空，届时将永久删除。",
            "其中 %ld 项需人工复核。本次操作将项目移入废纸篓；废纸篓之后可能被清空，届时将永久删除。",
        ])
        let tableURL = Self.packageRoot.appendingPathComponent("Resources/Localization/\(language.rawValue).lproj/Localizable.strings")
        let table = try #require(NSDictionary(contentsOf: tableURL) as? [String: String])
        let source = try String(contentsOf: tableURL, encoding: .utf8)
        let placeholder = try NSRegularExpression(pattern: #"%(?:\d+\$)?(?:ld|lu|lld|llu|@|\d*\.?\d*[fd])"#)
        #expect(AppLanguage.allCases.count == 17)
        for key in keys {
            let value = try #require(table[key], "\(language.rawValue) is missing \(key)")
            #expect(!value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(AppLocalization.string(key, locale: language.locale) == value)
            let actualPlaceholders = placeholder.matches(in: value, range: NSRange(value.startIndex..., in: value))
                .compactMap { Range($0.range, in: value).map { String(value[$0]) } }
            #expect(actualPlaceholders == (key.contains("%ld") ? ["%ld"] : []))
            let declaration = try NSRegularExpression(pattern: "^\\s*\"" + NSRegularExpression.escapedPattern(for: key) + "\"\\s*=", options: .anchorsMatchLines)
            #expect(declaration.numberOfMatches(in: source, range: NSRange(source.startIndex..., in: source)) == 1)
            if language != .simplifiedChinese { #expect(value != key) }
            if language != .english && language != .simplifiedChinese && language != .traditionalChinese {
                #expect(value != AppLocalization.string(key, language: .english))
            }
            if key.contains("%ld") {
                for count in [1, 2, 42] {
                    #expect(AppLocalization.format(key, locale: language.locale, [count])
                        == value.replacingOccurrences(of: "%ld", with: String(count)))
                }
            }
        }
        #expect(table["zisla 不会永久删除这些内容。"] == nil)
        #expect(table["其中 %ld 项需人工复核。zisla 不会永久删除这些内容。"] == nil)
    }

    @Test
    func cleanupWarningsUseTheRequestedLanguageAndKeepTheReviewCount() {
        let key = "其中 %ld 项需人工复核。本次操作将项目移入废纸篓；废纸篓之后可能被清空，届时将永久删除。"
        #expect(AppLocalization.format(key, locale: AppLanguage.english.locale, [3])
            == "3 of them need manual review. This action moves items to the Trash. The Trash may be emptied later, permanently deleting them.")
        #expect(AppLocalization.format(key, locale: AppLanguage.french.locale, [2])
            == "Dont 2 nécessitent une vérification manuelle. Cette action déplace les éléments dans la Corbeille. Si elle est vidée ultérieurement, ils seront supprimés définitivement.")
        #expect(AppLocalization.format(key, locale: AppLanguage.traditionalChinese.locale, [1])
            == "其中 1 項需人工複核。本次操作會將項目移入垃圾桶；垃圾桶之後可能被清空，屆時將永久刪除。")
    }

    private static func runtimeKeys() throws -> Set<String> {
        let source = try String(contentsOf: packageRoot.appendingPathComponent("Sources/Zisla/SystemMonitorView.swift"), encoding: .utf8)
        let start = try #require(source.range(of: "cachedManualReviewCount > 0"))
        let end = try #require(source.range(of: "private var selectedByteSize:", range: start.upperBound..<source.endIndex))
        let confirmation = String(source[start.lowerBound..<end.lowerBound])
        let calls = try NSRegularExpression(pattern: #"AppLocalization\.text\("([^"]+)""#)
        return Set(calls.matches(in: confirmation, range: NSRange(confirmation.startIndex..., in: confirmation)).map {
            String(confirmation[Range($0.range(at: 1), in: confirmation)!])
        })
    }

    private static var packageRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }
}
