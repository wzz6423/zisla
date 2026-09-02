import Foundation
import SQLite3

enum MailIndexReaderError: Error, Equatable, Sendable {
    case unavailable
    case openFailed
    case queryFailed
}

struct MailIndexReader: Sendable {
    private struct MailboxDetails {
        let rowID: Int64
        let accountName: String
        let emailAddresses: Set<String>
        let isInbox: Bool
    }

    let databaseURL: URL
    let maxMessages: Int

    init(databaseURL: URL? = nil, maxMessages: Int = 30) {
        self.databaseURL = databaseURL ?? Self.defaultDatabaseURL()
        self.maxMessages = min(max(1, maxMessages), 120)
    }

    static func defaultDatabaseURL(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        let mailDirectory = home.appendingPathComponent("Library/Mail", isDirectory: true)
        let versions = (try? FileManager.default.contentsOfDirectory(
            at: mailDirectory,
            includingPropertiesForKeys: nil
        )) ?? []
        let indexURL = versions
            .compactMap { directory -> (version: Int, url: URL)? in
                let name = directory.lastPathComponent
                guard name.first == "V", let version = Int(name.dropFirst()) else { return nil }
                let url = directory.appendingPathComponent("MailData/Envelope Index")
                return FileManager.default.fileExists(atPath: url.path) ? (version, url) : nil
            }
            .max { $0.version < $1.version }?
            .url
        return indexURL ?? mailDirectory.appendingPathComponent("V10/MailData/Envelope Index")
    }

    func snapshot(accountNames: Set<String>) throws -> MailSnapshot {
        guard FileManager.default.isReadableFile(atPath: databaseURL.path) else {
            throw MailIndexReaderError.unavailable
        }

        var db: OpaquePointer?
        guard sqlite3_open_v2(
            databaseURL.path,
            &db,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX,
            nil
        ) == SQLITE_OK else {
            sqlite3_close(db)
            throw MailIndexReaderError.openFailed
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 500)

        let mailboxes = try mailboxDetails(in: db)
        let inboxMailboxes = mailboxes.filter(\.isInbox)
        let queriedMailboxes = accountNames.isEmpty
            ? inboxMailboxes
            : inboxMailboxes.filter { accountNames.contains($0.accountName) }

        var accountAddresses: [String: Set<String>] = [:]
        for mailbox in inboxMailboxes {
            accountAddresses[mailbox.accountName, default: []].formUnion(mailbox.emailAddresses)
        }
        let accounts = accountAddresses.map { name, addresses in
            MailScriptAccount(name: name, emailAddresses: addresses.sorted())
        }
        guard !queriedMailboxes.isEmpty else {
            return MailSnapshot(accounts: accounts, messages: [])
        }

        let mailboxPlaceholders = Array(repeating: "?", count: queriedMailboxes.count).joined(separator: ", ")
        let sql = """
            SELECT
                m.message_id,
                COALESCE((
                    SELECT a.address
                    FROM sender_addresses AS sa
                    INNER JOIN addresses AS a ON a.ROWID = sa.address
                    WHERE sa.sender = m.sender
                    ORDER BY a.ROWID ASC
                    LIMIT 1
                ), ''),
                COALESCE(s.subject, ''),
                COALESCE(sm.summary, ''),
                COALESCE(m.display_date, m.date_received, 0),
                m.read,
                mb.url
            FROM messages AS m
            INNER JOIN mailboxes AS mb ON mb.ROWID = m.mailbox
            LEFT JOIN subjects AS s ON s.ROWID = m.subject
            LEFT JOIN summaries AS sm ON sm.ROWID = m.summary
            WHERE m.deleted = 0 AND m.mailbox IN (\(mailboxPlaceholders))
            ORDER BY COALESCE(m.display_date, m.date_received) DESC, m.message_id DESC, m.ROWID DESC
            LIMIT ?
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            sqlite3_finalize(statement)
            throw MailIndexReaderError.queryFailed
        }
        defer { sqlite3_finalize(statement) }
        for (index, mailbox) in queriedMailboxes.enumerated() {
            guard sqlite3_bind_int64(statement, Int32(index + 1), mailbox.rowID) == SQLITE_OK else {
                throw MailIndexReaderError.queryFailed
            }
        }
        guard sqlite3_bind_int(
            statement,
            Int32(queriedMailboxes.count + 1),
            Int32(maxMessages)
        ) == SQLITE_OK else {
            throw MailIndexReaderError.queryFailed
        }

        var rows: [MailScriptRow] = []
        var stepResult: Int32 = SQLITE_ROW
        while stepResult == SQLITE_ROW {
            stepResult = sqlite3_step(statement)
            if stepResult == SQLITE_ROW {
                let messageID = sqlite3_column_int64(statement, 0)
                guard messageID > 0, let mailboxURL = stringColumn(statement, 6) else { continue }
                let account = accountDetails(forMailboxURL: mailboxURL)

                let subject = stringColumn(statement, 2) ?? ""
                let summary = stringColumn(statement, 3) ?? ""
                rows.append(MailScriptRow(
                    accountName: account.name,
                    messageID: String(messageID),
                    sender: stringColumn(statement, 1) ?? "",
                    subject: subject,
                    body: summary.isEmpty ? subject : summary,
                    receivedAt: Date(timeIntervalSince1970: Double(sqlite3_column_int64(statement, 4))),
                    isRead: sqlite3_column_int(statement, 5) != 0
                ))
            }
        }
        guard stepResult == SQLITE_DONE else {
            throw MailIndexReaderError.queryFailed
        }

        return MailSnapshot(
            accounts: accounts,
            messages: rows
        )
    }

    private func mailboxDetails(in database: OpaquePointer?) throws -> [MailboxDetails] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT ROWID, url FROM mailboxes", -1, &statement, nil) == SQLITE_OK else {
            sqlite3_finalize(statement)
            throw MailIndexReaderError.queryFailed
        }
        defer { sqlite3_finalize(statement) }

        var mailboxes: [MailboxDetails] = []
        var stepResult = sqlite3_step(statement)
        while stepResult == SQLITE_ROW {
            let rowID = sqlite3_column_int64(statement, 0)
            if rowID > 0, let mailboxURL = stringColumn(statement, 1) {
                let account = accountDetails(forMailboxURL: mailboxURL)
                mailboxes.append(MailboxDetails(
                    rowID: rowID,
                    accountName: account.name,
                    emailAddresses: account.emailAddresses,
                    isInbox: isInboxMailboxURL(mailboxURL)
                ))
            }
            stepResult = sqlite3_step(statement)
        }
        guard stepResult == SQLITE_DONE else {
            throw MailIndexReaderError.queryFailed
        }
        return mailboxes
    }

    private func isInboxMailboxURL(_ mailboxURL: String) -> Bool {
        guard let encodedPath = URLComponents(string: mailboxURL)?.percentEncodedPath,
              let encodedMailboxName = encodedPath.split(separator: "/").last,
              let mailboxName = encodedMailboxName.removingPercentEncoding else {
            return false
        }
        return mailboxName.caseInsensitiveCompare("INBOX") == .orderedSame
    }

    private func stringColumn(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let value = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: value)
    }

    private func accountDetails(forMailboxURL mailboxURL: String) -> (name: String, emailAddresses: Set<String>) {
        let components = URLComponents(string: mailboxURL)
        let user = components?.user?.removingPercentEncoding ?? components?.user
        let host = components?.host?.removingPercentEncoding ?? components?.host
        let name = (user?.isEmpty == false ? user : host) ?? "Mail"
        return (name, name.contains("@") ? [name] : [])
    }
}
