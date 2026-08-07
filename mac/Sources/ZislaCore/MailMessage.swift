import Foundation

/// A configured account in the system Mail.app. The account name is used by AppleScript for precise targeting.
public struct MailAccount: Identifiable, Equatable, Sendable {
    public let id: String
    public let emailAddresses: [String]

    public init(name: String, emailAddresses: [String] = []) {
        id = name
        self.emailAddresses = emailAddresses
    }

    public var displayName: String {
        emailAddresses.first ?? id
    }

    public var detail: String {
        emailAddresses.dropFirst().joined(separator: "、")
    }

    public var primaryEmailAddress: String? {
        emailAddresses.first
    }
}

/// A snapshot of a message in the Mail.app inbox; the body is kept in memory only.
public struct MailMessage: Identifiable, Equatable, Sendable {
    public let id: String
    public let accountName: String
    public let messageID: Int
    public let sender: String
    public let subject: String
    public let body: String
    public let receivedAt: Date
    public let isRead: Bool

    public init(
        accountName: String,
        messageID: Int,
        sender: String,
        subject: String,
        body: String,
        receivedAt: Date,
        isRead: Bool
    ) {
        self.id = "\(accountName)\u{1F}\(messageID)"
        self.accountName = accountName
        self.messageID = messageID
        self.sender = sender
        self.subject = subject
        self.body = body
        self.receivedAt = receivedAt
        self.isRead = isRead
    }

    public var title: String {
        let value = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "（无主题）" : value
    }

    public var preview: String {
        let normalized = body
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? "没有可显示的正文" : normalized
    }
}

public struct MailNotification: Equatable, Sendable {
    public let message: MailMessage
    public let newMessageCount: Int
    public let pairID: String

    public init(message: MailMessage, newMessageCount: Int, pairID: String = UUID().uuidString) {
        self.message = message
        self.newMessageCount = max(1, newMessageCount)
        self.pairID = pairID
    }

    public func makeNotices() -> (left: IslandNotice, right: IslandNotice) {
        let sender = message.sender.isEmpty ? "未知发件人" : message.sender
        let prefix = "mail-notification-\(pairID)"
        return (
            IslandNotice(
                id: "\(prefix)-left",
                title: message.title,
                detail: sender,
                kind: .info,
                side: .left,
                createdAt: message.receivedAt,
                style: .status,
                symbolName: "envelope.fill"
            ),
            IslandNotice(
                id: "\(prefix)-right",
                title: String(newMessageCount),
                detail: sender,
                kind: .info,
                side: .right,
                createdAt: message.receivedAt,
                style: .status
            )
        )
    }
}
