import Foundation
import Testing
import ZislaCore

@testable import Zisla

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
        let titleStart = try #require(source.range(of: "private var startPauseTitle: String"))
        let titleEnd = try #require(source.range(of: "private var toolTogglesRow: some View"))
        let service = try String(
            contentsOf: packageURL.appendingPathComponent("Sources/ZislaKit/SystemClockService.swift"),
            encoding: .utf8
        )
        let timerSource = panel + source[titleStart.lowerBound..<titleEnd.lowerBound] + service
        let expression = try NSRegularExpression(pattern: #"AppLocalization\.text\("([^"]+)""#)
        let keys = expression.matches(in: timerSource, range: NSRange(timerSource.startIndex..., in: timerSource))
            .compactMap { match in
                Range(match.range(at: 1), in: timerSource).map { String(timerSource[$0]) }
            }
        #expect(!keys.isEmpty, "系统时钟入口应使用本地化文案")
        let durationExpression = try NSRegularExpression(pattern: #"durationInput\("([^"]+)""#)
        let durationKeys = durationExpression.matches(in: panel, range: NSRange(panel.startIndex..., in: panel))
            .compactMap { match in
                Range(match.range(at: 1), in: panel).map { String(panel[$0]) }
            }
        #expect(durationKeys == ["小时", "分钟", "秒"])

        let tableURL = packageURL.appendingPathComponent(
            "Resources/Localization/\(language.rawValue).lproj/Localizable.strings"
        )
        let table = try #require(NSDictionary(contentsOf: tableURL) as? [String: String])
        for key in Set(keys + durationKeys + ["闹钟", "打开系统「时钟」App"]) {
            let translation = try #require(table[key], "\(language.rawValue) 缺少「\(key)」")
            #expect(!translation.isEmpty)
            #expect(AppLocalization.string(key, language: language) == translation)
            #expect(translation.components(separatedBy: "%@").count == key.components(separatedBy: "%@").count)
        }
    }
}

@MainActor
struct ToolboxClockDurationTests {
    nonisolated private static let durationCases: [(Int, Int, Int, Int)] = [
        (0, 0, 0, 1),
        (-1, -2, -3, 1),
        (0, 0, 1, 1),
        (1, 2, 3, 3_723),
        (0, 61, 70, 3_730),
        (-1, 1, 30, 90),
        (1, -1, -1, 3_600),
        (Int.max, 0, 0, Int.max / 2),
        (0, Int.max, 0, Int.max / 2),
        (0, 0, Int.max, Int.max / 2),
        (Int.max / 3_600, 31, 0, Int.max / 2),
        (0, Int.max / 60, 8, Int.max / 2),
        (Int.max / 2 / 3_600 + 1, 0, 0, Int.max / 2),
    ]

    @Test(arguments: ToolboxClockDurationTests.durationCases)
    func durationInputsStayPositiveAndBounded(hours: Int, minutes: Int, seconds: Int, expected: Int) {
        #expect(ToolboxModuleView.durationSeconds(hours: hours, minutes: minutes, seconds: seconds) == expected)
    }
}
