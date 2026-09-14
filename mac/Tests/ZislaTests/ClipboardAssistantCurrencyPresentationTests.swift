import Foundation
import Testing
import XCTest
import ZislaCore

@testable import Zisla

@MainActor
struct ClipboardAssistantCurrencyPresentationTests {
    @Test
    func pendingRateSurvivesHoverSettingsAndScreenshots() throws {
        let controller = ClipboardAssistantController(windowPresenter: { _, _ in })
        defer { controller.dismiss(animated: false) }
        _ = try #require(controller.present(Self.pending, visualStyle: .transparent))

        #expect(controller.dismissalProgress(at: .distantFuture) == nil)

        controller.setHovered(true)
        controller.setHovered(false)
        #expect(controller.dismissalProgress() == nil)

        for duration in ClipboardAssistantDisplayDuration.allCases {
            controller.displayDuration = duration
            #expect(controller.dismissalProgress() == nil)
        }
        controller.displayDuration = .fiveSeconds

        controller.setScreenshotActive(true)
        controller.setScreenshotSelectionActive(true)
        controller.setScreenshotSelectionActive(false)
        controller.setScreenshotActive(false)
        #expect(controller.dismissalProgress() == nil)

        controller.setSystemScreenshotActive(true)
        controller.setSystemScreenshotActive(false)

        #expect(controller.dismissalProgress() == nil)
        #expect(controller.presentation.detection == Self.pending)
    }

    @Test(arguments: [ClipboardAssistantDisplayDuration.threeSeconds, .fiveSeconds, .sevenSeconds], [false, true])
    func completedRateUsesTheConfiguredDurationAndActuallyDismisses(
        duration: ClipboardAssistantDisplayDuration,
        failed: Bool
    ) async throws {
        let gate = DismissalGate()
        let controller = ClipboardAssistantController(
            windowPresenter: { _, _ in },
            dismissSleeper: { await gate.sleep(for: $0) }
        )
        defer { controller.dismiss(animated: false) }
        let generation = try #require(controller.present(Self.pending, visualStyle: .transparent))
        controller.displayDuration = duration
        let completed = Self.completed(failed: failed)

        controller.updateDetection(completed, for: generation)

        #expect(controller.presentation.detection == completed)
        #expect(controller.dismissalProgress() != nil)
        await Self.expectAutomaticDismissal(controller, gate: gate, duration: try #require(duration.expiresAfter))
    }

    @Test(arguments: [false, true])
    func completedRateRespectsNeverDismiss(failed: Bool) throws {
        let controller = ClipboardAssistantController(windowPresenter: { _, _ in })
        defer { controller.dismiss(animated: false) }
        let generation = try #require(controller.present(Self.pending, visualStyle: .transparent))
        controller.displayDuration = .never
        let completed = Self.completed(failed: failed)

        controller.updateDetection(completed, for: generation)
        controller.setHovered(true)
        controller.setHovered(false)

        #expect(controller.presentation.detection == completed)
        #expect(controller.dismissalProgress(at: .distantFuture) == nil)
    }

    @Test(arguments: [false, true])
    func completedRateWaitsForHoverExitBeforeStartingTheFullDuration(failed: Bool) async throws {
        let gate = DismissalGate()
        let controller = ClipboardAssistantController(
            windowPresenter: { _, _ in },
            dismissSleeper: { await gate.sleep(for: $0) }
        )
        defer { controller.dismiss(animated: false) }
        let generation = try #require(controller.present(Self.pending, visualStyle: .transparent))
        controller.setHovered(true)

        controller.updateDetection(Self.completed(failed: failed), for: generation)

        #expect(controller.dismissalProgress(at: .distantFuture) == 0)
        controller.setHovered(false)
        await Self.expectAutomaticDismissal(controller, gate: gate, duration: 5)
    }

    @Test(arguments: [false, true])
    func olderResultCannotReplaceAnIdenticalNewRequest(failed: Bool) throws {
        let controller = ClipboardAssistantController(windowPresenter: { _, _ in })
        defer { controller.dismiss(animated: false) }
        let oldGeneration = try #require(controller.present(Self.pending, visualStyle: .transparent))
        let newGeneration = try #require(controller.present(Self.pending, visualStyle: .transparent))
        let completed = Self.completed(failed: failed)

        controller.updateDetection(completed, for: oldGeneration)

        #expect(controller.presentation.detection == Self.pending)
        #expect(controller.dismissalProgress() == nil)

        controller.updateDetection(completed, for: newGeneration)

        #expect(controller.presentation.detection == completed)
        #expect(controller.dismissalProgress() != nil)
    }

    @Test(arguments: [false, true], [false, true])
    func dismissedPromptIgnoresLateResults(animated: Bool, failed: Bool) throws {
        let controller = ClipboardAssistantController(windowPresenter: { _, _ in })
        let generation = try #require(controller.present(Self.pending, visualStyle: .transparent))

        controller.dismiss(animated: animated)
        controller.updateDetection(Self.completed(failed: failed), for: generation)

        #expect(controller.presentation.detection == nil)
        #expect(controller.dismissalProgress() == nil)
    }

    @Test(arguments: [false, true])
    func lockingTheScreenInvalidatesPendingResults(failed: Bool) throws {
        let controller = ClipboardAssistantController(windowPresenter: { _, _ in })
        let generation = try #require(controller.present(Self.pending, visualStyle: .transparent))

        controller.setScreenLocked(true)
        controller.updateDetection(Self.completed(failed: failed), for: generation)
        #expect(controller.present(Self.pending, visualStyle: .transparent) == nil)
        controller.setScreenLocked(false)

        #expect(controller.presentation.detection == nil)
        #expect(controller.dismissalProgress() == nil)
    }

    @Test
    func replacingAPendingRateWithTextKeepsOrdinaryDismissal() async throws {
        let gate = DismissalGate()
        let controller = ClipboardAssistantController(
            windowPresenter: { _, _ in },
            dismissSleeper: { await gate.sleep(for: $0) }
        )
        defer { controller.dismiss(animated: false) }
        let generation = try #require(controller.present(Self.pending, visualStyle: .transparent))
        let text = ClipboardAssistantDetection(kind: .text, title: "replacement")

        controller.present(text, visualStyle: .transparent)
        controller.updateDetection(Self.completed(failed: false), for: generation)

        #expect(controller.presentation.detection == text)
        await Self.expectAutomaticDismissal(controller, gate: gate, duration: 5)
    }

    @Test(arguments: [false, true])
    func completedRateWaitsForScreenshotToEnd(failed: Bool) async throws {
        let gate = DismissalGate()
        let controller = ClipboardAssistantController(
            windowPresenter: { _, _ in },
            dismissSleeper: { await gate.sleep(for: $0) }
        )
        defer { controller.dismiss(animated: false) }
        let generation = try #require(controller.present(Self.pending, visualStyle: .transparent))
        controller.setSystemScreenshotActive(true)

        controller.updateDetection(Self.completed(failed: failed), for: generation)

        #expect(controller.dismissalProgress(at: .distantFuture) == 0)
        controller.setSystemScreenshotActive(false)
        await Self.expectAutomaticDismissal(controller, gate: gate, duration: 5)
    }

    private static func expectAutomaticDismissal(
        _ controller: ClipboardAssistantController,
        gate: DismissalGate,
        duration: Double
    ) async {
        let started = await XCTWaiter.fulfillment(of: [gate.started], timeout: 5)
        #expect(started == .completed)
        guard started == .completed else {
            await gate.release()
            return
        }
        #expect(await gate.durations == [.seconds(duration)])
        let dismissed = XCTestExpectation(description: "The completed prompt dismisses after its reading duration")
        controller.onPresentationChanged = { presented in
            if !presented { dismissed.fulfill() }
        }

        await gate.release()
        let result = await XCTWaiter.fulfillment(of: [dismissed], timeout: 5)
        controller.onPresentationChanged = nil

        #expect(result == .completed)
        #expect(controller.presentation.detection == nil)
    }

    private static func completed(failed: Bool) -> ClipboardAssistantDetection {
        failed
            ? ClipboardAssistantDetection(kind: .currency, title: "fixture failure", detail: pending.detail)
            : ClipboardAssistantDetection(
                kind: .currency,
                title: "CNY 700",
                detail: .currencyRate(sourceCurrencyCode: "USD", targetCurrencyCode: "CNY", rate: 7),
                actions: [.copyText("CNY 700")]
            )
    }

    private static let pending = ClipboardAssistantDetection(
        kind: .currency,
        title: "100 USD",
        detail: .currencyExpression(
            amount: 100,
            amountText: "100",
            sourceCurrencyCode: "USD",
            targetCurrencyCode: "CNY"
        )
    )
}

private actor DismissalGate {
    nonisolated let started = XCTestExpectation(description: "The reading duration starts")
    private(set) var durations: [Duration] = []
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private var isReleased = false

    func sleep(for duration: Duration) async {
        durations.append(duration)
        if durations.count == 1 { started.fulfill() }
        guard !isReleased else { return }
        await withCheckedContinuation { continuations.append($0) }
    }

    func release() {
        isReleased = true
        let pending = continuations
        continuations.removeAll()
        for continuation in pending { continuation.resume() }
    }
}
