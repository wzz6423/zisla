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
