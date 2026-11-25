import Foundation
import Testing
import ZislaCore

struct ToolboxLocalizationTests {
    private static let timerKeys: Set<String> = ["开始", "暂停", "取消", "小时", "分钟", "秒", "计时器名称", "添加计时器"]

    @Test(arguments: AppLanguage.allCases)
    func timerLabelsUseRequestedLanguage(language: AppLanguage) throws {
        let source = try Self.toolboxSource()
        let call = try NSRegularExpression(pattern: #"(?:AppLocalization\.text|durationInput)\("([^"]+)""#)
        let queriedKeys = Set(call.matches(in: source, range: NSRange(source.startIndex..., in: source))
            .compactMap { Range($0.range(at: 1), in: source).map { String(source[$0]) } })
            .union(["开始", "暂停"])
        #expect(Self.timerKeys.isSubset(of: queriedKeys))

        let tableURL = Self.packageURL.appendingPathComponent(
            "Resources/Localization/\(language.rawValue).lproj/Localizable.strings"
        )
        let table = try #require(NSDictionary(contentsOf: tableURL) as? [String: String])
        for key in Self.timerKeys {
            let translation = try #require(table[key], "\(language.rawValue) 缺少「\(key)」")
            #expect(!translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(!translation.contains("%"), "\(language.rawValue) 的「\(key)」包含额外格式标记")
            #expect(AppLocalization.string(key, locale: language.locale) == translation)
        }

        if language == .english {
            #expect(AppLocalization.string("开始", locale: language.locale) == "Start")
            #expect(AppLocalization.string("暂停", locale: language.locale) == "Pause")
        }
        if language == .arabic {
            #expect(AppLocalization.string("开始", locale: language.locale) == "بدء")
            #expect(AppLocalization.string("暂停", locale: language.locale) == "إيقاف مؤقت")
        }
    }

    @Test(arguments: AppLanguage.allCases)
    func independentCountdownNamesAndCompletionMessagesCoverEveryLanguage(language: AppLanguage) throws {
        let table = try #require(NSDictionary(contentsOf: Self.packageURL.appendingPathComponent(
            "Resources/Localization/\(language.rawValue).lproj/Localizable.strings"
        )) as? [String: String])
        for key in ["计时器", "计时结束", "计时器名称", "添加计时器", "取消"] {
            let translation = try #require(table[key], "Missing \(key) in \(language.rawValue)")
            #expect(!translation.isEmpty && !translation.contains("%"))
            #expect(AppLocalization.string(key, locale: language.locale) == translation)
            if language != .simplifiedChinese && language != .traditionalChinese { #expect(translation != key) }
        }
        if language == .english {
            #expect(AppLocalization.string("添加计时器", locale: language.locale) == "Add timer")
            #expect(AppLocalization.string("计时结束", locale: language.locale) == "Timer finished")
        }
        if language == .arabic {
            #expect(AppLocalization.string("计时器", locale: language.locale) == "مؤقت")
            #expect(AppLocalization.string("计时结束", locale: language.locale) == "انتهى المؤقت")
        }
    }

    private static func toolboxSource() throws -> String {
        try String(
            contentsOf: packageURL.appendingPathComponent("Sources/Zisla/ToolboxModuleView.swift"),
            encoding: .utf8
        )
    }

    private static var packageURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
