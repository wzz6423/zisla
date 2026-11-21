import Combine
import Foundation
import Translation
import Testing
import XCTest
import ZislaKit

@testable import Zisla

@MainActor
struct ClipboardSystemTranslationBridgeTests {
    @available(macOS 15.0, *)
    @Test
    func installedAutomaticDetectionKeepsTheSystemSourceSelection() async throws {
        let request = ClipboardSystemTranslationBridge.Request(id: UUID(), text: "Hello world.", targetLanguage: "zh-CN")
        let configuration = try await ClipboardSystemTranslationBridge.installedConfiguration(
            for: request,
            statusForText: { text, target in
                #expect(text == request.text)
                #expect(target == Locale.Language(identifier: request.targetLanguage))
                return .installed
            },
            statusForLanguages: { _, _ in
                Issue.record("Successful automatic detection must not need a language hint")
                return .unsupported
            }
        )
        #expect(configuration.source == nil)
        #expect(configuration.target == Locale.Language(identifier: "zh-CN"))
    }

    @available(macOS 15.0, *)
    @Test
    func aShortEnglishDetectionFailureUsesTheInstalledExplicitLanguagePair() async throws {
        let request = ClipboardSystemTranslationBridge.Request(id: UUID(), text: "Hello world.", targetLanguage: "zh-CN")
        let configuration = try await ClipboardSystemTranslationBridge.installedConfiguration(
            for: request,
            statusForText: { _, _ in throw TranslationError.unableToIdentifyLanguage },
            statusForLanguages: { source, target in
                #expect(source == Locale.Language(identifier: "en"))
                #expect(target == Locale.Language(identifier: "zh-CN"))
                return .installed
            }
        )
        #expect(configuration.source == Locale.Language(identifier: "en"))
        #expect(configuration.target == Locale.Language(identifier: "zh-CN"))
    }

    @available(macOS 15.0, *)
    @Test(arguments: [false, true])
    func languagePackagesThatAreNotInstalledNeverStartASystemSession(useHint: Bool) async {
        let request = ClipboardSystemTranslationBridge.Request(id: UUID(), text: "Hello world.", targetLanguage: "zh-CN")
        for status in [LanguageAvailability.Status.supported, .unsupported] {
            do {
                _ = try await ClipboardSystemTranslationBridge.installedConfiguration(
                    for: request,
                    statusForText: { _, _ in
                        if useHint { throw TranslationError.unableToIdentifyLanguage }
                        return status
                    },
                    statusForLanguages: { _, _ in status }
                )
                Issue.record("A missing language package must not configure a system session")
            } catch {
                #expect(error as? ClipboardTranslationError == .unavailable)
            }
        }
    }

    @available(macOS 15.0, *)
    @Test
    func otherSystemFailuresAndTextWithoutALanguageNeverGuessASource() async {
        for error in [TranslationError.internalError, .unableToIdentifyLanguage] {
            let text = error ~= TranslationError.unableToIdentifyLanguage ? "123 + 456" : "Hello world."
            let request = ClipboardSystemTranslationBridge.Request(id: UUID(), text: text, targetLanguage: "zh-CN")
            do {
                _ = try await ClipboardSystemTranslationBridge.installedConfiguration(
                    for: request,
                    statusForText: { _, _ in throw error },
                    statusForLanguages: { _, _ in
                        Issue.record("A failure without a detected source must not request a language pair")
                        return .installed
                    }
                )
                Issue.record("The system failure must be preserved")
            } catch let received {
                #expect(error ~= received)
            }
        }
    }

    @available(macOS 15.0, *)
    @Test(arguments: [false, true])
    func cancellationNeverConfiguresAnInstalledSystemSession(useHint: Bool) async {
        let request = ClipboardSystemTranslationBridge.Request(id: UUID(), text: "Hello world.", targetLanguage: "zh-CN")
        let task = Task {
            _ = try await ClipboardSystemTranslationBridge.installedConfiguration(
                for: request,
                statusForText: { _, _ in
                    if useHint { throw TranslationError.unableToIdentifyLanguage }
                    withUnsafeCurrentTask { $0?.cancel() }
                    return .installed
                },
                statusForLanguages: { _, _ in
                    withUnsafeCurrentTask { $0?.cancel() }
                    return .installed
                }
            )
        }
        switch await task.result {
        case .success: Issue.record("Cancelled translation must not configure a system session")
        case .failure(let error): #expect(error is CancellationError)
        }
    }

    @available(macOS 15.0, *)
    @Test
    func automaticTranslationIncludesTheInstalledSystemProvider() async throws {
        let bridge = ClipboardSystemTranslationBridge()
        let requested = XCTestExpectation(description: "Automatic translation requested the system provider")
        let observation = bridge.$request.sink { request in
            if request != nil { requested.fulfill() }
        }
        defer { observation.cancel() }
        let task = Task {
            try await bridge.autoTranslate("Complete OCR text\nSecond line", targetLanguage: "ja", service: .init(providers: []))
        }
        #expect(await XCTWaiter.fulfillment(of: [requested], timeout: 3) == .completed)
        let request = try #require(bridge.request)
        #expect(request.text == "Complete OCR text\nSecond line")
        #expect(request.targetLanguage == "ja")
        bridge.complete(id: request.id, result: .success("System translation\nSecond line"))
        #expect(try await task.value == "System translation\nSecond line")
        #expect(bridge.request == nil)
    }

    @Test
    func replacementCancelsTheOldRequestAndIgnoresDuplicateOrOutOfOrderResults() async throws {
        let bridge = ClipboardSystemTranslationBridge()
        let (oldTask, oldID) = try await begin(bridge, text: "first")
        let (task, id) = try await begin(bridge, text: "second")
        switch await oldTask.result {
        case .success: Issue.record("被替换的系统翻译必须取消")
        case .failure(let error): #expect(error is CancellationError)
        }
        bridge.complete(id: oldID, result: .success("迟到的旧结果"))
        #expect(bridge.request?.id == id)
        #expect(bridge.request?.text == "second")
        bridge.complete(id: id, result: .success("完整系统译文"))
        #expect(try await task.value == "完整系统译文")
        bridge.complete(id: id, result: .success("重复结果"))
        #expect(bridge.request == nil)
        bridge.cancel()
        #expect(bridge.request == nil)
    }

    @Test(arguments: [false, true])
    func userCancellationReleasesTheContinuationAndAllowsAnotherRequest(cancelTask: Bool) async throws {
        let bridge = ClipboardSystemTranslationBridge()
        let (task, id) = try await begin(bridge, text: "source")
        if cancelTask { task.cancel() } else { bridge.cancel() }
        switch await task.result {
        case .success: Issue.record("取消不应返回系统译文")
        case .failure(let error): #expect(error is CancellationError)
        }
        #expect(bridge.request == nil)
        let (retry, retryID) = try await begin(bridge, text: "retry")
        bridge.complete(id: id, result: .failure(CancellationError()))
        #expect(bridge.request?.id == retryID)
        bridge.complete(id: retryID, result: .success("重试成功"))
        #expect(try await retry.value == "重试成功")
        #expect(bridge.request == nil)
    }

    @Test
    func anAlreadyCancelledTaskDoesNotPublishASystemRequest() async {
        let bridge = ClipboardSystemTranslationBridge()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await bridge.translate("source", targetLanguage: "zh-CN")
        }
        switch await task.result {
        case .success: Issue.record("已取消任务不应调用系统翻译")
        case .failure(let error): #expect(error is CancellationError)
        }
        #expect(bridge.request == nil)
    }

    private func begin(
        _ bridge: ClipboardSystemTranslationBridge,
        text: String
    ) async throws -> (Task<String, any Error>, UUID) {
        let requested = XCTestExpectation(description: "系统翻译请求已发布")
        let observation = bridge.$request.sink { request in
            if request?.text == text { requested.fulfill() }
        }
        let task = Task { try await bridge.translate(text, targetLanguage: "zh-CN") }
        let completed = await XCTWaiter.fulfillment(of: [requested], timeout: 3)
        observation.cancel()
        #expect(completed == .completed)
        return (task, try #require(bridge.request?.id))
    }
}
