import AppKit
import Foundation
import Testing
import XCTest
import ZislaCore
import ZislaKit

@testable import Zisla

@MainActor
struct ClipboardTranslationPresentationTests {
    @Test
    func loadingDoesNotStartAReadingTimerAfterHoverSettingsOrScreenshotChanges() async throws {
        let controller = makeController()
        let gate = TranslationResultGate()
        controller.translate(
            "source", targetLanguage: "zh-CN",
            service: .init(providers: [{ _, _ in try await gate.wait() }]),
            copyResult: { _ in Issue.record("加载中不得复制"); return true }
        )
        let task = try #require(controller.translationTask)
        #expect(await XCTWaiter.fulfillment(of: [gate.started], timeout: 3) == .completed)
        for duration in ClipboardAssistantDisplayDuration.allCases {
            controller.displayDuration = duration
            controller.setHovered(true)
            controller.setHovered(false)
            #expect(controller.dismissalProgress(at: .distantFuture) == nil)
        }
        controller.displayDuration = .threeSeconds
        controller.setSystemScreenshotActive(true)
        controller.setSystemScreenshotActive(false)
        #expect(controller.presentation.translation == .loading)
        #expect(controller.dismissalProgress(at: .distantFuture) == nil)
        controller.dismiss(animated: false)
        await gate.resolve("已取消")
        await task.value
    }

    @Test(arguments: [false, true])
    func copyingRequiresBothTheCurrentRowAndCompletedWindowReveal(windowFirst: Bool) async throws {
        let controller = makeController()
        defer { controller.dismiss(animated: false) }
        var copies: [String] = []
        let result = "  完整译文\n第二行  "
        let generation = try await resolve(controller, result: result) { copies.append($0); return true }
        let shown = ClipboardTranslationPresentation.result(text: result, copied: nil)
        #expect(copies.isEmpty)
        #expect(shown.statusKey == "自动翻译")
        #expect(controller.dismissalProgress() == nil)
        if windowFirst {
            controller.translationWindowDidAppear(for: generation)
            #expect(copies.isEmpty)
            appear(shown, on: controller, generation: generation)
        } else {
            appear(shown, on: controller, generation: generation)
            #expect(copies.isEmpty)
            controller.translationWindowDidAppear(for: generation)
        }
        #expect(copies == [result])
        #expect(controller.presentation.translation == .result(text: result, copied: true))
        appear(shown, on: controller, generation: generation)
        controller.translationWindowDidAppear(for: generation)
        #expect(copies == [result], "重复出现或动画完成回调不得重复复制")
    }

    @Test
    func obsoleteDisplayCallbacksCannotCopyAnIdenticalNewTranslation() async throws {
        let controller = makeController()
        defer { controller.dismiss(animated: false) }
        var copies: [String] = []
        let oldGeneration = try await resolve(controller, result: "同样译文") { copies.append("old:" + $0); return true }
        controller.present(Self.detection, visualStyle: .transparent)
        let generation = try await resolve(controller, result: "同样译文") { copies.append("new:" + $0); return true }
        let shown = ClipboardTranslationPresentation.result(text: "同样译文", copied: nil)
        controller.translationWindowDidAppear(for: oldGeneration)
        appear(shown, on: controller, generation: oldGeneration)
        controller.translationWindowDidAppear(for: generation)
        #expect(copies.isEmpty)
        appear(shown, on: controller, generation: oldGeneration)
        #expect(copies.isEmpty)
        appear(shown, on: controller, generation: generation)
        #expect(copies == ["new:同样译文"])
    }

    @Test(arguments: [false, true])
    func aNewCopyWithoutANewDetectionInvalidatesPendingOrUndisplayedResults(afterResult: Bool) async throws {
        let controller = makeController()
        defer { controller.dismiss(animated: false) }
        var sourceIsCurrent = true
        var copies: [String] = []
        let gate = TranslationResultGate()
        controller.translate(
            "source", targetLanguage: "zh-CN",
            service: .init(providers: [{ _, _ in try await gate.wait() }]),
            isSourceCurrent: { sourceIsCurrent },
            copyResult: { copies.append($0); return true }
        )
        let task = try #require(controller.translationTask)
        let generation = controller.presentation.translationGeneration
        if !afterResult { sourceIsCurrent = false }
        await gate.resolve("旧译文")
        await task.value
        if afterResult {
            #expect(controller.presentation.translation == .result(text: "旧译文", copied: nil))
            sourceIsCurrent = false
            controller.translationWindowDidAppear(for: generation)
            appear(.result(text: "旧译文", copied: nil), on: controller, generation: generation)
        }
        #expect(copies.isEmpty)
        #expect(controller.presentation.detection == nil)
        #expect(controller.presentation.translation == nil)
    }

    @Test(arguments: ["close", "voice", "lock", "newCopy"])
    func cancellationDiscardsLateResultsAndDisplayCallbacks(reason: String) async throws {
        let controller = makeController()
        defer { controller.dismiss(animated: false) }
        let gate = TranslationResultGate()
        var copies: [String] = []
        controller.translate(
            "source", targetLanguage: "zh-CN",
            service: .init(providers: [{ _, _ in try await gate.wait() }]),
            copyResult: { copies.append($0); return true }
        )
        let task = try #require(controller.translationTask)
        let generation = controller.presentation.translationGeneration
        #expect(await XCTWaiter.fulfillment(of: [gate.started], timeout: 3) == .completed)
        let replacement = ClipboardAssistantDetection(kind: .text, title: "new clipboard")
        switch reason {
        case "lock": controller.setScreenLocked(true)
        case "newCopy": controller.present(replacement, visualStyle: .transparent)
        default: controller.dismiss(animated: reason == "close")
        }
        await task.value
        await gate.resolve("迟到译文")
        #expect(await XCTWaiter.fulfillment(of: [gate.returned], timeout: 3) == .completed)
        controller.translationWindowDidAppear(for: generation)
        appear(.result(text: "迟到译文", copied: nil), on: controller, generation: generation)
        #expect(copies.isEmpty)
        #expect(controller.presentation.translation == nil)
        #expect(controller.presentation.detection == (reason == "newCopy" ? replacement : nil))
        controller.setScreenLocked(false)
        #expect(controller.presentation.translation == nil)
    }

    @Test(arguments: [false, true])
    func screenshotHidingDefersCopyUntilTheRestoredRowAppears(systemScreenshot: Bool) async throws {
        let controller = makeController()
        defer { controller.dismiss(animated: false) }
        var copies: [String] = []
        let generation = try await resolve(controller, result: "截图后展示的译文") { copies.append($0); return true }
        let shown = ClipboardTranslationPresentation.result(text: "截图后展示的译文", copied: nil)
        controller.translationWindowDidAppear(for: generation)
        if systemScreenshot {
            controller.setSystemScreenshotActive(true)
        } else {
            controller.setScreenshotActive(true)
            controller.setScreenshotSelectionActive(true)
        }
        appear(shown, on: controller, generation: generation)
        #expect(copies.isEmpty)
        #expect(controller.presentation.translationIsPaused)
        #expect(controller.dismissalProgress() == nil)
        if systemScreenshot {
            controller.setSystemScreenshotActive(false)
        } else {
            controller.setScreenshotSelectionActive(false)
            controller.setScreenshotActive(false)
        }
        #expect(copies.isEmpty, "恢复窗口本身不应把隐藏时的回调当作新展示")
        #expect(!controller.presentation.translationIsPaused)
        controller.translationWindowDidAppear(for: generation)
        #expect(copies.isEmpty, "迟到的窗口完成回调不能重放截图隐藏时的字幕回调")
        appear(shown, on: controller, generation: generation)
        #expect(copies == ["截图后展示的译文"])
    }

    @Test
    func aLongTranslationRestartsItsFullReadingDurationAfterScreenshotAndCopiesOnce() async throws {
        let gate = DismissalGate()
        let scheduled = AsyncStream<Duration>.makeStream()
        let controller = makeController(dismissSleeper: { duration in
            scheduled.continuation.yield(duration)
            await gate.sleep(for: duration)
        })
        defer {
            controller.dismiss(animated: false)
            scheduled.continuation.finish()
            Task { await gate.release() }
        }
        var copies = 0
        var sourceIsCurrent = true
        let result = String(repeating: "完整长译文必须滚动到末尾。", count: 80)
        let generation = try await resolve(controller, result: result, isSourceCurrent: { sourceIsCurrent }) { _ in
            copies += 1
            sourceIsCurrent = false
            return true
        }
        controller.displayDuration = .threeSeconds
        controller.translationWindowDidAppear(for: generation)
        appear(.result(text: result, copied: nil), on: controller, generation: generation)
        var durations = scheduled.stream.makeAsyncIterator()
        let duration = await durations.next()
        let expected = ClipboardTranslationPresentation.readingSeconds(for: result, rowWidth: 240)
        #expect(expected > 16)
        #expect(duration == .seconds(expected))
        controller.setSystemScreenshotActive(true)
        controller.setSystemScreenshotActive(false)
        #expect(controller.dismissalProgress() == nil, "截图恢复后先等待字幕行重现")
        appear(.result(text: result, copied: true), on: controller, generation: generation)
        #expect(await durations.next() == duration)
        #expect(copies == 1, "自身写入后 changeCount 已改变，恢复只读展示不应再次校验原始版本")
        #expect(controller.presentation.translation == .result(text: result, copied: true))
    }

    @Test(arguments: [false, true])
    func copyFailureAndTranslationFailureRemainVisibleWithoutClaimingSuccess(translationFails: Bool) async throws {
        let controller = makeController()
        defer { controller.dismiss(animated: false) }
        var copies = 0
        let service = ClipboardTranslationService(
            providers: [{ _, _ in
                if translationFails { throw URLError(.notConnectedToInternet) }
                return "译文"
            }],
            waitForTimeout: {
                if translationFails { return }
                try await Task.sleep(for: .seconds(15))
            }
        )
        controller.translate("source", targetLanguage: "zh-CN", service: service) { _ in copies += 1; return false }
        await controller.translationTask?.value
        let generation = controller.presentation.translationGeneration
        let shown = try #require(controller.presentation.translation)
        controller.translationWindowDidAppear(for: generation)
        appear(shown, on: controller, generation: generation)
        let expected: ClipboardTranslationPresentation = translationFails ? .failed : .result(text: "译文", copied: false)
        #expect(controller.presentation.translation == expected)
        #expect(copies == (translationFails ? 0 : 1))
        #expect(expected.statusKey == (translationFails ? "翻译失败，请重试或使用浏览器翻译" : "无法写入剪贴板"))
        #expect(controller.dismissalProgress() == nil, "永不自动关闭设置仍然有效")
    }

    @Test
    func aTranslationEqualToTheLoadingLabelStillBecomesACopiedResult() async throws {
        let controller = makeController()
        defer { controller.dismiss(animated: false) }
        let text = ClipboardTranslationPresentation.loading.rowText(locale: Locale(identifier: "zh-Hans"))
        var copies: [String] = []
        let generation = try await resolve(controller, result: text) { copies.append($0); return true }
        controller.translationWindowDidAppear(for: generation)
        appear(.result(text: text, copied: nil), on: controller, generation: generation)
        #expect(copies == [text])
        let source = try String(contentsOf: Self.packageRoot.appendingPathComponent("Sources/Zisla/ClipboardTranslationResultView.swift"), encoding: .utf8)
        #expect(source.contains(".task(id: translation)"), "字幕相同时仍需按加载/结果阶段重新执行展示回调")
    }

    @Test
    func translationUsesTheSmallVoiceGeometryAndAnUncappedCompleteScrollPass() {
        for width: CGFloat in [180, 240, 320] {
            let geometry = VoiceRecordingIslandGeometry(
                collapsedSize: CGSize(width: width, height: 34),
                availableSize: CGSize(width: width, height: 54)
            )
            #expect(geometry.surfaceSize == CGSize(width: width, height: 54))
            #expect(geometry.transcriptRowFrame.height == 20)
            let text = String(repeating: "long translated text ", count: 200)
            let travel = TransientNoticeMetrics.textWidth(of: text) - (width - 24)
            #expect(ClipboardTranslationPresentation.readingSeconds(for: text, rowWidth: width) > travel / 32)
        }
        #expect(ClipboardTranslationPresentation.readingSeconds(for: "短译文", rowWidth: 240) == 4)
    }

    @Test
    func everyTranslationStateAndActionResolvesInAllSeventeenLocales() throws {
        let states: [ClipboardTranslationPresentation] = [
            .loading, .failed, .result(text: "text", copied: nil),
            .result(text: "text", copied: true), .result(text: "text", copied: false),
        ]
        let keys = Set(states.map(\.statusKey) + ["关闭", ClipboardAssistantToastView.actionLabel(.autoTranslate("source"))])
        #expect(keys.count == 6)
        #expect(AppLanguage.allCases.count == 17)
        for language in AppLanguage.allCases {
            let file = Self.packageRoot.appendingPathComponent("Resources/Localization/\(language.rawValue).lproj/Localizable.strings")
            let table = try #require(NSDictionary(contentsOf: file) as? [String: String])
            for key in keys {
                let localized = try #require(table[key], "\(language.rawValue) 缺少 \(key)")
                #expect(!localized.isEmpty)
                #expect(AppLocalization.string(key, locale: language.locale) == localized)
                if language != .simplifiedChinese && language != .traditionalChinese {
                    #expect(localized != key, "\(language.rawValue) 未翻译 \(key)")
                }
            }
            #expect(ClipboardTranslationPresentation.loading.rowText(locale: language.locale) == table["正在翻译…"])
            #expect(ClipboardTranslationPresentation.failed.rowText(locale: language.locale) == table["翻译失败，请重试或使用浏览器翻译"])
            #expect(language.isRightToLeft == (language == .arabic))
        }
        #expect(ClipboardTranslationPresentation.loading.rowText(locale: Locale(identifier: "en")) == "Translating…")
        #expect(ClipboardTranslationPresentation.loading.rowText(locale: Locale(identifier: "ar")) == "جارٍ الترجمة…")
        #expect(ClipboardAssistantToastView.actionLabel(.translate("source")) == "翻译")
    }

    private func makeController(
        dismissSleeper: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) -> ClipboardAssistantController {
        let controller = ClipboardAssistantController(windowPresenter: { _, _ in }, dismissSleeper: dismissSleeper)
        controller.displayDuration = .never
        controller.present(Self.detection, visualStyle: .transparent)
        return controller
    }

    private func resolve(
        _ controller: ClipboardAssistantController,
        result: String,
        isSourceCurrent: @escaping () -> Bool = { true },
        copyResult: @escaping (String) -> Bool
    ) async throws -> Int {
        controller.translate(
            "source", targetLanguage: "zh-CN",
            service: .init(providers: [{ _, _ in result }]),
            isSourceCurrent: isSourceCurrent, copyResult: copyResult
        )
        let task = try #require(controller.translationTask)
        await task.value
        #expect(controller.presentation.translation == .result(text: result, copied: nil))
        return controller.presentation.translationGeneration
    }

    private func appear(
        _ value: ClipboardTranslationPresentation,
        on controller: ClipboardAssistantController,
        generation: Int
    ) {
        controller.translationDidAppear(value, for: generation, rowWidth: 240, locale: Locale(identifier: "zh-Hans"))
    }

    private static let detection = ClipboardAssistantDetection(
        kind: .nonSystemLanguageText, title: "source", actions: [.autoTranslate("source"), .translate("source")]
    )

    private static var packageRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }
}

private actor TranslationResultGate {
    nonisolated let started = XCTestExpectation(description: "翻译请求开始")
    nonisolated let returned = XCTestExpectation(description: "不配合取消的平台仍返回")
    private var continuation: CheckedContinuation<String, Never>?
    private var value: String?

    func wait() async throws -> String {
        started.fulfill()
        defer { returned.fulfill() }
        if let value { return value }
        return await withCheckedContinuation { continuation = $0 }
    }

    func resolve(_ value: String) {
        self.value = value
        continuation?.resume(returning: value)
        continuation = nil
    }
}
