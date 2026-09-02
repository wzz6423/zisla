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
  internal static var applicationActivationHandler: () -> Void = {
    NSApp.activate(ignoringOtherApps: true)
  }
  public var allowsKeyWindow = false
  public var allowsNativeGlassActivation = true
  /// Re-asserting the same value happens on every island refresh — a new track landing in the media
  /// header, a module resize. Only a real transition may reclaim activation; reclaiming on a refresh
  /// pulls the caret out of whatever text field the user is typing in.
  public var keepsNativeGlassActive = false {
    didSet {
      guard keepsNativeGlassActive != oldValue else { return }
      restoreNativeGlassActivationIfNeeded()
    }
  }
  /// Prevents app activation or key-window reacquisition during recording, preserving focus in the target input.
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

    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard let action = Self.editingAction(for: event),
              let firstResponder,
              NSApp.sendAction(action, to: firstResponder, from: self)
        else {
            return super.performKeyEquivalent(with: event)
        }
        return true
    }

  public override func resignKey() {
        // Keep this recovery branch: Liquid Glass needs the panel to remain key after a normal
        // resignation. Do not replace it with an unconditional `super.resignKey()`.
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

    /// Reclaims activation for the glass surface on a deliberate reveal. Refresh paths must not call
    /// this: it activates the app, which moves keyboard focus off the user's current text field.
    public func activateNativeGlassIfNeeded() {
        restoreNativeGlassActivationIfNeeded(allowingApplicationActivation: true)
    }

    private func restoreNativeGlassActivationIfNeeded(allowingApplicationActivation: Bool = false) {
        guard !avoidsAppActivation,
              allowsNativeGlassActivation,
              keepsNativeGlassActive,
              isVisible else { return }
        // Lifecycle recovery must suppress only application activation. The panel still has to become key so
        // NSGlassEffectView keeps its native compositing path instead of falling back to frosted glass.
        // Do not automatically reclaim focus while pinned; activate only when unpinned.
        // Lifecycle recovery stays non-activating; only an explicit reveal opts into application activation.
        if allowingApplicationActivation && !isPinned {
            Self.applicationActivationHandler()
        }
        makeKeyAndOrderFront(nil)
    }

    private func handleContentViewClick() {
        // Explicitly activate the app and window when the user clicks the island.
        NSApp.activate(ignoringOtherApps: true)
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
    // Only the first reveal may activate the app. Refreshes keep the original compositor ordering
    // path, while the non-activating restore above preserves the frontmost app's caret.
    if plan == .show { activateNativeGlassIfNeeded() }
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
