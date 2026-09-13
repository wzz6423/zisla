import Foundation
import Testing
import ZislaCore

struct ToolboxClockLocalizationTests {
    @Test(arguments: AppLanguage.allCases)
    func systemClockEntryIsTranslated(language: AppLanguage) throws {
        let packageURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: packageURL.appendingPathComponent("Sources/Zisla/ToolboxModuleView.swift"),
            encoding: .utf8
        )
        let start = try #require(source.range(of: "private var focusPanel: some View"))
        let end = try #require(source.range(of: "private var toolActions: some View"))
        let panel = String(source[start.lowerBound..<end.lowerBound])
        let expression = try NSRegularExpression(pattern: #"AppLocalization\.text\("([^"]+)"\)"#)
        let keys = expression.matches(in: panel, range: NSRange(panel.startIndex..., in: panel))
            .compactMap { match in
                Range(match.range(at: 1), in: panel).map { String(panel[$0]) }
            }
        #expect(!keys.isEmpty, "系统时钟入口应使用本地化文案")

        let tableURL = packageURL.appendingPathComponent(
            "Resources/Localization/\(language.rawValue).lproj/Localizable.strings"
        )
        let table = try #require(NSDictionary(contentsOf: tableURL) as? [String: String])
        for key in keys {
            let translation = try #require(table[key], "\(language.rawValue) 缺少「\(key)」")
            #expect(!translation.isEmpty)
            #expect(AppLocalization.string(key, language: language) == translation)
        }
    }
}
