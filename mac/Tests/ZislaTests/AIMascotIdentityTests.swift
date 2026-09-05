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
