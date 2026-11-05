import AppKit
import Foundation
import Testing
import ZislaCore

struct UserCareLocalizationTests {
    @Test(arguments: AppLanguage.allCases)
    func everyLanguageContainsAndRendersAllUserCareCopy(language: AppLanguage) throws {
        let careKeys = Self.reminderKeys + [
            "用户关怀", "温柔提醒休息、喝水和走动", "关怀提醒间隔",
            "小时 0–99，分、秒 0–59，总时长至少 1 秒",
        ]
        let keys = careKeys + ["小时", "分钟", "秒", "保存"]
        #expect(AppLanguage.allCases.count == 17)
        #expect(Set(keys).count == keys.count)
        let table = try Self.table(language)
        let english = try Self.table(.english)
        for key in keys {
            let value = try #require(table[key], "Missing \(language.rawValue) translation for \(key)")
            #expect(!value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(!value.contains("%"), "User care copy must not introduce format placeholders")
            #expect(AppLocalization.string(key, locale: language.locale) == value)
            if careKeys.contains(key) && language != .simplifiedChinese && language != .traditionalChinese {
                #expect(value != key, "Untranslated Chinese in \(language.rawValue): \(key)")
            }
            if careKeys.contains(key) && language != .english && language != .simplifiedChinese && language != .traditionalChinese {
                #expect(value != english[key], "Copied English in \(language.rawValue): \(key)")
            }
        }
        for reminder in UserCareReminder.allCases {
            let ordinary = reminder.localizedMessage(petEnabled: false, language: language)
            let pet = reminder.localizedMessage(petEnabled: true, language: language)
            #expect(ordinary != pet, "Pet and ordinary voices must differ in \(language.rawValue)")
            for petEnabled in [false, true] {
                let body = try #require(table[reminder.localizationKey(petEnabled: petEnabled)])
                let message = reminder.localizedMessage(petEnabled: petEnabled, language: language)
                #expect(message.hasPrefix(body + " "), "The displayed message must use the selected locale and tone")
                #expect(message.count > body.count + 1 && !message.contains("%"))
            }
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
        #expect(UserCareReminder.focusCompleted.localizedMessage(petEnabled: true, language: .english)
            == "Human, time's up. Let's rest a little. 🍵")
        #expect(UserCareReminder.restCompleted.localizedMessage(petEnabled: true, language: .traditionalChinese)
            == "人，休息好啦，我陪你繼續～ (๑•̀ㅂ•́)و✧")
        #expect(UserCareReminder.breathe.localizedMessage(petEnabled: false, language: .arabic)
            == "تنفّس ببطء وامنح نفسك بعض المساحة. 🌿")
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
        for reminder in UserCareReminder.allCases {
            for petEnabled in [false, true] {
                let value = reminder.localizedMessage(petEnabled: petEnabled, language: language)
                let textWidth = (value as NSString).size(withAttributes: [.font: font]).width
                let travel = max(0, textWidth - availableWidth + 16)
                let duration = max(3, Double(travel) / 90)
                #expect(duration <= 6, "\(language.rawValue) reminder needs \(duration) seconds to reveal its final words")
            }
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
