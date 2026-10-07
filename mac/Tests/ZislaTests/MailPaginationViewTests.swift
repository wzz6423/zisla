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
    func pullToRefreshTriggersOnceAfterDraggingPastTheThresholdAndResetsOnRelease() {
        var gesture = MailPullToRefreshGesture()

        let firstDelta = gesture.consume(deltaY: 30, phase: .began, momentumPhase: [], isAtTop: true)
        let thresholdReached = gesture.consume(deltaY: 35, phase: .changed, momentumPhase: [], isAtTop: true)
        let duplicate = gesture.consume(deltaY: 35, phase: .changed, momentumPhase: [], isAtTop: true)
        let released = gesture.consume(deltaY: 0, phase: .ended, momentumPhase: [], isAtTop: true)
        let secondStart = gesture.consume(deltaY: 50, phase: .began, momentumPhase: [], isAtTop: true)
        let secondThreshold = gesture.consume(deltaY: 15, phase: .changed, momentumPhase: [], isAtTop: true)

        #expect([firstDelta, thresholdReached, duplicate, released, secondStart, secondThreshold] == [false, true, false, false, false, true])
    }

    @Test
    func pullToRefreshRequiresDraggingPastTheTopWithoutMomentum() {
        var gesture = MailPullToRefreshGesture()

        let awayFromTop = gesture.consume(deltaY: 61, phase: .began, momentumPhase: [], isAtTop: false)
        let momentum = gesture.consume(deltaY: 61, phase: .began, momentumPhase: .began, isAtTop: true)
        let wrongDirection = gesture.consume(deltaY: -61, phase: .began, momentumPhase: [], isAtTop: true)
        let belowThreshold = gesture.consume(deltaY: 59, phase: .began, momentumPhase: [], isAtTop: true)
        let thresholdReached = gesture.consume(deltaY: 1, phase: .changed, momentumPhase: [], isAtTop: true)

        #expect([awayFromTop, momentum, wrongDirection, belowThreshold, thresholdReached] == [false, false, false, false, true])
    }

    @Test
    func aNewPullDiscardsThePreviousGesturesPartialDistance() {
        var gesture = MailPullToRefreshGesture()

        let interruptedPull = gesture.consume(deltaY: 40, phase: .began, momentumPhase: [], isAtTop: true)
        let newPull = gesture.consume(deltaY: 30, phase: .began, momentumPhase: [], isAtTop: true)
        let thresholdReached = gesture.consume(deltaY: 30, phase: .changed, momentumPhase: [], isAtTop: true)

        #expect([interruptedPull, newPull, thresholdReached] == [false, false, true])
    }

    @Test
    func refreshAccessibilityLabelUsesEverySupportedLanguage() {
        #expect(AppLanguage.allCases.count == 17)
        for language in AppLanguage.allCases {
            let label = AppLocalization.string("刷新收件箱", language: language)
            #expect(!label.isEmpty)
            if language != .simplifiedChinese {
                #expect(label != "刷新收件箱", "Missing refresh label for \(language.rawValue)")
            }
        }
    }

    @Test(arguments: [NSEvent.Phase.ended, .cancelled])
    func releasedOrCancelledPullsDiscardPartialDistance(phase: NSEvent.Phase) {
        var gesture = MailPullToRefreshGesture()

        let partialPull = gesture.consume(deltaY: 40, phase: .began, momentumPhase: [], isAtTop: true)
        let interrupted = gesture.consume(deltaY: 80, phase: phase, momentumPhase: [], isAtTop: true)
        let remainingAfterReset = gesture.consume(deltaY: 40, phase: .changed, momentumPhase: [], isAtTop: true)
        let thresholdReached = gesture.consume(deltaY: 20, phase: .changed, momentumPhase: [], isAtTop: true)

        #expect([partialPull, interrupted, remainingAfterReset, thresholdReached] == [false, false, false, true])
    }

    @Test(arguments: [true, false])
    func reversingDirectionOrLeavingTheTopDiscardsPartialDistance(leavesTop: Bool) {
        var gesture = MailPullToRefreshGesture()

        let partialPull = gesture.consume(deltaY: 40, phase: .began, momentumPhase: [], isAtTop: true)
        let interrupted = gesture.consume(deltaY: leavesTop ? 40 : -1, phase: .changed, momentumPhase: [], isAtTop: !leavesTop)
        let remainingAfterReset = gesture.consume(deltaY: 40, phase: .changed, momentumPhase: [], isAtTop: true)
        let thresholdReached = gesture.consume(deltaY: 20, phase: .changed, momentumPhase: [], isAtTop: true)

        #expect([partialPull, interrupted, remainingAfterReset, thresholdReached] == [false, false, false, true])
    }

    @Test
    func scrollWheelsWithoutGesturePhasesRequireANewPullDistanceForEachRefresh() {
        var gesture = MailPullToRefreshGesture()

        let firstPartial = gesture.consume(deltaY: 40, phase: [], momentumPhase: [], isAtTop: true)
        let firstThreshold = gesture.consume(deltaY: 20, phase: [], momentumPhase: [], isAtTop: true)
        let secondPartial = gesture.consume(deltaY: 40, phase: [], momentumPhase: [], isAtTop: true)
        let secondThreshold = gesture.consume(deltaY: 20, phase: [], momentumPhase: [], isAtTop: true)

        #expect([firstPartial, firstThreshold, secondPartial, secondThreshold] == [false, true, false, true])
    }

    @Test
    func nativePullEventsStayWithinTheEnabledMailList() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 160),
            styleMask: .borderless, backing: .buffered, defer: false
        )
        let otherWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 160),
            styleMask: .borderless, backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        otherWindow.isReleasedWhenClosed = false
        defer {
            window.contentView = nil
            window.close()
            otherWindow.close()
        }
        var refreshes = 0
        let scrollView = NSScrollView(frame: window.contentView!.bounds)
        let document = MailRefreshTestDocument(frame: NSRect(x: 0, y: 0, width: 240, height: 500))
        let host = MailPullToRefreshHost(isEnabled: true) { refreshes += 1 }
        document.addSubview(host)
        scrollView.documentView = document
        window.contentView = scrollView
        scrollView.contentView.scroll(to: .zero)
        let inside = scrollView.convert(NSPoint(x: 20, y: 20), to: nil)
        let outside = scrollView.convert(NSPoint(x: scrollView.bounds.maxX + 20, y: 20), to: nil)
        #expect(host.enclosingScrollView === scrollView)

        host.handle(MailRefreshTestEvent(window: otherWindow, location: inside))
        host.handle(MailRefreshTestEvent(window: window, location: outside))
        #expect(refreshes == 0, "Scrolling another window or the message detail must not refresh the inbox")

        host.isEnabled = false
        host.handle(MailRefreshTestEvent(window: window, location: inside))
        #expect(refreshes == 0, "A refresh already in progress must suppress new gestures")

        host.isEnabled = true
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: 80))
        host.handle(MailRefreshTestEvent(window: window, location: inside))
        #expect(refreshes == 0, "Browsing the middle of the list must not refresh it")

        scrollView.contentView.scroll(to: .zero)
        host.handle(MailRefreshTestEvent(window: window, location: inside))
        host.handle(MailRefreshTestEvent(window: window, location: inside, phase: .changed))
        #expect(refreshes == 1)
        host.removeFromSuperview()
        host.handle(MailRefreshTestEvent(window: window, location: inside))
        #expect(refreshes == 1, "A detached mail list must not continue handling scroll input")

        document.addSubview(host)
        host.handle(MailRefreshTestEvent(window: window, location: inside, deltaY: 40))
        host.removeFromSuperview()
        document.addSubview(host)
        host.handle(MailRefreshTestEvent(window: window, location: inside, phase: .changed, deltaY: 40))
        #expect(refreshes == 1, "Remounting the list must discard the previous partial pull")
        host.handle(MailRefreshTestEvent(window: window, location: inside, phase: .changed, deltaY: 20))
        #expect(refreshes == 2)
        NSApplication.shared.sendEvent(MailRefreshTestEvent(window: window, location: inside))
        #expect(refreshes == 3, "The mounted list must receive scroll events through AppKit's local monitor")
    }

    @Test
    func pullHandlerPreservesMessageRowClicks() throws {
        var selections = 0
        var refreshes = 0
        let hosting = NSHostingView(rootView:
            MailRefreshScrollView(isEnabled: true, onRefresh: { refreshes += 1 }) {
                Button("Fixture message") { selections += 1 }
                    .buttonStyle(.plain)
                    .frame(width: 240, height: 160)
            }.frame(width: 240, height: 160)
        )
        let window = NSPanel(
            contentRect: NSRect(x: -100_000, y: -100_000, width: 240, height: 160),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        defer {
            window.contentView = nil
            window.close()
        }
        hosting.sizingOptions = []
        #expect(NSScreen.screens.allSatisfy { !$0.frame.intersects(window.frame) })
        // SwiftUI installs its event graph only after the window is ordered in.
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let location = hosting.convert(NSPoint(x: 120, y: 80), to: nil)
        let timestamp = ProcessInfo.processInfo.systemUptime
        let down = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown, location: location, modifierFlags: [], timestamp: timestamp,
            windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1
        ))
        let up = try #require(NSEvent.mouseEvent(
            with: .leftMouseUp, location: location, modifierFlags: [], timestamp: timestamp + 0.01,
            windowNumber: window.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 0
        ))
        window.sendEvent(down)
        window.sendEvent(up)

        #expect(selections == 1, "The native pull handler must not intercept message-row clicks")
        #expect(refreshes == 0)
    }

    @Test(arguments: [CGFloat(0), 400])
    func refreshScrollViewHostsNativePullHandlingForEmptyAndLongLists(height: CGFloat) async throws {
        let hosting = NSHostingView(rootView:
            MailRefreshScrollView(isEnabled: true, onRefresh: {}) {
                Color.clear.frame(height: height)
            }
            .frame(width: 240, height: 160)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 160),
            styleMask: .borderless, backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        defer {
            window.contentView = nil
            window.close()
        }
        var pullHost: MailPullToRefreshHost?
        let deadline = Date().addingTimeInterval(2)
        repeat {
            hosting.layoutSubtreeIfNeeded()
            var pending = [hosting as NSView]
            while let view = pending.popLast() {
                if let host = view as? MailPullToRefreshHost { pullHost = host }
                pending.append(contentsOf: view.subviews)
            }
            if pullHost?.enclosingScrollView != nil { break }
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
        } while Date() < deadline
        let host = try #require(pullHost, "SwiftUI must mount the native pull handler inside the mail list")
        let scrollView = try #require(host.enclosingScrollView)
        let document = try #require(scrollView.documentView)
        #expect(document.frame.height >= 160, "Empty inboxes must still offer a full-height pull target")
        #expect(scrollView.verticalScrollElasticity == .allowed)
        #expect(host.isEnabled)
        #expect(!window.isVisible)

        var refreshes = 0
        hosting.rootView = MailRefreshScrollView(isEnabled: false, onRefresh: { refreshes += 1 }) {
            Color.clear.frame(height: height)
        }.frame(width: 240, height: 160)
        hosting.layoutSubtreeIfNeeded()
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        #expect(!host.isEnabled, "The mounted handler must observe loading-state updates")
        hosting.rootView = MailRefreshScrollView(isEnabled: true, onRefresh: { refreshes += 1 }) {
            Color.clear.frame(height: height)
        }.frame(width: 240, height: 160)
        hosting.layoutSubtreeIfNeeded()
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        let inside = scrollView.convert(NSPoint(x: 20, y: 20), to: nil)
        host.handle(MailRefreshTestEvent(window: window, location: inside))
        #expect(refreshes == 1, "The mounted handler must call the updated refresh action")
    }

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

@MainActor
private final class MailRefreshTestDocument: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
private final class MailRefreshTestEvent: NSEvent {
    private let targetWindow: NSWindow
    private let targetWindowNumber: Int
    private let location: NSPoint
    private let scrollPhase: NSEvent.Phase
    private let scrollDelta: CGFloat

    init(window: NSWindow, location: NSPoint, phase: NSEvent.Phase = .began, deltaY: CGFloat = 60) {
        targetWindow = window
        targetWindowNumber = window.windowNumber
        self.location = location
        scrollPhase = phase
        scrollDelta = deltaY
        super.init()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var window: NSWindow? { targetWindow }
    override var type: NSEvent.EventType { .scrollWheel }
    override var windowNumber: Int { targetWindowNumber }
    override var locationInWindow: NSPoint { location }
    override var scrollingDeltaY: CGFloat { scrollDelta }
    override var phase: NSEvent.Phase { scrollPhase }
    override var momentumPhase: NSEvent.Phase { [] }
}
