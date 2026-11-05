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

    @Test
    func notesUseTheirOwnCreationAndUpdateVoicesAndDecorations() {
        #expect(UserCareReminder.noteCreated.localizedMessage(petEnabled: false, language: .simplifiedChinese)
            == "我记住了，记得回来看看～ 📝")
        #expect(UserCareReminder.noteCreated.localizedMessage(petEnabled: true, language: .simplifiedChinese)
            == "人，我记住了，记得回来看看～ 📝")
        #expect(UserCareReminder.noteUpdated.localizedMessage(petEnabled: false, language: .simplifiedChinese)
            == "更新好了，记得回来看看～ 📌")
        #expect(UserCareReminder.noteUpdated.localizedMessage(petEnabled: true, language: .simplifiedChinese)
            == "人，更新好了，记得回来看看～ 📌")
    }

    @Test
    func eyeDropCopyIsConditionalAndDefersToTheExistingPrescription() {
        #expect(UserCareReminder.eyeDrops.localizationKey(petEnabled: false)
            == "有在用眼药水的话，记得按医嘱使用哦。")
        #expect(UserCareReminder.eyeDrops.localizationKey(petEnabled: true)
            == "人，有在用眼药水的话，记得按医嘱使用哦。")
        #expect(UserCareReminder.blink.localizedMessage(petEnabled: false, language: .simplifiedChinese)
            == "轻轻眨眨眼，让眼睛歇一会儿吧。 👀")
    }
}
