import Foundation
import Testing
import ZislaCore

struct ApplicationInstallationCleanupLocalizationTests {
    @Test(arguments: AppLanguage.allCases)
    func everyLanguageRendersInstallationDetailsWithTheVersionAndPaths(language: AppLanguage) throws {
        let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: packageRoot.appendingPathComponent("Sources/ZislaKit/ApplicationInstallationCleanup.swift"), encoding: .utf8)
        let calls = try NSRegularExpression(pattern: #"AppLocalization\.text\("([^"]+)""#)
        var keys = calls.matches(in: source, range: NSRange(source.startIndex..., in: source)).map {
            String(source[Range($0.range(at: 1), in: source)!])
        }
        #expect(keys.count == 2)
        keys.append("应用副本或当前版本状态已变化，已保留目标")
        let tableURL = packageRoot.appendingPathComponent("Resources/Localization/\(language.rawValue).lproj/Localizable.strings")
        let table = try #require(NSDictionary(contentsOf: tableURL) as? [String: String])
        for key in keys {
            let value = try #require(table[key], "Missing \(language.rawValue) installation detail: \(key)")
            let count = key.contains("%@") ? 3 : 0
            #expect(value.components(separatedBy: "%@").count == count + 1)
            #expect(AppLocalization.string(key, locale: language.locale) == value)
            let fields = Array(["157.0.8103.52", "/Applications/Chrome 2.app", "/Applications/Chrome.app"].prefix(count))
            let rendered = AppLocalization.format(key, locale: language.locale, fields.map { $0 as CVarArg })
            #expect(fields.allSatisfy(rendered.contains))
            #expect(!rendered.contains("%@"))
            if language != .simplifiedChinese { #expect(value != key) }
            if language != .english && language != .simplifiedChinese && language != .traditionalChinese {
                #expect(value != AppLocalization.string(key, language: .english))
            }
        }
    }
}
