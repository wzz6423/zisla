import AppKit

private final class ClickBlockingContentView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        // WindowServer routes fully transparent window pixels to the window underneath.
        NSColor.black.withAlphaComponent(1.0 / 255.0).setFill()
        NSBezierPath(rect: dirtyRect).fill()
    }
}

@MainActor
public final class IslandPanel: NSPanel {
  public var allowsKeyWindow = false
  private var transitionGeneration: UInt64 = 0

    public override var canBecomeKey: Bool { allowsKeyWindow }
    public override var canBecomeMain: Bool { false }

    public override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    public init(
        contentView: NSView,
        frame: CGRect,
        blocksClicksInTransparentAreas: Bool = false
    ) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .statusBar
        // isFloatingPanel 会在窗口显示时回落到 floating 合成层，遮在菜单栏后方。
        // canJoinAllApplications 让浮层进入其他 app 的全屏 Space；fullScreenAuxiliary 只覆盖本 app 全屏窗口。
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .canJoinAllApplications, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        // 岛固定深色，不随系统明暗切换
        appearance = NSAppearance(named: .darkAqua)
    hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        acceptsMouseMovedEvents = true
        becomesKeyOnlyIfNeeded = true
        if blocksClicksInTransparentAreas {
            let blockingView = ClickBlockingContentView(
                frame: CGRect(origin: .zero, size: frame.size)
            )
            contentView.frame = blockingView.bounds
            contentView.autoresizingMask = [.width, .height]
            blockingView.addSubview(contentView)
            self.contentView = blockingView
        } else {
            self.contentView = contentView
        }
    }

  public func present(
    at frame: CGRect,
    from collapsedFrame: CGRect? = nil,
    animated: Bool = true
  ) {
    _ = collapsedFrame
    _ = animated
    guard !isVisible || self.frame != frame else { return }
    transitionGeneration &+= 1
    let requiresReposition = isVisible
    // NSPanel 在可见状态下变更 frame 时会显示窗口服务器的中间帧，哪怕
    // animationBehavior 为 .none。先移出合成层再定位，展开仅由 SwiftUI 遮罩绘制。
    if requiresReposition { orderOut(nil) }
    alphaValue = 1
    setFrame(frame, display: true)
    orderFrontRegardless()
  }

  public func resize(to frame: CGRect, animated: Bool = true) {
    guard self.frame != frame else { return }
    transitionGeneration &+= 1
    _ = animated
    let requiresReposition = isVisible
    if requiresReposition { orderOut(nil) }
    setFrame(frame, display: true)
    if requiresReposition { orderFrontRegardless() }
  }

  public func dismiss(to collapsedFrame: CGRect? = nil, animated: Bool = true) {
    guard isVisible else { return }
    transitionGeneration &+= 1
    let generation = transitionGeneration
    guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
      orderOut(nil)
      return
    }
    _ = collapsedFrame
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.14
      context.allowsImplicitAnimation = true
      animator().alphaValue = 0
    } completionHandler: { [weak self] in
      MainActor.assumeIsolated {
        guard let self, self.transitionGeneration == generation else { return }
        self.orderOut(nil)
        self.alphaValue = 1
      }
    }
  }
}
