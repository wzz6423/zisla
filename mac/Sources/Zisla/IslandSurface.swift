import AppKit
import ZislaCore
import ZislaKit
import SwiftUI

/// The island's visual surface: a solid-black top that smoothly fades through a
/// smoked transition into a transmissive frosted-glass bottom. The frosted glass
/// is rendered in dark appearance so it reads as a smoked, non-white translucent
/// material that refracts the desktop behind — an iOS 27 Siri–like feel.
struct IslandSurface<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder private let content: () -> Content
    private let isCollapsed: Bool
    private let collapsedSize: CGSize
    private let expandedSize: CGSize
    private let visualStyle: IslandVisualStyle
    private let notchBackground: IslandNotchBackground

    init(
        isCollapsed: Bool = false,
        collapsedSize: CGSize = CGSize(width: 240, height: 34),
        expandedSize: CGSize = CGSize(width: 748, height: 324),
        visualStyle: IslandVisualStyle = .frosted,
        notchBackground: IslandNotchBackground = .black,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.isCollapsed = isCollapsed
        self.collapsedSize = collapsedSize
        self.expandedSize = expandedSize
        self.visualStyle = visualStyle
        self.notchBackground = notchBackground
        self.content = content
    }

    var body: some View {
        ZStack(alignment: .top) {
            unifiedSurface
                .allowsHitTesting(false)
            content()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Keeps the mask's layout size fixed, redrawing only the outline within its canvas — if the
        // mask view's frame changes during animation, SwiftUI/AppKit layout interpolation briefly shifts the outline leftward.
        .mask {
            IslandRevealMask(
                collapsedSize: collapsedSize,
                expandedSize: expandedSize,
                isCollapsed: isCollapsed
            )
            .animation(
                reduceMotion
                    ? nil
                    // Collapse stays quick and crisp; expand gets a spring with a hint of
                    // bounce, matching the iOS Dynamic Island reveal feel.
                    : isCollapsed
                        ? .smooth(duration: 0.18)
                        : .snappy(duration: 0.28, extraBounce: 0.05),
                value: isCollapsed
            )
        }
    }

    // MARK: - Island surface

    @ViewBuilder
    private var unifiedSurface: some View {
        if isCollapsed {
            collapsedSurface
        } else {
            switch visualStyle {
            case .frosted:
                frostedSurface
            case .transparent:
                transparentSurface
            }
        }
    }

    private var frostedSurface: some View {
        ZStack(alignment: .top) {
            Color.black
            if !reduceTransparency {
                // Bottom transmissive frosted glass (smoked, refracts the desktop, no white bloom).
                glassBody
                // Ambient light field sits between the glass and the crown so the solid
                // crown keeps covering it where text legibility matters.
                IslandLightField(visualStyle: .frosted)
                // Solid-black crown on top + smoked transition.
                crown
                IslandSheenSweep(visualStyle: .frosted)
                    .id(visualStyle)
                IslandRimLight(visualStyle: .frosted)
            } else {
                // Accessibility: opaque black → smoked gradient.
                surfaceGradient
            }
        }
    }

    @ViewBuilder
    private var transparentSurface: some View {
        if reduceTransparency {
            ZStack(alignment: .top) {
                Color.black
                surfaceGradient
            }
        } else {
            ZStack(alignment: .top) {
                transparentLiquidGlassShell
                IslandLightField(visualStyle: .transparent)
                transparentCrown
                IslandSheenSweep(visualStyle: .transparent)
                    .id(visualStyle)
                IslandRimLight(visualStyle: .transparent)
            }
        }
    }

    @ViewBuilder
    private var collapsedSurface: some View {
        if reduceTransparency {
            Color.black
        } else {
            Group {
                switch notchBackground {
                case .black:
                    Color.black
                case .frosted:
                    VisualEffectBackground(alphaValue: 0.92, material: .popover)
                }
            }
            .frame(width: collapsedSize.width, height: collapsedSize.height)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    /// Solid-black crown on top + smooth downward transition.
    /// The solid-black section covers NowPlayingHeader + toolbar (white text); below it an eased gradient fades black into the smoked frosted glass.
    /// Gradient stops decrease evenly to avoid a density jump ("sunken" feel) in the middle.
    /// Crown adapts to the expanded surface height: full size above the floor, compressed below.
    private var crown: some View {
        let metrics = IslandCrownGeometry.crownMetrics(
            forSurfaceHeight: expandedSize.height,
            blendHeight: crownBlend
        )
        return VStack(spacing: 0) {
            Rectangle()
                .fill(Color.black.opacity(crownOpacity))
                .frame(height: metrics.solidHeight)
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(crownOpacity), location: 0),
                    .init(color: .black.opacity(crownOpacity * 0.70), location: 0.3),
                    .init(color: .black.opacity(crownOpacity * 0.35), location: 0.65),
                    .init(color: .black.opacity(0.0), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: metrics.blendHeight)
            Spacer(minLength: 0)
        }
        .allowsHitTesting(false)
    }

    /// Visually stays black while allowing the transparent panel to retain a very faint translucency.
    private let crownOpacity: CGFloat = 0.98
    /// Crown-to-frosted-glass blend height. Extended to 60pt for a smoother black → smoked merge.
    private let crownBlend: CGFloat = 60

    /// Island surface base: transmissive smoked frosted glass.
    ///
    /// `.glassEffect(.regular)` is dropped for large-area backgrounds — it collapses to
    /// solid black in dark colorScheme (Liquid Glass is designed for floating controls, not
    /// full-surface backgrounds). Instead, `NSVisualEffectView` with `.hudWindow` +
    /// `.behindWindow` + dark appearance is used: truly transmissive through the desktop
    /// behind the window, rendering as smoked semi-transparent frosted glass in dark mode —
    /// no white bloom, no pure black, stable and predictable. The solid-black crown handles
    /// the transition at the top.
    private var glassBody: some View {
        VisualEffectBackground()
    }

    // MARK: - Transparent glass (macOS 27 / Liquid Glass approximation)

    /// The clear layer keeps the lower edge refractive; the regular layer above it restores
    /// enough frosted contrast for module content to remain readable.
    private var transparentLiquidGlassShell: some View {
        ZStack {
            NativeLiquidGlassShell(isCollapsed: isCollapsed, material: .clear)
            NativeLiquidGlassShell(isCollapsed: isCollapsed, material: .regular)
                .mask(alignment: .bottom) {
                    // A single gradient avoids an AppKit compositor seam at the boundary
                    // between separately laid-out opaque and fading mask views.
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: 0.72),
                            .init(color: .black.opacity(0.92), location: 0.78),
                            .init(color: .black.opacity(0.70), location: 0.84),
                            .init(color: .black.opacity(0.38), location: 0.90),
                            .init(color: .black.opacity(0.12), location: 0.96),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The top remains completely opaque: Liquid Glass starts below the crown, where the module content lives.
    private var transparentCrown: some View {
        let metrics = IslandCrownGeometry.crownMetrics(
            forSurfaceHeight: expandedSize.height,
            blendHeight: transparentCrownBlend
        )
        return VStack(spacing: 0) {
            Rectangle()
                .fill(Color.black)
                .frame(height: metrics.solidHeight)
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black.opacity(0.78), location: 0.35),
                    .init(color: .black.opacity(0.34), location: 0.72),
                    .init(color: .black.opacity(0.0), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: metrics.blendHeight)
            Spacer(minLength: 0)
        }
        .allowsHitTesting(false)
    }

    private let transparentCrownBlend = IslandCrownGeometry.crownBlendHeight

    // MARK: - Surface gradient (accessibility: opaque black → smoked)

    /// Accessibility (Reduce Transparency) mode: opaque black → smoked vertical gradient,
    /// removes frosted glass and transparency while preserving contrast for light-colored text.
    private var surfaceGradient: some View {
        LinearGradient(
            stops: [
                .init(color: .black, location: 0.00),
                .init(color: .black, location: 0.40),
                .init(color: Color(white: 0.10), location: 0.62),
                .init(color: Color(white: 0.16), location: 1.00),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

private struct IslandRevealMask: Shape {
    let collapsedSize: CGSize
    let expandedSize: CGSize
    private var revealProgress: CGFloat

    init(collapsedSize: CGSize, expandedSize: CGSize, isCollapsed: Bool) {
        self.collapsedSize = collapsedSize
        self.expandedSize = expandedSize
        revealProgress = isCollapsed ? 0 : 1
    }

    var animatableData: CGFloat {
        get { revealProgress }
        set { revealProgress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let transform = IslandSurfaceTransform(
            collapsedSize: collapsedSize,
            expandedSize: expandedSize,
            revealProgress: revealProgress
        )
        let visibleFrame = transform.visibleFrame(in: rect.size)
        let frame = CGRect(
            x: rect.midX - visibleFrame.width / 2,
            y: rect.minY,
            width: visibleFrame.width,
            height: visibleFrame.height
        )
        let progress = min(1, max(0, revealProgress))

        return IslandSilhouette(
            topCornerRadius: 5 * (1 - progress),
            bottomCornerRadius: 14 + (IslandSurfaceGeometry.expandedBottomCornerRadius - 14) * progress
        )
        .path(in: frame)
    }
}

/// Island outline: expanded state sits flush with the top of the screen; bottom uses a continuous large corner radius.
struct IslandSilhouette: InsettableShape {
    var topCornerRadius: CGFloat = 0
    var bottomCornerRadius: CGFloat = 34
    var insetAmount: CGFloat = 0

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let topRadius = max(0, min(topCornerRadius - insetAmount, r.height / 2, r.width / 2))
        let bottomRadius = max(0, min(bottomCornerRadius - insetAmount, r.height / 2, r.width / 2))
        return UnevenRoundedRectangle(
            cornerRadii: .init(
                topLeading: topRadius,
                bottomLeading: bottomRadius,
                bottomTrailing: bottomRadius,
                topTrailing: topRadius
            ),
            style: .continuous
        )
        .path(in: r)
    }

    func inset(by amount: CGFloat) -> some InsettableShape {
        var shape = self
        shape.insetAmount += amount
        return shape
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    /// 0…1; lower values make the material more transmissive; nil uses the system default (1.0).
    var alphaValue: CGFloat? = nil
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        // Resolve each semantic material against the app's fixed dark appearance.
        view.appearance = NSAppearance(named: .darkAqua)
        if let alphaValue {
            view.alphaValue = alphaValue
        }
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        // Sync alpha on style switch so a reused NSView doesn't keep the old transmissivity.
        nsView.alphaValue = alphaValue ?? 1
    }
}

/// Module-level liquid glass pane (composer input, cards): the same native renderer as the
/// island's transparent shell, so panes refract the desktop instead of overlaying flat darkness.
/// macOS 26+ only — `IslandGlassSurface` falls back to the frosted material on older systems.
struct LiquidGlassPaneBackground: NSViewRepresentable {
    var cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSView {
        guard #available(macOS 26.0, *) else { return NSView() }
        let view = NSGlassEffectView()
        // Same trick as the island shell: a transparent content host guarantees the full
        // compositing path so the pane doesn't render as just an edge.
        let host = NSView(frame: view.bounds)
        host.autoresizingMask = [.width, .height]
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.clear.cgColor
        view.contentView = host
        configure(view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard #available(macOS 26.0, *), let view = nsView as? NSGlassEffectView else { return }
        configure(view)
    }

    @available(macOS 26.0, *)
    private func configure(_ view: NSGlassEffectView) {
        // `.regular` plus a dark tint reads as frosted; the clear material keeps the input
        // pane visibly distinct from the frosted-mode branch while retaining native refraction.
        view.style = .clear
        view.tintColor = nil
        view.cornerRadius = cornerRadius
    }
}

/// Uses the system Liquid Glass renderer only as an optical shell. Keeping content out of the
/// native view avoids its large-surface white wash while retaining the real refraction effect.
private enum NativeLiquidGlassMaterial {
    case regular
    case clear
}

private struct NativeLiquidGlassShell: NSViewRepresentable {
    let isCollapsed: Bool
    let material: NativeLiquidGlassMaterial

    init(isCollapsed: Bool, material: NativeLiquidGlassMaterial = .regular) {
        self.isCollapsed = isCollapsed
        self.material = material
    }

    func makeNSView(context: Context) -> NSView {
        if #available(macOS 26.0, *) {
            let view = LiquidGlassShellView()
            configure(view)
            view.setCollapsed(isCollapsed)
            return view
        }
        return NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if #available(macOS 26.0, *), let glass = nsView as? LiquidGlassShellView {
            configure(glass)
            glass.setCollapsed(isCollapsed)
        }
    }

    @available(macOS 26.0, *)
    private func configure(_ view: LiquidGlassShellView) {
        switch material {
        case .regular:
            view.style = .regular
            view.tintColor = NSColor.black.withAlphaComponent(0.23)
        case .clear:
            view.style = .clear
            view.tintColor = nil
        }
        view.alphaValue = 1
        view.cornerRadius = IslandSurfaceGeometry.expandedBottomCornerRadius
        view.installTransparentContentHostIfNeeded()
    }
}

@available(macOS 26.0, *)
private final class LiquidGlassShellView: NSGlassEffectView {
    private var isCollapsed = true
    private var refreshGeneration = 0

    func setCollapsed(_ isCollapsed: Bool) {
        let didExpand = self.isCollapsed && !isCollapsed
        self.isCollapsed = isCollapsed
        guard didExpand else { return }

        refreshGeneration &+= 1
        scheduleRevealRefreshes()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, !isCollapsed else { return }
        refreshGeneration &+= 1
        scheduleRevealRefreshes()
    }

    /// NSGlassEffectView guarantees its full compositing path for `contentView`; an empty shell
    /// may otherwise render only an edge until an interaction causes a later compositor pass.
    func installTransparentContentHostIfNeeded() {
        guard contentView == nil else { return }

        let host = NSView(frame: bounds)
        host.autoresizingMask = [.width, .height]
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.clear.cgColor
        contentView = host
    }

    private func scheduleRevealRefreshes() {
        let generation = refreshGeneration
        refreshAfterReveal(generation: generation, delay: 0)
        refreshAfterReveal(generation: generation, delay: 0.24)
    }

    private func refreshAfterReveal(generation: Int, delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.refreshGeneration == generation, !self.isCollapsed,
                  self.window != nil
            else { return }
            self.needsLayout = true
            self.layoutSubtreeIfNeeded()
            self.needsDisplay = true
            self.displayIfNeeded()
        }
    }
}

// `IconButton` has been moved to DesignSystem.swift (unified implementation with size and activation-state tokens).
