import Foundation

/// Pet behavior: switches "mood/activity" in response to external events (AI task state, user tap).
/// Actual animation is handled by `PetSpriteView`, which drives programmatic idle (floating/breathing/small jump) based on `activity`.
///
/// The pet is fixed inside the Dynamic Island and does not walk or cross sides.
@MainActor
public final class PetBehaviorController: ObservableObject {
  @Published public private(set) var activity: Activity = .idle
  private let tapFeedbackDuration: Duration
  private var externalActivity: Activity?
  private var tapResetTask: Task<Void, Never>?

  public init() {
    tapFeedbackDuration = .milliseconds(800)
  }

  init(tapFeedbackDuration: Duration) {
    self.tapFeedbackDuration = tapFeedbackDuration
  }

  deinit {
    tapResetTask?.cancel()
  }

  /// Drives pet state from an external activity event. Pass `nil` to return to idle.
  public func setActivity(_ activity: Activity?) {
    externalActivity = activity
    tapResetTask?.cancel()
    tapResetTask = nil
    self.activity = activity ?? .idle
  }

  /// Tap feedback must not override an ongoing external task state, otherwise the delayed callback would incorrectly reset the working state to idle.
  public func handleTap() {
    guard externalActivity == nil else { return }

    tapResetTask?.cancel()
    activity = .succeeded
    let duration = tapFeedbackDuration
    tapResetTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: duration)
      guard !Task.isCancelled,
        let self,
        self.externalActivity == nil,
        self.activity == .succeeded
      else { return }
      self.activity = .idle
      self.tapResetTask = nil
    }
  }

  public enum Activity: Sendable, Equatable {
    case idle
    case working
    case waiting
    case failed
    case succeeded
  }
}
