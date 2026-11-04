import AppKit
import Foundation
import Testing
import ZislaCore

struct UserCareLocalizationTests {
    @Test(arguments: AppLanguage.allCases)
    func everyLanguageContainsAndRendersAllUserCareCopy(language: AppLanguage) throws {
        let keys = Self.reminderKeys + ["用户关怀", "连续使用 45 分钟后，温柔提醒休息、喝水和走动"]
        #expect(AppLanguage.allCases.count == 17)
        #expect(Set(keys).count == 18)
        let table = try Self.table(language)
        let english = try Self.table(.english)
        for key in keys {
            let value = try #require(table[key], "Missing \(language.rawValue) translation for \(key)")
            #expect(!value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(!value.contains("%"), "User care copy must not introduce format placeholders")
            #expect(AppLocalization.string(key, locale: language.locale) == value)
            if language != .simplifiedChinese && language != .traditionalChinese {
                #expect(value != key, "Untranslated Chinese in \(language.rawValue): \(key)")
            }
            if language != .english && language != .simplifiedChinese && language != .traditionalChinese {
                #expect(value != english[key], "Copied English in \(language.rawValue): \(key)")
            }
        }
        for reminder in UserCareReminder.allCases {
            let ordinary = AppLocalization.string(reminder.localizationKey(petEnabled: false), language: language)
            let pet = AppLocalization.string(reminder.localizationKey(petEnabled: true), language: language)
            #expect(ordinary != pet, "Pet and ordinary voices must differ in \(language.rawValue)")
        }
    }

    @Test
    func requestedLanguagesProduceExpectedReminderVoices() {
        #expect(AppLocalization.string("用户关怀", language: .english) == "Wellbeing")
        #expect(AppLocalization.string("用户关怀", language: .traditionalChinese) == "使用者關懷")
        #expect(AppLocalization.string("用户关怀", language: .arabic) == "العناية بك")
        #expect(AppLocalization.string(UserCareReminder.water.localizationKey(petEnabled: false), language: .english)
            == "Have a sip of water. Take your time.")
        #expect(AppLocalization.string(UserCareReminder.water.localizationKey(petEnabled: true), language: .english)
            == "Human, have some water. I'll wait.")
        #expect(AppLocalization.string(UserCareReminder.bedtime.localizationKey(petEnabled: true), language: .arabic)
            == "يا صديقي الإنسان، تأخر الوقت. لنذهب ونرتاح.")
        for reminder in UserCareReminder.allCases {
            #expect(reminder.localizationKey(petEnabled: true).hasPrefix("人，"))
            #expect(!reminder.localizationKey(petEnabled: false).hasPrefix("人，"))
        }
    }

    @MainActor
    @Test(arguments: AppLanguage.allCases)
    func existingMessageScrollCanReachEveryReminderWithinItsSixSecondLifetime(language: AppLanguage) {
        let font = NSFont.systemFont(ofSize: 11, weight: .medium)
        let availableWidth: CGFloat = 252 - 22 - 8 - 24
        for key in Self.reminderKeys {
            let value = AppLocalization.string(key, language: language)
            let textWidth = (value as NSString).size(withAttributes: [.font: font]).width
            let travel = max(0, textWidth - availableWidth + 16)
            let duration = max(3, Double(travel) / 90)
            #expect(duration <= 6, "\(language.rawValue) reminder needs \(duration) seconds to reveal its final words")
        }
    }

    private static var reminderKeys: [String] {
        UserCareReminder.allCases.flatMap { reminder in
            [false, true].map { reminder.localizationKey(petEnabled: $0) }
        }
    }

    private static func table(_ language: AppLanguage) throws -> [String: String] {
        let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try #require(NSDictionary(contentsOf: packageRoot.appendingPathComponent(
            "Resources/Localization/\(language.rawValue).lproj/Localizable.strings"
        )) as? [String: String])
    }
}
