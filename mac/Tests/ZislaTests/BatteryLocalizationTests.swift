import Foundation
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

/// 电池链路文案统一走 `BatteryLocalization`：任一语言缺 key 都会让界面静默退回中文原文，
/// 因此这里从源码扫出运行时真正查询的 key，再逐语言核对资源，让新增文案漏翻译时测试先失败。
struct BatteryLocalizationTests {
    @Test
    func historyTextUsesRequestedLanguage() {
        let now = Date(timeIntervalSince1970: 10_000)

        #expect(
            BatteryLocalization.historyText(
                lastUnpluggedAt: now.addingTimeInterval(-30 * 60),
                now: now,
                locale: Locale(identifier: "en")
            ) == "On battery 30 min"
        )
        #expect(
            BatteryLocalization.historyText(
                lastUnpluggedAt: now.addingTimeInterval(-90 * 60),
                now: now,
                locale: Locale(identifier: "ja")
            ) == "バッテリー駆動 1時間30分"
        )
        #expect(
            BatteryLocalization.historyText(
                lastUnpluggedAt: nil,
                now: now,
                locale: Locale(identifier: "en")
            ) == nil
        )
    }

    @Test
    func statusTextUsesRequestedLanguage() {
        let onBattery = BatterySnapshot(
            level: 0.4,
            isCharging: false,
            isPluggedIn: false,
            isCharged: false,
            timeRemainingMinutes: 95
        )
        let english = Locale(identifier: "en")

        #expect(BatteryLocalization.summaryStatusText(onBattery, locale: english) == "On battery")
        #expect(BatteryLocalization.detailStatusText(onBattery, locale: english) == "95 min left")
    }

    @Test
    func everyLanguageTranslatesBatteryKeys() throws {
        let keys = try Self.batteryLocalizationKeys()
        #expect(keys.count >= 50, "key 扫描失效，只找到 \(keys.count) 个")

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

    /// 这些 key 由 `ZislaKit` 枚举的 `displayName` 和设置项文案间接传入，无法从调用点扫出。
    private static let indirectKeys = [
        "蓝牙", "已授权设备", "鼠标", "键盘", "触控板", "配件", "未知设备",
        "设备", "左", "右", "盒",
        "电池监控", "显示电池详细信息与健康状态",
    ]

    private static let localizedSourceFiles = [
        "BatteryLocalization.swift",
        "BatteryDetailView.swift",
        "LockScreenModuleView.swift",
        "LockScreenOverlayView.swift",
        "SideNoticeView.swift",
    ]

    private static func batteryLocalizationKeys() throws -> [String] {
        let call = try NSRegularExpression(
            pattern: #"(?:BatteryLocalization\.)?(?:localized|string|format)\(([^()]*)\)"#
        )
        let literal = try NSRegularExpression(pattern: #""((?:[^"\\]|\\.)*)""#)
        var keys = Set(indirectKeys)

        for name in localizedSourceFiles {
            let source = try String(
                contentsOf: sourcesURL.appendingPathComponent("Zisla/\(name)"),
                encoding: .utf8
            )
            for match in call.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
                guard let argumentsRange = Range(match.range(at: 1), in: source) else { continue }
                let arguments = String(source[argumentsRange])
                let argumentsRangeAll = NSRange(arguments.startIndex..., in: arguments)
                for hit in literal.matches(in: arguments, range: argumentsRangeAll) {
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
