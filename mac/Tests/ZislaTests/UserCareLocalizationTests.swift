import AppKit
import Foundation
import Testing
import ZislaCore

@testable import Zisla

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
        #expect(UserCareReminder.eyeDrops.localizedMessage(petEnabled: false, language: .english)
            == "If you use eye drops, follow your clinician's directions. 💧")
        #expect(UserCareReminder.eyeDrops.localizedMessage(petEnabled: true, language: .english)
            == "Human, if you use eye drops, follow your clinician's directions. 💧")
        #expect(UserCareReminder.noteCreated.localizedMessage(petEnabled: true, language: .traditionalChinese)
            == "人，我記住了，記得回來看看～ 📝")
        #expect(UserCareReminder.noteUpdated.localizedMessage(petEnabled: false, language: .japanese)
            == "更新したよ。また見に来てね。 📌")
        for reminder in UserCareReminder.allCases {
            #expect(reminder.localizationKey(petEnabled: true).hasPrefix("人，"))
            #expect(!reminder.localizationKey(petEnabled: false).hasPrefix("人，"))
        }
    }

    @MainActor
    @Test(arguments: AppLanguage.allCases)
    func transientIslandBudgetCanReadEveryHealthAndEventMessage(language: AppLanguage) {
        let geometry = VoiceRecordingIslandGeometry(
            collapsedSize: CGSize(width: 240, height: 34),
            surfaceSize: CGSize(width: 240, height: 54)
        )
        let rowWidth = geometry.transcriptRowFrame.width
        let availableWidth = rowWidth - TransientNoticeMetrics.rowHorizontalPadding * 2
        for reminder in UserCareReminder.allCases {
            for petEnabled in [false, true] {
                let value = reminder.localizedMessage(petEnabled: petEnabled, language: language)
                let travel = max(0, TransientNoticeMetrics.textWidth(of: value) - availableWidth)
                let pass = Duration.seconds(Double(travel) / TransientNoticeMetrics.pointsPerSecond)
                let duration = TransientNoticeMetrics.displayDuration(for: value, rowWidth: rowWidth)
                #expect(duration > pass, "\(language.rawValue) message must finish scrolling before dismissal: \(value)")
                #expect(duration >= .seconds(TransientNoticeMetrics.minimumSeconds))
                #expect(duration <= .seconds(TransientNoticeMetrics.maximumSeconds))
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
