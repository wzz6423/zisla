import Testing

@testable import ZislaKit

@MainActor
struct PetBehaviorControllerTests {
  @Test
  func tapDoesNotOverrideAnExternalActivity() {
    let behavior = PetBehaviorController(tapFeedbackDuration: .milliseconds(1))
    behavior.setActivity(.working)

    behavior.handleTap()

    #expect(behavior.activity == .working)
  }

  @Test
  func externalActivitySupersedesPendingTapFeedback() {
    let behavior = PetBehaviorController(tapFeedbackDuration: .milliseconds(10))
    behavior.handleTap()
    #expect(behavior.activity == .succeeded)

    behavior.setActivity(.working)

    #expect(behavior.activity == .working)
  }

  @Test
  func tapEntersTemporarySuccessStateWhenNoExternalActivityExists() {
    let behavior = PetBehaviorController(tapFeedbackDuration: .milliseconds(10))
    behavior.handleTap()

    #expect(behavior.activity == .succeeded)
  }
}
