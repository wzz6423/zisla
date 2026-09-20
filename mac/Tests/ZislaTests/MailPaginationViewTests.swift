import AppKit
import Combine
import SwiftUI
import Testing
import XCTest
import ZislaCore

@testable import Zisla
@testable import ZislaKit

@MainActor
@Suite(.serialized)
struct MailPaginationViewTests {
    @Test
    func loadingPlaceholderDoesNotCancelTheRequestedPage() async throws {
        let gate = MailPaginationTestGate()
        var requests = 0
        let mail = makeService {
            requests += 1
            if requests == 1 { return .success(.snapshot(snapshot(id: 1))) }
            await gate.wait()
            return .success(.snapshot(snapshot(id: 2, account: "work", hasMore: false)))
        }
        await mail.refresh()
        let controls = MailPaginationTestControls()
        controls.accountName = "work"
        controls.replacesTriggerWhileLoading = true
        let loadingAppeared = XCTestExpectation(description: "The loading view replaces the empty-account trigger")
        controls.onLoadingAppear = {
            controls.showsTrigger = false
            loadingAppeared.fulfill()
        }
        let (completed, observation) = nextCompletion(of: mail)
        let window = host(mail, controls: controls)
        defer {
            observation.cancel()
            cleanUp(window, mail: mail, controls: controls, gate: gate)
        }

        try await wait(for: loadingAppeared)
        gate.open()
        try await wait(for: completed)

        #expect(mail.messages.map(\.messageID) == [1, 2])
        #expect(mail.messages.last?.accountName == "work")
        #expect(!mail.canLoadMore)
        #expect(!mail.isLoading)
    }

    @Test
    func emptyAccountContinuesThroughPagesWithoutMatchingMessages() async throws {
        var requests = 0
        let mail = makeService {
            requests += 1
            return .success(.snapshot(snapshot(
                id: requests,
                account: requests < 3 ? "personal" : "work"
            )))
        }
        await mail.refresh()
        let controls = MailPaginationTestControls()
        controls.accountName = "work"
        controls.onlyRequestsForEmptyAccount = true
        controls.replacesTriggerWhileLoading = true
        let found = XCTestExpectation(description: "Pagination finds the selected account on a later page")
        let observation = mail.$messages.first { $0.contains { $0.accountName == "work" } }.sink { _ in
            found.fulfill()
        }
        let window = host(mail, controls: controls)
        defer {
            observation.cancel()
            cleanUp(window, mail: mail, controls: controls)
        }

        try await wait(for: found)

        #expect(mail.messages.map(\.messageID) == [1, 2, 3])
        #expect(requests == 3)
        #expect(mail.canLoadMore)
    }

    @Test
    func disappearingFooterFinishesOnePageAndWaitsUntilVisibleAgain() async throws {
        let gate = MailPaginationTestGate()
        let started = XCTestExpectation(description: "The requested page starts")
        var requests = 0
        let mail = makeService {
            requests += 1
            if requests == 2 {
                started.fulfill()
                await gate.wait()
            }
            return .success(.snapshot(snapshot(id: requests, hasMore: requests < 3)))
        }
        await mail.refresh()
        let controls = MailPaginationTestControls()
        controls.showsTrigger = false
        let initiallyHidden = XCTestExpectation(description: "The footer has not appeared")
        controls.onPlaceholderAppear = { initiallyHidden.fulfill() }
        let window = host(mail, controls: controls)
        defer { cleanUp(window, mail: mail, controls: controls, gate: gate) }
        try await wait(for: initiallyHidden)
        #expect(requests == 1)

        controls.showsTrigger = true
        try await wait(for: started)
        let hidden = XCTestExpectation(description: "The footer scrolls out of the view")
        controls.onPlaceholderAppear = { hidden.fulfill() }
        controls.showsTrigger = false
        try await wait(for: hidden)
        let (completed, observation) = nextCompletion(of: mail)
        defer { observation.cancel() }
        gate.open()
        try await wait(for: completed)

        #expect(mail.messages.map(\.messageID) == [1, 2])
        #expect(requests == 2)
        #expect(mail.canLoadMore)

        let (lastPage, lastObservation) = nextCompletion(of: mail)
        defer { lastObservation.cancel() }
        controls.showsTrigger = true
        try await wait(for: lastPage)
        #expect(mail.messages.map(\.messageID) == [1, 2, 3])
        #expect(!mail.canLoadMore)
    }

    @Test
    func failedPageWaitsForANewRequestBeforeRetrying() async throws {
        var requests = 0
        let mail = makeService {
            requests += 1
            switch requests {
            case 1: return .success(.snapshot(snapshot(id: 1)))
            case 2: return .failure(.failed("Injected mail failure"))
            default: return .success(.snapshot(snapshot(id: 2, account: "work", hasMore: false)))
            }
        }
        await mail.refresh()
        let controls = MailPaginationTestControls()
        let (failed, observation) = nextCompletion(of: mail)
        let window = host(mail, controls: controls)
        defer {
            observation.cancel()
            cleanUp(window, mail: mail, controls: controls)
        }
        try await wait(for: failed)
        #expect(mail.errorDescription == "Injected mail failure")

        let hidden = XCTestExpectation(description: "The failed page trigger is removed")
        controls.onPlaceholderAppear = { hidden.fulfill() }
        controls.showsTrigger = false
        try await wait(for: hidden)
        let resubmitted = XCTestExpectation(description: "The same page trigger is recreated")
        controls.onTriggerTaskFinished = { resubmitted.fulfill() }
        controls.showsTrigger = true
        try await wait(for: resubmitted)

        #expect(requests == 2)
        #expect(mail.messages.map(\.messageID) == [1])
        #expect(mail.paginationGeneration == 1)
        #expect(!mail.isLoading)

        let changedFilter = XCTestExpectation(description: "The user selects a different account after a failure")
        controls.onPlaceholderAppear = { changedFilter.fulfill() }
        controls.showsTrigger = false
        try await wait(for: changedFilter)
        controls.accountName = "work"
        let (retried, retryObservation) = nextCompletion(of: mail)
        defer { retryObservation.cancel() }
        controls.showsTrigger = true
        try await wait(for: retried)
        #expect(mail.messages.map(\.messageID) == [1, 2])
        #expect(mail.errorDescription == nil)
        #expect(requests == 3)
    }

    @Test
    func switchingAccountDuringLoadingDoesNotReplaceTheRunningPage() async throws {
        let gate = MailPaginationTestGate()
        let started = XCTestExpectation(description: "A page is in flight while the account filter changes")
        var requests = 0
        let mail = makeService {
            requests += 1
            if requests == 1 { return .success(.snapshot(snapshot(id: 1))) }
            started.fulfill()
            await gate.wait()
            return .success(.snapshot(snapshot(id: 2, account: "work", hasMore: false)))
        }
        await mail.refresh()
        let controls = MailPaginationTestControls()
        let window = host(mail, controls: controls)
        defer { cleanUp(window, mail: mail, controls: controls, gate: gate) }
        try await wait(for: started)

        let hidden = XCTestExpectation(description: "The old filter's footer disappears")
        controls.onPlaceholderAppear = { hidden.fulfill() }
        controls.showsTrigger = false
        try await wait(for: hidden)
        let reappeared = XCTestExpectation(description: "The new filter requests the pending page")
        controls.onTriggerTaskFinished = { reappeared.fulfill() }
        controls.accountName = "work"
        controls.showsTrigger = true
        try await wait(for: reappeared)
        let (completed, observation) = nextCompletion(of: mail)
        defer { observation.cancel() }
        gate.open()
        try await wait(for: completed)

        #expect(mail.messages.map(\.messageID) == [1, 2])
        #expect(requests == 2)
        #expect(!mail.isLoading)
    }

    @Test
    func closingTheListCancelsItsPendingPage() async throws {
        let gate = MailPaginationTestGate()
        let started = XCTestExpectation(description: "The list owns a pending page")
        var requests = 0
        let mail = makeService {
            requests += 1
            if requests == 1 { return .success(.snapshot(snapshot(id: 1))) }
            started.fulfill()
            await gate.wait()
            return .success(.snapshot(snapshot(id: 2, hasMore: false)))
        }
        await mail.refresh()
        let controls = MailPaginationTestControls()
        let window = host(mail, controls: controls)
        defer { cleanUp(window, mail: mail, controls: controls, gate: gate) }
        try await wait(for: started)
        let closed = XCTestExpectation(description: "The entire list leaves the view tree")
        controls.onContainerRemoved = { closed.fulfill() }
        controls.isActive = false
        try await wait(for: closed)
        let (completed, observation) = nextCompletion(of: mail)
        defer { observation.cancel() }
        gate.open()
        try await wait(for: completed)

        #expect(mail.messages.map(\.messageID) == [1])
        #expect(mail.paginationGeneration == 1)
        #expect(mail.canLoadMore)
        #expect(!mail.isLoading)
    }

    @Test(arguments: ["第一段\n\n" + String(repeating: "完整正文", count: 400) + "\n最后一段", "  缩进\t内容\r\n下一行\n"])
    func detailPreservesCompleteBodyAndParagraphs(body: String) {
        #expect(MailModuleView.messageBodyText(message(body: body)) == body)
    }

    @Test(arguments: ["", " \n\r\t "])
    func emptyDetailUsesTheExistingLocalizedPlaceholder(body: String) {
        #expect(MailModuleView.messageBodyText(message(body: body)) == AppLocalization.text("没有可显示的正文"))
    }

    private func makeService(
        result: @escaping @MainActor () async -> Result<MailScriptOutput, MailScriptError>
    ) -> MailService {
        MailService(
            commandRunner: { _, _ in await result() },
            indexReader: MailIndexReader(databaseURL: URL(fileURLWithPath: "/does/not/exist")),
            mailRunning: { true }
        )
    }

    private func snapshot(id: Int, account: String = "personal", hasMore: Bool = true) -> MailSnapshot {
        MailSnapshot(
            accounts: [
                MailScriptAccount(name: "personal", emailAddresses: ["personal@example.com"]),
                MailScriptAccount(name: "work", emailAddresses: ["work@example.com"]),
            ],
            messages: [MailScriptRow(
                accountName: account,
                messageID: String(id),
                sender: "sender@example.com",
                subject: "Fixture \(id)",
                body: "Fixture body",
                receivedAt: Date(timeIntervalSince1970: Double(2_000 - id)),
                isRead: true
            )],
            hasMore: hasMore
        )
    }

    private func message(body: String) -> MailMessage {
        MailMessage(
            accountName: "personal", messageID: 1, sender: "sender@example.com",
            subject: "Fixture", body: body, receivedAt: .distantPast, isRead: true
        )
    }

    private func nextCompletion(of mail: MailService) -> (XCTestExpectation, AnyCancellable) {
        let expectation = XCTestExpectation(description: "The requested page finishes")
        let observation = mail.$isLoading.dropFirst().first { !$0 }.sink { _ in expectation.fulfill() }
        return (expectation, observation)
    }

    private func wait(for expectation: XCTestExpectation) async throws {
        let result = await XCTWaiter.fulfillment(of: [expectation], timeout: 5)
        try #require(result == .completed, "Timed out: \(expectation.expectationDescription)")
    }

    private func host(_ mail: MailService, controls: MailPaginationTestControls) -> NSWindow {
        let hosting = NSHostingView(rootView:
            MailPaginationTestHost(mail: mail, controls: controls).frame(width: 240, height: 160)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 160),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.alphaValue = 0
        window.contentView = hosting
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        return window
    }

    private func cleanUp(
        _ window: NSWindow, mail: MailService, controls: MailPaginationTestControls,
        gate: MailPaginationTestGate? = nil
    ) {
        controls.isActive = false
        mail.stop()
        gate?.open()
        window.orderOut(nil)
        window.contentView = nil
    }
}

@MainActor
private final class MailPaginationTestControls: ObservableObject {
    @Published var isActive = true
    @Published var showsTrigger = true
    @Published var accountName: String?
    var replacesTriggerWhileLoading = false
    var onlyRequestsForEmptyAccount = false
    var onLoadingAppear: () -> Void = {}
    var onPlaceholderAppear: () -> Void = {}
    var onTriggerTaskFinished: () -> Void = {}
    var onContainerRemoved: () -> Void = {}
    var triggerAttempts = 0
}

private struct MailPaginationTestHost: View {
    @ObservedObject var mail: MailService
    @ObservedObject var controls: MailPaginationTestControls

    private var isAccountEmpty: Bool {
        !mail.messages.contains { $0.accountName == controls.accountName }
    }

    var body: some View {
        if controls.isActive {
            MailPaginationContainer(mail: mail, accountName: controls.accountName) { loadMore in
                if controls.replacesTriggerWhileLoading && mail.isLoading {
                    Color.clear.onAppear { controls.onLoadingAppear() }
                } else if controls.showsTrigger && mail.canLoadMore
                    && (!controls.onlyRequestsForEmptyAccount || isAccountEmpty) {
                    Color.clear.task(id: mail.paginationGeneration) {
                        controls.triggerAttempts += 1
                        // Bound a regressed retry loop so a failed test cannot keep issuing work.
                        guard controls.triggerAttempts <= 8 else { return }
                        await loadMore()
                        controls.onTriggerTaskFinished()
                    }
                } else {
                    Color.clear.onAppear { controls.onPlaceholderAppear() }
                }
            }
        } else {
            Color.clear.onAppear { controls.onContainerRemoved() }
        }
    }
}

@MainActor
private final class MailPaginationTestGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
}
