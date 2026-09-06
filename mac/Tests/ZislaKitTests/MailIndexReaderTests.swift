import Foundation
import SQLite3
import Testing
@testable import ZislaKit

struct MailIndexReaderTests {
    @Test
    func reportsUnavailableWhenIndexDoesNotExist() {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Zisla-missing-mail-index-\(UUID().uuidString).db")

        #expect(throws: MailIndexReaderError.unavailable) {
            try MailIndexReader(databaseURL: databaseURL).snapshot(accountNames: [])
        }
    }

    @Test
    func readsInboxMessagesWithoutLaunchingMail() throws {
        let databaseURL = try makeMailIndex()
        defer { try? FileManager.default.removeItem(at: databaseURL) }

        try execute("""
            INSERT INTO mailboxes (ROWID, url) VALUES
                (1, 'imap://work%40example.com@mail.example.com/INBOX'),
                (2, 'imap://work%40example.com@mail.example.com/Sent');
            INSERT INTO addresses (ROWID, address, comment) VALUES (1, 'sender@example.com', '');
            INSERT INTO sender_addresses (address, sender) VALUES (1, 1);
            INSERT INTO subjects (ROWID, subject) VALUES (1, '收件箱主题'), (2, '已发送主题');
            INSERT INTO summaries (ROWID, summary) VALUES (1, '收件箱摘要');
            INSERT INTO messages (message_id, sender, subject, summary, date_received, display_date, mailbox, read, deleted)
            VALUES
                (42, 1, 1, 1, 1_720_000_000, 1_720_000_000, 1, 0, 0),
                (43, 1, 2, NULL, 1_720_000_100, 1_720_000_100, 2, 1, 0);
            """, at: databaseURL)

        let snapshot = try MailIndexReader(databaseURL: databaseURL).snapshot(accountNames: [])

        #expect(snapshot.accounts.map(\.name) == ["work@example.com"])
        #expect(snapshot.accounts.first?.emailAddresses == ["work@example.com"])
        #expect(snapshot.messages.count == 1)
        #expect(snapshot.messages.first?.messageID == "42")
        #expect(snapshot.messages.first?.sender == "sender@example.com")
        #expect(snapshot.messages.first?.subject == "收件箱主题")
        #expect(snapshot.messages.first?.body == "收件箱摘要")
        #expect(snapshot.messages.first?.isRead == false)
    }

    @Test
    func filtersSelectedAccountBeforeApplyingMessageLimit() throws {
        let databaseURL = try makeMailIndex()
        defer { try? FileManager.default.removeItem(at: databaseURL) }

        try execute("""
            INSERT INTO mailboxes (ROWID, url) VALUES
                (1, 'imap://busy%40example.com@mail.example.com/INBOX'),
                (2, 'imap://quiet%40example.com@mail.example.com/INBOX');
            INSERT INTO subjects (ROWID, subject) VALUES (1, 'Busy'), (2, 'Quiet');
            INSERT INTO messages (message_id, subject, date_received, display_date, mailbox, read, deleted)
            VALUES
                (101, 1, 2_000, 2_000, 1, 0, 0),
                (102, 1, 1_999, 1_999, 1, 0, 0),
                (103, 1, 1_998, 1_998, 1, 0, 0),
                (104, 1, 1_997, 1_997, 1, 0, 0),
                (105, 1, 1_996, 1_996, 1, 0, 0),
                (106, 1, 1_995, 1_995, 1, 0, 0),
                (107, 1, 1_994, 1_994, 1, 0, 0),
                (108, 1, 1_993, 1_993, 1, 0, 0),
                (201, 2, 1_000, 1_000, 2, 0, 0);
            """, at: databaseURL)

        let snapshot = try MailIndexReader(databaseURL: databaseURL, maxMessages: 2)
            .snapshot(accountNames: ["quiet@example.com"])

        #expect(snapshot.messages.map(\.messageID) == ["201"])
    }

    @Test
    func excludesNonInboxMailboxesWhenOtherURLPartsContainInbox() throws {
        let databaseURL = try makeMailIndex()
        defer { try? FileManager.default.removeItem(at: databaseURL) }

        try execute("""
            INSERT INTO mailboxes (ROWID, url) VALUES
                (1, 'imap://inbox-owner%40example.com@mail.example.com/Sent'),
                (2, 'imap://owner%40example.com@inbox.mail.example.com/Sent'),
                (3, 'imap://owner%40example.com@mail.example.com/Archive%2FINBOX');
            INSERT INTO subjects (ROWID, subject) VALUES
                (1, 'Account match'), (2, 'Host match'), (3, 'Encoded mailbox name');
            INSERT INTO messages (message_id, subject, date_received, display_date, mailbox, read, deleted)
            VALUES
                (301, 1, 1_000, 1_000, 1, 0, 0),
                (302, 2, 999, 999, 2, 0, 0),
                (303, 3, 998, 998, 3, 0, 0);
            """, at: databaseURL)

        let snapshot = try MailIndexReader(databaseURL: databaseURL).snapshot(accountNames: [])

        #expect(snapshot.messages.isEmpty)
    }

    @Test
    func filtersMessagesForSelectedAccounts() throws {
        let databaseURL = try makeMailIndex()
        defer { try? FileManager.default.removeItem(at: databaseURL) }

        try execute("""
            INSERT INTO mailboxes (ROWID, url) VALUES
                (1, 'imap://work%40example.com@mail.example.com/INBOX'),
                (2, 'imap://personal%40example.com@mail.example.com/INBOX'),
                (3, 'imap://sent-only%40example.com@mail.example.com/Sent');
            INSERT INTO subjects (ROWID, subject) VALUES
                (1, '工作邮件'), (2, '个人邮件'), (3, '已发送邮件');
            INSERT INTO messages (message_id, subject, date_received, display_date, mailbox, read, deleted)
            VALUES
                (11, 1, 1_720_000_000, 1_720_000_000, 1, 0, 0),
                (12, 2, 1_720_000_100, 1_720_000_100, 2, 1, 0),
                (13, 3, 1_720_000_200, 1_720_000_200, 3, 1, 0);
            """, at: databaseURL)

        let snapshot = try MailIndexReader(databaseURL: databaseURL)
            .snapshot(accountNames: ["work@example.com"])

        #expect(snapshot.messages.map(\.messageID) == ["11"])
        #expect(snapshot.messages.first?.body == "工作邮件")

        let unmatchedSelection = try MailIndexReader(databaseURL: databaseURL)
            .snapshot(accountNames: ["旧账户名称"])
        #expect(unmatchedSelection.messages.isEmpty)

        let existingAccountWithoutInbox = try MailIndexReader(databaseURL: databaseURL)
            .snapshot(accountNames: ["sent-only@example.com"])
        #expect(existingAccountWithoutInbox.messages.isEmpty)
    }

    @Test
    func ordersMessagesWithEqualTimestampsDeterministically() throws {
        let databaseURL = try makeMailIndex()
        defer { try? FileManager.default.removeItem(at: databaseURL) }

        try execute("""
            INSERT INTO mailboxes (ROWID, url) VALUES
                (1, 'imap://work%40example.com@mail.example.com/INBOX');
            INSERT INTO subjects (ROWID, subject) VALUES (1, 'Earlier row'), (2, 'Later row');
            INSERT INTO messages (message_id, subject, date_received, display_date, mailbox, read, deleted)
            VALUES
                (10, 1, 1_720_000_000, 1_720_000_000, 1, 0, 0),
                (20, 2, 1_720_000_000, 1_720_000_000, 1, 0, 0);
            """, at: databaseURL)

        let snapshot = try MailIndexReader(databaseURL: databaseURL).snapshot(accountNames: [])

        #expect(snapshot.messages.map(\.messageID) == ["20", "10"])
    }

    @Test
    func readsOlderPagesWithOffsetAndReportsWhetherMoreExist() throws {
        let databaseURL = try makeMailIndex()
        defer { try? FileManager.default.removeItem(at: databaseURL) }

        try execute("""
            INSERT INTO mailboxes (ROWID, url) VALUES
                (1, 'imap://work%40example.com@mail.example.com/INBOX');
            INSERT INTO subjects (ROWID, subject) VALUES (1, 'One'), (2, 'Two'), (3, 'Three');
            INSERT INTO messages (message_id, subject, date_received, display_date, mailbox, read, deleted)
            VALUES
                (1, 1, 3_000, 3_000, 1, 0, 0),
                (2, 2, 2_000, 2_000, 1, 0, 0),
                (3, 3, 1_000, 1_000, 1, 0, 0);
            """, at: databaseURL)

        let reader = MailIndexReader(databaseURL: databaseURL, maxMessages: 2)
        let first = try reader.snapshot(accountNames: [])
        #expect(first.messages.map(\.messageID) == ["1", "2"])
        #expect(first.hasMore)

        let older = try reader.snapshot(accountNames: [], offset: 2)
        #expect(older.messages.map(\.messageID) == ["3"])
        #expect(!older.hasMore)
    }
}

private func makeMailIndex() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("Zisla-mail-index-\(UUID().uuidString).db")
    try execute("""
        CREATE TABLE mailboxes (url TEXT NOT NULL);
        CREATE TABLE messages (
            message_id INTEGER NOT NULL,
            sender INTEGER,
            subject INTEGER NOT NULL,
            summary INTEGER,
            date_received INTEGER,
            display_date INTEGER,
            mailbox INTEGER NOT NULL,
            read INTEGER NOT NULL DEFAULT 0,
            deleted INTEGER NOT NULL DEFAULT 0
        );
        CREATE TABLE sender_addresses (address INTEGER PRIMARY KEY, sender INTEGER NOT NULL);
        CREATE TABLE addresses (address TEXT NOT NULL, comment TEXT NOT NULL);
        CREATE TABLE subjects (subject TEXT NOT NULL);
        CREATE TABLE summaries (summary TEXT NOT NULL);
        """, at: url)
    return url
}

private func execute(_ sql: String, at url: URL) throws {
    var db: OpaquePointer?
    guard sqlite3_open(url.path, &db) == SQLITE_OK else {
        sqlite3_close(db)
        throw MailIndexTestError.openFailed
    }
    defer { sqlite3_close(db) }

    var error: UnsafeMutablePointer<CChar>?
    guard sqlite3_exec(db, sql, nil, nil, &error) == SQLITE_OK else {
        sqlite3_free(error)
        throw MailIndexTestError.queryFailed
    }
}

private enum MailIndexTestError: Error {
    case openFailed
    case queryFailed
}
