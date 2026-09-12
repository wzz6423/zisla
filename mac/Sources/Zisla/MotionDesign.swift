import SwiftUI
import ZislaCore
import ZislaKit

/// Zisla's motion system: spring tokens, button press feedback, and directional module
/// transitions.
///
/// Design principles (Apple HIG Motion / Dynamic Island conventions):
/// - Springs over ease curves: interruptible and continuous, matching macOS system feel.
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
    /// Island reveal: the surface grows out of the collapsed pill, with a hint of bounce at the end.
    /// Duration matches `islandRecycle` so growing and shrinking take the same time; only the
    /// curve differs (spring with bounce vs. bounce-free ease).
    static let islandReveal: Animation = .snappy(duration: 0.22, extraBounce: 0.05)
    /// Island recycle: the pointer left, so the surface folds straight back into the pill it grew
    /// from. No bounce — a fold that overshoots reads as the island hesitating to leave.
    static let islandRecycle: Animation = .smooth(duration: 0.22)
    /// The surface and its content dissolve on the same clock as the fold, weighted to its end, so
    /// the eye follows the island being drawn back into the notch instead of a blink-out.
    static let islandRecycleFade: Animation = .easeIn(duration: 0.22)
    /// Delay before the panel returns to its module size after a voice take — must outlast the fold
    /// and its fade, because the module panel reserves a pet slot that re-offsets the surface from
    /// the panel center and would drag the still-visible pill sideways.
    static let islandRecycleSettleDelay: Duration = .milliseconds(280)
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

    /// Lightweight directional transition for the settings window's long, scrollable pages.
    static func settingsPagePush(direction: CGFloat) -> AnyTransition {
        let d: CGFloat = direction >= 0 ? 1 : -1
        return .asymmetric(
            insertion: .modifier(
                active: ModulePushModifier(offsetX: 14 * d, blurRadius: 0, scale: 1, opacity: 0),
                identity: ModulePushModifier(offsetX: 0, blurRadius: 0, scale: 1, opacity: 1)
            ),
            removal: .modifier(
                active: ModulePushModifier(offsetX: -14 * d, blurRadius: 0, scale: 1, opacity: 0),
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

// MARK: - Selection glass background

/// Unified selection state background: subtle frosted glass with soft highlight and shadow.
/// Shared across Quick Notes rows, PDF tool navigation, and outlined pickers.
struct SelectionGlassBackground: View {
    var cornerRadius: CGFloat = 7
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(fillColor)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: edgeColor.opacity(0.10), location: 0),
                            .init(color: edgeColor.opacity(0.03), location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
        }
        .shadow(color: .black.opacity(0.025), radius: 1, y: 0.5)
    }

    private var fillColor: Color {
        let opacity = colorScheme == .dark
            ? (reduceTransparency ? 0.12 : 0.10)
            : (reduceTransparency ? 0.08 : 0.055)
        return Color.primary.opacity(opacity)
    }

    private var edgeColor: Color {
        colorScheme == .dark ? .white : .black
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

/// A compact text switch with the shared frosted selection background, used by settings
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
    var usesGlassSelection = true
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
        height: CGFloat = 34,
        usesGlassSelection: Bool = true
    ) {
        _selection = selection
        self.options = options
        self.title = title
        self.selectionID = selectionID
        self.symbol = symbol
        self.fontSize = fontSize
        self.width = width
        self.height = height
        self.usesGlassSelection = usesGlassSelection
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
                selectionBackground
                    .matchedGeometryEffect(id: selectionID, in: selectionNamespace)
            }
        }
        .accessibilityLabel(title(option))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var selectionBackground: some View {
        if usesGlassSelection {
            SelectionGlassBackground(cornerRadius: 6)
        } else {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(0.16))
        }
    }

    @ViewBuilder
    private func optionLabel(_ option: Option, isSelected: Bool) -> some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol(option))
            }
            AppLocalizedText(title(option))
                .fitsSingleLine()
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
