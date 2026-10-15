import Foundation
import Testing
import ZislaCore
import ZislaKit

struct FirstLaunchOnboardingLocalizationTests {
    private let keys: Set<String> = [
        "onboarding.hello",
        "onboarding.thanks",
        "onboarding.continue",
        "onboarding.skip_intro",
        "onboarding.back",
        "onboarding.finish",
        "onboarding.skip_permission",
        "onboarding.grant",
        "onboarding.open_settings",
        "onboarding.granted",
        "onboarding.not_granted",
        "onboarding.restricted",
        "onboarding.requesting",
        "onboarding.retry",
        "onboarding.mute",
        "onboarding.unmute",
        "onboarding.manual",
        "onboarding.unavailable",
        "onboarding.introduction.title",
        "onboarding.introduction.body",
        "onboarding.feature.island.title",
        "onboarding.feature.island.body",
        "onboarding.feature.tools.title",
        "onboarding.feature.tools.body",
        "onboarding.feature.ai.title",
        "onboarding.feature.ai.body",
        "onboarding.permissions.title",
        "onboarding.permissions.body",
        "onboarding.permission.accessibility.title",
        "onboarding.permission.accessibility.body",
        "onboarding.permission.input_monitoring.title",
        "onboarding.permission.input_monitoring.body",
        "onboarding.permission.screen_recording.title",
        "onboarding.permission.screen_recording.body",
        "onboarding.permission.system_audio.title",
        "onboarding.permission.system_audio.body",
        "onboarding.permission.microphone.title",
        "onboarding.permission.microphone.body",
        "onboarding.permission.camera.title",
        "onboarding.permission.camera.body",
        "onboarding.permission.speech_recognition.title",
        "onboarding.permission.speech_recognition.body",
        "onboarding.permission.calendar.title",
        "onboarding.permission.calendar.body",
        "onboarding.permission.reminders.title",
        "onboarding.permission.reminders.body",
        "onboarding.permission.location.title",
        "onboarding.permission.location.body",
        "onboarding.permission.notifications.title",
        "onboarding.permission.notifications.body",
        "onboarding.permission.bluetooth.title",
        "onboarding.permission.bluetooth.body",
        "onboarding.permission.automation.title",
        "onboarding.permission.automation.body",
        "onboarding.permission.files.title",
        "onboarding.permission.files.body",
        "onboarding.permission.full_disk_access.title",
        "onboarding.permission.full_disk_access.body",
        "onboarding.ready.title",
        "onboarding.ready.body",
    ]

    @Test(arguments: AppLanguage.allCases)
    func everyLanguageHasCompleteNonemptyTranslations(language: AppLanguage) throws {
        let table = try translations(for: language)
        #expect(keys.count == 60)
        #expect(Set(OnboardingPermissionID.allCases.flatMap { [$0.titleKey, $0.bodyKey] }).isSubset(of: keys))
        for key in keys.sorted() {
            let value = try #require(table[key], "Missing \(language.rawValue) translation for \(key)")
            #expect(
                !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "Empty \(language.rawValue) translation for \(key)"
            )
            #expect(value != key, "Untranslated \(language.rawValue) key: \(key)")
            #expect(
                AppLocalization.string(key, language: language) == value,
                "Incorrect \(language.rawValue) localization for \(key)"
            )
        }
    }

    @Test(arguments: AppLanguage.allCases)
    func thanksPreservesFeedbackAddress(language: AppLanguage) throws {
        let table = try translations(for: language)
        let thanks = try #require(table["onboarding.thanks"])
        #expect(thanks.contains("github.com/wzz6423/zisla"))
        if language == .simplifiedChinese {
            #expect(thanks == "感谢您选择使用zisla，如有问题或建议烦请在github.com/wzz6423/zisla提交issue进行反馈")
        }
    }

    @Test
    func specifiedGreetingsMatchExactly() throws {
        let greetings: [(AppLanguage, String)] = [
            (.english, "Hello"),
            (.simplifiedChinese, "你好"),
            (.traditionalChinese, "你好"),
            (.german, "hallo"),
        ]
        for (language, greeting) in greetings {
            let table = try translations(for: language)
            #expect(table["onboarding.hello"] == greeting)
            #expect(AppLocalization.string("onboarding.hello", language: language) == greeting)
        }
    }

    private func translations(for language: AppLanguage) throws -> [String: String] {
        let resource = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Localization/\(language.rawValue).lproj/Localizable.strings")
        return try #require(
            try PropertyListSerialization.propertyList(from: Data(contentsOf: resource), format: nil) as? [String: String]
        )
    }
}
