import Foundation
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

/// 系统监控历史链路的文案统一走 `AppLocalization`：缺 key 只会静默回落中文原文，构建和 `tsc`
/// 都不报错，因此这里从源码扫出运行时真正查询的 key，再逐语言核对资源，让漏翻译在测试里先失败。
struct SystemMetricsHistoryLocalizationTests {
    @Test
    func spanTextIsLocalizedAndClamped() {
        #expect(SystemMetricsHistoryPresentation.spanText(5_400, language: .english) == "1h 30m")
        #expect(SystemMetricsHistoryPresentation.spanText(7 * 24 * 3600, language: .english) == "7d")
        // 少于一分钟的区间按一分钟显示，避免出现 0。
        #expect(SystemMetricsHistoryPresentation.spanText(0, language: .english) == "1m")
        #expect(SystemMetricsHistoryPresentation.spanText(120, language: .simplifiedChinese).contains("分钟"))
    }

    @Test
    func rateTextUsesByteUnits() {
        let text = SystemMetricsHistoryPresentation.rateText(1_500_000)
        #expect(text.hasSuffix("/s"))
        #expect(text.contains("MB"))
    }

    @Test
    func everyLanguageTranslatesHistoryKeys() throws {
        let keys = try Self.historyKeys()
        #expect(keys.count >= 60, "key 扫描失效，只找到 \(keys.count) 个")

        for language in AppLanguage.allCases {
            let table = try #require(
                Self.stringsTable(for: language),
                "无法解析 \(language.rawValue) 的 Localizable.strings"
            )
            for key in keys {
                let value = try #require(table[key], "\(language.rawValue) 缺少「\(key)」")
                #expect(
                    Self.placeholders(in: value) == Self.placeholders(in: key),
                    "\(language.rawValue) 的「\(key)」占位符不一致：\(value)"
                )
            }
        }
    }

    /// 抽查具体译文：只校验 key 存在无法发现「整块照抄中文」的漏翻。
    @Test
    func historyCopyIsActuallyTranslated() throws {
        let english = try #require(Self.stringsTable(for: .english))
        #expect(english["查看历史记录"] == "View History")
        #expect(english["导出"] == "Export")
        #expect(english["24 小时"] == "24 hours")
        #expect(english["读"] == "Read")
        #expect(english["写"] == "Write")
        #expect(english["上传"] == "Upload")

        let japanese = try #require(Self.stringsTable(for: .japanese))
        #expect(japanese["查看历史记录"] == "履歴を表示")
        #expect(japanese["系统历史"] == "システム履歴")
        #expect(japanese["风扇 %ld"] == "ファン %ld")
    }

    /// 这些 key 由 `ZislaKit` 的枚举与图表模型间接传入，无法从视图调用点直接扫出。
    private static func modelKeys() -> [String] {
        var keys = SystemMetricsHistoryRange.allCases.map(\.titleKey)
        keys += ["记录历史", "按分钟记录 CPU、GPU、内存、硬盘、风扇与网络，可随时查看趋势并导出表格"]

        let records = [
            SystemMetricsRecord(
                timestamp: Date(timeIntervalSince1970: 1_000),
                gpuUsage: 0.5,
                fanRPMs: [1_000, 1_100, 1_200]
            ),
            SystemMetricsRecord(
                timestamp: Date(timeIntervalSince1970: 1_060),
                gpuUsage: 0.6,
                fanRPMs: [1_050, 1_150, 1_250]
            ),
        ]
        let sections = SystemMetricsHistorySeriesBuilder.sections(
            records: records,
            range: .all,
            now: Date(timeIntervalSince1970: 1_060)
        )
        keys += sections.flatMap { [$0.titleKey] + $0.series.map(\.titleKey) }
        return keys
    }

    private static let localizedSourceFiles = [
        "IslandRootView.swift",
        "SystemMonitorView.swift",
        "SystemMetricsHistoryView.swift",
    ]

    private static func historyKeys() throws -> [String] {
        let call = try NSRegularExpression(pattern: #"AppLocalization\.text\(([^()]*)\)"#)
        let literal = try NSRegularExpression(pattern: #""((?:[^"\\]|\\.)*)""#)
        var keys = Set(modelKeys())

        for name in localizedSourceFiles {
            let source = try String(
                contentsOf: sourcesURL.appendingPathComponent("Zisla/\(name)"),
                encoding: .utf8
            )
            for match in call.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
                guard let argumentsRange = Range(match.range(at: 1), in: source) else { continue }
                let arguments = String(source[argumentsRange])
                for hit in literal.matches(in: arguments, range: NSRange(arguments.startIndex..., in: arguments)) {
                    guard let keyRange = Range(hit.range(at: 1), in: arguments) else { continue }
                    keys.insert(String(arguments[keyRange]))
                }
            }
        }
        return keys.sorted()
    }

    private static func stringsTable(for language: AppLanguage) -> [String: String]? {
        let url = localizationURL
            .appendingPathComponent("\(language.rawValue).lproj", isDirectory: true)
            .appendingPathComponent("Localizable.strings")
        return NSDictionary(contentsOf: url) as? [String: String]
    }

    private static func placeholders(in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"%(?:ld|@|\d*\.?\d*[fd])"#) else { return [] }
        return regex
            .matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap { Range($0.range, in: text).map { String(text[$0]) } }
            .sorted()
    }

    private static var sourcesURL: URL {
        packageRootURL.appendingPathComponent("Sources", isDirectory: true)
    }

    private static var localizationURL: URL {
        packageRootURL
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
