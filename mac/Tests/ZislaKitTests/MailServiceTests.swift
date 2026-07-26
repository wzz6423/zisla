import Foundation
import Testing
@testable import ZislaCore
@testable import ZislaKit

struct MailServiceTests {
    @Test @MainActor
    func messageRowsDiscardInvalidIdentifiersAndSortNewestFirst() {
        let messages = MailService.messages(from: [
            MailScriptRow(
                accountName: "个人邮箱",
                messageID: "12",
                sender: "older@example.com",
                subject: "旧邮件",
                body: "旧正文",
                receivedAt: Date(timeIntervalSince1970: 100),
                isRead: true
            ),
            MailScriptRow(
                accountName: "工作邮箱",
                messageID: "not-an-id",
                sender: "invalid@example.com",
                subject: "忽略",
                body: "",
                receivedAt: Date(),
                isRead: false
            ),
            MailScriptRow(
                accountName: "工作邮箱",
                messageID: "13",
                sender: "new@example.com",
                subject: "新邮件",
                body: "新正文",
                receivedAt: Date(timeIntervalSince1970: 200),
                isRead: false
            ),
        ])

        #expect(messages.map(\.messageID) == [13, 12])
        #expect(messages.map(\.accountName) == ["工作邮箱", "个人邮箱"])
        #expect(messages.map(\.isRead) == [false, true])
    }

    @Test @MainActor
    func generatedScriptsUseAccountSpecificActionsAndSelectedSender() {
        let compose = MailService.composeScript(
            fromAddress: "work@example.com",
            to: ["alice@example.com", "bob@example.com"],
            subject: "主题 \"A\"",
            body: "第一行\n第二行"
        )

        #expect(compose.contains("tell application \"Mail\""))
        #expect(compose.contains("address:\"alice@example.com\""))
        #expect(compose.contains("address:\"bob@example.com\""))
        #expect(compose.contains("主题 \\\"A\\\""))
        #expect(compose.contains("第一行\\n第二行"))
        #expect(compose.contains("set sender of outgoingMessage to \"work@example.com\""))

        let message = MailMessage(
            accountName: "工作邮箱",
            messageID: 42,
            sender: "alice@example.com",
            subject: "主题",
            body: "正文",
            receivedAt: .now,
            isRead: false
        )
        let scripts = [
            MailService.markReadScript(message: message),
            MailService.markJunkScript(message: message),
            MailService.deleteScript(message: message),
            MailService.replyScript(message: message, body: "收到"),
        ]

        for script in scripts {
            #expect(script.contains("first account whose name is \"工作邮箱\""))
            #expect(script.contains("whose id is 42"))
        }
        #expect(scripts[0].contains("read status of targetMessage to true"))
        #expect(scripts[1].contains("junk mail status of targetMessage to true"))
        #expect(scripts[2].contains("delete targetMessage"))
        #expect(scripts[3].contains("reply targetMessage"))
    }

    @Test @MainActor
    func inboxScriptIncludesAllAccountsButOnlyReadsSelectedInboxes() {
        let script = MailService.inboxScript(accountNames: ["工作邮箱", "个人邮箱"])

        #expect(script.contains("set selectedAccountNames to {"))
        #expect(script.contains("\"工作邮箱\""))
        #expect(script.contains("\"个人邮箱\""))
        #expect(script.contains("set accountList to every account"))
        #expect(script.contains("repeat with i from 1 to accountCount"))
        #expect(script.contains("set end of accountRows to {accountName, accountAddresses}"))
        #expect(script.contains("accountName is in selectedAccountNames"))
    }

    @Test @MainActor
    func inboxScriptIsDefensiveAgainstUnreachableAccountsAndMessages() {
        let script = MailService.inboxScript(accountNames: [])

        // If any account's inbox fails to resolve, the whole fetch must not blow up.
        #expect(script.contains("on error"))
        #expect(script.contains("messages of inbox of mailAccount"))
        #expect(script.contains("set mailAccount to item i of accountList"))
        #expect(script.contains("-- 单封邮件不可读（损坏/超大），跳过"))
        #expect(script.contains("-- 该账户的 inbox 当前不可访问"))
        // When an account name is unreadable, fill a placeholder so later indices stay aligned.
        #expect(script.contains("未知账户"))
    }

    @Test @MainActor
    func unavailableMailIsNeverLaunchedAutomatically() {
        #expect(MailService.mailUnavailableMessage(isRunning: false) ==
            "Mail.app 当前未运行。zisla 不会自动打开它；请在需要同步时自行启动 Mail.app 后重试。"
        )
        #expect(MailService.mailUnavailableMessage(isRunning: true) == nil)
    }
}
