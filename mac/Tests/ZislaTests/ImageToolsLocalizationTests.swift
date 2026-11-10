import Foundation
import Testing
import ZislaCore
import ZislaKit
@testable import Zisla

struct ImageToolsLocalizationTests {
    @Test(arguments: AppLanguage.allCases)
    func imageToolsLabelsAndFailuresUseEveryRequestedLanguage(language: AppLanguage) throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let paths = ["Sources/Zisla/ImageToolsModuleView.swift", "Sources/Zisla/ImageToolsModel.swift",
                     "Sources/ZislaKit/ImageProcessingService.swift", "Sources/ZislaKit/ImageProcessingOptions.swift"]
        let expression = try NSRegularExpression(pattern: #""([^"\n]*[\u4e00-\u9fff][^"\n]*)""#)
        var keys = Set<String>()
        for path in paths {
            let source = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
            keys.formUnion(expression.matches(in: source, range: NSRange(source.startIndex..., in: source))
                .compactMap { Range($0.range(at: 1), in: source).map { String(source[$0]) } })
        }
        keys.formUnion([SettingsSection.imageTools.title, SettingsSection.imageTools.subtitle, ManagedTool.libvips.purpose, ManagedTool.libavif.purpose])
        #expect(keys.count >= 50)
        let tableURL = root.appendingPathComponent("Resources/Localization/\(language.rawValue).lproj/Localizable.strings")
        let table = try #require(NSDictionary(contentsOf: tableURL) as? [String: String])
        let english = try #require(NSDictionary(contentsOf: root.appendingPathComponent("Resources/Localization/en.lproj/Localizable.strings")) as? [String: String])
        let placeholders = try NSRegularExpression(pattern: #"%(?:\d+\$)?[-+0-9.]*l?[@df]"#)
        func markers(_ value: String) -> [String] {
            placeholders.matches(in: value, range: NSRange(value.startIndex..., in: value))
                .compactMap { Range($0.range, in: value).map { String(value[$0]) } }
        }
        for key in keys {
            let value = try #require(table[key], "\(language.rawValue) is missing \(key)")
            #expect(!value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(markers(value) == markers(key))
            #expect(AppLocalization.string(key, locale: language.locale) == value)
            if language != .english && language != .simplifiedChinese,
               [SettingsSection.imageTools.title, SettingsSection.imageTools.subtitle, ImageToolOperation.compress.detail,
                ImageToolOperation.convert.detail, ImageToolOperation.resize.detail, ImageToolOperation.smallest.detail].contains(key) {
                #expect(value != english[key], "\(language.rawValue) copied the English text for \(key)")
            }
        }
    }
}
