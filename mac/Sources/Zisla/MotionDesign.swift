import SwiftUI
import ZislaCore

/// Zisla's motion system: spring tokens, button press feedback, directional module
/// transitions, and the island's ambient light effects.
///
/// Design principles (Apple HIG Motion / Dynamic Island conventions):
/// - Springs over ease curves: interruptible and continuous, matching macOS system feel.
/// - Light effects are additive (`plusLighter`) at very low opacity — they must read as
///   ambience on the smoked glass, never as content.
/// - Every animated layer honors Reduce Motion and unmounts entirely when the island is
///   collapsed, so the resting energy cost is zero.

// MARK: - Motion tokens

enum ZislaMotion {
    /// Directional module page switch.
    static let moduleSwitch: Animation = .smooth(duration: 0.32)
    static let moduleDepthScale: CGFloat = 0.985
    /// Island surface size change between module layouts; a hint of bounce gives the
    /// resize a breathing quality without overshooting text layout noticeably.
    static let surfaceResize: Animation = .snappy(duration: 0.34, extraBounce: 0.02)
    /// Delay before the NSPanel shrinks down to the final size — must outlast `surfaceResize`
    /// so SwiftUI's shrinking content is never clipped by the window edge mid-animation.
    static let surfaceResizeSettleDelay: Duration = .milliseconds(450)
    /// Selection indicator sliding between buttons (matchedGeometryEffect).
    static let selection: Animation = .snappy(duration: 0.26, extraBounce: 0.08)
    /// Hover feedback on buttons.
    static let hover: Animation = .snappy(duration: 0.18)
    /// Press feedback on buttons.
    static let press: Animation = .snappy(duration: 0.14)
    /// Content swap inside the settings window.
    static let settingsPageSwitch: Animation = .smooth(duration: 0.28)
}

enum ZislaMotionPalette {
    /// A warm key light makes an activated control feel revealed rather than merely recolored.
    static let illumination = Color(red: 1.00, green: 0.82, blue: 0.16)
    static let refraction = Color(red: 0.48, green: 0.88, blue: 1.00)
}

// MARK: - Pressable button style

/// Spring scale feedback for hover and press. Replaces `.plain` where motion is wanted;
/// visuals are otherwise identical to the plain style (label rendered as-is).
struct PressableStyle: ButtonStyle {
    var hoverScale: CGFloat = 1.06
    var pressedScale: CGFloat = 0.90

    func makeBody(configuration: Configuration) -> some View {
        // ButtonStyle itself is not a View, so hover state lives in a nested view.
        PressableLabel(
            configuration: configuration,
            hoverScale: hoverScale,
            pressedScale: pressedScale
        )
    }

    private struct PressableLabel: View {
        let configuration: Configuration
        let hoverScale: CGFloat
        let pressedScale: CGFloat
        @State private var isHovering = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .scaleEffect(scale)
                .animation(
                    configuration.isPressed ? ZislaMotion.press : ZislaMotion.hover,
                    value: configuration.isPressed
                )
                .animation(ZislaMotion.hover, value: isHovering)
                .onHover { isHovering = $0 }
        }

        private var scale: CGFloat {
            guard !reduceMotion else { return 1 }
            if configuration.isPressed { return pressedScale }
            return isHovering ? hoverScale : 1
        }
    }
}

// MARK: - Directional module transition

private struct ModulePushModifier: ViewModifier {
    var offsetX: CGFloat
    var blurRadius: CGFloat
    var scale: CGFloat
    var opacity: Double

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .offset(x: offsetX)
            .opacity(opacity)
            .blur(radius: blurRadius, opaque: false)
    }
}

extension AnyTransition {
    /// Directional push between module pages: the incoming page slides in from the
    /// navigation direction with a slight blur, the outgoing page continues onward.
    /// `direction` is +1 when moving right in the module order, -1 when moving left.
    static func modulePush(direction: CGFloat) -> AnyTransition {
        let d: CGFloat = direction >= 0 ? 1 : -1
        return .asymmetric(
            insertion: .modifier(
                active: ModulePushModifier(
                    offsetX: 26 * d,
                    blurRadius: 5,
                    scale: ZislaMotion.moduleDepthScale,
                    opacity: 0
                ),
                identity: ModulePushModifier(offsetX: 0, blurRadius: 0, scale: 1, opacity: 1)
            ),
            removal: .modifier(
                active: ModulePushModifier(
                    offsetX: -26 * d,
                    blurRadius: 5,
                    scale: ZislaMotion.moduleDepthScale,
                    opacity: 0
                ),
                identity: ModulePushModifier(offsetX: 0, blurRadius: 0, scale: 1, opacity: 1)
            )
        )
    }
}

// MARK: - Deferred mounting

/// Defers expensive content construction until SwiftUI has completed the current update pass.
struct DeferredMount<Content: View>: View {
    @State private var isMounted = false
    private let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    @ViewBuilder
    var body: some View {
        Group {
            if isMounted {
                content()
            } else {
                Color.clear
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .task {
            guard !isMounted else { return }
            await Task.yield()
            mountIfNeeded()
        }
    }

    @MainActor
    private func mountIfNeeded() {
        guard !Task.isCancelled, !isMounted else { return }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isMounted = true
        }
    }
}

// MARK: - Ambient light field

/// Slow-drifting diffuse light behind the island surface, drawn by one asynchronous Canvas
/// at a deliberately capped rate and mounted only while the island is expanded.
struct IslandLightField: View {
    let visualStyle: IslandVisualStyle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Orb {
        var color: Color
        /// Radius relative to the surface's shorter side.
        var radiusRatio: CGFloat
        /// Drift amplitude relative to surface size.
        var amplitude: CGSize
        /// Angular velocity (rad/s) — full drift cycles take 40–70 s.
        var speed: Double
        var phase: Double
        /// Rest position in unit coordinates.
        var center: CGPoint
        var maxOpacity: Double
    }

    /// Cool spectrum (ice blue / violet / aqua) tuned for the smoked dark glass.
    private static let frostedOrbs: [Orb] = [
        .init(
            color: Color(red: 0.55, green: 0.75, blue: 1.00),
            radiusRatio: 0.95,
            amplitude: CGSize(width: 0.20, height: 0.10),
            speed: 0.11, phase: 0.0,
            center: CGPoint(x: 0.22, y: 0.80),
            maxOpacity: 0.075
        ),
        .init(
            color: Color(red: 0.66, green: 0.55, blue: 1.00),
            radiusRatio: 0.78,
            amplitude: CGSize(width: 0.17, height: 0.12),
            speed: 0.16, phase: 2.1,
            center: CGPoint(x: 0.78, y: 0.66),
            maxOpacity: 0.060
        ),
        .init(
            color: Color(red: 0.45, green: 0.95, blue: 0.90),
            radiusRatio: 0.60,
            amplitude: CGSize(width: 0.24, height: 0.08),
            speed: 0.09, phase: 4.2,
            center: CGPoint(x: 0.52, y: 0.96),
            maxOpacity: 0.050
        ),
    ]

    /// Liquid Glass is clearer, so it uses lower-opacity, smaller light pools than the smoky surface.
    private static let liquidOrbs: [Orb] = [
        .init(
            color: Color(red: 0.70, green: 0.86, blue: 1.00),
            radiusRatio: 0.78,
            amplitude: CGSize(width: 0.17, height: 0.08),
            speed: 0.12, phase: 0.6,
            center: CGPoint(x: 0.22, y: 0.82),
            maxOpacity: 0.050
        ),
        .init(
            color: Color(red: 0.58, green: 1.00, blue: 0.88),
            radiusRatio: 0.52,
            amplitude: CGSize(width: 0.21, height: 0.10),
            speed: 0.10, phase: 3.4,
            center: CGPoint(x: 0.72, y: 0.72),
            maxOpacity: 0.038
        ),
    ]

    var body: some View {
        Group {
            if reduceMotion {
                Canvas(rendersAsynchronously: true) { context, size in
                    Self.draw(
                        into: &context,
                        size: size,
                        time: 0,
                        animated: false,
                        visualStyle: visualStyle
                    )
                }
            } else {
                // The field moves over tens of seconds, so 20 fps is visually continuous while
                // avoiding display-rate redraws on ProMotion panels.
                TimelineView(.periodic(from: .now, by: 1.0 / 20.0)) { timeline in
                    let time = timeline.date.timeIntervalSinceReferenceDate
                    Canvas(rendersAsynchronously: true) { context, size in
                        Self.draw(
                            into: &context,
                            size: size,
                            time: time,
                            animated: true,
                            visualStyle: visualStyle
                        )
                    }
                }
            }
        }
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private static func draw(
        into context: inout GraphicsContext,
        size: CGSize,
        time: TimeInterval,
        animated: Bool,
        visualStyle: IslandVisualStyle
    ) {
        let minSide = min(size.width, size.height)
        guard minSide > 0 else { return }
        let orbs = visualStyle == .transparent ? liquidOrbs : frostedOrbs
        for orb in orbs {
            let angle = time * orb.speed + orb.phase
            let x = (orb.center.x + (animated ? sin(angle) * orb.amplitude.width : 0)) * size.width
            let y = (orb.center.y + (animated ? cos(angle * 0.8) * orb.amplitude.height : 0)) * size.height
            // Opacity breathes slightly out of phase with the drift so the light feels alive
            // rather than merely translating.
            let breathe = animated ? 0.75 + 0.25 * sin(angle * 0.6 + orb.phase) : 0.85
            let opacity = orb.maxOpacity * breathe
            let radius = minSide * orb.radiusRatio
            context.fill(
                Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: orb.color.opacity(opacity), location: 0),
                        .init(color: orb.color.opacity(opacity * 0.45), location: 0.45),
                        .init(color: orb.color.opacity(0), location: 1),
                    ]),
                    center: CGPoint(x: x, y: y),
                    startRadius: 0,
                    endRadius: radius
                )
            )
        }
    }
}

// MARK: - Sheen sweep

/// One-shot specular highlight that sweeps across the surface right after the island
/// expands or changes style — the "glass catching light" moment. It removes its own gradient
/// after the pass, so an idle expanded island does not retain this effect's rendering work.
struct IslandSheenSweep: View {
    let visualStyle: IslandVisualStyle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 0
    @State private var isVisible = false

    var body: some View {
        Group {
            if !reduceMotion && isVisible {
                GeometryReader { geo in
                    let band = geo.size.width * 0.38
                    let travel = geo.size.width + band * 2
                    let peakOpacity = visualStyle == .transparent ? 0.13 : 0.09
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0), location: 0),
                            .init(
                                color: ZislaMotionPalette.refraction.opacity(peakOpacity * 0.56),
                                location: 0.35
                            ),
                            .init(color: .white.opacity(peakOpacity), location: 0.5),
                            .init(
                                color: ZislaMotionPalette.refraction.opacity(peakOpacity * 0.56),
                                location: 0.65
                            ),
                            .init(color: .white.opacity(0), location: 1),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: band, height: geo.size.height * 1.6)
                    .rotationEffect(.degrees(14))
                    .offset(x: -band + travel * progress, y: -geo.size.height * 0.3)
                }
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .task(id: reduceMotion) {
            guard !reduceMotion else {
                isVisible = false
                return
            }
            progress = 0
            isVisible = true
            // Slight delay lets the reveal mask mostly settle before the light passes.
            withAnimation(.easeInOut(duration: 0.85).delay(0.12)) {
                progress = 1
            }
            try? await Task.sleep(for: .milliseconds(1_100))
            guard !Task.isCancelled else { return }
            isVisible = false
        }
    }
}

// MARK: - Rim light

/// Static rim light along the island silhouette: a hairline stroke that brightens toward
/// the bottom corners, reading as desk light caught by the glass edge. Zero animation cost.
struct IslandRimLight: View {
    let visualStyle: IslandVisualStyle

    var body: some View {
        IslandSilhouette(
            topCornerRadius: 0,
            bottomCornerRadius: IslandSurfaceGeometry.expandedBottomCornerRadius
        )
        .strokeBorder(
            LinearGradient(
                stops: [
                    .init(color: .white.opacity(0), location: 0),
                    .init(color: rimColor.opacity(0.04), location: 0.55),
                    .init(color: rimColor.opacity(0.13), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            ),
            lineWidth: 1
        )
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var rimColor: Color {
        visualStyle == .transparent ? ZislaMotionPalette.refraction : .white
    }
}

// MARK: - Selection illumination

/// A moving dark-glass focus lens: the glyph settles into place while an outer pulse expands
/// away. The transient parts remove themselves visually after the selection lands, leaving the
/// restrained framed state shown in the motion reference.
struct MotionFocusLens: View {
    var cornerRadius: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var settleProgress: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            let pulseScale = 0.82 + settleProgress * 0.42
            ZStack {
                shape.fill(
                    LinearGradient(
                        stops: [
                            .init(color: .black.opacity(0.82), location: 0),
                            .init(color: .black.opacity(0.56), location: 0.30),
                            .init(color: .black.opacity(0.10), location: 0.68),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                shape.strokeBorder(.white.opacity(0.24), lineWidth: 0.75)
                shape
                    .strokeBorder(.white.opacity(0.22 * (1 - settleProgress)), lineWidth: 1)
                    .scaleEffect(pulseScale)
                    .opacity(1 - settleProgress)
                LinearGradient(
                    colors: [.clear, .white.opacity(0.22), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .rotationEffect(.degrees(-18))
                .offset(x: proxy.size.width * (-0.65 + settleProgress * 1.3))
                .mask(shape)
                .opacity((1 - settleProgress) * 0.75)
            }
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .white, location: 0),
                        .init(color: .white, location: 0.34),
                        .init(color: .white.opacity(0.18), location: 0.70),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .shadow(color: .black.opacity(0.16), radius: 3, y: 1)
        .allowsHitTesting(false)
        .task(id: reduceMotion) {
            guard !reduceMotion else {
                settleProgress = 1
                return
            }
            settleProgress = 0
            withAnimation(.smooth(duration: 0.42)) {
                settleProgress = 1
            }
        }
    }
}

/// A compact text switch with a neutral outlined selection indicator, shared by the settings
/// appearance rows and the download format switch.
struct IslandOutlinedPicker<Option: Hashable>: View {
    @Binding var selection: Option
    let options: [Option]
    let title: (Option) -> String
    let selectionID: String
    var symbol: ((Option) -> String)? = nil
    var fontSize: CGFloat = 9
    var width: CGFloat = 168
    var height: CGFloat = 34
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionNamespace

    init(
        selection: Binding<Option>,
        options: [Option],
        title: @escaping (Option) -> String,
        selectionID: String,
        symbol: ((Option) -> String)? = nil,
        fontSize: CGFloat = 9,
        width: CGFloat = 168,
        height: CGFloat = 34
    ) {
        _selection = selection
        self.options = options
        self.title = title
        self.selectionID = selectionID
        self.symbol = symbol
        self.fontSize = fontSize
        self.width = width
        self.height = height
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(options, id: \.self) { option in
                optionButton(option)
            }
        }
        .padding(3)
        .frame(width: width, height: height)
        .animation(reduceMotion ? nil : ZislaMotion.selection, value: selection)
    }

    private func optionButton(_ option: Option) -> some View {
        let isSelected = selection == option
        return Button {
            guard selection != option else { return }
            if reduceMotion {
                selection = option
            } else {
                withAnimation(ZislaMotion.selection) {
                    selection = option
                }
            }
        } label: {
            optionLabel(option, isSelected: isSelected)
        }
        .buttonStyle(PressableStyle(hoverScale: 1.025, pressedScale: 0.95))
        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.50), lineWidth: 1)
                    .matchedGeometryEffect(id: selectionID, in: selectionNamespace)
            }
        }
        .accessibilityLabel(title(option))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private func optionLabel(_ option: Option, isSelected: Bool) -> some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol(option))
            }
            Text(title(option))
                .lineLimit(1)
        }
        .font(.system(size: fontSize, weight: isSelected ? .semibold : .medium))
        .frame(maxWidth: .infinity, minHeight: height - 6)
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

struct IslandVisualStylePicker: View {
    @Binding var selection: IslandVisualStyle

    var body: some View {
        IslandOutlinedPicker(
            selection: $selection,
            options: Array(IslandVisualStyle.allCases),
            title: { $0.title },
            selectionID: "island-style-selection"
        )
    }
}

struct IslandNotchBackgroundPicker: View {
    @Binding var selection: IslandNotchBackground

    var body: some View {
        IslandOutlinedPicker(
            selection: $selection,
            options: Array(IslandNotchBackground.allCases),
            title: { $0.title },
            selectionID: "island-notch-background-selection"
        )
    }
}
