import Testing

@testable import ZislaCore

struct UserCareMessageTests {
    @Test(arguments: UserCareReminder.allCases, [false, true])
    func displayedMessageKeepsTheLocalizedBodyAndAddsOneSharedDecoration(reminder: UserCareReminder, petEnabled: Bool) {
        let body = AppLocalization.string(reminder.localizationKey(petEnabled: petEnabled), language: .english)
        let message = reminder.localizedMessage(petEnabled: petEnabled, language: .english)
        #expect(message.hasPrefix(body + " "))
        let decoration = String(message.dropFirst(body.count + 1))
        #expect(!decoration.isEmpty && !decoration.contains(" "))
        #expect(!message.contains("%"))
    }

    @Test
    func completionAndStretchMessagesUseTheRequestedFriendlyVoice() {
        #expect(UserCareReminder.focusCompleted.localizedMessage(petEnabled: true, language: .simplifiedChinese)
            == "人，时间到啦，该休息了～ 🍵")
        #expect(UserCareReminder.restCompleted.localizedMessage(petEnabled: false, language: .simplifiedChinese)
            == "休息结束啦，按自己的节奏继续吧～ 🌿")
        #expect(UserCareReminder.stretch.localizedMessage(petEnabled: true, language: .simplifiedChinese)
            == "人，放松肩颈，和我伸个懒腰吧。 (๑•̀ㅂ•́)و✧")
        #expect(UserCareReminder.water.localizedMessage(petEnabled: false, language: .english)
            == "Have a sip of water. Take your time. 💧")
    }
}
