import AppKit
import QuartzCore
import ZislaKit
import SwiftUI

/// Pixel pet sprite view that plays a procedural idle animation driven by `activity`.
///
/// - Single-frame sprite: gentle vertical bob + breathing scale over time; tap triggers a small jump.
/// - Horizontal frame strip: cycles frames at `fps`.
/// Single-frame sprites use compositing-layer animation; static first frame is shown when `reduceMotion` is on.
struct PetSpriteView: View {
  var sprite: PetSprite
  var activity: PetBehaviorController.Activity
  var size: CGFloat

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var tapPulse: CGFloat = 1
  @State private var tapResetTask: Task<Void, Never>?
  var onTap: () -> Void = {}

  /// Bob amplitude varies by activity: more energetic when working, subdued when failed or waiting.
  private var bobAmplitude: CGFloat {
    switch activity {
    case .idle: size * 0.04
    case .working: size * 0.07
    case .failed: size * 0.015
    case .waiting: size * 0.02
    case .succeeded: size * 0.11
    }
  }

  /// Bob period in seconds: shorter = livelier.
  private var bobPeriod: TimeInterval {
    switch activity {
    case .idle: 1.4
    case .working: 0.8
    case .failed: 2.0
    case .waiting: 2.4
    case .succeeded: 0.64
    }
  }

  var body: some View {
    Group {
      if reduceMotion {
        frameImageView(sprite.frame(at: 0))
          .onTapGesture(perform: triggerTapFeedback)
      } else {
        GPUAnimatedPetSprite(
          sprite: sprite,
          bobAmplitude: bobAmplitude,
          bobPeriod: bobPeriod,
          onTap: triggerTapFeedback
        )
        .scaleEffect(tapPulse)
      }
    }
    .frame(width: size, height: size)
    .contentShape(Rectangle())
    .onDisappear {
      tapResetTask?.cancel()
      tapResetTask = nil
    }
    .accessibilityHidden(true)
  }

  private func frameImageView(_ image: NSImage) -> some View {
    Image(nsImage: image)
      .interpolation(.none)  // Pixel art: preserve hard edges when scaling up
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

private struct GPUAnimatedPetSprite: NSViewRepresentable {
  var sprite: PetSprite
  var bobAmplitude: CGFloat
  var bobPeriod: TimeInterval
  var onTap: () -> Void

  func makeNSView(context: Context) -> PetSpriteLayerView {
    let view = PetSpriteLayerView()
    view.onTap = onTap
    view.configure(
      sprite: sprite,
      bobAmplitude: bobAmplitude,
      bobPeriod: bobPeriod
    )
    return view
  }

  func updateNSView(_ nsView: PetSpriteLayerView, context: Context) {
    nsView.onTap = onTap
    nsView.configure(
      sprite: sprite,
      bobAmplitude: bobAmplitude,
      bobPeriod: bobPeriod
    )
  }
}

@MainActor
private final class PetSpriteLayerView: NSView {
  private struct Configuration: Equatable {
    var imageID: ObjectIdentifier
    var frames: Int
    var frameRate: Double
    var bobAmplitude: CGFloat
    var bobPeriod: TimeInterval
  }

  private let spriteLayer = CALayer()
  private var configuration: Configuration?
  var onTap: (() -> Void)?

  init() {
    super.init(frame: .zero)
    wantsLayer = true
    layer?.backgroundColor = NSColor.clear.cgColor
    spriteLayer.contentsGravity = .resizeAspect
    spriteLayer.magnificationFilter = .nearest
    spriteLayer.minificationFilter = .nearest
    layer?.addSublayer(spriteLayer)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layout() {
    super.layout()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    spriteLayer.frame = bounds
    spriteLayer.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    CATransaction.commit()
  }

  override func mouseDown(with event: NSEvent) {
    onTap?()
  }

  func configure(
    sprite: PetSprite,
    bobAmplitude: CGFloat,
    bobPeriod: TimeInterval
  ) {
    let frameRate = min(12, max(1, sprite.fps))
    let next = Configuration(
      imageID: ObjectIdentifier(sprite.image),
      frames: sprite.frames,
      frameRate: frameRate,
      bobAmplitude: bobAmplitude,
      bobPeriod: bobPeriod
    )
    guard configuration != next else { return }
    configuration = next

    spriteLayer.removeAllAnimations()
    if sprite.frames > 1 {
      configureFrameAnimation(sprite: sprite, frameRate: frameRate)
    } else {
      spriteLayer.contents = sprite.image.cgImage(forProposedRect: nil, context: nil, hints: nil)
      configureBobbingAnimation(amplitude: bobAmplitude, period: bobPeriod)
    }
  }

  private func configureFrameAnimation(sprite: PetSprite, frameRate: Double) {
    let frames = (0..<sprite.frames).compactMap {
      sprite.frame(at: $0).cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
    guard frames.count == sprite.frames, let first = frames.first else {
      spriteLayer.contents = sprite.image.cgImage(forProposedRect: nil, context: nil, hints: nil)
      return
    }

    spriteLayer.contents = first
    let animation = CAKeyframeAnimation(keyPath: "contents")
    animation.values = frames
    animation.calculationMode = .discrete
    animation.duration = Double(frames.count) / frameRate
    animation.repeatCount = .infinity
    animation.isRemovedOnCompletion = false
    spriteLayer.add(animation, forKey: "pet.frames")
  }

  private func configureBobbingAnimation(amplitude: CGFloat, period: TimeInterval) {
    let translation = CABasicAnimation(keyPath: "transform.translation.y")
    translation.fromValue = -amplitude
    translation.toValue = amplitude

    let breathing = CABasicAnimation(keyPath: "transform.scale")
    breathing.fromValue = 0.97
    breathing.toValue = 1.03

    let animation = CAAnimationGroup()
    animation.animations = [translation, breathing]
    animation.duration = period / 2
    animation.autoreverses = true
    animation.repeatCount = .infinity
    animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    animation.isRemovedOnCompletion = false
    spriteLayer.add(animation, forKey: "pet.bobbing")
  }
}

/// Full pet view that wires together the behavior controller and sprite renderer.
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
