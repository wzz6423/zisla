import AppKit

@objc private protocol EditingActionTarget {
    func undo(_ sender: Any?)
    func redo(_ sender: Any?)
}

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
  internal var applicationActivationHandler: () -> Void = {
    NSApp.activate(ignoringOtherApps: true)
  }
  public var allowsKeyWindow = false
  /// Records that the transparent style's native glass surface is on screen. The active-appearance
  /// override below is what keeps that surface rendering, so this never influences focus.
  public var keepsNativeGlassActive = false
  /// Prevents app activation while recording, preserving focus in the target input.
  public var avoidsAppActivation = false
  public var isPinned = false
  private var transitionGeneration: UInt64 = 0
  private nonisolated(unsafe) var clickMonitor: Any?

    /// Window level used when the collapsed island sits above other windows (same layer as the menu bar).
    public static let onTopLevel = NSWindow.Level.statusBar
    /// Window level used when the collapsed island sinks below the menu bar: lower than both the menu bar (24) and normal windows, so they cover it.
    public static let onBottomLevel = NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue - 1)

    public override var canBecomeKey: Bool { allowsKeyWindow }
    public override var canBecomeMain: Bool { false }

    /// `NSGlassEffectView` renders its full Liquid Glass treatment only while the host window paints
    /// as active, and AppKit derives that from key status — which this `.nonactivatingPanel` must
    /// never take, because `makeKeyAndOrderFront` flips `NSApp.isActive` and pulls the caret out of
    /// whatever the user is typing in even while another app stays frontmost. Claiming active
    /// appearance separates the two: measured pixel-identical to a key window's glass with
    /// `isKeyWindow` still false, which is what lets automatic refreshes (track changes, notice
    /// updates, repositioning) leave focus completely alone. Unconditional on purpose — there is no
    /// inactive look to preserve, since the island is always dark and never follows the system
    /// appearance, and a state-dependent answer would need an invalidation hook AppKit only fires on
    /// real key changes. If a future AppKit stops asking, the island simply falls back to today's
    /// frosted rendering.
    @objc(_hasActiveAppearance)
    private func islandHasActiveAppearance() -> Bool { true }

    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard let action = Self.editingAction(for: event),
              let firstResponder,
              NSApp.sendAction(action, to: firstResponder, from: self)
        else {
            return super.performKeyEquivalent(with: event)
        }
        return true
    }

    /// Moves the panel without leaving the window server's ordering. The zero-duration context
    /// suppresses the ambient implicit-animation transaction that otherwise smears the frame change
    /// across intermediate positions; ordering the panel out and back in cured the same smear but
    /// dropped the window from the server's ordering, costing a frame and a Space rejoin.
    private func setFrameWithoutReordering(_ frame: CGRect) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            setFrame(frame, display: true)
        }
    }

    private func handleContentViewClick() {
        // A deliberate click may take focus — but not while recording, when the caret belongs to the
        // app being dictated into.
        guard !avoidsAppActivation else { return }
        applicationActivationHandler()
        makeKeyAndOrderFront(nil)
    }

    /// The other deliberate path to the caret: the user opened a text surface inside the island
    /// (quick notes, mail, teleprompter) on purpose. Never called for automatic content refreshes.
    public func takeKeyboardFocus() {
        guard !avoidsAppActivation, canBecomeKey else { return }
        applicationActivationHandler()
        makeKeyAndOrderFront(nil)
    }

    private static func editingAction(for event: NSEvent) -> Selector? {
        let modifiers = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])
        let key = event.charactersIgnoringModifiers?.lowercased()

        return switch (key, modifiers) {
        case ("a", .command): #selector(NSResponder.selectAll(_:))
        case ("c", .command): #selector(NSText.copy(_:))
        case ("v", .command): #selector(NSText.paste(_:))
        case ("x", .command): #selector(NSText.cut(_:))
        case ("z", .command): #selector(EditingActionTarget.undo(_:))
        case ("z", [.command, .shift]): #selector(EditingActionTarget.redo(_:))
        default: nil
        }
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

        // Monitor mouse clicks within the window.
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
        /// Visible at a different frame: move it, then re-assert ordering.
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
    alphaValue = 1
    if plan != .refront { setFrameWithoutReordering(frame) }
    orderFrontRegardless()
  }

  public func resize(to frame: CGRect, animated: Bool = true) {
    guard self.frame != frame else { return }
    transitionGeneration &+= 1
    _ = animated
    setFrameWithoutReordering(frame)
    if isVisible { orderFrontRegardless() }
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
