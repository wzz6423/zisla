import Combine
import Foundation
import SQLite3
import Testing
@testable import ZislaCore
@testable import ZislaKit

struct MailServiceTests {
    @Test(arguments: [nil, "work"] as [String?]) @MainActor
    func markingAllReadIncludesOlderPagesAndRespectsEnabledAccountsAndTheFilter(accountName: String?) async throws {
        let names = ["work", "personal", "disabled"]
        var readAccounts: Set<String> = []
        var mutationSources: [String] = []
        let service = MailService(
            commandRunner: { source, expectsSnapshot in
                if !expectsSnapshot {
                    mutationSources.append(source)
                    readAccounts.formUnion(names.filter { source.contains(MailService.appleScriptString($0)) })
                    return .success(.succeeded)
                }
                guard let bounds = mailServiceRequestBounds(source) else {
                    Issue.record("The inbox script must contain pagination bounds")
                    return .failure(.failed("Missing pagination bounds"))
                }
                let rows = (1...24).map { id in
                    let name = id.isMultiple(of: 2) ? "personal" : "work"
                    return MailScriptRow(
                        accountName: name, messageID: String(id), sender: "sender@example.com",
                        subject: "Message \(id)", body: "Body \(id)",
                        receivedAt: Date(timeIntervalSince1970: Double(2_000 - id)),
                        isRead: readAccounts.contains(name), htmlBody: "<p>Body \(id)</p>"
                    )
                }
                return .success(.snapshot(MailSnapshot(
                    accounts: names.map { MailScriptAccount(name: $0, emailAddresses: ["\($0)@example.com"]) },
                    messages: Array(rows.dropFirst(bounds.offset).prefix(bounds.limit)),
                    hasMore: bounds.offset + bounds.limit < rows.count
                )))
            },
            indexReader: MailIndexReader(databaseURL: URL(fileURLWithPath: "/does/not/exist")),
            mailRunning: { true }
        )
        service.start(accountNames: ["work", "personal"])
        service.stop()
        await service.refresh(checkForNewMail: false)
        #expect(service.messages.count == 10)
        #expect(service.canLoadMore)

        #expect(await service.markAllRead(accountName: accountName) == .success)
        #expect(readAccounts == (accountName == nil ? ["work", "personal"] : ["work"]))
        #expect(mutationSources.count == 1, "Bulk marking must use one queued script rather than one write per loaded message")
        #expect(mutationSources.allSatisfy { !$0.contains("check for new mail") })
        await service.loadMore()
        await service.loadMore()

        #expect(service.messages.count == 24)
        #expect(!service.canLoadMore)
        for message in service.messages {
            #expect(message.isRead == readAccounts.contains(message.accountName), "The filter must also apply beyond the first page")
            #expect(message.body == "Body \(message.messageID)")
            #expect(message.htmlBody == "<p>Body \(message.messageID)</p>")
        }
        #expect(!service.isMutating)
    }

    @Test @MainActor
    func bulkReadWaitsForSuccessAndPreservesNewArrivalsAfterAStaleRefresh() async throws {
        let started = MailOperationQueueTestGate()
        let release = MailOperationQueueTestGate()
        var didWrite = false
        let service = MailService(
            commandRunner: { _, expectsSnapshot in
                if !expectsSnapshot {
                    await started.signal()
                    await release.wait()
                    didWrite = true
                    return .success(.succeeded)
                }
                let snapshot = makeMailServiceSnapshot(account: "work", messageID: 1, hasMore: true)
                return .success(.snapshot(MailSnapshot(
                    accounts: snapshot.accounts,
                    messages: snapshot.messages + (didWrite ? makeMailServiceSnapshot(account: "work", messageID: 2).messages : []),
                    hasMore: true
                )))
            },
            indexReader: MailIndexReader(databaseURL: URL(fileURLWithPath: "/does/not/exist")),
            mailRunning: { true }
        )
        await service.refresh(checkForNewMail: false)
        let original = try #require(service.messages.first)
        let pending = Task { await service.markAllRead() }
        await started.wait()
        #expect(service.isMutating)
        #expect(service.messages == [original], "Unread badges must remain until Mail confirms the write")
        await release.signal()
        #expect(await pending.value == .success)
        #expect(service.messages.first { $0.messageID == 1 }?.isRead == true)
        #expect(service.messages.first { $0.messageID == 2 }?.isRead == false, "Mail arriving during the operation must retain its server read state")
        #expect(service.canLoadMore)
        #expect(!service.isMutating)
    }

    @Test(arguments: ["Injected inbox failure", "Not authorized to send Apple events (-1743)"]) @MainActor
    func failedBulkReadRefreshesPartialChangesAndCanBeRetried(failure: String) async {
        var attempts = 0
        let service = MailService(
            commandRunner: { _, expectsSnapshot in
                if !expectsSnapshot {
                    attempts += 1
                    return attempts == 1 ? .failure(.failed(failure)) : .success(.succeeded)
                }
                return .success(.snapshot(MailSnapshot(
                    accounts: ["personal", "work"].map { MailScriptAccount(name: $0, emailAddresses: []) },
                    messages: ["personal", "work"].map { name in
                        MailScriptRow(
                            accountName: name, messageID: "1", sender: "sender@example.com",
                            subject: "Fixture", body: "Body", receivedAt: .distantPast,
                            isRead: name == "work" ? attempts > 0 : attempts > 1
                        )
                    }
                )))
            },
            indexReader: MailIndexReader(databaseURL: URL(fileURLWithPath: "/does/not/exist")),
            mailRunning: { true }
        )
        await service.refresh(checkForNewMail: false)

        let result = await service.markAllRead()

        if failure.contains("authorized") {
            #expect(result == .failed(AppLocalization.text("需要授权 zisla 控制 Mail.app\n请打开「系统设置 → 隐私与安全性 → 自动化」，\n在列表中找到并开启 zisla 对 Mail 的访问权限")))
        } else {
            #expect(result == .failed(failure))
        }
        #expect(service.messages.first { $0.accountName == "work" }?.isRead == true)
        #expect(service.messages.first { $0.accountName == "personal" }?.isRead == false)
        #expect(!service.isMutating)
        #expect(!service.isLoading)

        #expect(await service.markAllRead() == .success)
        #expect(service.unreadCount == 0)
        #expect(!service.isMutating)
    }

    @Test @MainActor
    func bulkReadDoesNotLaunchMailOrAlterReadFlagsWhenMailIsClosed() async {
        var isRunning = true
        var requests = 0
        let service = MailService(
            commandRunner: { _, _ in
                requests += 1
                return .success(.snapshot(makeMailServiceSnapshot(account: "work", messageID: 1)))
            },
            indexReader: MailIndexReader(databaseURL: URL(fileURLWithPath: "/does/not/exist")),
            mailRunning: { isRunning }
        )
        await service.refresh(checkForNewMail: false)
        let messages = service.messages
        isRunning = false

        #expect(await service.markAllRead() == .failed(MailService.mailUnavailableMessage(isRunning: false)!))
        #expect(service.messages == messages)
        #expect(requests == 1)
        #expect(!service.isMutating)
    }

    @Test(arguments: ["disabled", "missing"]) @MainActor
    func bulkReadCannotWriteToAnAccountOutsideTheEnabledSelection(accountName: String) async {
        var requests = 0
        let service = MailService(
            commandRunner: { _, _ in
                requests += 1
                return .success(.snapshot(MailSnapshot(
                    accounts: ["work", "disabled"].map { MailScriptAccount(name: $0, emailAddresses: []) },
                    messages: makeMailServiceSnapshot(account: "work", messageID: 1).messages
                )))
            },
            indexReader: MailIndexReader(databaseURL: URL(fileURLWithPath: "/does/not/exist")),
            mailRunning: { true }
        )
        service.start(accountNames: ["work"])
        service.stop()
        await service.refresh(checkForNewMail: false)
        let messages = service.messages

        #expect(await service.markAllRead(accountName: accountName) == .success)
        #expect(service.messages == messages)
        #expect(requests == 1, "An empty eligible scope must never fall back to all accounts")
    }

    @Test @MainActor
    func bulkReadWithNoAccountsIsANoOp() async {
        let service = MailService(
            commandRunner: { _, _ in
                Issue.record("An empty account list must not invoke Mail automation")
                return .failure(.failed("Unexpected command"))
            },
            indexReader: MailIndexReader(databaseURL: URL(fileURLWithPath: "/does/not/exist")),
            mailRunning: { true }
        )
        #expect(await service.markAllRead() == .success)
        #expect(service.messages.isEmpty)
        #expect(!service.isMutating)
    }

    @Test @MainActor
    func bulkReadSharesTheQueueWithIndividualMailOperations() async throws {
        let started = MailOperationQueueTestGate()
        let release = MailOperationQueueTestGate()
        var events: [String] = []
        let service = MailService(
            commandRunner: { source, expectsSnapshot in
                if expectsSnapshot {
                    return .success(.snapshot(makeMailServiceSnapshot(account: "work", messageID: 1)))
                }
                if source.contains("set read status of targetMessage") {
                    events.append("single-start")
                    await started.signal()
                    await release.wait()
                    events.append("single-end")
                } else {
                    events.append("bulk")
                }
                return .success(.succeeded)
            },
            indexReader: MailIndexReader(databaseURL: URL(fileURLWithPath: "/does/not/exist")),
            mailRunning: { true }
        )
        await service.refresh(checkForNewMail: false)
        let message = try #require(service.messages.first)
        let first = Task { await service.markRead(message) }
        await started.wait()
        let second = Task { await service.markAllRead() }
        await release.signal()

        #expect(await first.value == .success)
        #expect(await second.value == .success)
        #expect(events == ["single-start", "single-end", "bulk"])
        #expect(!service.isMutating)
    }

    @Test(arguments: [Set<String>(), ["personal"], ["personal", "work"], ["missing"]], [false, true]) @MainActor
    func bulkReadScriptContinuesAfterAnUnavailableInboxAndReportsFailure(accountNames: Set<String>, fails: Bool) throws {
        let source = MailService.markAllReadScript(accountNames: accountNames)
            .replacingOccurrences(of: "tell application \"Mail\"", with: "")
            .replacingOccurrences(of: "end tell", with: "")
            .replacingOccurrences(of: "set targetAccount to first account whose name is (targetAccountName as text)", with: """
                set targetAccount to targetAccountName as text
                if targetAccount is not in {"personal", "work"} then error "Account unavailable"
                """)
            .replacingOccurrences(of: "set read status of (every message of mailbox \"INBOX\" of targetAccount whose read status is false) to true", with: """
                if targetAccount is "personal" and \(fails ? "true" : "false") then error "Injected inbox failure" number -1743
                set end of changedAccounts to targetAccount
                """)
        let script = try #require(NSAppleScript(source: """
            using terms from application "Mail"
                set changedAccounts to {}
                set failureCode to 0
                try
                    \(source)
                on error number errorCode
                    set failureCode to errorCode
                end try
                return {changedAccounts, failureCode}
            end using terms from
            """))
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        #expect(error == nil, "The local fixture must not execute Mail.app object lookups")
        let changed = try #require(result.atIndex(1))
        let names = (1..<(changed.numberOfItems + 1)).compactMap { changed.atIndex($0)?.stringValue }
        #expect(names == accountNames.sorted().filter { $0 == "work" || ($0 == "personal" && !fails) })
        let expectedCode = accountNames.contains("missing") ? -2700 : (fails && accountNames.contains("personal") ? -1743 : 0)
        let failureCode = try #require(result.atIndex(2)?.int32Value)
        #expect(Int(failureCode) == expectedCode, "The Mail error code must survive partial success for permission failures")
    }

    @Test(arguments: ["work", "工作邮箱 \"A\" \\ Inbox", "Name\n\" & error \"Injected\" & \""]) @MainActor
    func bulkReadScriptCompilesAndKeepsAccountNamesAsData(accountName: String) throws {
        let source = MailService.markAllReadScript(accountNames: [accountName])
        let script = try #require(NSAppleScript(source: source))
        var error: NSDictionary?
        #expect(script.compileAndReturnError(&error))
        #expect(error == nil)
        #expect(source.contains("set targetAccountNames to {\(MailService.appleScriptString(accountName))}"))
        #expect(source.contains("every message of mailbox \"INBOX\" of targetAccount whose read status is false"))
    }

    @Test @MainActor
    func manualRefreshRequestsNewMailInsteadOfOnlyRereadingTheInbox() async {
        let service = MailService(
            commandRunner: { script, _ in
                let requestedNewMail = script.contains("check for new mail for mailAccount")
                return .success(.snapshot(makeMailServiceSnapshot(
                    account: "work", messageID: requestedNewMail ? 2 : 1
                )))
            },
            indexReader: MailIndexReader(databaseURL: URL(fileURLWithPath: "/does/not/exist")),
            mailRunning: { true }
        )

        await service.refresh()

        #expect(service.messages.map(\.messageID) == [2], "Manual refresh must request new mail, not just return cached inbox data")
        #expect(!service.isLoading)
        #expect(service.errorDescription == nil)
    }

    @Test @MainActor
    func automaticRefreshAndPaginationDoNotRequestNewMail() async {
        let pollingStarted = MailOperationQueueTestGate()
        var scripts: [String] = []
        let service = MailService(
            commandRunner: { script, _ in
                scripts.append(script)
                if scripts.count == 3 { await pollingStarted.signal() }
                return .success(.snapshot(makeMailServiceSnapshot(
                    account: "work", messageID: scripts.count, hasMore: scripts.count == 1
                )))
            },
            indexReader: MailIndexReader(databaseURL: URL(fileURLWithPath: "/does/not/exist")),
            mailRunning: { true }
        )

        await service.refresh(checkForNewMail: false)
        await service.loadMore()

        #expect(service.messages.map(\.messageID).sorted() == [1, 2])
        #expect(!service.canLoadMore)

        service.start(accountNames: ["work"])
        await pollingStarted.wait()
        service.stop()

        #expect(scripts.count == 3)
        #expect(scripts.allSatisfy { !$0.contains("check for new mail") })
    }

    @Test(arguments: [false, true]) @MainActor
    func mailOperationsOnlyReloadARunningMailAppWithoutCheckingForNewMail(isMailRunning: Bool) async throws {
        var mailAvailable = true
        var scripts: [String] = []
        let service = MailService(
            commandRunner: { script, _ in
                scripts.append(script)
                if script.contains("set read status") { return .success(.succeeded) }
                return .success(.snapshot(makeMailServiceSnapshot(account: "work", messageID: 1)))
            },
            indexReader: MailIndexReader(databaseURL: URL(fileURLWithPath: "/does/not/exist")),
            mailRunning: { mailAvailable }
        )
        await service.refresh(checkForNewMail: false)
        let message = try #require(service.messages.first)
        mailAvailable = isMailRunning

        let result = await service.markRead(message)

        #expect((result == .success) == isMailRunning)
        #expect(service.messages.first?.isRead == isMailRunning)
        #expect(scripts.count == (isMailRunning ? 3 : 1), "Only a running Mail.app may perform the write and reload the inbox")
        #expect(scripts.allSatisfy { !$0.contains("check for new mail") })
    }

    @Test @MainActor
    func manualRefreshFailureKeepsMessagesAndPaginationUntilRetrySucceeds() async {
        var requests = 0
        let service = MailService(
            commandRunner: { _, _ in
                requests += 1
                if requests == 2 { return .failure(.failed("Injected mail check failure")) }
                return .success(.snapshot(makeMailServiceSnapshot(
                    account: "work", messageID: requests, hasMore: requests == 1
                )))
            },
            indexReader: MailIndexReader(databaseURL: URL(fileURLWithPath: "/does/not/exist")),
            mailRunning: { true }
        )
        await service.refresh(checkForNewMail: false)
        let previousMessages = service.messages
        let previousGeneration = service.paginationGeneration

        await service.refresh()

        #expect(service.messages == previousMessages)
        #expect(service.paginationGeneration == previousGeneration)
        #expect(service.canLoadMore)
        #expect(service.errorDescription == "Injected mail check failure")
        #expect(!service.isLoading)

        await service.refresh()

        #expect(service.messages.map(\.messageID) == [3])
        #expect(service.errorDescription == nil)
        #expect(!service.canLoadMore)
        #expect(!service.isLoading)
    }

    @Test @MainActor
    func manualRefreshReadsTheIndexWithoutLaunchingMailWhenItIsClosed() async throws {
        let databaseURL = try makeMailServiceIndex()
        defer { try? FileManager.default.removeItem(at: databaseURL) }
        try executeMailServiceSQL("""
            INSERT INTO mailboxes (ROWID, url) VALUES (1, 'imap://work%40example.com@mail.example.com/INBOX');
            INSERT INTO messages (message_id, subject, mailbox) VALUES (7, 1, 1);
            """, at: databaseURL)
        let service = MailService(
            commandRunner: { _, _ in
                Issue.record("Refreshing the index must not launch Mail or request automation access")
                return .failure(.failed("Unexpected Mail command"))
            },
            indexReader: MailIndexReader(databaseURL: databaseURL),
            mailRunning: { false }
        )

        await service.refresh()

        #expect(service.messages.map(\.messageID) == [7])
        #expect(service.errorDescription == nil)
        #expect(!service.isLoading)
    }

    @Test @MainActor
    func repeatedManualRefreshDoesNotStartOverlappingMailChecks() async {
        let started = MailOperationQueueTestGate()
        let release = MailOperationQueueTestGate()
        var requests = 0
        let service = MailService(
            commandRunner: { _, _ in
                requests += 1
                await started.signal()
                await release.wait()
                return .success(.snapshot(makeMailServiceSnapshot(account: "work", messageID: 1)))
            },
            indexReader: MailIndexReader(databaseURL: URL(fileURLWithPath: "/does/not/exist")),
            mailRunning: { true }
        )
        let pending = Task { await service.refresh() }
        await started.wait()

        await service.refresh()

        #expect(requests == 1)
        #expect(service.isLoading)
        await release.signal()
        await pending.value
        #expect(service.messages.map(\.messageID) == [1])
        #expect(!service.isLoading)
    }

    @Test @MainActor
    func mailOperationsQueueInSubmissionOrderAndReturnIndividualResults() async {
        let queue = MailOperationQueue()
        let firstStarted = MailOperationQueueTestGate()
        let releaseFirst = MailOperationQueueTestGate()
        var events: [String] = []

        let first = Task { @MainActor in
            await queue.enqueue {
                events.append("first-start")
                await firstStarted.signal()
                await releaseFirst.wait()
                events.append("first-end")
                return .success
            }
        }
        await firstStarted.wait()

        let second = Task { @MainActor in
            await queue.enqueue {
                events.append("second")
                return .failed("second failed")
            }
        }

        await releaseFirst.signal()
        #expect(await first.value == .success)
        #expect(await second.value == .failed("second failed"))
        #expect(events == ["first-start", "first-end", "second"])
    }

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
    func runningMailProvidesAccountIdentitySenderAndFullBodyEvenWhenIndexIsReadable() async throws {
        let databaseURL = try makeMailServiceIndex()
        defer { try? FileManager.default.removeItem(at: databaseURL) }
        try executeMailServiceSQL("""
            INSERT INTO mailboxes (ROWID, url) VALUES (1, 'imap://11111111-2222-3333-4444-555555555555/INBOX');
            INSERT INTO subjects (ROWID, subject) VALUES (1, '快速主题');
            INSERT INTO summaries (ROWID, summary) VALUES (1, '快速摘要');
            INSERT INTO messages (message_id, subject, summary, date_received, display_date, mailbox, read, deleted)
            VALUES (42, 1, 1, 1_720_000_000, 1_720_000_000, 1, 0, 0);
            """, at: databaseURL)

        let body = String(repeating: "完整正文", count: 400) + "\n\n最后一段"
        let service = MailService(
            commandRunner: { _, _ in
                .success(.snapshot(MailSnapshot(
                    accounts: [MailScriptAccount(name: "工作邮箱", emailAddresses: ["work@example.com"])],
                    messages: [MailScriptRow(
                        accountName: "工作邮箱",
                        messageID: "7",
                        sender: "Sender <sender@example.com>",
                        subject: "完整主题",
                        body: body,
                        receivedAt: Date(timeIntervalSince1970: 1_720_000_000),
                        isRead: false
                    )]
                )))
            },
            indexReader: MailIndexReader(databaseURL: databaseURL),
            mailRunning: { true }
        )

        await service.refresh()

        #expect(service.accounts == [MailAccount(name: "工作邮箱", emailAddresses: ["work@example.com"])])
        #expect(service.messages.map(\.messageID) == [7])
        #expect(service.messages.first?.accountName == "工作邮箱")
        #expect(service.messages.first?.sender == "Sender <sender@example.com>")
        #expect(service.messages.first?.body == body)
        #expect(service.errorDescription == nil)
    }

    @Test @MainActor
    func readsMailAppWhenLocalIndexReturnsNoMessages() async throws {
        let databaseURL = try makeMailServiceIndex()
        defer { try? FileManager.default.removeItem(at: databaseURL) }
        try executeMailServiceSQL(
            "INSERT INTO mailboxes (ROWID, url) VALUES (1, 'imap://work%40example.com@mail.example.com/INBOX');",
            at: databaseURL
        )

        var appleScriptCalls = 0
        let service = MailService(
            commandRunner: { _, _ in
                appleScriptCalls += 1
                return .success(.snapshot(MailSnapshot(
                    accounts: [MailScriptAccount(name: "work@example.com", emailAddresses: ["work@example.com"])],
                    messages: [MailScriptRow(
                        accountName: "work@example.com",
                        messageID: "7",
                        sender: "sender@example.com",
                        subject: "来自 Mail.app",
                        body: "正文",
                        receivedAt: .now,
                        isRead: false
                    )]
                )))
            },
            indexReader: MailIndexReader(databaseURL: databaseURL),
            mailRunning: { true }
        )

        await service.refresh()

        #expect(appleScriptCalls == 1)
        #expect(service.messages.map(\.messageID) == [7])
    }

    @Test(arguments: [false, true]) @MainActor
    func runningMailDoesNotHideAnEmptyInboxOrAnErrorBehindIndexData(fails: Bool) async throws {
        let databaseURL = try makeMailServiceIndex()
        defer { try? FileManager.default.removeItem(at: databaseURL) }
        try executeMailServiceSQL("""
            INSERT INTO mailboxes (ROWID, url) VALUES (1, 'imap://work%40example.com@mail.example.com/INBOX');
            INSERT INTO messages (message_id, subject, mailbox) VALUES (42, 1, 1);
            """, at: databaseURL)
        let service = MailService(
            commandRunner: { _, _ in
                fails
                    ? .failure(.failed("Mail access denied"))
                    : .success(.snapshot(MailSnapshot(accounts: [], messages: [])))
            },
            indexReader: MailIndexReader(databaseURL: databaseURL),
            mailRunning: { true }
        )

        await service.refresh()

        #expect(service.messages.isEmpty)
        #expect(service.accounts.isEmpty)
        #expect(service.errorDescription == (fails ? "Mail access denied" : nil))
        #expect(!service.needsMailIndexAccess)
        #expect(!service.isLoading)
    }

    @Test(arguments: [false, true]) @MainActor
    func refreshKeepsLoadedPagesCurrentAndResetsTheWindowWhenAccountsChange(isMailRunning: Bool) async throws {
        let databaseURL = try makeMailServiceIndex()
        defer { try? FileManager.default.removeItem(at: databaseURL) }
        let accountName = "work@example.com"
        var inboxRows = (1...135).map { index in
            MailScriptRow(
                accountName: accountName,
                messageID: String(index),
                sender: "sender@example.com",
                subject: "Message",
                body: "Body",
                receivedAt: Date(timeIntervalSince1970: Double(1_000 - index)),
                isRead: true
            )
        }
        let values = (1...135).map { "(\($0), 1, \(1_000 - $0), 1, 1)" }.joined(separator: ",")
        try executeMailServiceSQL("""
            INSERT INTO mailboxes (ROWID, url) VALUES (1, 'imap://work%40example.com@mail.example.com/INBOX');
            INSERT INTO messages (message_id, subject, date_received, mailbox, read) VALUES \(values);
            """, at: databaseURL)
        let service = MailService(
            commandRunner: { script, _ in
                #expect(isMailRunning, "Reading the index must not launch Mail")
                guard let (offset, limit) = mailServiceRequestBounds(script) else {
                    return .failure(.failed("Missing inbox request bounds"))
                }
                return .success(.snapshot(MailSnapshot(
                    accounts: [MailScriptAccount(name: accountName, emailAddresses: [accountName])],
                    messages: Array(inboxRows.dropFirst(offset).prefix(limit)),
                    hasMore: offset + limit < inboxRows.count
                )))
            },
            indexReader: MailIndexReader(databaseURL: databaseURL),
            mailRunning: { isMailRunning }
        )
        defer { service.stop() }

        await service.refresh()
        #expect(service.messages.count == 10)
        for _ in 0..<12 { await service.loadMore() }
        #expect(service.messages.count == 130)

        inboxRows.removeAll { ["5", "115"].contains($0.messageID) }
        inboxRows.insert(MailScriptRow(
            accountName: accountName,
            messageID: "1000",
            sender: "new@example.com",
            subject: "New message",
            body: "New body",
            receivedAt: Date(timeIntervalSince1970: 2_000),
            isRead: false
        ), at: 0)
        try executeMailServiceSQL("""
            UPDATE messages SET deleted = 1 WHERE message_id IN (5, 115);
            INSERT INTO messages (message_id, subject, date_received, mailbox) VALUES (1000, 1, 2000, 1);
            """, at: databaseURL)

        await service.refresh()
        #expect(service.messages.map(\.messageID) == inboxRows.prefix(130).compactMap { Int($0.messageID) })
        #expect(service.canLoadMore)
        await service.loadMore()
        #expect(service.messages.map(\.messageID) == inboxRows.compactMap { Int($0.messageID) })
        #expect(!service.canLoadMore)

        service.start(accountNames: [accountName])
        await service.refresh()
        #expect(service.messages.count == 10)
        #expect(service.canLoadMore)
    }

    @Test @MainActor
    func refreshingAfterUnreadableMessagesDoesNotShrinkTheLoadedWindow() async {
        let rows = (1...25).map { index in
            MailScriptRow(
                accountName: "work", messageID: String(index), sender: "sender@example.com",
                subject: "Message", body: "Body",
                receivedAt: Date(timeIntervalSince1970: Double(1_000 - index)), isRead: true
            )
        }
        let unreadableIDs: Set<String> = ["2", "4", "6", "8", "10"]
        let service = MailService(
            commandRunner: { script, _ in
                guard let (offset, limit) = mailServiceRequestBounds(script) else {
                    return .failure(.failed("Missing inbox request bounds"))
                }
                return .success(.snapshot(MailSnapshot(
                    accounts: [MailScriptAccount(name: "work", emailAddresses: ["work@example.com"])],
                    messages: rows.dropFirst(offset).prefix(limit).filter { !unreadableIDs.contains($0.messageID) },
                    hasMore: offset + limit < rows.count
                )))
            },
            indexReader: MailIndexReader(databaseURL: URL(fileURLWithPath: "/does/not/exist")),
            mailRunning: { true }
        )
        await service.refresh()
        await service.loadMore()
        await service.loadMore()
        let messages = service.messages
        #expect(messages.count == 20)

        for _ in 0..<2 {
            await service.refresh()
            #expect(service.messages == messages)
            #expect(!service.canLoadMore)
        }
    }

    @Test(arguments: [false, true]) @MainActor
    func stoppingDiscardsLateRefreshResults(fails: Bool) async {
        let started = MailOperationQueueTestGate()
        let release = MailOperationQueueTestGate()
        let service = MailService(
            commandRunner: { _, _ in
                await started.signal()
                await release.wait()
                return fails
                    ? .failure(.failed("Late failure"))
                    : .success(.snapshot(makeMailServiceSnapshot(account: "old", messageID: 1)))
            },
            indexReader: MailIndexReader(databaseURL: URL(fileURLWithPath: "/does/not/exist")),
            mailRunning: { true }
        )
        let refresh = Task { await service.refresh() }
        await started.wait()

        service.stop()
        await release.signal()
        await refresh.value

        #expect(service.messages.isEmpty)
        #expect(service.accounts.isEmpty)
        #expect(service.errorDescription == nil)
        #expect(service.paginationGeneration == 0)
        #expect(!service.isLoading)
    }

    @Test @MainActor
    func staleRefreshCannotClearNewRefreshLoadingState() async {
        let firstStarted = MailOperationQueueTestGate()
        let releaseFirst = MailOperationQueueTestGate()
        let secondStarted = MailOperationQueueTestGate()
        let releaseSecond = MailOperationQueueTestGate()
        var requestCount = 0
        let service = MailService(
            commandRunner: { _, _ in
                requestCount += 1
                if requestCount == 1 {
                    await firstStarted.signal()
                    await releaseFirst.wait()
                    return .failure(.failed("Superseded failure"))
                }
                await secondStarted.signal()
                await releaseSecond.wait()
                return .success(.snapshot(makeMailServiceSnapshot(account: "new", messageID: 2)))
            },
            indexReader: MailIndexReader(databaseURL: URL(fileURLWithPath: "/does/not/exist")),
            mailRunning: { true }
        )
        let first = Task { await service.refresh() }
        await firstStarted.wait()
        service.stop()
        let second = Task { await service.refresh() }
        await secondStarted.wait()

        await releaseFirst.signal()
        await first.value
        #expect(service.isLoading)
        #expect(service.errorDescription == nil)

        await releaseSecond.signal()
        await second.value
        #expect(service.messages.map(\.messageID) == [2])
        #expect(!service.isLoading)
    }

    @Test(arguments: [false, true], [false, true]) @MainActor
    func restartedPollingDiscardsLateManualRefreshResults(fails: Bool, oldCompletesFirst: Bool) async {
        let firstStarted = MailOperationQueueTestGate()
        let releaseFirst = MailOperationQueueTestGate()
        let secondStarted = MailOperationQueueTestGate()
        let releaseSecond = MailOperationQueueTestGate()
        var scripts: [String] = []
        let service = MailService(
            commandRunner: { script, _ in
                scripts.append(script)
                switch scripts.count {
                case 1:
                    await firstStarted.signal()
                    await releaseFirst.wait()
                    return fails
                        ? .failure(.failed("Late failure"))
                        : .success(.snapshot(makeMailServiceSnapshot(account: "old", messageID: 1)))
                case 2:
                    await secondStarted.signal()
                    await releaseSecond.wait()
                    return .success(.snapshot(makeMailServiceSnapshot(account: "new", messageID: 2, hasMore: true)))
                default:
                    return .success(.snapshot(makeMailServiceSnapshot(account: "new", messageID: 3)))
                }
            },
            indexReader: MailIndexReader(databaseURL: URL(fileURLWithPath: "/does/not/exist")),
            mailRunning: { true }
        )
        defer { service.stop() }
        let first = Task { await service.refresh() }
        await firstStarted.wait()
        service.stop()
        service.start(accountNames: ["new"])
        await secondStarted.wait()

        let completed = AsyncStream<Void>.makeStream()
        let observation = service.$isLoading.filter { !$0 }.prefix(1).sink { _ in
            completed.continuation.yield()
        }
        defer {
            observation.cancel()
            completed.continuation.finish()
        }
        if oldCompletesFirst {
            await releaseFirst.signal()
            await first.value
            #expect(service.isLoading)
            #expect(service.messages.isEmpty)
            #expect(service.errorDescription == nil)
        }
        await releaseSecond.signal()
        for await _ in completed.stream { break }
        if !oldCompletesFirst {
            await releaseFirst.signal()
            await first.value
        }

        #expect(service.messages.map(\.messageID) == [2])
        #expect(service.accounts.map(\.id) == ["new"])
        #expect(service.paginationGeneration == 1)
        #expect(service.canLoadMore)
        #expect(service.errorDescription == nil)
        #expect(!service.needsMailIndexAccess)
        #expect(!service.isLoading)
        await service.loadMore()
        #expect(scripts.count == 3)
        #expect(scripts.last?.contains("set remainingOffset to 10") == true)
        #expect(scripts.last?.contains("set selectedAccountNames to {\"new\"}") == true)
        #expect(service.messages.map(\.messageID).sorted() == [2, 3])
        #expect(service.paginationGeneration == 2)
        #expect(!service.canLoadMore)
    }

    @Test @MainActor
    func selectingAccountRefreshesWhilePreviousSelectionIsStillLoading() async {
        let firstStarted = MailOperationQueueTestGate()
        let releaseFirst = MailOperationQueueTestGate()
        var scripts: [String] = []
        let service = MailService(
            commandRunner: { script, _ in
                scripts.append(script)
                if scripts.count == 1 {
                    await firstStarted.signal()
                    await releaseFirst.wait()
                    return .success(.snapshot(makeMailServiceSnapshot(account: "old", messageID: 1)))
                }
                return .success(.snapshot(makeMailServiceSnapshot(account: "new", messageID: 2)))
            },
            indexReader: MailIndexReader(databaseURL: URL(fileURLWithPath: "/does/not/exist")),
            mailRunning: { true }
        )
        let first = Task {
            service.start(accountNames: ["old"])
            await service.refresh()
        }
        await firstStarted.wait()

        service.start(accountNames: ["new"])
        await service.refresh()
        #expect(service.messages.map(\.accountName) == ["new"])
        #expect(scripts.last?.contains("set selectedAccountNames to {\"new\"}") == true)

        service.stop()
        await releaseFirst.signal()
        await first.value
        #expect(service.messages.map(\.messageID) == [2])
    }

    @Test @MainActor
    func cancelledRefreshDoesNotFallBackToMail() async {
        var scriptRequests = 0
        let service = MailService(
            commandRunner: { _, _ in
                scriptRequests += 1
                return .failure(.failed("Cancelled request must not reach Mail"))
            },
            indexReader: MailIndexReader(databaseURL: URL(fileURLWithPath: "/does/not/exist")),
            mailRunning: { true }
        )
        let refresh = Task { await service.refresh() }
        refresh.cancel()
        await refresh.value

        #expect(scriptRequests == 0)
        #expect(service.errorDescription == nil)
        #expect(!service.isLoading)
    }

    @Test(arguments: [false, true]) @MainActor
    func cancellingRefreshPreservesLoadedMessagesAndPagination(fails: Bool) async {
        let started = MailOperationQueueTestGate()
        let release = MailOperationQueueTestGate()
        var requestCount = 0
        let service = MailService(
            commandRunner: { _, _ in
                requestCount += 1
                if requestCount == 1 {
                    return .success(.snapshot(makeMailServiceSnapshot(account: "current", messageID: 1)))
                }
                await started.signal()
                await release.wait()
                return fails
                    ? .failure(.failed("Cancelled failure"))
                    : .success(.snapshot(makeMailServiceSnapshot(account: "old", messageID: 2)))
            },
            indexReader: MailIndexReader(databaseURL: URL(fileURLWithPath: "/does/not/exist")),
            mailRunning: { true }
        )
        await service.refresh()
        let messages = service.messages
        let accounts = service.accounts
        let refresh = Task { await service.refresh() }
        await started.wait()
        refresh.cancel()
        await release.signal()
        await refresh.value

        #expect(service.messages == messages)
        #expect(service.accounts == accounts)
        #expect(service.paginationGeneration == 1)
        #expect(!service.canLoadMore)
        #expect(service.errorDescription == nil)
        #expect(!service.isLoading)
    }

    @Test @MainActor
    func failedRefreshRetainsPaginationUntilRetrySucceeds() async {
        var scripts: [String] = []
        let service = MailService(
            commandRunner: { script, _ in
                scripts.append(script)
                if scripts.count == 1 {
                    return .success(.snapshot(makeMailServiceSnapshot(account: "current", messageID: 1, hasMore: true)))
                }
                if scripts.count == 2 {
                    return .failure(.failed("Refresh failed"))
                }
                return .success(.snapshot(makeMailServiceSnapshot(account: "current", messageID: 2)))
            },
            indexReader: MailIndexReader(databaseURL: URL(fileURLWithPath: "/does/not/exist")),
            mailRunning: { true }
        )
        service.start(accountNames: ["current"])
        await service.refresh()
        let messages = service.messages
        let accounts = service.accounts
        service.stop()
        service.start(accountNames: ["current"])
        await service.refresh()

        #expect(service.messages == messages)
        #expect(service.accounts == accounts)
        #expect(service.paginationGeneration == 1)
        #expect(service.canLoadMore)
        #expect(service.errorDescription == "Refresh failed")
        #expect(!service.isLoading)

        await service.loadMore()
        #expect(scripts.last?.contains("set remainingOffset to 10") == true)
        #expect(service.messages.map(\.messageID).sorted() == [1, 2])
        #expect(service.paginationGeneration == 2)
        #expect(!service.canLoadMore)
        #expect(service.errorDescription == nil)
        service.stop()
    }

    @Test @MainActor
    func changingAccountsPausesPaginationUntilTheFirstPageSucceeds() async {
        var scripts: [String] = []
        let service = MailService(
            commandRunner: { script, _ in
                scripts.append(script)
                if scripts.count == 1 {
                    return .success(.snapshot(makeMailServiceSnapshot(account: "old", messageID: 1, hasMore: true)))
                }
                if scripts.count == 2 {
                    return .failure(.failed("New account unavailable"))
                }
                return .success(.snapshot(makeMailServiceSnapshot(account: "new", messageID: 2)))
            },
            indexReader: MailIndexReader(databaseURL: URL(fileURLWithPath: "/does/not/exist")),
            mailRunning: { true }
        )
        service.start(accountNames: ["old"])
        await service.refresh()
        #expect(service.canLoadMore)

        service.start(accountNames: ["new"])
        await service.refresh()
        #expect(service.errorDescription == "New account unavailable")
        #expect(!service.canLoadMore)
        await service.loadMore()
        #expect(scripts.count == 2)

        await service.refresh()
        #expect(scripts.last?.contains("set selectedAccountNames to {\"new\"}") == true)
        #expect(scripts.last?.contains("set remainingOffset to 0") == true)
        #expect(service.messages.map(\.accountName) == ["new"])
        #expect(service.errorDescription == nil)
        #expect(!service.isLoading)
        service.stop()
    }

    @Test @MainActor
    func cancelledRefreshKeepsIndexErrorAndSubsequentRefreshCanRecover() async {
        let started = MailOperationQueueTestGate()
        let release = MailOperationQueueTestGate()
        var isMailRunning = false
        var requestCount = 0
        let service = MailService(
            commandRunner: { _, _ in
                requestCount += 1
                if requestCount == 1 {
                    await started.signal()
                    await release.wait()
                    return .failure(.failed("Cancelled failure"))
                }
                if requestCount == 2 {
                    return .failure(.failed("Mail fetch failed"))
                }
                return .success(.snapshot(makeMailServiceSnapshot(account: "current", messageID: 1)))
            },
            indexReader: MailIndexReader(databaseURL: URL(fileURLWithPath: "/does/not/exist")),
            mailRunning: { isMailRunning }
        )
        await service.refresh()
        let indexError = service.errorDescription
        #expect(indexError != nil)
        #expect(service.needsMailIndexAccess)

        isMailRunning = true
        let refresh = Task { await service.refresh() }
        await started.wait()
        refresh.cancel()
        await release.signal()
        await refresh.value

        #expect(service.errorDescription == indexError)
        #expect(service.needsMailIndexAccess)
        #expect(service.messages.isEmpty)
        #expect(service.paginationGeneration == 0)
        #expect(!service.isLoading)

        await service.refresh()
        #expect(service.errorDescription == "Mail fetch failed")
        #expect(!service.needsMailIndexAccess)
        await service.refresh()
        #expect(service.errorDescription == nil)
        #expect(!service.needsMailIndexAccess)
        #expect(service.messages.map(\.messageID) == [1])
    }

    @Test @MainActor
    func reselectingTheSameAccountsKeepsTheCurrentRefresh() async {
        let started = MailOperationQueueTestGate()
        let release = MailOperationQueueTestGate()
        var requestCount = 0
        let service = MailService(
            commandRunner: { _, _ in
                requestCount += 1
                if requestCount == 1 {
                    await started.signal()
                    await release.wait()
                }
                return .success(.snapshot(makeMailServiceSnapshot(account: "current", messageID: requestCount)))
            },
            indexReader: MailIndexReader(databaseURL: URL(fileURLWithPath: "/does/not/exist")),
            mailRunning: { true }
        )
        let refresh = Task {
            service.start(accountNames: ["current"])
            await service.refresh()
        }
        await started.wait()
        service.start(accountNames: ["current"])
        #expect(service.isLoading)
        await service.refresh()
        #expect(requestCount == 1)

        await release.signal()
        await refresh.value
        service.stop()
        #expect(service.messages.map(\.messageID) == [1])
        #expect(!service.isLoading)
    }

    @Test @MainActor
    func stoppingBeforeIndexResponseDiscardsItsFailure() async {
        weak var activeService: MailService?
        let service = MailService(
            commandRunner: { _, _ in .failure(.failed("Mail is unavailable")) },
            indexReader: MailIndexReader(databaseURL: URL(fileURLWithPath: "/does/not/exist")),
            mailRunning: {
                activeService?.stop()
                return false
            }
        )
        activeService = service
        await service.refresh()

        #expect(service.errorDescription == nil)
        #expect(!service.needsMailIndexAccess)
        #expect(!service.isLoading)
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

    @Test(arguments: [false, true], [
        [String](),
        ["invoice.pdf"],
        ["报告 100%.pdf", "quote\" and \\ path.txt", "line\nbreak.txt", "x\" & error \"injected.txt"],
    ]) @MainActor
    func attachmentScriptsSendEverySelectedFileAndPreserveTheBody(isReply: Bool, fileNames: [String]) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let urls = fileNames.map { directory.appendingPathComponent($0) }
        let data = Data("Attachment fixture".utf8)
        for url in urls { try data.write(to: url) }
        let body = "第一行\n第二行包含 \"引号\" 和 \\ 路径"
        let message = MailService.messages(from: makeMailServiceSnapshot(account: "work", messageID: 42).messages)[0]
        let source = isReply
            ? MailService.replyScript(message: message, body: body, attachmentURLs: urls)
            : MailService.composeScript(fromAddress: "work@example.com", to: ["alice@example.com"],
                                        subject: "Files", body: body, attachmentURLs: urls)
        let script = try #require(NSAppleScript(source: source))
        var error: NSDictionary?
        #expect(script.compileAndReturnError(&error), "Attachment scripts must compile against Mail's real dictionary")
        #expect(error == nil)

        let result = try executeMailAttachmentFixture(source, isReply: isReply)

        #expect(result.atIndex(1)?.booleanValue == true)
        let paths = try #require(result.atIndex(2))
        let attachedURLs = (0..<paths.numberOfItems).compactMap { paths.atIndex($0 + 1)?.stringValue }
            .map { URL(fileURLWithPath: $0).resolvingSymlinksInPath() }
        #expect(attachedURLs == urls.map { $0.resolvingSymlinksInPath() },
                "Every selected file must be attached before send, including literal special characters")
        #expect(result.atIndex(3)?.stringValue == body + (isReply ? "\r\rOriginal body" : ""),
                "Attachments must not replace or append file-name placeholders to the message body")
        #expect(result.atIndex(4)?.int32Value == 0)
        for url in urls { #expect(try Data(contentsOf: url) == data, "Sending must leave source files unchanged") }
    }

    @Test(arguments: [false, true]) @MainActor
    func missingAttachmentStopsTheScriptBeforeSending(isReply: Bool) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let existing = directory.appendingPathComponent("exists.txt")
        let missing = directory.appendingPathComponent("removed.pdf")
        try Data("Keep this file".utf8).write(to: existing)
        let message = MailService.messages(from: makeMailServiceSnapshot(account: "work", messageID: 42).messages)[0]
        let source = isReply
            ? MailService.replyScript(message: message, body: "Body", attachmentURLs: [existing, missing])
            : MailService.composeScript(fromAddress: nil, to: ["alice@example.com"], subject: "Files",
                                        body: "Body", attachmentURLs: [existing, missing])

        let result = try executeMailAttachmentFixture(source, isReply: isReply)

        #expect(result.atIndex(1)?.booleanValue == false, "An unreadable attachment must prevent send")
        #expect(result.atIndex(2)?.numberOfItems == 1)
        let attachedPath = try #require(result.atIndex(2)?.atIndex(1)?.stringValue)
        #expect(URL(fileURLWithPath: attachedPath).resolvingSymlinksInPath() == existing.resolvingSymlinksInPath())
        #expect(result.atIndex(4)?.int32Value == -1700, "A missing file must fail alias coercion before send")
        #expect(try String(contentsOf: existing, encoding: .utf8) == "Keep this file")
        #expect(!FileManager.default.fileExists(atPath: missing.path))
    }

    @Test(arguments: [false, true], [false, true]) @MainActor
    func attachmentOperationsForwardFilesAndReleaseMutationState(isReply: Bool, fails: Bool) async throws {
        let urls = [URL(fileURLWithPath: "/fixture/report.pdf"), URL(fileURLWithPath: "/fixture/photo.png")]
        var mutationScripts: [String] = []
        var refreshes = 0
        let service = MailService(
            commandRunner: { source, expectsSnapshot in
                if expectsSnapshot {
                    refreshes += 1
                    return .success(.snapshot(makeMailServiceSnapshot(account: "work", messageID: 42, hasMore: true)))
                }
                mutationScripts.append(source)
                return fails ? .failure(.failed("Attachment file not found (-43)")) : .success(.succeeded)
            },
            indexReader: MailIndexReader(databaseURL: URL(fileURLWithPath: "/does/not/exist")),
            mailRunning: { true }
        )
        await service.refresh(checkForNewMail: false)
        let messages = service.messages
        let generation = service.paginationGeneration
        let message = try #require(messages.first)

        let result = isReply
            ? await service.reply(to: message, body: "Body", attachmentURLs: urls)
            : await service.send(fromAddress: "work@example.com", to: "alice@example.com, bob@example.com",
                                 subject: "Files", body: "Body", attachmentURLs: urls)

        #expect(result == (fails ? .failed("Attachment file not found (-43)") : .success))
        let source = try #require(mutationScripts.first)
        for url in urls {
            #expect(source.contains("file name:(POSIX file \(MailService.appleScriptString(url.path)) as alias)"),
                    "The public send/reply operation must pass each selected URL to Mail")
        }
        #expect(service.messages == messages)
        #expect(service.canLoadMore)
        #expect(service.paginationGeneration == generation + (fails ? 0 : 1))
        #expect(refreshes == (fails ? 1 : 2), "A failed attachment operation must not refresh as if it was sent")
        #expect(!service.isMutating, "Both successful and failed operations must release the mutation state")
    }

    @Test(arguments: [false, true]) @MainActor
    func attachmentFreeOperationsKeepExistingPublicCalls(isReply: Bool) async throws {
        var mutationSource = ""
        let service = MailService(
            commandRunner: { source, expectsSnapshot in
                if expectsSnapshot { return .success(.snapshot(makeMailServiceSnapshot(account: "work", messageID: 42))) }
                mutationSource = source
                return .success(.succeeded)
            },
            indexReader: MailIndexReader(databaseURL: URL(fileURLWithPath: "/does/not/exist")),
            mailRunning: { true }
        )
        let message = MailService.messages(from: makeMailServiceSnapshot(account: "work", messageID: 42).messages)[0]
        let result = isReply
            ? await service.reply(to: message, body: "Body")
            : await service.send(fromAddress: nil, to: "alice@example.com", subject: "No files", body: "Body")

        #expect(result == .success)
        #expect(!mutationSource.contains("make new attachment"))
        let fixture = try executeMailAttachmentFixture(mutationSource, isReply: isReply)
        #expect(fixture.atIndex(1)?.booleanValue == true)
        #expect(fixture.atIndex(2)?.numberOfItems == 0)
    }

    @Test(arguments: [false, true], [true, false]) @MainActor
    func attachmentsDoNotBypassBodyValidationOrLaunchMail(isReply: Bool, isMailRunning: Bool) async {
        var requestedSources: [String] = []
        let service = MailService(
            commandRunner: { source, _ in
                requestedSources.append(source)
                return .success(.succeeded)
            },
            indexReader: MailIndexReader(databaseURL: URL(fileURLWithPath: "/does/not/exist")),
            mailRunning: { isMailRunning }
        )
        let message = MailService.messages(from: makeMailServiceSnapshot(account: "work", messageID: 42).messages)[0]
        let urls = [URL(fileURLWithPath: "/fixture/report.pdf")]
        let body = isMailRunning ? " \n\t " : "Body"
        let result = isReply
            ? await service.reply(to: message, body: body, attachmentURLs: urls)
            : await service.send(fromAddress: nil, to: "alice@example.com", subject: "Files", body: body,
                                 attachmentURLs: urls)

        let expected = isMailRunning
            ? (isReply ? "回复内容不能为空" : "邮件正文不能为空")
            : MailService.mailUnavailableMessage(isRunning: false)!
        #expect(result == .failed(expected))
        #expect(requestedSources.isEmpty, "Invalid input or a closed Mail.app must not issue any script")
        #expect(!service.isMutating)
    }

    @Test @MainActor
    func inboxScriptIncludesAllAccountsButOnlyReadsSelectedInboxes() {
        let script = MailService.inboxScript(accountNames: ["工作邮箱", "个人邮箱"])

        #expect(script.contains("set selectedAccountNames to {"))
        #expect(script.contains("\"工作邮箱\""))
        #expect(script.contains("\"个人邮箱\""))
        #expect(script.contains("set accountList to every account"))
        #expect(script.contains("repeat with i from 1 to accountCount"))
        #expect(script.contains("set accountName to name of mailAccount as text"))
        #expect(script.contains("set rawAddresses to email addresses of mailAccount"))
        #expect(!script.contains("set accountProperties to properties of mailAccount"))
        #expect(script.contains("set end of accountRows to {accountName, accountAddresses}"))
        #expect(script.contains("accountName is in selectedAccountNames"))
    }

    @Test @MainActor
    func inboxScriptReadsRequestedPageAndSignalsOlderMessages() {
        let script = MailService.inboxScript(accountNames: [], pageSize: 10, offset: 20)

        #expect(script.contains("set remainingOffset to 20"))
        #expect(script.contains("set remainingPageSize to 10"))
        #expect(script.contains("set startIndex to remainingOffset + 1"))
        #expect(script.contains("set endIndex to remainingOffset + remainingPageSize"))
        #expect(script.contains("set messageProperties to properties of mailMessage"))
        #expect(script.contains("id of messageProperties as text"))
        #expect(script.contains("content of messageProperties"))
        #expect(script.contains("set remainingPageSize to remainingPageSize - (endIndex - startIndex + 1)"))
        #expect(script.contains("if startIndex <= endIndex then"))
        #expect(script.contains("set hasMoreMessages to true"))
        #expect(script.contains("return {accountRows, messageRows, hasMoreMessages}"))
    }

    @Test(arguments: [false, true]) @MainActor
    func inboxScriptCompilesAgainstTheMailDictionary(checkForNewMail: Bool) throws {
        let script = try #require(NSAppleScript(source: MailService.inboxScript(
            accountNames: ["work"], checkForNewMail: checkForNewMail
        )))
        var error: NSDictionary?

        #expect(script.compileAndReturnError(&error))
        #expect(error == nil)
    }

    @Test(arguments: [Set<String>(), ["work"], ["missing"]], [false, true]) @MainActor
    func inboxChecksOnlySelectedAccountsBeforeReadingThem(accountNames: Set<String>, fails: Bool) throws {
        let source = MailService.inboxScript(accountNames: accountNames, checkForNewMail: true)
            .replacingOccurrences(of: "tell application \"Mail\"", with: "")
            .replacingOccurrences(of: "end tell", with: "")
            .replacingOccurrences(of: "every account", with: "fixtureAccounts")
            .replacingOccurrences(of: "check for new mail for mailAccount", with: """
                set end of requestEvents to "check:" & name of mailAccount
                if \(fails ? "true" : "false") then error "Injected mail check failure"
                """)
            .replacingOccurrences(of: "set inboxMessages to messages of mailbox \"INBOX\" of mailAccount", with: """
                set end of requestEvents to "read:" & name of mailAccount
                set inboxMessages to {}
                """)
            .replacingOccurrences(of: "return {accountRows, messageRows, hasMoreMessages}", with: "return requestEvents")
        let script = try #require(NSAppleScript(source: """
            using terms from application "Mail"
                set requestEvents to {}
                set fixtureAccounts to {{name:"personal", email addresses:{"personal@example.com"}}, {name:"work", email addresses:{"work@example.com"}}}
                \(source)
            end using terms from
            """))
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        let selected = ["personal", "work"].filter { accountNames.isEmpty || accountNames.contains($0) }

        if fails && !selected.isEmpty {
            #expect((error?[NSAppleScript.errorMessage] as? String)?.contains("Injected mail check failure") == true,
                    "A failed mail check must not be reported as a successful cache refresh")
        } else {
            #expect(error == nil)
            let events = (0..<result.numberOfItems).compactMap { result.atIndex($0 + 1)?.stringValue }
            #expect(events == selected.flatMap { ["check:\($0)", "read:\($0)"] })
        }
    }

    @Test(arguments: [
        "",
        "第一段\n\n第二段包含 \"引号\" 和 \\ 路径",
        String(repeating: "完整正文🪷", count: 400) + "\n\n最后一段",
    ], [false, true]) @MainActor
    func inboxScriptPreservesCompleteMessageBody(body: String, sourceAvailable: Bool) throws {
        // Replace only Mail's object lookups; execute the generated paging and body logic locally.
        let source = MailService.inboxScript(accountNames: [])
            .replacingOccurrences(of: "tell application \"Mail\"", with: "")
            .replacingOccurrences(of: "end tell", with: "")
            .replacingOccurrences(of: "every account", with: "fixtureAccounts")
            .replacingOccurrences(of: "messages of mailbox \"INBOX\" of mailAccount", with: "fixtureInbox of mailAccount")
            .replacingOccurrences(of: "properties of mailMessage", with: "mailMessage")
        let html = "<html><body><h1>邮件提醒 🪷</h1><a href=\"https://example.com\">查看详情</a></body></html>"
        let rawSource = try #require(String(data: Data(("Content-Type: text/html; charset=utf-8\n\n" + html).utf8), encoding: .isoLatin1))
        let sourceProperty = sourceAvailable ? ", source:\(MailService.appleScriptString(rawSource))" : ""
        let script = try #require(NSAppleScript(source: """
            using terms from application "Mail"
                set fixtureDate to current date
                set year of fixtureDate to 2024
                set month of fixtureDate to January
                set day of fixtureDate to 1
                set time of fixtureDate to 0
                set fixtureMessage to {id:7, sender:"sender@example.com", subject:"Fixture", content:\(MailService.appleScriptString(body)), date received:fixtureDate, read status:false\(sourceProperty)}
                set fixtureAccounts to {{name:"Work", email addresses:{"work@example.com"}, fixtureInbox:{fixtureMessage}}}
                \(source)
            end using terms from
            """))
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)

        #expect(error == nil)
        let rows = try #require(result.atIndex(2))
        #expect(rows.numberOfItems == 1)
        #expect(rows.atIndex(1)?.atIndex(5)?.stringValue == body)
        let messages = MailService.messages(from: MailService.snapshot(from: result).messages)
        #expect(messages.first?.body == body)
        #expect(messages.first?.htmlBody == (sourceAvailable ? html : nil))
    }

    @Test @MainActor
    func markingReadPreservesHTMLAndUsesPlainTextForThePreview() async throws {
        let html = "<h1>Rich message</h1>"
        let service = MailService(
            commandRunner: { _, _ in
                .success(.snapshot(MailSnapshot(
                    accounts: [],
                    messages: [MailScriptRow(
                        accountName: "work", messageID: "7", sender: "sender@example.com",
                        subject: "Fixture", body: "Plain\npreview", receivedAt: .distantPast,
                        isRead: false, htmlBody: html
                    )]
                )))
            },
            indexReader: MailIndexReader(databaseURL: URL(fileURLWithPath: "/does/not/exist")),
            mailRunning: { true }
        )
        await service.refresh()
        let message = try #require(service.messages.first)
        service.markReadLocally(message)

        #expect(service.messages.first?.isRead == true)
        #expect(service.messages.first?.htmlBody == html)
        #expect(service.messages.first?.preview == "Plain preview")
    }

    @Test @MainActor
    func refreshAndLoadMoreAppendPagesWithoutRepeatingTheLastPage() async {
        var requestedScripts: [String] = []
        let firstPage = (1...10).map { index in
            MailScriptRow(
                accountName: "工作邮箱",
                messageID: String(index),
                sender: "sender@example.com",
                subject: "邮件 \(index)",
                body: "正文 \(index)",
                receivedAt: Date(timeIntervalSince1970: Double(1_000 - index)),
                isRead: true
            )
        }
        let secondPage = (10...20).map { index in
            MailScriptRow(
                accountName: "工作邮箱",
                messageID: String(index),
                sender: "sender@example.com",
                subject: "邮件 \(index)",
                body: "正文 \(index)",
                receivedAt: Date(timeIntervalSince1970: Double(1_000 - index)),
                isRead: true
            )
        }

        let service = MailService(
            commandRunner: { script, _ in
                requestedScripts.append(script)
                let isSecondPage = script.contains("set remainingOffset to 10")
                return .success(.snapshot(MailSnapshot(
                    accounts: [MailScriptAccount(name: "工作邮箱", emailAddresses: ["work@example.com"])],
                    messages: isSecondPage ? secondPage : firstPage,
                    hasMore: !isSecondPage
                )))
            },
            indexReader: MailIndexReader(databaseURL: URL(fileURLWithPath: "/does/not/exist")),
            mailRunning: { true }
        )

        await service.refresh()
        #expect(service.messages.count == 10)
        #expect(service.messages.first?.messageID == 1)
        #expect(service.canLoadMore)
        #expect(service.paginationGeneration == 1)

        await service.loadMore()
        #expect(service.messages.count == 20)
        #expect(service.messages.map(\.messageID) == Array(1...20))
        #expect(!service.canLoadMore)
        #expect(service.paginationGeneration == 2)
        #expect(requestedScripts.count == 2)
        #expect(requestedScripts[1].contains("set remainingOffset to 10"))

        await service.loadMore()
        #expect(requestedScripts.count == 2)
    }

    @Test @MainActor
    func loadMoreAdvancesAfterAResultAddsNoNewMessages() async {
        var requestedScripts: [String] = []
        let rows: (ClosedRange<Int>) -> [MailScriptRow] = { range in
            range.map { index in
                MailScriptRow(
                    accountName: "工作邮箱",
                    messageID: String(index),
                    sender: "sender@example.com",
                    subject: "邮件 \(index)",
                    body: "正文 \(index)",
                    receivedAt: Date(timeIntervalSince1970: Double(1_000 - index)),
                    isRead: true
                )
            }
        }

        let service = MailService(
            commandRunner: { script, _ in
                requestedScripts.append(script)
                switch requestedScripts.count {
                case 1:
                    return .success(.snapshot(MailSnapshot(
                        accounts: [MailScriptAccount(name: "工作邮箱", emailAddresses: ["work@example.com"])],
                        messages: rows(1...10),
                        hasMore: true
                    )))
                case 2:
                    return .success(.snapshot(MailSnapshot(
                        accounts: [MailScriptAccount(name: "工作邮箱", emailAddresses: ["work@example.com"])],
                        messages: rows(1...10),
                        hasMore: true
                    )))
                default:
                    return .success(.snapshot(MailSnapshot(
                        accounts: [MailScriptAccount(name: "工作邮箱", emailAddresses: ["work@example.com"])],
                        messages: rows(11...20),
                        hasMore: false
                    )))
                }
            },
            indexReader: MailIndexReader(databaseURL: URL(fileURLWithPath: "/does/not/exist")),
            mailRunning: { true }
        )

        await service.refresh()
        await service.loadMore()
        #expect(service.messages.count == 10)
        #expect(service.canLoadMore)
        #expect(service.paginationGeneration == 2)

        await service.loadMore()
        #expect(service.messages.count == 20)
        #expect(!service.canLoadMore)
        #expect(requestedScripts.count == 3)
        #expect(requestedScripts[1].contains("set remainingOffset to 10"))
        #expect(requestedScripts[2].contains("set remainingOffset to 20"))
    }

    @Test @MainActor
    func inboxScriptIsDefensiveAgainstUnreachableAccountsAndMessages() {
        let script = MailService.inboxScript(accountNames: [])

        // If any account's inbox fails to resolve, the whole fetch must not blow up.
        #expect(script.contains("on error"))
        #expect(script.contains("messages of mailbox \"INBOX\" of mailAccount"))
        #expect(script.contains("set mailAccount to item i of accountList"))
        // When an account name is unreadable, fill a placeholder so later indices stay aligned.
        #expect(script.contains("未知账户"))
    }

    @Test @MainActor
    func everyScriptAddressesTheAccountInboxByMailboxName() {
        // Mail 16 rejects `inbox of <account>` with "can't get inbox of account id …", which made
        // the fetch return zero messages and every write-back unreachable.
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
            MailService.inboxScript(accountNames: []),
            MailService.markReadScript(message: message),
            MailService.markJunkScript(message: message),
            MailService.deleteScript(message: message),
            MailService.replyScript(message: message, body: "收到"),
        ]

        for script in scripts {
            #expect(script.contains("mailbox \"INBOX\" of "))
            #expect(!script.contains("of inbox of "))
        }
    }

    @Test @MainActor
    func mailBundleIdentifierMatchesMailAppExactly() throws {
        // `runningApplications(withBundleIdentifier:)` compares case-sensitively, so a camel-cased
        // identifier silently reports "Mail.app isn't running" while Mail is open.
        #expect(MailService.mailBundleIdentifier == MailService.mailBundleIdentifier.lowercased())

        let installedPlist = [
            "/System/Applications/Mail.app/Contents/Info.plist",
            "/Applications/Mail.app/Contents/Info.plist",
        ].first { FileManager.default.fileExists(atPath: $0) }
        // Nothing to compare against on a machine without Mail.app.
        guard let installedPlist else { return }

        let plist = try PropertyListSerialization.propertyList(
            from: Data(contentsOf: URL(fileURLWithPath: installedPlist)),
            format: nil
        ) as? [String: Any]
        let identifier = try #require(plist?["CFBundleIdentifier"] as? String)
        #expect(MailService.mailBundleIdentifier == identifier)
    }

    @Test @MainActor
    func unavailableMailIsNeverLaunchedAutomatically() {
        #expect(MailService.mailUnavailableMessage(isRunning: false) ==
            "Mail.app 当前未运行。zisla 不会自动打开它；请在需要同步时自行启动 Mail.app 后重试。"
        )
        #expect(MailService.mailUnavailableMessage(isRunning: true) == nil)
    }
}

@MainActor
private func executeMailAttachmentFixture(_ source: String, isReply: Bool) throws -> NSAppleEventDescriptor {
    // Replace Mail's object access and commands only; keep content edits, alias resolution and send order.
    let target = isReply ? "replyMessage" : "outgoingMessage"
    let lines = try source.split(separator: "\n").map { rawLine -> String in
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("tell ") || line == "end tell" { return "" }
        if line.hasPrefix("set targetAccount to ") { return "" }
        if line.hasPrefix("set targetMessage to ") { return "set targetMessage to {content:\"Original body\"}" }
        if line.hasPrefix("make new attachment ") {
            #expect(line.contains("at end of content of \(target)"), "Attachments must belong to the message being sent")
            let start = try #require(line.range(of: "{file name:"))
            return "set end of attachedPaths to POSIX path of " + line[start.upperBound..<line.index(before: line.endIndex)]
        }
        if line == "send" || line == "send replyMessage" { return "set wasSent to true" }
        return line
            .replacingOccurrences(of: "make new outgoing message with properties ", with: "")
            .replacingOccurrences(of: "set sender of outgoingMessage to ", with: "set fixtureSender to ")
            .replacingOccurrences(of: "make new to recipient at end of to recipients with properties ", with: "set end of fixtureRecipients to ")
            .replacingOccurrences(of: "reply targetMessage", with: "{content:content of targetMessage}")
    }.joined(separator: "\n")
    let script = try #require(NSAppleScript(source: """
        using terms from application "Mail"
            set attachedPaths to {}
            set fixtureRecipients to {}
            set wasSent to false
            set failureNumber to 0
            try
                \(lines)
            on error number errorNumber
                set failureNumber to errorNumber
            end try
            return {wasSent, attachedPaths, content of \(target), failureNumber}
        end using terms from
        """))
    var error: NSDictionary?
    let result = script.executeAndReturnError(&error)
    #expect(error == nil, "The local Mail fixture must execute without accessing Mail.app")
    return result
}

private actor MailOperationQueueTestGate {
    private var isSignaled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isSignaled {
            isSignaled = false
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func signal() {
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.resume()
        } else {
            isSignaled = true
        }
    }
}

private func makeMailServiceSnapshot(account: String, messageID: Int, hasMore: Bool = false) -> MailSnapshot {
    MailSnapshot(
        accounts: [MailScriptAccount(name: account, emailAddresses: ["\(account)@example.com"])],
        messages: [MailScriptRow(
            accountName: account,
            messageID: String(messageID),
            sender: "sender@example.com",
            subject: "Message",
            body: "Body",
            receivedAt: Date(timeIntervalSince1970: 1_000),
            isRead: false
        )],
        hasMore: hasMore
    )
}

private func mailServiceRequestBounds(_ script: String) -> (offset: Int, limit: Int)? {
    func value(_ name: String) -> Int? {
        script.split(separator: "\n")
            .first { $0.trimmingCharacters(in: .whitespaces).hasPrefix("set \(name) to ") }?
            .split(separator: " ").last.flatMap { Int($0) }
    }
    guard let offset = value("remainingOffset"), let limit = value("remainingPageSize") else { return nil }
    return (offset, limit)
}

private func makeMailServiceIndex() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("Zisla-mail-service-index-\(UUID().uuidString).db")
    try executeMailServiceSQL("""
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

private func executeMailServiceSQL(_ sql: String, at url: URL) throws {
    var database: OpaquePointer?
    guard sqlite3_open(url.path, &database) == SQLITE_OK else {
        sqlite3_close(database)
        throw MailServiceTestError.openFailed
    }
    defer { sqlite3_close(database) }

    var error: UnsafeMutablePointer<CChar>?
    guard sqlite3_exec(database, sql, nil, nil, &error) == SQLITE_OK else {
        sqlite3_free(error)
        throw MailServiceTestError.queryFailed
    }
}

private enum MailServiceTestError: Error {
    case openFailed
    case queryFailed
}
