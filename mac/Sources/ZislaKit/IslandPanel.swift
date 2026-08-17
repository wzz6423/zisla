import AppKit

private final class ClickBlockingContentView: NSView {
    var onMouseDown: (() -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        // WindowServer routes fully transparent window pixels to the window underneath.
        NSColor(white: 0, alpha: 1.0 / 255.0).setFill()
        NSBezierPath(rect: dirtyRect).fill()
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        onMouseDown?()
    }
}

@MainActor
public final class IslandPanel: NSPanel {
  public var allowsKeyWindow = false
  public var allowsNativeGlassActivation = true
  public var keepsNativeGlassActive = false {
    didSet { restoreNativeGlassActivationIfNeeded() }
  }
  /// 语音录音期间不激活或重新获得 key window，保持目标输入焦点。
  public var avoidsAppActivation = false
  public var isPinned = false
  private var transitionGeneration: UInt64 = 0
  private nonisolated(unsafe) var clickMonitor: Any?

    /// Window level used when the collapsed island sits above other windows (same layer as the menu bar).
    public static let onTopLevel = NSWindow.Level.statusBar
    /// Window level used when the collapsed island sinks below the menu bar: lower than both the menu bar (24) and normal windows, so they cover it.
    public static let onBottomLevel = NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue - 1)

    public override var canBecomeKey: Bool {
        allowsKeyWindow || (allowsNativeGlassActivation && keepsNativeGlassActive) || (isPinned && allowsKeyWindow)
    }
    public override var canBecomeMain: Bool { false }

  public override func resignKey() {
        guard !avoidsAppActivation,
              allowsNativeGlassActivation,
              keepsNativeGlassActive,
              isVisible else {
            super.resignKey()
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.restoreNativeGlassActivationIfNeeded()
        }
    }

    private func restoreNativeGlassActivationIfNeeded() {
        guard !avoidsAppActivation,
              allowsNativeGlassActivation,
              keepsNativeGlassActive,
              isVisible else { return }
        // 固定时不自动抢回焦点，只在非固定状态下自动激活。
        if !isPinned {
            NSApp.activate(ignoringOtherApps: true)
        }
        makeKeyAndOrderFront(nil)
    }

    private func handleContentViewClick() {
        // 当用户点击灵动岛内容时，主动激活应用和窗口
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }

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

        level = Self.onTopLevel
        // isFloatingPanel causes the window to fall back into the floating compositing layer when shown, hiding it behind the menu bar.
        // `stationary` keeps the cross-display pet in the full-screen Space instead of tracking the active app's Space.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .canJoinAllApplications, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        // The island is always dark; it does not follow the system light/dark mode toggle.
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
            blockingView.onMouseDown = { [weak self] in
                self?.handleContentViewClick()
            }
            contentView.frame = blockingView.bounds
            contentView.autoresizingMask = [.width, .height]
            blockingView.addSubview(contentView)
            self.contentView = blockingView
        } else {
            self.contentView = contentView
        }

        // 监听窗口内的鼠标点击事件
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self = self, event.window === self else { return event }
            self.handleContentViewClick()
            return event
        }
    }

    deinit {
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    /// How `present(at:)` reaches a target frame from the panel's current state.
    enum PresentationPlan: Equatable {
        /// Already visible at the target frame: re-assert window ordering without touching the frame.
        case refront
        /// Not on screen yet: position it, then order it in.
        case show
        /// Visible at a different frame: leave the compositing layer before moving.
        case reposition
    }

    /// A visible panel at the target frame must still be re-fronted, never skipped: when another app
    /// opens a full-screen Space, WindowServer drops this window from that Space's ordering even with
    /// `canJoinAllSpaces`, and `orderFrontRegardless()` is the only thing that rejoins it. The
    /// active-Space observer's re-present is the recovery path, so it may not resolve to a no-op.
    static func presentationPlan(isVisible: Bool, currentFrame: CGRect, targetFrame: CGRect)
        -> PresentationPlan
    {
        guard isVisible else { return .show }
        return currentFrame == targetFrame ? .refront : .reposition
    }

  public func present(
    at frame: CGRect,
    from collapsedFrame: CGRect? = nil,
    animated: Bool = true
  ) {
    _ = collapsedFrame
    _ = animated
    let plan = Self.presentationPlan(
      isVisible: isVisible,
      currentFrame: self.frame,
      targetFrame: frame
    )
    // Supersedes any in-flight dismiss fade so its completion cannot order this panel back out.
    transitionGeneration &+= 1
    // NSPanel produces WindowServer intermediate frames when its frame changes while visible, even with
    // animationBehavior set to .none. Move it out of the compositing layer first, then reposition it;
    // expansion is drawn solely by the SwiftUI mask.
    if plan == .reposition { orderOut(nil) }
    alphaValue = 1
    if plan != .refront { setFrame(frame, display: true) }
    orderFrontRegardless()
    restoreNativeGlassActivationIfNeeded()
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
      Task { @MainActor in
        guard let self, self.transitionGeneration == generation else { return }
        self.orderOut(nil)
        self.alphaValue = 1
      }
    }
  }
}
