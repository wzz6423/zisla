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
    var edge: IslandEdge = .top

    init(collapsedSize: CGSize, surfaceSize: CGSize) {
        self.collapsedSize = collapsedSize
        self.surfaceSize = surfaceSize
    }

    init(collapsedSize: CGSize, availableSize: CGSize, edge: IslandEdge = .top) {
        self.collapsedSize = collapsedSize
        self.edge = edge
        surfaceSize = CGSize(
            // The available size is already the collapsed pill's overflow width (notch +
            // wings); recording only adds one transcript row below, never a wider bottom.
            width: max(0, availableSize.width),
            height: edge.isVertical ? max(0, availableSize.height) : min(
                max(0, availableSize.height),
                max(0, collapsedSize.height) + Self.transcriptRowHeight
            )
        )
    }

    /// The top row spans the full overflow width: on notched screens the physical notch
    /// covers the center, so the mic and waveform must land in the left/right wings.
    var topRowFrame: CGRect {
        if edge.isVertical {
            let width = min(max(0, collapsedSize.width), surfaceSize.width)
            return CGRect(
                x: edge == .right ? surfaceSize.width - width : 0,
                y: 0, width: width, height: surfaceSize.height
            )
        }
        let height = min(max(0, collapsedSize.height), max(0, surfaceSize.height))
        return CGRect(
            x: 0,
            y: edge == .bottom ? surfaceSize.height - height : 0,
            width: surfaceSize.width,
            height: height
        )
    }

    var transcriptRowFrame: CGRect {
        if edge.isVertical {
            return CGRect(
                x: edge == .left ? topRowFrame.maxX : 0,
                y: 0, width: max(0, surfaceSize.width - topRowFrame.width), height: surfaceSize.height
            )
        }
        return CGRect(
            x: 0,
            y: edge == .bottom ? 0 : topRowFrame.maxY,
            width: surfaceSize.width,
            height: max(0, surfaceSize.height - topRowFrame.height)
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
    @Environment(\.layoutDirection) private var layoutDirection
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
    private let resultSweep: AIResultSweepController?
    private let layoutStyle: IslandLayoutStyle
    private let collapsedFrame: CGRect?
    private let edge: IslandEdge
    private let contentTopInset: CGFloat

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
        resultSweep: AIResultSweepController? = nil,
        layoutStyle: IslandLayoutStyle = .notch,
        collapsedFrame: CGRect? = nil,
        edge: IslandEdge = .top,
        contentTopInset: CGFloat = IslandDashboardLayout.contentTopInset,
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
        self.resultSweep = resultSweep
        self.layoutStyle = layoutStyle
        self.collapsedFrame = collapsedFrame
        self.edge = edge
        self.contentTopInset = contentTopInset
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
                .environment(\.layoutDirection, layoutDirection)
            if maskIsCollapsed, let resultSweep {
                if layoutStyle == .pill {
                    let frame = collapsedFrame ?? CGRect(
                        x: (expandedSize.width - collapsedSize.width) / 2,
                        y: 0, width: collapsedSize.width, height: collapsedSize.height
                    )
                    AIResultSweepOverlay(controller: resultSweep, edge: edge)
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                } else {
                    AIResultSweepOverlay(controller: resultSweep, edge: edge)
                }
            }
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
                collapsedCenterOffsetX: collapsedCenterOffsetX,
                layoutStyle: layoutStyle,
                collapsedFrame: collapsedFrame
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
        .environment(\.layoutDirection, layoutStyle == .pill ? .leftToRight : layoutDirection)
    }

    // MARK: - Island surface

    @ViewBuilder
    private var unifiedSurface: some View {
        if renderingPolicy.usesExpandedMaterial {
            if usesCompactGlassSurface, layoutStyle == .pill, edge.isVertical {
                compactSideSurface
            } else {
                switch visualStyle {
                case .frosted:
                    frostedSurface
                case .transparent:
                    transparentSurface
                }
            }
        } else {
            collapsedSurface
        }
    }

    private var compactSideSurface: some View {
        let crownWidth = collapsedSize.width
        let blendWidth = min(expandedSize.width, crownWidth + 60)
        return ZStack {
            if reduceTransparency {
                Color(white: 0.10)
            } else if visualStyle == .transparent {
                transparentLiquidGlassShell
            } else {
                glassBody
            }
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: min(1, crownWidth / max(1, expandedSize.width))),
                    .init(color: .clear, location: min(1, blendWidth / max(1, expandedSize.width)))
                ],
                startPoint: edge == .left ? .leading : .trailing,
                endPoint: edge == .left ? .trailing : .leading
            )
        }
    }

    private var frostedSurface: some View {
        ZStack(alignment: .top) {
            Color.black
            if !reduceTransparency {
                // Bottom transmissive frosted glass (smoked, refracts the desktop, no white bloom).
                glassBody
                // Solid-black crown on top + smoked transition. Deliberately no ambient light
                // overlays: their additive plusLighter white reads as blurry line-shaped patches
                // on the smoked glass rather than ambience, so the surface stays a smooth gradient.
                if renderingPolicy.showsCrown {
                    crown
                } else if usesCompactGlassSurface {
                    compactCrown
                }
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
                // Same reasoning as `frostedSurface`: no additive white overlays on the glass.
                if renderingPolicy.showsCrown {
                    transparentCrown
                } else if usesCompactGlassSurface {
                    compactCrown
                }
            }
        }
    }

    @ViewBuilder
    private var collapsedSurface: some View {
        if layoutStyle == .pill {
            GeometryReader { proxy in
                let frame = collapsedFrame ?? CGRect(
                    x: (proxy.size.width - collapsedSize.width) / 2,
                    y: 0, width: collapsedSize.width, height: collapsedSize.height
                )
                IslandCollapsedMaterial(style: notchBackground)
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
            }
        } else if reduceTransparency {
            Color.black
        } else {
            Group {
                switch notchBackground {
                case .black:
                    Color.black
                case .frosted:
                    VisualEffectBackground(alphaValue: 0.92, material: .popover)
                case .liquidGlass:
                    IslandCollapsedMaterial(style: .liquidGlass)
                }
            }
            .frame(width: collapsedSize.width, height: collapsedSize.height)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    /// Solid-black crown on top + smooth downward transition.
    /// The solid-black section covers NowPlayingHeader + toolbar (white text); below it an eased gradient fades black into the smoked frosted glass.
    /// The blend follows `IslandCrownFade`'s smoothstep curve so it meets the solid crown above and the flat glass below with zero slope, rather than ending a straight ramp on a slope break the eye renders as a white edge.
    /// Crown adapts to the expanded surface height: full size above the floor, compressed below.
    private var crown: some View {
        let metrics = IslandCrownGeometry.crownMetrics(
            forSurfaceHeight: expandedSize.height,
            blendHeight: crownBlend,
            contentTopInset: contentTopInset
        )
        return IslandCrownSurface(
            solidHeight: metrics.solidHeight,
            blendHeight: metrics.blendHeight,
            peakOpacity: crownOpacity
        )
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
        return IslandCrownSurface(
            solidHeight: solidHeight,
            blendHeight: blendHeight,
            peakOpacity: compactCrownOpacity
        )
        .scaleEffect(x: 1, y: edge == .bottom ? -1 : 1)
        .allowsHitTesting(false)
    }

    /// Liquid Glass keeps the recording crown fully opaque, matching the expanded transparent
    /// crown; frosted retains its faint translucency.
    private var compactCrownOpacity: CGFloat {
        visualStyle == .transparent ? 1 : crownOpacity
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
            blendHeight: transparentCrownBlend,
            contentTopInset: contentTopInset
        )
        return IslandCrownSurface(
            solidHeight: metrics.solidHeight,
            blendHeight: metrics.blendHeight,
            peakOpacity: 1
        )
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

/// One drawing primitive prevents independently antialiased edges from exposing the glass
/// when the crown and its parent frame are animating together.
struct IslandCrownSurface: View, Animatable {
    var solidHeight: CGFloat
    var blendHeight: CGFloat
    let peakOpacity: CGFloat

    // Resolve the gradient against the interpolated lengths, not the destination layout.
    nonisolated var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(solidHeight, blendHeight) }
        set {
            solidHeight = newValue.first
            blendHeight = newValue.second
        }
    }

    var gradientStops: [Gradient.Stop] {
        let height = solidHeight + blendHeight
        let denominator = height == 0 ? 1 : height
        return IslandCrownFade.curve.map {
            .init(
                color: .black.opacity(peakOpacity * $0.alpha),
                location: (solidHeight + blendHeight * $0.location) / denominator
            )
        }
    }

    var body: some View {
        LinearGradient(stops: gradientStops, startPoint: .top, endPoint: .bottom)
            .frame(height: solidHeight + blendHeight)
    }
}

struct IslandRevealMask: Shape {
    let collapsedSize: CGSize
    let expandedSize: CGSize
    let collapsedTopCornerRadius: CGFloat
    let expandedBottomCornerRadius: CGFloat
    let collapsedCenterOffsetX: CGFloat
    let layoutStyle: IslandLayoutStyle
    let collapsedFrame: CGRect?
    private var revealProgress: CGFloat

    init(
        collapsedSize: CGSize,
        expandedSize: CGSize,
        isCollapsed: Bool,
        collapsedTopCornerRadius: CGFloat = 5,
        expandedBottomCornerRadius: CGFloat = IslandSurfaceGeometry.expandedBottomCornerRadius,
        collapsedCenterOffsetX: CGFloat = 0,
        layoutStyle: IslandLayoutStyle = .notch,
        collapsedFrame: CGRect? = nil
    ) {
        self.collapsedSize = collapsedSize
        self.expandedSize = expandedSize
        self.collapsedTopCornerRadius = collapsedTopCornerRadius
        self.expandedBottomCornerRadius = expandedBottomCornerRadius
        self.collapsedCenterOffsetX = collapsedCenterOffsetX
        self.layoutStyle = layoutStyle
        self.collapsedFrame = collapsedFrame
        revealProgress = isCollapsed ? 0 : 1
    }

    var animatableData: CGFloat {
        get { revealProgress }
        set { revealProgress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        if layoutStyle == .pill {
            let start = collapsedFrame ?? CGRect(
                x: rect.midX - collapsedSize.width / 2,
                y: rect.minY, width: collapsedSize.width, height: collapsedSize.height
            )
            let progress = min(1, max(0, revealProgress))
            let frame = CGRect(
                x: start.minX + (rect.minX - start.minX) * progress,
                y: start.minY + (rect.minY - start.minY) * progress,
                width: start.width + (rect.width - start.width) * progress,
                height: start.height + (rect.height - start.height) * progress
            )
            let radius = min(start.width, start.height) / 2
            return RoundedRectangle(cornerRadius: radius + (expandedBottomCornerRadius - radius) * progress)
                .path(in: frame)
        }
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
enum NativeLiquidGlassMaterial {
    case regular
    case clear
}

struct NativeLiquidGlassShell: NSViewRepresentable {
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
