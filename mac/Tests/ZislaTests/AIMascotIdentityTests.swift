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
}
