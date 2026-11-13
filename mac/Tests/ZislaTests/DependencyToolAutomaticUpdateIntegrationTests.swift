import Foundation
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

struct DependencyToolAutomaticUpdateIntegrationTests {
    @Test(arguments: AppLanguage.allCases, [false, true])
    func dependencySearchAlwaysTargetsTheIndependentFeatureRow(language: AppLanguage, recommendationsVisible: Bool) {
        let settings = FeatureSettings(recommendedToolsEnabled: recommendationsVisible)
        let query = AppLocalization.string("自动更新依赖组件", locale: language.locale)
        let matches = SettingsSearchIndex.results(for: query, settings: settings, locale: language.locale)
        #expect(matches.first?.section == .features)
        #expect(matches.first?.anchor == .row("自动更新依赖组件"))
        #expect(SettingsSearchAnchor.row("自动更新依赖组件").localized(locale: language.locale) == .row(query))
    }

    @Test(arguments: AppLanguage.allCases)
    func dependencyUpdateLabelsHaveRuntimeTranslations(language: AppLanguage) throws {
        let file = Self.packageRoot.appendingPathComponent("Resources/Localization/\(language.rawValue).lproj/Localizable.strings")
        let table = try #require(NSDictionary(contentsOf: file) as? [String: String])
        let source = try String(contentsOf: file, encoding: .utf8)
        for key in ["自动更新依赖组件", "每天更新已安装的依赖组件"] {
            let value = try #require(table[key], "\(language.rawValue) is missing \(key)")
            #expect(!value.isEmpty)
            #expect(!value.contains("%"))
            #expect(AppLocalization.string(key, language: language) == value)
            let expression = try NSRegularExpression(pattern: "^\\s*\"" + NSRegularExpression.escapedPattern(for: key) + "\"\\s*=", options: .anchorsMatchLines)
            #expect(expression.numberOfMatches(in: source, range: NSRange(source.startIndex..., in: source)) == 1)
            if language != .simplifiedChinese { #expect(value != key) }
            if ![AppLanguage.simplifiedChinese, .traditionalChinese, .english].contains(language) {
                #expect(value != AppLocalization.string(key, language: .english), "\(language.rawValue) copied English for \(key)")
            }
        }
    }

    private static var packageRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }
}
