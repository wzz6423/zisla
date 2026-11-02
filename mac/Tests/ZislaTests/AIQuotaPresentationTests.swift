import Foundation
import Testing
import ZislaCore
@testable import Zisla

struct AIQuotaPresentationTests {
    @Test func allSeventeenLanguagesTranslateQuotaKeysAndPreservePlaceholders() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let keys = ["剩余额度", "套餐额度", "5 小时额度", "每周额度", "试用额度", "额度重置：%@"]
        #expect(AppLanguage.allCases.count == 17)
        for language in AppLanguage.allCases {
            let file = root.appendingPathComponent("Resources/Localization/\(language.rawValue).lproj/Localizable.strings")
            let table = try #require(NSDictionary(contentsOf: file) as? [String: String])
            for key in keys {
                let value = try #require(table[key], "\(language.rawValue): \(key)")
                #expect(!value.isEmpty)
                if language != .simplifiedChinese { #expect(value != key) }
                #expect(value.components(separatedBy: "%@").count == key.components(separatedBy: "%@").count)
                #expect(AppLocalization.string(key, language: language) == value)
            }
        }
        #expect(AIQuotaPresentation.windowKey(.plan) == "套餐额度")
        #expect(AIQuotaPresentation.windowKey(.fiveHours) == "5 小时额度")
        #expect(AIQuotaPresentation.windowKey(.weekly) == "每周额度")
        #expect(AIQuotaPresentation.windowKey(.trial) == "试用额度")
    }

    @Test func quotaHelpUsesSelectedLanguageForNumbersAndResetAndHandlesAbsentReset() {
        let quota = AIQuotaSnapshot(provider: .cursor, window: .plan, usedPercent: 25,
            resetsAt: Date(timeIntervalSince1970: 2_000_000_000), checkedAt: .distantPast)
        let english = AIQuotaPresentation.helpText(quota, locale: AppLanguage.english.locale)
        #expect(english.contains("75%") && english.contains("Quota resets:"))
        let chinese = AIQuotaPresentation.helpText(quota, locale: AppLanguage.simplifiedChinese.locale)
        #expect(chinese.contains("额度重置："))
        let arabic = AIQuotaPresentation.helpText(quota, locale: AppLanguage.arabic.locale)
        #expect(arabic.contains(AppLocalization.string("额度重置：%@", language: .arabic).replacingOccurrences(of: "%@", with: "")))
        var trial = quota
        trial.resetsAt = nil
        #expect(!AIQuotaPresentation.helpText(trial, locale: AppLanguage.english.locale).contains("resets"))
    }
}
