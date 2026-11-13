import Foundation
import Testing
@testable import ZislaCore

struct MailMessageTests {
    @Test(arguments: ["qq", "Qq", "qQ", "QQ"])
    func qqAccountNamesKeepBrandCapitalizationWithoutChangingIdentity(name: String) {
        let account = MailAccount(name: name)
        let addressedAccount = MailAccount(name: name, emailAddresses: ["fixture@qq.com"])

        #expect(MailAccount.displayAccountName(name) == "QQ")
        #expect(account.displayName == "QQ")
        #expect(account.id == name)
        #expect(account.emailAddresses.isEmpty)
        #expect(account.primaryEmailAddress == nil)
        #expect(addressedAccount.displayName == "fixture@qq.com")
        #expect(addressedAccount.id == name)
        #expect(addressedAccount.emailAddresses == ["fixture@qq.com"])
        #expect(addressedAccount.primaryEmailAddress == "fixture@qq.com")
    }

    @Test(arguments: ["", "Gmail", "iCloud", "Outlook", "个人邮箱", "Qqq", "QQ 工作", "Qq@example.com", "fixture@qq.com"])
    func otherAccountNamesAndEmailAddressesKeepTheirOriginalSpelling(name: String) {
        let account = MailAccount(name: name)
        let addressedAccount = MailAccount(name: name, emailAddresses: ["fixture@qq.com"])

        #expect(MailAccount.displayAccountName(name) == name)
        #expect(account.displayName == name)
        #expect(account.id == name)
        #expect(addressedAccount.id == name)
        #expect(addressedAccount.displayName == "fixture@qq.com")
    }

    @Test(arguments: AppLanguage.allCases)
    func localizedRepliesPreserveQQBrandCapitalization(language: AppLanguage) {
        let accountName = MailAccount.displayAccountName("Qq")
        let text = AppLocalization.format("通过 %@ 回复给 %@", locale: language.locale, [accountName, "fixture@example.com"])

        #expect(AppLanguage.allCases.count == 17)
        #expect(AppLocalization.string(accountName, language: language) == "QQ")
        #expect(text.contains("QQ"))
        #expect(!text.contains("Qq"))
        #expect(text.contains("fixture@example.com"))
    }

    @Test
    func titleAndPreviewNormalizeMailboxContent() {
        let message = MailMessage(
            accountName: "个人邮箱",
            messageID: 7,
            sender: "alice@example.com",
            subject: "   ",
            body: "第一行\n\n第二行\t内容",
            receivedAt: Date(timeIntervalSince1970: 1_000),
            isRead: false
        )

        #expect(message.title == "（无主题）")
        #expect(message.preview == "第一行 第二行 内容")
    }

    @Test
    func messagesWithTheSameSystemIdentifierInDifferentAccountsRemainDistinct() {
        let personal = MailMessage(
            accountName: "个人邮箱",
            messageID: 7,
            sender: "alice@example.com",
            subject: "个人邮件",
            body: "正文",
            receivedAt: .now,
            isRead: false
        )
        let work = MailMessage(
            accountName: "工作邮箱",
            messageID: 7,
            sender: "alice@example.com",
            subject: "工作邮件",
            body: "正文",
            receivedAt: .now,
            isRead: false
        )

        #expect(personal.id != work.id)
        #expect(personal.messageID == work.messageID)
    }

    @Test
    func mailAppMessagesBuildCompactNotificationPair() {
        let message = MailMessage(
            accountName: "工作邮箱",
            messageID: 42,
            sender: "Alice",
            subject: "季度计划",
            body: "请查收",
            receivedAt: Date(timeIntervalSince1970: 2_000),
            isRead: false
        )

        let pair = MailNotification(
            message: message,
            newMessageCount: 3,
            pairID: "batch"
        ).makeNotices()

        #expect(message.messageID == 42)
        #expect(pair.left.id == "mail-notification-batch-left")
        #expect(pair.left.side == .left)
        #expect(pair.left.title == "季度计划")
        #expect(pair.left.detail == "Alice")
        #expect(pair.left.symbolName == "envelope.fill")
        #expect(pair.right.id == "mail-notification-batch-right")
        #expect(pair.right.side == .right)
        #expect(pair.right.title == "3")
        #expect(pair.right.detail == "Alice")
    }

    @Test
    func mailIntegrationDefaultsOnAndLegacySettingsRemainDecodable() throws {
        #expect(FeatureSettings.default.mailEnabled == true)

        let data = Data(#"{"mediaEnabled":true,"fileShelfEnabled":true,"aiProgressEnabled":true,"downloaderEnabled":true,"calendarEnabled":true,"toolboxEnabled":true,"systemMonitorEnabled":true,"weatherEnabled":true,"lockScreenInfoEnabled":true,"quickNotesEnabled":true,"updateChecksEnabled":true,"automaticUpdatesEnabled":true,"clipboardDetectionEnabled":false,"sideNoticesEnabled":true,"hoverActivationEnabled":true,"activityNoticeDisplayDuration":"threeSeconds"}"#.utf8)
        let decoded = try JSONDecoder().decode(FeatureSettings.self, from: data)

        #expect(decoded.mailEnabled == true)
        #expect(decoded.mailAccountNames.isEmpty)
    }

    @Test
    func mailIntegrationSettingRoundTrips() throws {
        var settings = FeatureSettings.default
        settings.mailEnabled = true
        settings.mailAccountNames = ["个人邮箱", "工作邮箱"]
        settings.mailCompactStyle = .detailed

        let decoded = try JSONDecoder().decode(
            FeatureSettings.self,
            from: JSONEncoder().encode(settings)
        )

        #expect(decoded.mailEnabled == true)
        #expect(decoded.mailAccountNames == ["个人邮箱", "工作邮箱"])
        #expect(decoded.mailCompactStyle == .detailed)
    }
}
