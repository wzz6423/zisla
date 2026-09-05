import AppKit
import Combine
import SkyLightWindow
import SwiftUI
import ZislaCore
import ZislaKit

private extension ClipboardAssistantController {
    /// The clipboard assistant needs extra horizontal space for the content preview and trailing actions.
    static let islandRowWidth = ScreenLayoutConfiguration().expandedSize.width + 60
    static let defaultRowHeight = ScreenLayoutConfiguration().simulatedIslandSize.height

    static func trailingControlsWidth(
        for detection: ClipboardAssistantDetection,
        isLightweightMode: Bool
    ) -> CGFloat {
        let horizontalPadding: CGFloat = 22
        guard !isLightweightMode, let action = detection.action else {
            return horizontalPadding + 20
        }
        let title = AppLocalization.string(
            ClipboardAssistantToastView.actionLabel(action),
            language: AppModel.shared.languageStore.language
        )
        let textWidth = (title as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
        ]).width
        return horizontalPadding + 22 + 8 + textWidth + 24 + 8 + 19 + 8 + 20
    }
}

    /// Borderless always-on-top panel hosting the assistant island row; mirrors IslandPanel's setup.
@MainActor
final class ClipboardAssistantWindow: NSPanel {
    static let defaultWindowLevel = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(contentView: NSView, frame: CGRect) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = Self.defaultWindowLevel
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .canJoinAllApplications, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        appearance = NSAppearance(named: .darkAqua)
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        self.contentView = contentView
        SkyLightOperator.shared.delegateWindow(self)
    }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

/// Presentation state driving the island row's SwiftUI content.
@MainActor
final class ClipboardAssistantPresentation: ObservableObject {
    @Published var detection: ClipboardAssistantDetection?
    /// Thumbnail preview shown for copied images.
    @Published var imageThumbnail: NSImage?
    /// Matches the surface to the Dynamic Island appearance selected in Settings.
    @Published var visualStyle: IslandVisualStyle = .transparent
    /// The crown remains the same height as the notch the prompt expands from.
    @Published var islandTopHeight: CGFloat = ScreenLayoutConfiguration().simulatedIslandSize.height
    @Published var physicalNotchWidth: CGFloat = 0
    /// Toggled from the view so the countdown pauses while the pointer rests on the toast.
    var isHovered = false
}

/// Shows a one-row island prompt after every copy, offering smart next-step actions for the copied
/// content.
@MainActor
final class ClipboardAssistantController: ObservableObject {
    let presentation = ClipboardAssistantPresentation()
    /// Lets the main island pause hover activation while this row occupies its trigger area.
    var onPresentationChanged: ((Bool) -> Void)?
    /// Auto-dismiss setting for newly presented assistant prompts.
    var displayDuration: ClipboardAssistantDisplayDuration = .fiveSeconds {
        didSet {
            guard displayDuration != oldValue, presentation.detection != nil else { return }
            if displayDuration.expiresAfter == nil || presentation.isHovered {
                cancelDismissTask()
            } else {
                scheduleDismiss()
            }
        }
    }
    /// Executes a detection action; provided by AppModel.
    var onPerformAction: ((ClipboardAssistantAction) -> Void)?
    /// Compact reminder mode: no buttons, tapping anywhere performs the primary action.
    var isLightweightMode = false {
        didSet {
            guard isLightweightMode != oldValue else { return }
            presentation.objectWillChange.send()
        }
    }

    /// Where the assistant row stands while a screenshot session runs.
    private enum ScreenshotPhase {
        /// No screenshot session.
        case inactive
        /// The display is about to be frozen; the row stays visible at its normal level so the
        /// frozen image includes it.
        case capturing
        /// The selection overlay renders the frozen capture (which already contains the row), so
        /// the row hides to avoid a duplicate on top of the overlay.
        case selecting
        /// The overlay is gone (region picked or cancelled) and the row behaves normally again.
        case restored
    }

    private var screenshotPhase = ScreenshotPhase.inactive
    private var isSystemScreenshotActive = false
    private var isScreenshotActive: Bool {
        screenshotPhase != .inactive || isSystemScreenshotActive
    }
    private var isSharingAnchorHeld = false

    private var window: ClipboardAssistantWindow?
    private var dismissTask: Task<Void, Never>?
    private var presentationGeneration = 0
    private var dismissalGeneration = 0
    private let triggerMonitor = ClipboardAssistantTriggerMonitor()
    private let gestureMonitor = ClipboardAssistantMouseGestureMonitor()
    @Published private(set) var isMoreActionsPresented = false

    /// Applies the user-configured quick triggers (hotkey + mouse side button).
    /// Returns `false` when a configured trigger needs the input-monitoring permission
    /// that has not been granted yet.
    @discardableResult
    func setTriggers(
        hotkey: VoiceInputHotkeyPreset?,
        mouseButton: Int?
    ) -> Bool {
        triggerMonitor.apply(hotkey: hotkey, mouseButton: mouseButton) { [weak self] in
            MainActor.assumeIsolated { self?.performCurrentAction() }
        }
    }

    /// Enables the hold-left + right-click quick copy gesture. Returns `false` when either the
    /// input-monitoring or the accessibility permission is missing.
    @discardableResult
    func setMouseGesture(
        enabled: Bool,
        onQuickCopy: @escaping () -> Void
    ) -> Bool {
        guard enabled else {
            gestureMonitor.stop()
            return true
        }
        return gestureMonitor.start(onCopy: onQuickCopy)
    }

    var isMouseGestureActive: Bool { gestureMonitor.isActive }

    /// Window accessor used by the toast view to animate expansion.
    var windowForFrameUpdate: NSWindow? { window }

    /// Anchor for system sharing launched from the assistant row.
    var sharingAnchorView: NSView? { window?.contentView }

    func setMoreActionsPresented(_ presented: Bool) {
        guard isMoreActionsPresented != presented else { return }
        isMoreActionsPresented = presented
    }

    /// A screenshot session keeps the prompt long enough for the frozen capture, then restores it
    /// after the selection overlay leaves.
    func setScreenshotActive(_ active: Bool) {
        setScreenshotPhase(active ? .capturing : .inactive)
    }

    /// Native screenshot selection is live rather than frozen, so the assistant must leave the
    /// screen before it can cover the system selection or markup UI.
    func setSystemScreenshotActive(_ active: Bool) {
        guard isSystemScreenshotActive != active else { return }
        isSystemScreenshotActive = active
        if active {
            presentation.isHovered = false
            setMoreActionsPresented(false)
        }
        applyScreenshotPhase()
        updateScreenshotDismissal()
    }

    /// The selection overlay already contains the frozen row, so hide the live window to avoid a
    /// duplicate outside the selected region.
    func setScreenshotSelectionActive(_ active: Bool) {
        guard screenshotPhase != .inactive else { return }
        if active { setMoreActionsPresented(false) }
        setScreenshotPhase(active ? .selecting : .restored)
    }

    private func setScreenshotPhase(_ phase: ScreenshotPhase) {
        guard screenshotPhase != phase else { return }
        screenshotPhase = phase
        // The pointer moves onto the selection overlay, so hover must not outlive the capture.
        if phase == .capturing {
            presentation.isHovered = false
        }
        applyScreenshotPhase()
        updateScreenshotDismissal()
    }

    private func updateScreenshotDismissal() {
        if screenshotPhase == .capturing || screenshotPhase == .selecting || isSystemScreenshotActive {
            cancelDismissTask()
        } else {
            scheduleDismiss()
        }
    }

    private func applyScreenshotPhase() {
        guard let window else { return }
        let hidesLiveWindow = screenshotPhase == .selecting || isSystemScreenshotActive
        window.ignoresMouseEvents = hidesLiveWindow
        window.level = ClipboardAssistantWindow.defaultWindowLevel
        guard presentation.detection != nil else { return }
        if hidesLiveWindow {
            if window.isVisible {
                window.orderOut(nil)
            }
        } else if screenshotPhase == .restored || screenshotPhase == .inactive {
            if !window.isVisible {
                window.alphaValue = 1
                window.orderFrontRegardless()
            }
        }
    }

    func present(_ detection: ClipboardAssistantDetection, visualStyle: IslandVisualStyle) {
        setMoreActionsPresented(false)
        guard !isScreenshotActive else { return }
        isSharingAnchorHeld = false
        cancelDismissTask()
        presentationGeneration &+= 1
        presentation.isHovered = false
        presentation.visualStyle = visualStyle
        presentation.detection = detection
        presentation.imageThumbnail = Self.thumbnail(for: detection)
        showWindow(detection)
        onPresentationChanged?(true)
        scheduleDismiss()
    }

    func dismiss(animated: Bool = true) {
        setMoreActionsPresented(false)
        isSharingAnchorHeld = false
        cancelDismissTask()
        presentationGeneration &+= 1
        let generation = presentationGeneration
        guard let window, window.isVisible else {
            presentation.detection = nil
            onPresentationChanged?(false)
            return
        }
        guard animated else {
            window.orderOut(nil)
            window.alphaValue = 1
            presentation.detection = nil
            onPresentationChanged?(false)
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard self.presentationGeneration == generation else { return }
                window.orderOut(nil)
                window.alphaValue = 1
                self.presentation.detection = nil
                self.onPresentationChanged?(false)
            }
        })
    }

    /// Fires the given action and dismisses after completion; sharing keeps the anchor until its picker closes.
    func perform(_ action: ClipboardAssistantAction) {
        setMoreActionsPresented(false)
        let generation = presentationGeneration
        if case .share = action {
            isSharingAnchorHeld = true
            cancelDismissTask()
        }
        onPerformAction?(action)
        guard !isSharingAnchorHeld else { return }
        guard presentationGeneration == generation else { return }
        dismiss()
    }

    /// Fires the current detection's primary action (quick trigger or lightweight-mode tap).
    func performCurrentAction() {
        guard let action = presentation.detection?.action else { return }
        perform(action)
    }

    func setHovered(_ hovered: Bool) {
        guard presentation.isHovered != hovered else { return }
        presentation.isHovered = hovered
        if hovered {
            cancelDismissTask()
        } else {
            scheduleDismiss()
        }
    }

    private func scheduleDismiss() {
        cancelDismissTask()
        guard presentation.detection != nil else { return }
        guard !isScreenshotActive else { return }
        guard !isSharingAnchorHeld else { return }
        guard let seconds = displayDuration.expiresAfter else {
            dismissTask = nil
            return
        }
        let presentationGeneration = self.presentationGeneration
        let dismissalGeneration = self.dismissalGeneration
        dismissTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(seconds))
            } catch {
                return
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                guard self.presentationGeneration == presentationGeneration,
                      self.dismissalGeneration == dismissalGeneration else { return }
                if self.presentation.isHovered { return }
                self.dismiss()
            }
        }
    }

    private func cancelDismissTask() {
        dismissTask?.cancel()
        dismissTask = nil
        dismissalGeneration &+= 1
    }

    static func thumbnail(for detection: ClipboardAssistantDetection) -> NSImage? {
        for action in detection.actions {
            if case let .saveImage(data) = action {
                return NSImage(data: data)
            }
        }
        return nil
    }

    private func showWindow(_ detection: ClipboardAssistantDetection) {
        guard let screen = WindowPlacement.screenUnderMouse() ?? NSScreen.main else { return }
        let screenSnapshot = ScreenSnapshot(screen: screen)
        let layout = screenSnapshot.map { ScreenLayoutEngine().layout(for: $0) }
        let collapsedFrame = layout?.collapsedFrame
            ?? CGRect(
                x: screen.frame.midX,
                y: screen.frame.maxY - Self.defaultRowHeight,
                width: 0,
                height: Self.defaultRowHeight
            )
        if let layout {
            let topology = layout.topology
            presentation.physicalNotchWidth = topology.hasPhysicalNotch ? topology.anchorFrame.width : 0
        } else {
            presentation.physicalNotchWidth = 0
        }
        let width = ClipboardAssistantToastView.requiredRowWidth(
            baseWidth: Self.islandRowWidth,
            maximumWidth: max(320, screen.frame.width - 48),
            notchWidth: presentation.physicalNotchWidth,
            trailingControlsWidth: Self.trailingControlsWidth(
                for: detection,
                isLightweightMode: isLightweightMode
            )
        )
        presentation.islandTopHeight = collapsedFrame.height
        let frame = CGRect(
            x: collapsedFrame.midX - width / 2,
            y: collapsedFrame.minY,
            width: width,
            height: collapsedFrame.height
        )
        let window: ClipboardAssistantWindow
        if let existing = self.window {
            window = existing
        } else {
            let hostingView = NSHostingView(
                rootView: AppLanguageEnvironment(
                    languageStore: AppModel.shared.languageStore,
                    content: ClipboardAssistantToastView(
                        presentation: presentation,
                        controller: self
                    )
                )
            )
            hostingView.sizingOptions = []
            hostingView.wantsLayer = true
            hostingView.layer?.backgroundColor = NSColor.clear.cgColor
            window = ClipboardAssistantWindow(contentView: hostingView, frame: frame)
            self.window = window
        }
        window.setFrame(frame, display: false)
        window.alphaValue = 0
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }
    }

}

/// Dynamic Island-styled row: thumbnail or kind icon (color swatch for colors), preview lines,
/// an optional expandable full-content view, and the offered actions. All visible strings are
/// rendered through the app localization so they follow the user's interface language.
struct ClipboardAssistantToastView: View {
    @ObservedObject var presentation: ClipboardAssistantPresentation
    @ObservedObject var controller: ClipboardAssistantController

    private static let maxExpandedContentHeight: CGFloat = 220
    @Environment(\.locale) private var locale
    @State private var isExpanded = false

    private var rowHeight: CGFloat {
        max(1, presentation.islandTopHeight)
    }

    private var detailIsVisible: Bool {
        rowHeight >= 30
    }

    private var controlVerticalPadding: CGFloat {
        min(6, max(2, (rowHeight - 14) / 2))
    }

    var body: some View {
        GeometryReader { geometry in
            if let detection = presentation.detection {
                IslandSurface(
                    isCollapsed: !isExpanded,
                    collapsedSize: CGSize(
                        width: geometry.size.width,
                        height: min(geometry.size.height, presentation.islandTopHeight)
                    ),
                    expandedSize: geometry.size,
                    visualStyle: presentation.visualStyle,
                    collapsedTopCornerRadius: 0,
                    bottomCornerRadius: VoiceRecordingIslandGeometry.bottomCornerRadius
                ) {
                    VStack(spacing: 0) {
                        toastHeader(detection)
                        if isExpanded, let content = expandableContent(detection) {
                            Rectangle()
                                .fill(Color.white.opacity(0.08))
                                .frame(height: 0.5)
                                .padding(.horizontal, 14)
                            expandedContentView(content)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
                .animation(.spring(response: 0.3, dampingFraction: 0.85), value: presentation.detection)
                .onChange(of: presentation.detection) {
                    // A new copy collapses any previously expanded preview.
                    if isExpanded { isExpanded = false }
                }
            }
        }
        .ignoresSafeArea(edges: .top)
        .environment(\.colorScheme, .dark)
    }

    // MARK: Header row

    @ViewBuilder
    private func toastHeader(_ detection: ClipboardAssistantDetection) -> some View {
        Group {
            if presentation.physicalNotchWidth > 0 {
                physicalNotchHeader(detection)
            } else {
                continuousHeader(detection)
                    .padding(.horizontal, 14)
            }
        }
        .frame(height: rowHeight)
        .contentShape(Rectangle())
        .contextMenu {
            actionMenuItems(detection.actions)
        }
        .onHover { hovering in
            controller.setHovered(hovering)
        }
    }

    private func continuousHeader(_ detection: ClipboardAssistantDetection) -> some View {
        HStack(spacing: 10) {
            headerContent(detection)
                .frame(maxWidth: .infinity, alignment: .leading)
            trailingControls(detection)
        }
    }

    private func physicalNotchHeader(_ detection: ClipboardAssistantDetection) -> some View {
        GeometryReader { geometry in
            let sideWidth = Self.physicalNotchSideWidth(
                totalWidth: geometry.size.width,
                notchWidth: presentation.physicalNotchWidth
            )
            let centerWidth = max(0, geometry.size.width - sideWidth * 2)
            HStack(spacing: 0) {
                headerContent(detection)
                    .padding(.leading, 14)
                    .padding(.trailing, 8)
                    .frame(width: sideWidth, height: rowHeight, alignment: .leading)
                    .clipped()

                Spacer(minLength: 0)
                    .frame(width: centerWidth)

                trailingControls(detection)
                    .padding(.leading, 8)
                    .padding(.trailing, 14)
                    .frame(width: sideWidth, height: rowHeight, alignment: .trailing)
                    .clipped()
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    nonisolated static func physicalNotchSideWidth(totalWidth: CGFloat, notchWidth: CGFloat) -> CGFloat {
        let totalWidth = max(0, totalWidth)
        let reservedCenterWidth = min(max(0, notchWidth), totalWidth)
        return (totalWidth - reservedCenterWidth) / 2
    }

    nonisolated static func requiredRowWidth(
        baseWidth: CGFloat,
        maximumWidth: CGFloat,
        notchWidth: CGFloat,
        trailingControlsWidth: CGFloat
    ) -> CGFloat {
        let baseWidth = max(0, baseWidth)
        let maximumWidth = max(0, maximumWidth)
        let minimumWidth = notchWidth > 0
            ? max(0, notchWidth) + max(0, trailingControlsWidth) * 2
            : baseWidth
        return min(maximumWidth, max(baseWidth, minimumWidth))
    }

    @ViewBuilder
    private func headerContent(_ detection: ClipboardAssistantDetection) -> some View {
        if let dragText = dragText(for: detection) {
            headerContentBody(detection)
                .onDrag { NSItemProvider(object: dragText as NSString) }
        } else {
            headerContentBody(detection)
        }
    }

    private func headerContentBody(_ detection: ClipboardAssistantDetection) -> some View {
        HStack(spacing: 10) {
            leadingAccessory(detection)

            VStack(alignment: .leading, spacing: 2) {
                Text(AppLocalization.text(detection.title))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
                    .fitsSingleLine()
                    .truncationMode(.middle)
                if detailIsVisible, let detailText = detailText(detection.detail) {
                    Text(detailText)
                        .font(.system(size: 9.5, weight: .regular))
                        .foregroundStyle(.white.opacity(0.55))
                        .fitsSingleLine()
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard controller.isLightweightMode else { return }
            controller.performCurrentAction()
        }
    }

    private func dragText(for detection: ClipboardAssistantDetection) -> String? {
        guard [.text, .nonSystemLanguageText, .code, .math].contains(detection.kind),
              let content = detection.fullContent,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return content
    }

    @ViewBuilder
    private func leadingAccessory(_ detection: ClipboardAssistantDetection) -> some View {
        if let thumbnail = presentation.imageThumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .scaledToFill()
                .frame(width: 38, height: max(16, min(28, rowHeight - 6)))
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
                )
        } else if let components = detection.colorComponents {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color(red: components.red, green: components.green, blue: components.blue))
                .frame(width: 26, height: max(16, min(26, rowHeight - 6)))
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
                )
        } else {
            Image(systemName: detection.kind.symbolName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: 26, height: max(16, min(26, rowHeight - 6)))
        }
    }

    private func trailingControls(_ detection: ClipboardAssistantDetection) -> some View {
        HStack(spacing: 8) {
            if controller.isLightweightMode {
                // Lightweight mode keeps the toast minimal: no buttons at all.
                Image(systemName: "sparkle")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(width: 20, height: max(16, min(20, rowHeight - 4)))
            } else {
                if canExpand(detection) {
                    Button {
                        toggleExpansion(detection)
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                            .frame(width: 22, height: max(16, min(22, rowHeight - 4)))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(isExpanded ? loc("收起") : loc("展开完整内容"))
                }
                if let primary = detection.action {
                    Button {
                        controller.perform(primary)
                    } label: {
                        Text(loc(Self.actionLabel(primary)))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.95))
                            .padding(.horizontal, 12)
                            .padding(.vertical, controlVerticalPadding)
                            .background(Capsule().fill(Color.white.opacity(0.14)))
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .buttonStyle(.plain)
                    .help(loc(Self.actionLabel(primary)))
                }
                if detection.action != nil {
                    Button {
                        controller.setMoreActionsPresented(!controller.isMoreActionsPresented)
                    } label: {
                        Image(systemName: "chevron.down.circle")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.92))
                            .frame(width: 19, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(loc("更多操作"))
                    .popover(isPresented: Binding(
                        get: { controller.isMoreActionsPresented },
                        set: { controller.setMoreActionsPresented($0) }
                    ), arrowEdge: .top) {
                        moreActionsPopover(for: detection)
                    }
                }
                Button {
                    controller.dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.45))
                        .frame(width: 20, height: max(16, min(20, rowHeight - 4)))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(loc("关闭"))
            }
        }
    }

    private func menuActions(for detection: ClipboardAssistantDetection) -> [ClipboardAssistantAction] {
        detection.secondaryActions.isEmpty
            ? [detection.action].compactMap { $0 }
            : detection.secondaryActions
    }

    @ViewBuilder
    private func moreActionsPopover(for detection: ClipboardAssistantDetection) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(menuActions(for: detection), id: \.identifier) { action in
                if case .blockSourceApp = action {
                    Divider()
                    moreActionButton(action, role: .destructive)
                } else {
                    moreActionButton(action)
                }
            }
        }
        .padding(6)
        .frame(minWidth: 190)
    }

    private func moreActionButton(
        _ action: ClipboardAssistantAction,
        role: ButtonRole? = nil
    ) -> some View {
        Button(role: role) {
            controller.setMoreActionsPresented(false)
            controller.perform(action)
        } label: {
            Text(actionTitle(action))
                .font(.system(size: 12))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func actionMenuItems(_ actions: [ClipboardAssistantAction]) -> some View {
        ForEach(actions, id: \.identifier) { action in
            if case .blockSourceApp = action {
                Divider()
                Button(role: .destructive) {
                    controller.perform(action)
                } label: {
                    Text(actionTitle(action))
                }
            } else {
                Button(actionTitle(action)) {
                    controller.perform(action)
                }
            }
        }
    }

    // MARK: Expanded content

    private func canExpand(_ detection: ClipboardAssistantDetection) -> Bool {
        guard ![.url, .text, .nonSystemLanguageText, .code, .math].contains(detection.kind) else {
            return false
        }
        guard !controller.isLightweightMode, let content = detection.fullContent else { return false }
        return content.count > 40 || content.contains("\n")
    }

    private func expandableContent(_ detection: ClipboardAssistantDetection) -> String? {
        canExpand(detection) ? detection.fullContent : nil
    }

    private func toggleExpansion(_ detection: ClipboardAssistantDetection) {
        isExpanded.toggle()
        let expanded = isExpanded
        guard let window = controller.windowForFrameUpdate else { return }
        guard let screen = WindowPlacement.screenUnderMouse() ?? NSScreen.main else { return }
        var frame = window.frame
        let topY = frame.maxY
        var newHeight = rowHeight
        if expanded {
            let textHeight = estimateExpandedHeight(detection.fullContent ?? "", width: frame.width)
            newHeight = rowHeight + min(textHeight, Self.maxExpandedContentHeight)
        }
        newHeight = min(newHeight, screen.visibleFrame.height - 80)
        frame.origin.y = topY - newHeight
        frame.size.height = newHeight
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(frame, display: false)
        }
    }

    private func estimateExpandedHeight(_ content: String, width: CGFloat) -> CGFloat {
        let font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        let textWidth = width - 40
        var totalLines: CGFloat = 0
        for line in content.components(separatedBy: "\n") {
            let lineWidth = (line as NSString).size(withAttributes: [.font: font]).width
            totalLines += lineWidth > 0 ? max(1, ceil(lineWidth / max(textWidth, 1))) : 1
        }
        return totalLines * 13 + 24
    }

    private func expandedContentView(_ content: String) -> some View {
        ScrollView(.vertical) {
            Text(content)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.78))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
        }
        .frame(height: isExpanded ? nil : 0)
    }

    // MARK: Localized strings

    private func loc(_ key: String) -> String {
        AppLocalization.string(key, locale: locale)
    }

    /// Locale-aware rendering of the structured detection detail.
    private func detailText(_ detail: ClipboardAssistantDetail?) -> String? {
        switch detail {
        case .characterCount(let count):
            AppLocalization.format("%ld 个字符", locale: locale, [count])
        case .characterAndWordCount(let characters, let words):
            AppLocalization.format("%ld 个字符 · %ld 个词", locale: locale, [characters, words])
        case .chineseCharacterCount(let count):
            AppLocalization.format("%ld 个字", locale: locale, [count])
        case .codeLines(let lines):
            AppLocalization.format("%ld 行", locale: locale, [lines])
        case .imageSize(let wide, let high, let bytes):
            "\(wide) × \(high) · " + byteCountText(bytes)
        case .fileSize(let bytes):
            byteCountText(bytes)
        case .mathExpression(let expression):
            expression + " ="
        case .rgb(let red, let green, let blue, let hex):
            String(format: "R%.0f G%.0f B%.0f · #%@", red * 255, green * 255, blue * 255, hex)
        case .path(let path):
            path
        case nil:
            nil
        }
    }

    private func byteCountText(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    /// Localization key for each executable action.
    static func actionLabel(_ action: ClipboardAssistantAction) -> String {
        switch action {
        case .openURL: "打开链接"
        case .openDownload: "下载"
        case .revealInFinder: "在 Finder 中显示"
        case .search: "搜索"
        case .translate: "翻译"
        case .composeMail: "写邮件"
        case .copyText: "复制结果"
        case .copyFullExpression: "复制完整算式"
        case .compress: "压缩为 ZIP"
        case .share: "系统共享"
        case .callPhone: "拨打电话"
        case .blockSourceApp: "不再显示来自 %@ 的复制"
        case .addToQuickNote: "发送到随记"
        case .sendToTeleprompter: "发送到提词器"
        case .saveImage: "保存图片"
        case .saveText: "保存文本"
        case .createCalendarEvent: "新建日程"
        }
    }

    private func actionTitle(_ action: ClipboardAssistantAction) -> String {
        if case .blockSourceApp(_, let appName) = action {
            return AppLocalization.format("不再显示来自 %@ 的复制", locale: locale, [appName])
        }
        return loc(Self.actionLabel(action))
    }
}


/// Fires the assistant's primary action from user-configured quick triggers:
/// - Ordinary hotkey combos register through Carbon (no permission needed).
/// - Modifier-only hotkeys use a listen-only event tap with double-tap detection, so ordinary
///   modifier usage (copy/paste chords) never fires the action accidentally.
/// - Mouse side buttons always require the input-monitoring permission.
@MainActor
final class ClipboardAssistantTriggerMonitor {
    private var configuredHotkey: VoiceInputHotkeyPreset?
    private var configuredMouseButton: Int?
    private var needsInputMonitoring = false
    private let carbonHotkeyManager = GlobalHotkeyManager()
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var modifierKeyCode: UInt32?
    private var lastModifierReleaseAt: TimeInterval = 0
    private var onTrigger: (() -> Void)?
    private static let doubleTapWindow: TimeInterval = 0.45

    /// Applies both triggers. Returns `false` when any configured trigger needs the
    /// input-monitoring permission that is not granted yet.
    @discardableResult
    func apply(
        hotkey: VoiceInputHotkeyPreset?,
        mouseButton: Int?,
        onTrigger: @escaping () -> Void
    ) -> Bool {
        guard hotkey != configuredHotkey || mouseButton != configuredMouseButton || needsInputMonitoring else {
            return true
        }
        stop()
        configuredHotkey = hotkey
        configuredMouseButton = mouseButton

        needsInputMonitoring = false
        if let hotkey {
            if hotkey.isModifierOnly {
                if GlobalHotkeyManager.hasInputMonitoringAccess {
                    modifierKeyCode = hotkey.keyCode
                    ensureEventTap()
                } else {
                    needsInputMonitoring = true
                }
            } else {
                carbonHotkeyManager.register(hotkey: hotkey, onKeyDown: onTrigger, onKeyUp: {})
            }
        }
        if mouseButton != nil {
            if GlobalHotkeyManager.hasInputMonitoringAccess {
                ensureEventTap()
            } else {
                needsInputMonitoring = true
            }
        }
        self.onTrigger = onTrigger
        return !needsInputMonitoring
    }

    func stop() {
        carbonHotkeyManager.unregister()
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        eventTap = nil
        runLoopSource = nil
        modifierKeyCode = nil
        lastModifierReleaseAt = 0
        configuredHotkey = nil
        configuredMouseButton = nil
        needsInputMonitoring = false
    }

    /// One shared listen-only tap covers both flagsChanged (modifier double-tap) and
    /// otherMouseDown (side button); the handler filters events by the current configuration.
    private func ensureEventTap() {
        guard eventTap == nil else { return }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(1) << CGEventType.flagsChanged.rawValue
                | CGEventMask(1) << CGEventType.otherMouseDown.rawValue,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<ClipboardAssistantTriggerMonitor>
                    .fromOpaque(userInfo).takeUnretainedValue()
                MainActor.assumeIsolated {
                    monitor.handle(type: type, event: event)
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source
    }

    private func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .flagsChanged:
            handleFlagsChanged(event)
        case .otherMouseDown:
            let buttonNumber = Int(event.getIntegerValueField(.mouseEventButtonNumber))
            guard buttonNumber == configuredMouseButton else { return }
            onTrigger?()
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
        default:
            break
        }
    }

    /// Double-tap detection for modifier-only hotkeys: only completed press-release cycles count.
    private func handleFlagsChanged(_ event: CGEvent) {
        guard let targetKeyCode = modifierKeyCode else { return }
        let keyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
        guard keyCode == targetKeyCode else { return }
        let stillPressed = CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(keyCode))
        guard !stillPressed else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let interval = now - lastModifierReleaseAt
        if interval > 0.03, interval <= Self.doubleTapWindow {
            lastModifierReleaseAt = 0
            onTrigger?()
        } else {
            lastModifierReleaseAt = now
        }
    }
}

/// Optional hold-left-mouse + right-click quick copy gesture: listens globally for a
/// right mouse-down while the left button is held, then simulates ⌘C so the selection lands in
/// the pasteboard and the assistant picks it up. Requires input monitoring (listening) and
/// accessibility (posting keystrokes) permissions.
@MainActor
final class ClipboardAssistantMouseGestureMonitor {
    private(set) var isActive = false
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var onCopy: (() -> Void)?
    private var commandCCopyTask: Task<Void, Never>?
    private var copyGeneration = 0

    /// Starts listening; returns `false` when the required permissions are missing.
    @discardableResult
    func start(onCopy: @escaping () -> Void) -> Bool {
        stop()
        guard GlobalHotkeyManager.hasInputMonitoringAccess,
              AccessibilityPermission.isTrusted else {
            return false
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(1) << CGEventType.otherMouseDown.rawValue,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<ClipboardAssistantMouseGestureMonitor>
                    .fromOpaque(userInfo).takeUnretainedValue()
                MainActor.assumeIsolated {
                    monitor.handle(type: type, event: event)
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source
        self.onCopy = onCopy
        isActive = true
        return true
    }

    func stop() {
        copyGeneration &+= 1
        commandCCopyTask?.cancel()
        commandCCopyTask = nil
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        eventTap = nil
        runLoopSource = nil
        onCopy = nil
        isActive = false
    }

    private func handle(type: CGEventType, event: CGEvent) {
        guard isActive else { return }
        switch type {
        case .otherMouseDown:
            // Right mouse down (CGEvent button 1) while the left button stays held.
            let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)
            guard buttonNumber == Int64(CGMouseButton.right.rawValue) else { return }
            guard CGEventSource.buttonState(.combinedSessionState, button: .left) else { return }
            postCommandC()
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
        default:
            break
        }
    }

    /// Defers ⌘C until the target app has processed the click without letting a stopped monitor post later.
    private func postCommandC() {
        commandCCopyTask?.cancel()
        let generation = copyGeneration
        commandCCopyTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(50))
            } catch {
                return
            }
            guard let self,
                  !Task.isCancelled,
                  self.isActive,
                  self.copyGeneration == generation else {
                return
            }
            let keyC: CGKeyCode = 8 // kVK_ANSI_C
            guard let down = CGEvent(keyboardEventSource: nil, virtualKey: keyC, keyDown: true),
                  let up = CGEvent(keyboardEventSource: nil, virtualKey: keyC, keyDown: false)
            else { return }
            down.flags = .maskCommand
            up.flags = .maskCommand
            down.post(tap: .cghidEventTap)
            do {
                try await Task.sleep(for: .milliseconds(30))
            } catch {
                up.post(tap: .cghidEventTap)
                return
            }
            up.post(tap: .cghidEventTap)
            guard !Task.isCancelled,
                  self.isActive,
                  self.copyGeneration == generation else {
                return
            }
            self.commandCCopyTask = nil
            self.onCopy?()
        }
    }
}
