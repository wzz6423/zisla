import Foundation

/// 宠物行为：根据外部事件（AI 任务状态、用户点击）切换「心情/活动」，
/// 实际动画由 `PetSpriteView` 按 `activity` 做程序化 idle（浮动/呼吸/小跳）。
///
/// 宠物固定在灵动岛内部，不横穿、不跑动。
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

  /// 外部活动事件驱动宠物状态。传入 `nil` 恢复待机。
  public func setActivity(_ activity: Activity?) {
    externalActivity = activity
    tapResetTask?.cancel()
    tapResetTask = nil
    self.activity = activity ?? .idle
  }

  /// 点击反馈不能覆盖仍在进行的外部任务状态，否则延迟回调会把工作状态错误重置为待机。
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
