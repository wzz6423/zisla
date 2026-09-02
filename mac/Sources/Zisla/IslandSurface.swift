import AppKit
import ZislaCore
import ZislaKit
import SwiftUI

struct IslandSurfaceRenderingPolicy: Equatable {
    let usesExpandedMaterial: Bool
    let showsCrown: Bool
    let nativeGlassIsCollapsed: Bool

    init(isCollapsed: Bool, usesCompactGlassSurface: Bool) {
        usesExpandedMaterial = !isCollapsed || usesCompactGlassSurface
        showsCrown = !isCollapsed && !usesCompactGlassSurface
        nativeGlassIsCollapsed = isCollapsed && !usesCompactGlassSurface
    }
}

struct VoiceRecordingIslandGeometry: Equatable {
    static let transcriptRowHeight: CGFloat = 20
    static let bottomCornerRadius: CGFloat = 14

    let collapsedSize: CGSize
    let surfaceSize: CGSize

    init(collapsedSize: CGSize, surfaceSize: CGSize) {
        self.collapsedSize = collapsedSize
        self.surfaceSize = surfaceSize
    }

    init(collapsedSize: CGSize, availableSize: CGSize) {
        self.collapsedSize = collapsedSize
        surfaceSize = CGSize(
            // The available size is already the collapsed pill's overflow width (notch +
            // wings); recording only adds one transcript row below, never a wider bottom.
            width: max(0, availableSize.width),
            height: min(
                max(0, availableSize.height),
                max(0, collapsedSize.height) + Self.transcriptRowHeight
            )
        )
    }

    /// The top row spans the full overflow width: on notched screens the physical notch
    /// covers the center, so the mic and waveform must land in the left/right wings.
    var topRowFrame: CGRect {
        CGRect(
            x: 0,
            y: 0,
            width: surfaceSize.width,
            height: min(max(0, collapsedSize.height), max(0, surfaceSize.height))
        )
    }

    var transcriptRowFrame: CGRect {
        CGRect(
            x: 0,
            y: topRowFrame.maxY,
            width: surfaceSize.width,
            height: max(0, surfaceSize.height - topRowFrame.maxY)
        )
    }
}

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
    private let usesCompactGlassSurface: Bool
    private let collapsedTopCornerRadius: CGFloat
    private let bottomCornerRadius: CGFloat?
    private let collapsedCenterOffsetX: CGFloat

    init(
        isCollapsed: Bool = false,
        collapsedSize: CGSize = CGSize(width: 240, height: 34),
        expandedSize: CGSize = CGSize(width: 748, height: 324),
        visualStyle: IslandVisualStyle = .frosted,
        notchBackground: IslandNotchBackground = .black,
        usesCompactGlassSurface: Bool = false,
        collapsedTopCornerRadius: CGFloat = 5,
        bottomCornerRadius: CGFloat? = nil,
        collapsedCenterOffsetX: CGFloat = 0,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.isCollapsed = isCollapsed
        self.collapsedSize = collapsedSize
        self.expandedSize = expandedSize
        self.visualStyle = visualStyle
        self.notchBackground = notchBackground
        self.usesCompactGlassSurface = usesCompactGlassSurface
        self.collapsedTopCornerRadius = collapsedTopCornerRadius
        self.bottomCornerRadius = bottomCornerRadius
        self.collapsedCenterOffsetX = collapsedCenterOffsetX
        self.content = content
    }

    private var renderingPolicy: IslandSurfaceRenderingPolicy {
        IslandSurfaceRenderingPolicy(
            isCollapsed: isCollapsed,
            usesCompactGlassSurface: usesCompactGlassSurface
        )
    }

    /// Compact surfaces may keep their pill radius while reusing the standard reveal path.
    private var rimBottomCornerRadius: CGFloat {
        bottomCornerRadius
            ?? (usesCompactGlassSurface
                ? VoiceRecordingIslandGeometry.bottomCornerRadius
                : IslandSurfaceGeometry.expandedBottomCornerRadius)
    }

    private var maskIsCollapsed: Bool {
        isCollapsed && !usesCompactGlassSurface
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
                isCollapsed: maskIsCollapsed,
                collapsedTopCornerRadius: collapsedTopCornerRadius,
                expandedBottomCornerRadius: rimBottomCornerRadius,
                collapsedCenterOffsetX: collapsedCenterOffsetX
            )
            .animation(
                reduceMotion
                    ? nil
                    // Collapse folds straight back into the pill; expand gets a spring with a hint
                    // of bounce, matching the iOS Dynamic Island reveal feel.
                    : maskIsCollapsed
                        ? ZislaMotion.islandRecycle
                        : ZislaMotion.islandReveal,
                value: maskIsCollapsed
            )
        }
    }

    // MARK: - Island surface

    @ViewBuilder
    private var unifiedSurface: some View {
        if renderingPolicy.usesExpandedMaterial {
            switch visualStyle {
            case .frosted:
                frostedSurface
            case .transparent:
                transparentSurface
            }
        } else {
            collapsedSurface
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
                if renderingPolicy.showsCrown {
                    crown
                } else if usesCompactGlassSurface {
                    compactCrown
                }
                IslandSheenSweep(visualStyle: .frosted)
                    .id(visualStyle)
                IslandRimLight(
                    visualStyle: .frosted,
                    bottomCornerRadius: rimBottomCornerRadius
                )
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
                if renderingPolicy.showsCrown {
                    transparentCrown
                } else if usesCompactGlassSurface {
                    compactCrown
                }
                IslandSheenSweep(visualStyle: .transparent)
                    .id(visualStyle)
                IslandRimLight(
                    visualStyle: .transparent,
                    bottomCornerRadius: rimBottomCornerRadius
                )
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

    /// Compact recording crown: the collapsed pill row stays solid black while the single added
    /// transcript row fades the black into the glass below — a one-row miniature of the expanded
    /// crown → glass transition, in either visual style. Scales with the (dynamic) collapsed
    /// height instead of the fixed chrome metrics, which would fill the whole 54pt surface
    /// with solid black.
    private var compactCrown: some View {
        let solidHeight = min(max(0, collapsedSize.height), max(0, expandedSize.height))
        let blendHeight = max(0, expandedSize.height - solidHeight)
        return VStack(spacing: 0) {
            Rectangle()
                .fill(Color.black.opacity(compactCrownOpacity))
                .frame(height: solidHeight)
            LinearGradient(stops: compactCrownStops, startPoint: .top, endPoint: .bottom)
                .frame(height: blendHeight)
            Spacer(minLength: 0)
        }
        .allowsHitTesting(false)
    }

    /// Liquid Glass keeps the recording crown fully opaque, matching the expanded transparent
    /// crown; frosted retains its faint translucency.
    private var compactCrownOpacity: CGFloat {
        visualStyle == .transparent ? 1 : crownOpacity
    }

    private var compactCrownStops: [Gradient.Stop] {
        if visualStyle == .transparent {
            // Liquid Glass uses the same gradient parameters as the expanded `transparentCrown`.
            [
                .init(color: .black, location: 0),
                .init(color: .black.opacity(0.78), location: 0.35),
                .init(color: .black.opacity(0.34), location: 0.72),
                .init(color: .black.opacity(0.0), location: 1),
            ]
        } else {
            [
                .init(color: .black.opacity(crownOpacity), location: 0),
                .init(color: .black.opacity(crownOpacity * 0.62), location: 0.4),
                .init(color: .black.opacity(crownOpacity * 0.28), location: 0.72),
                .init(color: .black.opacity(0.0), location: 1),
            ]
        }
    }

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

    /// The clear layer keeps the lower edge refractive; the regular overlay (masked to fade
    /// out toward the bottom) gives the body its smoked contrast — on the full expanded
    /// surface and the compact recording surface alike.
    private var transparentLiquidGlassShell: some View {
        // The recording surface keeps the collapsed pill's rounded bottom corners.
        let shellCornerRadius = usesCompactGlassSurface
            ? VoiceRecordingIslandGeometry.bottomCornerRadius
            : IslandSurfaceGeometry.expandedBottomCornerRadius

        return ZStack {
            NativeLiquidGlassShell(
                isCollapsed: renderingPolicy.nativeGlassIsCollapsed,
                material: .clear,
                cornerRadius: shellCornerRadius
            )

            if usesCompactGlassSurface {
                // The recording surface uses only `.clear` with a subtle black gradient to avoid `.regular`'s gray cast.
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.15), location: 0),
                        .init(color: .black.opacity(0.08), location: 0.6),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else {
                // The expanded surface uses `.regular` material with a mask.
                NativeLiquidGlassShell(
                    isCollapsed: renderingPolicy.nativeGlassIsCollapsed,
                    material: .regular,
                    cornerRadius: shellCornerRadius
                )
                .mask(alignment: .bottom) {
                    LinearGradient(
                        stops: expandedLiquidGlassMaskStops,
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The expanded Liquid Glass mask fades at the bottom to reveal edge refraction.
    private var expandedLiquidGlassMaskStops: [Gradient.Stop] {
        [
            .init(color: .black, location: 0),
            .init(color: .black, location: 0.72),
            .init(color: .black.opacity(0.92), location: 0.78),
            .init(color: .black.opacity(0.70), location: 0.84),
            .init(color: .black.opacity(0.38), location: 0.90),
            .init(color: .black.opacity(0.12), location: 0.96),
            .init(color: .clear, location: 1),
        ]
    }

    /// The compact recording mask preserves contrast at the top, then fades sharply to reveal the `.clear` layer's refraction.
    private var compactLiquidGlassMaskStops: [Gradient.Stop] {
        [
            .init(color: .black, location: 0),
            .init(color: .black.opacity(0.85), location: 0.5),
            .init(color: .black.opacity(0.35), location: 0.75),
            .init(color: .black.opacity(0.08), location: 0.92),
            .init(color: .clear, location: 1),
        ]
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
    let collapsedTopCornerRadius: CGFloat
    let expandedBottomCornerRadius: CGFloat
    let collapsedCenterOffsetX: CGFloat
    private var revealProgress: CGFloat

    init(
        collapsedSize: CGSize,
        expandedSize: CGSize,
        isCollapsed: Bool,
        collapsedTopCornerRadius: CGFloat = 5,
        expandedBottomCornerRadius: CGFloat = IslandSurfaceGeometry.expandedBottomCornerRadius,
        collapsedCenterOffsetX: CGFloat = 0
    ) {
        self.collapsedSize = collapsedSize
        self.expandedSize = expandedSize
        self.collapsedTopCornerRadius = collapsedTopCornerRadius
        self.expandedBottomCornerRadius = expandedBottomCornerRadius
        self.collapsedCenterOffsetX = collapsedCenterOffsetX
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
            x: rect.midX - visibleFrame.width / 2
                + IslandSurfaceTransform.collapsedCenterOffset(
                    collapsedCenterOffsetX,
                    revealProgress: revealProgress
                ),
            y: rect.minY,
            width: visibleFrame.width,
            height: visibleFrame.height
        )
        let progress = min(1, max(0, revealProgress))

        return IslandSilhouette(
            topCornerRadius: collapsedTopCornerRadius * (1 - progress),
            bottomCornerRadius: 14
                + (expandedBottomCornerRadius - 14) * progress
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
    let cornerRadius: CGFloat

    init(
        isCollapsed: Bool,
        material: NativeLiquidGlassMaterial = .regular,
        cornerRadius: CGFloat = IslandSurfaceGeometry.expandedBottomCornerRadius
    ) {
        self.isCollapsed = isCollapsed
        self.material = material
        self.cornerRadius = cornerRadius
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
        view.cornerRadius = cornerRadius
        view.installTransparentContentHostIfNeeded()
    }
}

@available(macOS 26.0, *)
private final class LiquidGlassShellView: NSGlassEffectView {
    private var isCollapsed = true
    private var refreshGeneration = 0
    private var lastLaidOutSize: CGSize = .zero

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

    override func layout() {
        super.layout()
        guard window != nil, !isCollapsed, bounds.size != lastLaidOutSize else { return }
        lastLaidOutSize = bounds.size
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
            // A module switch changes the shell's bounds without moving it to a new window. Flush
            // both the view and its window backing store so NSGlassEffectView rebuilds the
            // refraction pass instead of leaving the inactive-size snapshot rendered as a frosted
            // fallback.
            self.needsDisplay = true
            self.displayIfNeeded()
            self.window?.displayIfNeeded()
        }
    }
}

// `IconButton` has been moved to DesignSystem.swift (unified implementation with size and activation-state tokens).
