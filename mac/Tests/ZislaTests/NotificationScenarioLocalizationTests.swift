import Foundation
import Testing
import ZislaCore
import ZislaKit
@testable import Zisla

struct NotificationScenarioLocalizationTests {
    @Test(arguments: AppLanguage.allCases)
    func runtimeScenarioSettingsAndReviewKeysHaveTranslationsAndMatchingPlaceholders(language: AppLanguage) throws {
        let keys = try runtimeKeys()
        #expect(keys.count == 22)
        let table = try #require(NSDictionary(contentsOf: Self.packageRoot.appendingPathComponent(
            "Resources/Localization/\(language.rawValue).lproj/Localizable.strings")) as? [String: String])
        for key in keys {
            let translation = try #require(table[key], "Missing \(key) in \(language.rawValue)")
            #expect(!translation.isEmpty)
            #expect(placeholders(translation) == placeholders(key), "Incorrect placeholders in \(language.rawValue): \(key)")
            #expect(AppLocalization.string(key, language: language) == translation)
            if language != .simplifiedChinese && language != .traditionalChinese { #expect(translation != key) }
            if language != .english && language != .simplifiedChinese && language != .traditionalChinese {
                #expect(translation != AppLocalization.string(key, language: .english))
            }
        }
    }

    @Test
    func requestedLocaleFormatsTheReviewSummaryAndPreservesRTLDirection() {
        #expect(AppLanguage.allCases.count == 17)
        #expect(AppLocalization.string("场景通知策略", language: .english) == "Scenario Notification Rules")
        #expect(AppLocalization.format("已延后 %ld 条提示", locale: AppLanguage.english.locale, [3]) == "3 alerts deferred")
        #expect(AppLocalization.string("点击回顾", language: .arabic) == "انقر للمراجعة")
        #expect(AppLanguage.arabic.isRightToLeft)
        #expect(AppLanguage.allCases.filter(\.isRightToLeft) == [.arabic])
    }

    @Test(arguments: AppLanguage.allCases, [false, true])
    func searchFindsTheOptInRuleAndMeetingControlsOnlyAfterEnabling(language: AppLanguage, enabled: Bool) {
        let settings = FeatureSettings(notificationScenarios: .init(enabled: enabled))
        let query = AppLocalization.string("场景通知策略", language: language)
        let results = SettingsSearchIndex.results(for: query, settings: settings, locale: language.locale)
        #expect(results.contains { $0.anchor == .group("场景通知策略") && $0.section == .info })
        #expect(SettingsSearchIndex.items(settings: settings).contains { $0.title == "按日历自动开启会议场景" } == enabled)
        #expect(SettingsSearchIndex.items(settings: settings).contains { $0.title == "手动开启会议场景" } == enabled)
    }

    private func runtimeKeys() throws -> Set<String> {
        let settingsSource = try String(contentsOf: Self.packageRoot.appendingPathComponent(
            "Sources/Zisla/NotificationScenarioSettingsView.swift"), encoding: .utf8)
        let reviewSource = try String(contentsOf: Self.packageRoot.appendingPathComponent(
            "Sources/Zisla/ScenarioNotificationReviewView.swift"), encoding: .utf8)
        let queueSource = try String(contentsOf: Self.packageRoot.appendingPathComponent(
            "Sources/ZislaKit/SideNoticeQueue.swift"), encoding: .utf8)
        let calls = try NSRegularExpression(pattern: #"(?:row|AppLocalizedText|AppLocalization\.text)\("((?:[^"\\]|\\.)*)""#)
        var result: Set<String> = []
        for source in [settingsSource, reviewSource, queueSource] {
            for match in calls.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
                if let range = Range(match.range(at: 1), in: source) { result.insert(String(source[range])) }
            }
        }
        result.remove("显示器 %ld")
        result.formUnion(NotificationScenario.allCases.map(\.title))
        result.formUnion(ScenarioNotificationBehavior.allCases.map(\.title))
        result.formUnion(["仅管理 Zisla 提示，不更改系统专注模式", "以含会议链接的日程时间为准，不代表实际参会",
            "日历会议场景已生效", "仅本次运行有效，退出后关闭", "等待操作、失败、安全与低电量", "为此显示器单独设置"])
        return result
    }

    private func placeholders(_ text: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: #"%(?:ld|@|\d*\.?\d*[fd])"#)
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map {
            String(text[Range($0.range, in: text)!])
        }.sorted()
    }

    private static var packageRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }
}
