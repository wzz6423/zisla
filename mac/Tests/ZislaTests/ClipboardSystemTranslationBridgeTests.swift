import Combine
import Foundation
import Testing
import XCTest

@testable import Zisla

@MainActor
struct ClipboardSystemTranslationBridgeTests {
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
