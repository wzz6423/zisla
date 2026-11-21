import Foundation
import Testing
import ZislaKit
@testable import Zisla

@MainActor
struct AIAccountBalanceCookieInputTests {
    @Test func failedImportRetainsManualInputAndDoesNotRefreshOrExposeDependencyDetails() async {
        let input = AIAccountBalanceCookieInputModel(website: .qoder, importCookie: { _ in
            throw AIAccountBalanceBrowserCookieError.accessFailed
        }, saveCookie: { _, _, _ in Issue.record("Import must not save manual input") })
        input.cookie = "manual=fixture-private"
        var refreshes = 0
        await input.perform(.importBrowser, didChange: { refreshes += 1 })
        #expect(input.cookie == "manual=fixture-private")
        #expect(input.statusKey == AIAccountBalanceBrowserCookieError.accessFailed.statusKey)
        #expect(!input.isSaving && refreshes == 0)
    }

    @Test(arguments: [AIAccountBalanceCookieInputModel.Action.save, .remove, .importBrowser])
    func successfulMutationClearsManualInputAndRefreshesOnlyAfterPersistence(action: AIAccountBalanceCookieInputModel.Action) async {
        let calls = BalanceInputCalls()
        let input = AIAccountBalanceCookieInputModel(website: .qoderChina, importCookie: { website in calls.add("import:" + website.rawValue) },
                                                     saveCookie: { value, website, removing in
                                                         #expect(value == "manual=fixture")
                                                         calls.add((removing ? "remove:" : "save:") + website.rawValue)
                                                     })
        input.cookie = "manual=fixture"
        var refreshes = 0
        await input.perform(action, didChange: {
            #expect(calls.values.count == 1)
            refreshes += 1
        })
        #expect(input.cookie.isEmpty && !input.isSaving && refreshes == 1)
        #expect(input.statusKey == (action == .remove ? "额度查询凭据已清除" : "额度查询凭据已保存"))
        #expect(calls.values == [(action == .importBrowser ? "import:" : action == .remove ? "remove:" : "save:") + "qoderChina"])
    }

    @Test func storageFailureKeepsCorrectionInputAndExposesOnlyGenericStatus() async {
        let input = AIAccountBalanceCookieInputModel(website: .trae, importCookie: { _ in }, saveCookie: { _, _, _ in
            throw NSError(domain: "manual=fixture-private", code: 1)
        })
        input.cookie = "manual=fixture-private"
        await input.perform(.save, didChange: { Issue.record("Failed storage must not refresh") })
        #expect(input.cookie == "manual=fixture-private" && !input.isSaving)
        #expect(input.statusKey == "无法保存额度查询凭据，请检查 Cookie 格式或存储权限")
        #expect(input.statusKey?.contains("fixture-private") == false)
    }

    @Test func duplicateActionWhileImportIsRunningDoesNotReplaceItsStateOrSaveTheWebsite() async {
        let gate = BalanceInputGate()
        let input = AIAccountBalanceCookieInputModel(website: .zed, importCookie: { _ in gate.block() },
                                                     saveCookie: { _, _, _ in Issue.record("Duplicate action must not mutate storage") })
        input.cookie = "manual=retained"
        let first = Task { await input.perform(.importBrowser, didChange: {}) }
        await gate.waitUntilStarted()
        #expect(input.isSaving && input.statusKey == "正在读取默认浏览器 Cookie")
        await input.perform(.remove, didChange: { Issue.record("Duplicate action must not refresh") })
        #expect(input.cookie == "manual=retained" && input.isSaving)
        gate.release()
        await first.value
        #expect(!input.isSaving && input.cookie.isEmpty)
    }

    @Test(arguments: [false, true])
    func rebuildingCookieRowsSharesWebsiteBusyStateWhileOtherWebsitesRemainIndependent(failing: Bool) async throws {
        let gate = BalanceInputGate()
        let mutations = BalanceInputCalls()
        let inputs = AppModel.makeAccountBalanceCookieInputs { website in
            AIAccountBalanceCookieInputModel(website: website, importCookie: { importedWebsite in
                #expect(importedWebsite == .qoder)
                gate.block()
                if failing { throw AIAccountBalanceBrowserCookieError.accessFailed }
                mutations.add("import:" + importedWebsite.rawValue)
            }, saveCookie: { _, savedWebsite, removing in
                mutations.add((removing ? "remove:" : "save:") + savedWebsite.rawValue)
            })
        }
        let qoder = try #require(inputs[.qoder])
        let china = try #require(inputs[.qoderChina])
        #expect(qoder !== china && qoder.website == .qoder && china.website == .qoderChina)
        qoder.cookie = "manual=retained"
        var firstView: AIAccountBalanceCookieInput? = AIAccountBalanceCookieInput(input: qoder, didChange: {})
        let original = try #require(firstView?.input)
        let first = Task { await original.perform(.importBrowser, didChange: {}) }
        await gate.waitUntilStarted()
        firstView = nil
        let reopened = AIAccountBalanceCookieInput(input: try #require(inputs[.qoder]), didChange: {})
        #expect(reopened.input === original && reopened.input.isSaving)
        #expect(reopened.input.statusKey == "正在读取默认浏览器 Cookie")
        for action in [AIAccountBalanceCookieInputModel.Action.importBrowser, .save, .remove] {
            await reopened.input.perform(action, didChange: { Issue.record("A reopened row must not start another mutation") })
        }
        #expect(mutations.values.isEmpty && reopened.input.cookie == "manual=retained")
        let chinaView = AIAccountBalanceCookieInput(input: china, didChange: {})
        #expect(!chinaView.input.isSaving)
        chinaView.input.cookie = "china=manual"
        await chinaView.input.perform(.save, didChange: {})
        #expect(mutations.values == ["save:qoderChina"])
        #expect(original.isSaving && !chinaView.input.isSaving)
        gate.release()
        await first.value
        #expect(!reopened.input.isSaving)
        #expect(reopened.input.cookie == (failing ? "manual=retained" : ""))
        #expect(reopened.input.statusKey == (failing ? AIAccountBalanceBrowserCookieError.accessFailed.statusKey : "额度查询凭据已保存"))
        #expect(mutations.values == (failing ? ["save:qoderChina"] : ["save:qoderChina", "import:qoder"]))
        let reopenedAgain = AIAccountBalanceCookieInput(input: try #require(inputs[.qoder]), didChange: {})
        #expect(reopenedAgain.input === original)
        #expect(reopenedAgain.input.statusKey == reopened.input.statusKey)
    }
}

private final class BalanceInputCalls: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []
    var values: [String] { lock.withLock { storage } }
    func add(_ value: String) { lock.withLock { storage.append(value) } }
}

private final class BalanceInputGate: @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var started = false
    private var continuation: CheckedContinuation<Void, Never>?

    func block() {
        let waiting = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            started = true
            let waiting = continuation
            continuation = nil
            return waiting
        }
        waiting?.resume()
        semaphore.wait()
    }

    func waitUntilStarted() async {
        await withCheckedContinuation { continuation in
            let ready = lock.withLock { () -> Bool in
                if started { return true }
                self.continuation = continuation
                return false
            }
            if ready { continuation.resume() }
        }
    }

    func release() { semaphore.signal() }
}
