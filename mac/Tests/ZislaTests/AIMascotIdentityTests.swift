import AppKit
import Testing

@testable import Zisla
@testable import ZislaCore

@MainActor
struct AIMascotIdentityTests {
    @Test
    func distinguishesDeepSeekHarnessFromWorkBuddy() {
        #expect(AIMascotIdentity(
            provider: .harness,
            taskID: "dsh-session",
            title: "DeepSeek Harness"
        ) == .deepseekHarness)
        #expect(AIMascotIdentity(
            provider: .harness,
            taskID: "harnext-session",
            title: "harnext"
        ) == .harness)
    }

    @Test
    func recognizesDeepSeekHarnessUpdateNoticeID() {
        #expect(AIMascotIdentity(noticeID: "update-available-cli-dsh-left") == .deepseekHarness)
    }

    @Test
    func mapsZedProviderAndActivityNotice() {
        #expect(AIMascotIdentity(provider: .zed, taskID: "zed-thread-1") == .zed)
        #expect(AIMascotIdentity(noticeID: "ai-active-zed-zed-thread-1") == .zed)
    }

    @Test
    func distinguishesGeminiDesktopChatsFromCLISessions() {
        #expect(AIMascotIdentity(
            provider: .gemini,
            taskID: "gemini-desktop-chat-c1"
        ) == .geminiDesktop)
        #expect(AIMascotIdentity(provider: .gemini, taskID: "gemini-session-s1") == .gemini)
    }

    @Test
    func recognizesGeminiDesktopActivityNotice() {
        #expect(AIMascotIdentity(
            noticeID: "ai-active-gemini-gemini-desktop-chat-c1"
        ) == .geminiDesktop)
        #expect(AIMascotIdentity(noticeID: "ai-active-gemini-gemini-session-s1") == .gemini)
    }
}

@MainActor
struct AIMascotImageCacheTests {
    @Test
    func recoversFromTransientLoadFailureBeforeReturning() throws {
        let cache = AIMascotImageCache()
        let expected = NSImage(size: NSSize(width: 12, height: 12))
        var loadCount = 0

        let loaded = try #require(cache.image(for: "transient") {
            loadCount += 1
            return loadCount == 1 ? nil : expected
        })
        #expect(loaded === expected)

        let cached = cache.image(for: "transient") {
            loadCount += 1
            return nil
        }
        #expect(cached === expected)
        #expect(loadCount == 2)
    }

    @Test
    func persistentFailureDoesNotPoisonFutureLoads() throws {
        let cache = AIMascotImageCache()
        let expected = NSImage(size: NSSize(width: 12, height: 12))

        #expect(cache.image(for: "persistent") { nil } == nil)
        let loaded = try #require(cache.image(for: "persistent") { expected })

        #expect(loaded === expected)
    }
}
