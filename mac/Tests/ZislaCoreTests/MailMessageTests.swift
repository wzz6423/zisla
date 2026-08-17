import Foundation
import Testing
@testable import ZislaCore

struct MailMessageTests {
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
