import Foundation
import Testing
import ZislaCore

struct AlarmNotificationLocalizationTests {
    private static let failureKey = "无法设置闹钟通知：%@"
    private static let keys = [
        "闹钟通知未获允许，请在系统设置中开启通知。",
        "闹钟通知声音已关闭，请在系统设置中开启声音。",
        failureKey,
        "此处的闹钟不会同步到系统「时钟」。",
    ]

    @Test(arguments: AppLanguage.allCases)
    func alarmNotificationMessagesUseRequestedLanguage(language: AppLanguage) throws {
        let packageURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let tableURL = packageURL.appendingPathComponent(
            "Resources/Localization/\(language.rawValue).lproj/Localizable.strings"
        )
        let table = try #require(NSDictionary(contentsOf: tableURL) as? [String: String])
        let placeholder = try NSRegularExpression(pattern: #"%(?:ld|@|\d*\.?\d*[fd])"#)

        for key in Self.keys {
            let translation = try #require(table[key], "\(language.rawValue) 缺少「\(key)」")
            #expect(!translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            let placeholders = [key, translation].map { text in
                placeholder.matches(in: text, range: NSRange(text.startIndex..., in: text))
                    .compactMap { Range($0.range, in: text).map { String(text[$0]) } }
            }
            try #require(placeholders[0] == placeholders[1], "\(language.rawValue) 的「\(key)」占位符不一致")
            try #require(
                translation.components(separatedBy: "%").count == key.components(separatedBy: "%").count,
                "\(language.rawValue) 的「\(key)」包含额外格式标记"
            )
            #expect(AppLocalization.string(key, language: language) == translation)
            if language != .simplifiedChinese {
                #expect(translation != key, "\(language.rawValue) 的「\(key)」仍是简体中文")
            }
            if language != .english && language != .simplifiedChinese {
                #expect(
                    translation != AppLocalization.string(key, language: .english),
                    "\(language.rawValue) 的「\(key)」仍是英文"
                )
            }
        }

        let failureFormat = try #require(table[Self.failureKey])
        let detail = "fixture-error"
        let displayedDetail = language == .arabic ? "\u{2068}\(detail)\u{2069}" : detail
        #expect(
            AppLocalization.format(Self.failureKey, locale: language.locale, [detail])
                == failureFormat.replacingOccurrences(of: "%@", with: displayedDetail)
        )
    }
}
