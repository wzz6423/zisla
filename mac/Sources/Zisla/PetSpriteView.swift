import AppKit
import ZislaKit
import SwiftUI

/// 按 `activity` 播放程序化 idle 的像素宠物精灵视图。
///
/// - 单帧精灵：随时间做轻微上下浮动 + 呼吸缩放；点击触发小跳。
/// - 水平帧带：按 `fps` 循环帧。
/// 单帧精灵使用合成层动画；`reduceMotion` 时静态显示首帧。
struct PetSpriteView: View {
  var sprite: PetSprite
  var activity: PetBehaviorController.Activity
  var size: CGFloat

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var tapPulse: CGFloat = 1
  @State private var tapResetTask: Task<Void, Never>?
  @State private var bobbing = false
  var onTap: () -> Void = {}

  /// 浮动幅度随活动变化：工作中更活跃，失败/等待更蔫。
  private var bobAmplitude: CGFloat {
    switch activity {
    case .idle: size * 0.04
    case .working: size * 0.07
    case .failed: size * 0.015
    case .waiting: size * 0.02
    case .succeeded: size * 0.11
    }
  }

  /// 浮动周期（秒）：越短越活泼。
  private var bobPeriod: TimeInterval {
    switch activity {
    case .idle: 0.7
    case .working: 0.4
    case .failed: 1.0
    case .waiting: 1.2
    case .succeeded: 0.32
    }
  }

  var body: some View {
    Group {
      if sprite.frames > 1 && !reduceMotion {
        frameStripView
          .scaleEffect(tapPulse)
      } else if reduceMotion {
        frameImageView(sprite.frame(at: 0))
      } else {
        bobbingSprite
      }
    }
    .frame(width: size, height: size)
    .contentShape(Rectangle())
    .onTapGesture(perform: triggerTapFeedback)
    .onDisappear {
      tapResetTask?.cancel()
      tapResetTask = nil
      bobbing = false
    }
    .onAppear { bobbing = !reduceMotion }
    .onChange(of: reduceMotion) { _, reduced in bobbing = !reduced }
    .accessibilityHidden(true)
  }

  private var bobbingSprite: some View {
    let amp = bobAmplitude
    let period = bobPeriod
    return frameImageView(sprite.frame(at: 0))
      .offset(y: bobbing ? amp : -amp)
      .scaleEffect(tapPulse * (bobbing ? 1.03 : 0.97))
      .animation(
        .easeInOut(duration: period / 2).repeatForever(autoreverses: true),
        value: bobbing
      )
  }

  private var frameStripView: some View {
    let frameRate = min(12, max(1, sprite.fps))
    return TimelineView(.periodic(from: .now, by: 1 / frameRate)) { context in
      let elapsed = context.date.timeIntervalSinceReferenceDate
      let idx = Int(elapsed * frameRate) % sprite.frames
      frameImageView(sprite.frame(at: idx))
    }
  }

  private func frameImageView(_ image: NSImage) -> some View {
    Image(nsImage: image)
      .interpolation(.none)  // 像素风：放大保持硬边缘
      .resizable()
      .scaledToFit()
  }

  private func triggerTapFeedback() {
    onTap()
    guard !reduceMotion else { return }

    tapResetTask?.cancel()
    withAnimation(.spring(response: 0.22, dampingFraction: 0.5)) {
      tapPulse = 1.2
    }
    tapResetTask = Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(180))
      guard !Task.isCancelled else { return }
      withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
        tapPulse = 1
      }
    }
  }
}

/// 组装行为控制器与精灵渲染的完整宠物视图。
struct PetCompanionView: View {
  var sprite: PetSprite
  var size: CGFloat
  var behavior: PetBehaviorController

  var body: some View {
    PetSpriteView(
      sprite: sprite,
      activity: behavior.activity,
      size: size,
      onTap: { behavior.handleTap() }
    )
    .contentShape(Rectangle())
  }
}
