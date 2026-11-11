import Combine
import Foundation
import Testing
import ZislaCore

@testable import Zisla
@testable import ZislaKit

@MainActor
struct MailNotificationScenarioTests {
    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func routineRefreshPreservesDeferredMailAndExistingReviewUntilExplicitCancellation(disablesMail: Bool) async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        #expect(await fixture.refresh([]))
        #expect(fixture.hasLoadedMail && fixture.queue.left.isEmpty && fixture.queue.right.isEmpty)
        let unrelated = IslandNotice(id: "unrelated-error", title: "Other failure", kind: .error)
        fixture.queue.enqueue(unrelated, expiresAfter: nil)
        fixture.queue.setNotificationScenarios([.focus])

        #expect(await fixture.refresh([1]))
        #expect(fixture.visibleMail.count == 2)
        #expect(fixture.queue.presentationNotices(fixture.visibleMail, displayIdentifier: "display").isEmpty)
        #expect(await fixture.refresh([1]))
        #expect(fixture.visibleMail.isEmpty)
        fixture.queue.setNotificationScenarios([])
        let firstReview = fixture.queue.scenarioReview(displayIdentifier: "display")
        #expect(firstReview.map(\.title) == ["Mail 1"], "An unchanged inbox refresh must retain the deferred arrival")

        #expect(await fixture.refresh([1]))
        #expect(fixture.queue.scenarioReview(displayIdentifier: "display") == firstReview,
            "Refreshing an unchanged inbox must not erase or re-record an existing review")
        #expect(fixture.visibleMail.isEmpty, "A refresh must not replay the old mail rows")
        fixture.queue.setNotificationScenarios([.focus])
        #expect(await fixture.refresh([1, 2]))
        #expect(await fixture.refresh([1, 2]))
        fixture.queue.setNotificationScenarios([])
        #expect(fixture.queue.scenarioReview(displayIdentifier: "display").map(\.title) == ["Mail 1", "Mail 2"])
        #expect(fixture.visibleMail.isEmpty)

        fixture.queue.setNotificationScenarios([.focus])
        #expect(await fixture.refresh([1, 2, 3]))
        if disablesMail {
            fixture.settings.mailEnabled = false
            #expect(await fixture.refresh([1, 2, 3]))
            #expect(!fixture.hasLoadedMail)
        } else {
            fixture.queue.removeAll(withIDPrefix: "mail-notification-")
        }
        fixture.queue.setNotificationScenarios([])
        #expect(fixture.queue.scenarioReview(displayIdentifier: "display").isEmpty,
            "Explicit cancellation must remove both older review items and the current deferred arrival")
        #expect(fixture.visibleMail.isEmpty)
        #expect(fixture.queue.right == [unrelated], "Mail cleanup must preserve unrelated visible notices")
    }

    @Test(.timeLimit(.minutes(1)))
    func routineRefreshKeepsAnAlreadyPublishedMailReviewWithoutReplayingVisibleRows() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        #expect(await fixture.refresh([]))
        fixture.queue.setNotificationScenarios([.meeting])
        #expect(await fixture.refresh([1]))
        fixture.queue.setNotificationScenarios([])
        let review = fixture.queue.scenarioReview(displayIdentifier: "display")
        #expect(try #require(review.first).title == "Mail 1")
        #expect(fixture.queue.presentationNotices(fixture.visibleMail, displayIdentifier: "display").isEmpty)

        #expect(await fixture.refresh([1]))

        #expect(fixture.queue.scenarioReview(displayIdentifier: "display") == review,
            "A routine inbox refresh must preserve the exact published review and its timestamp")
        #expect(fixture.visibleMail.isEmpty)
        #expect(fixture.queue.scenarioReviewNotice(displayIdentifier: "display") != nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func initialLoadReadMessagesAndDisabledSideNoticesNeverReplayKnownMail() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        #expect(await fixture.refresh([1]))
        #expect(fixture.visibleMail.isEmpty, "The first inbox load is a baseline, not a new arrival")
        #expect(await fixture.refresh([1, 2], readIDs: [2]))
        #expect(fixture.visibleMail.isEmpty, "A newly loaded read message must not notify")
        fixture.settings.sideNoticesEnabled = false
        #expect(await fixture.refresh([1, 2, 3], readIDs: [2]))
        fixture.settings.sideNoticesEnabled = true
        #expect(await fixture.refresh([1, 2, 3], readIDs: [2]))
        #expect(fixture.visibleMail.isEmpty, "Re-enabling notices must not replay mail seen while disabled")
        #expect(await fixture.refresh([1, 2, 3, 4], readIDs: [2]))
        #expect(fixture.queue.left.first?.title == "Mail 4")
        #expect(fixture.queue.right.first?.title == "1")
        #expect(fixture.queue.scenarioReview(displayIdentifier: "display").isEmpty)
    }

    @MainActor
    private final class Fixture {
        let directory: URL
        let queue = SideNoticeQueue()
        var settings = FeatureSettings()
        var hasLoadedMail = false
        var knownMailMessageIDs: Set<String> = []
        private var rows: [MailScriptRow] = []
        private let processed = AsyncStream<Void>.makeStream()
        private var subscription: AnyCancellable?
        private lazy var mail = MailService(
            commandRunner: { [unowned self] _, expectsSnapshot in
                #expect(expectsSnapshot, "The fixture only permits inbox reads")
                let messages = await self.rows
                return .success(.snapshot(MailSnapshot(
                    accounts: [MailScriptAccount(name: "work", emailAddresses: ["work@example.com"])],
                    messages: messages
                )))
            },
            indexReader: MailIndexReader(databaseURL: directory.appendingPathComponent("unused-index.sqlite")),
            mailRunning: { true }
        )

        init() throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-mail-scenario-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            settings.mailEnabled = true
            settings.sideNoticesEnabled = true
            queue.configureNotificationScenarios(.init(enabled: true), displayIdentifiers: ["display"])
            subscription = mail.$messages.dropFirst().sink { [weak self] messages in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    AppModel.consumeMailMessages(messages, settings: self.settings, notices: self.queue,
                        hasLoadedMail: &self.hasLoadedMail, knownMailMessageIDs: &self.knownMailMessageIDs)
                    self.processed.continuation.yield(())
                }
            }
        }

        var visibleMail: [IslandNotice] {
            (queue.left + queue.right).filter { $0.id.hasPrefix("mail-notification-") }
        }

        func refresh(_ ids: [Int], readIDs: Set<Int> = []) async -> Bool {
            rows = ids.map { id in
                MailScriptRow(accountName: "work", messageID: String(id), sender: "sender@example.com",
                    subject: "Mail \(id)", body: "Body", receivedAt: Date(timeIntervalSince1970: Double(1_000 + id)),
                    isRead: readIDs.contains(id))
            }
            var iterator = processed.stream.makeAsyncIterator()
            await mail.refresh(checkForNewMail: false)
            return await iterator.next() != nil
        }

        func close() {
            subscription?.cancel()
            mail.stop()
            queue.removeAll()
            processed.continuation.finish()
            try? FileManager.default.removeItem(at: directory)
        }
    }
}
