import Combine
import Foundation
import SQLite3
import Testing
@testable import ZislaCore
@testable import ZislaKit

struct MailServiceTests {
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
        let html = "<html><body><h1>Workflow</h1><a href=\"https://example.com\">View run</a></body></html>"
        let rawSource = "Content-Type: text/html; charset=utf-8\n\n" + html
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
        #expect(script.contains("-- Skip unreadable individual messages (corrupt or excessively large)."))
        #expect(script.contains("-- This account's inbox is currently unavailable"))
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
    func runningMailIsLookedUpThroughThePinnedIdentifier() throws {
        // The constant above is only worth pinning if the lookup actually uses it; the original
        // defect was a camel-cased literal at this call site. Scan for the call line, skipping the
        // comments that name the very API being matched.
        let source = try String(contentsOf: Self.mailServiceSourceURL, encoding: .utf8)
        let lookup = try #require(
            source
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first { !$0.hasPrefix("//") && $0.contains("runningApplications(withBundleIdentifier:") }
        )

        #expect(lookup.contains("withBundleIdentifier: mailBundleIdentifier"))
    }

    private static var mailServiceSourceURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/ZislaKit/MailService.swift")
    }

    @Test @MainActor
    func unavailableMailIsNeverLaunchedAutomatically() {
        #expect(MailService.mailUnavailableMessage(isRunning: false) ==
            "Mail.app 当前未运行。zisla 不会自动打开它；请在需要同步时自行启动 Mail.app 后重试。"
        )
        #expect(MailService.mailUnavailableMessage(isRunning: true) == nil)
    }
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
