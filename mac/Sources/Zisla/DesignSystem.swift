import ZislaCore
import SwiftUI

/// Zisla's design tokens and base component library.
///
/// Provides a single, reusable visual source for the Dynamic Island and settings window,
/// eliminating scattered magic color/font/stroke values and ensuring consistent appearance.
/// Accessibility adjustment points (contrast, minimum font size) are centralized here.
///
/// - Color tokens are based on `Color.primary`, resolving correctly in both the dark Dynamic
///   Island (primary=white) and the theme-adaptive settings window (primary follows the system).
/// - Font tokens set 9pt as the minimum readable micro-copy size (previously 7–8pt was used).

// MARK: - Brand colors (AI providers, single source of truth)

/// Brand colors for each AI provider. The **only** definition point; progress bars,
/// icon tinting, and all other references pull from here to avoid inconsistent colors.
enum ProviderBrand {
    static func color(for provider: AIProvider) -> Color {
        switch provider {
        case .claude: Color(red: 0.95, green: 0.48, blue: 0.34)
        case .codex: Color(red: 0.36, green: 0.90, blue: 0.66)
        case .gemini: Color(red: 0.50, green: 0.68, blue: 1.00)
        case .grok: .primary
        case .gpt: Color(red: 0.42, green: 0.82, blue: 0.72)
        case .copilot: .primary
        case .kimi: Color(red: 0.29, green: 0.76, blue: 0.74)
        case .qwen: Color(red: 0.48, green: 0.62, blue: 1.00)
        case .coder: Color(red: 0.98, green: 0.78, blue: 0.30)
        case .zcode: Color(red: 0.22, green: 0.78, blue: 0.46)
        case .trae: Color(red: 0.40, green: 0.56, blue: 1.00)
        case .opencode: Color(red: 0.55, green: 0.85, blue: 0.55)
        case .harness: Color(red: 0.90, green: 0.45, blue: 0.50)
        case .doubao: Color(red: 0.35, green: 0.72, blue: 1.00)
        }
    }
}

// MARK: - Color tokens

extension Color {
    /// Card / module container fill (medium intensity).
    static let fillCard = Color.primary.opacity(0.12)
    /// Subdued fill for controls and icon buttons.
    static let fillControl = Color.primary.opacity(0.10)
    /// Card border.
    static let strokeCard = Color.primary.opacity(0.14)
    /// Subtle divider.
    static let dividerSubtle = Color.primary.opacity(0.08)
    /// Active-state accent background tint.
    static let accentTint = Color.accentColor.opacity(0.16)

    // Semantic colors: error=red, warning=orange, success=green, info=cyan. Consistent globally; do not mix.
    static let zislaError = Color.red
    static let zislaWarning = Color.orange
    static let zislaSuccess = Color.green
    static let zislaInfo = Color.cyan
}

// MARK: - Font tokens

extension Font {
    /// Minimum **readable** micro-copy font size on the Dynamic Island (9pt).
    /// Previously, chart axis labels, progress timestamps, and legends used 7–8pt,
    /// which is below the comfortable threshold on a 240pt-wide panel.
    static func islandMicro(
        weight: Font.Weight = .medium,
        design: Font.Design = .default
    ) -> Font {
        .system(size: 9, weight: weight, design: design)
    }
}

// MARK: - Dynamic Island geometry

enum IslandSurfaceGeometry {
    static let expandedBottomCornerRadius: CGFloat = 34
    static let moduleInset: CGFloat = 12
    static let moduleInnerCornerRadius: CGFloat = 8

    static let moduleOuterBottomCornerRadius = expandedBottomCornerRadius - moduleInset

    static func nestedBottomCornerRadius(inset: CGFloat) -> CGFloat {
        max(0, moduleOuterBottomCornerRadius - inset)
    }

    static func moduleContentShape(
        cornerRadius: CGFloat = moduleInnerCornerRadius,
        bottomLeadingRadius: CGFloat? = nil,
        bottomTrailingRadius: CGFloat? = nil
    ) -> UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            cornerRadii: .init(
                topLeading: cornerRadius,
                bottomLeading: bottomLeadingRadius ?? cornerRadius,
                bottomTrailing: bottomTrailingRadius ?? cornerRadius,
                topTrailing: cornerRadius
            ),
            style: .continuous
        )
    }
}

private struct IslandVisualStyleKey: EnvironmentKey {
    static let defaultValue: IslandVisualStyle = .frosted
}

extension EnvironmentValues {
    var islandVisualStyle: IslandVisualStyle {
        get { self[IslandVisualStyleKey.self] }
        set { self[IslandVisualStyleKey.self] = newValue }
    }
}

enum IslandGlassSurfaceKind {
    case card
    case input
}

private struct IslandGlassSurface: ViewModifier {
    @Environment(\.islandVisualStyle) private var visualStyle
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let kind: IslandGlassSurfaceKind
    let cornerRadius: CGFloat
    let bottomLeadingRadius: CGFloat?
    let bottomTrailingRadius: CGFloat?

    func body(content: Content) -> some View {
        content
            .background { surfaceBackground }
            .clipShape(shape)
            .overlay {
                // Native liquid glass draws its own specular rim; a hand-drawn edge would double it.
                if !usesNativeLiquidGlass {
                    shape.strokeBorder(edgeHighlight, lineWidth: 1)
                }
            }
    }

    /// Material follows the island theme: the transparent style gets the real refractive Liquid
    /// Glass pane, the frosted style gets frosted blur — never a flat black slab on either.
    @ViewBuilder
    private var surfaceBackground: some View {
        if reduceTransparency {
            shape.fill(reducedTransparencyFill)
        } else if usesNativeLiquidGlass {
            ZStack {
                LiquidGlassPaneBackground(cornerRadius: cornerRadius)
                if kind == .input {
                    // The native pane remains clear underneath; this only gives the typing area
                    // the same black crown → transparent lower reveal as the Liquid Glass island.
                    LinearGradient(
                        stops: [
                            // An opaque leading band intentionally covers the native glass rim.
                            .init(color: .black, location: 0),
                            .init(color: .black, location: 0.10),
                            .init(color: .black.opacity(0.76), location: 0.26),
                            .init(color: .black.opacity(0.34), location: 0.52),
                            .init(color: .clear, location: 0.82),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
            .allowsHitTesting(false)
        } else {
            ZStack {
                VisualEffectBackground(
                    alphaValue: materialAlpha,
                    material: kind == .input ? .sidebar : .hudWindow,
                    blendingMode: kind == .input ? .withinWindow : .behindWindow
                )
                shape.fill(tint)
            }
            .allowsHitTesting(false)
        }
    }

    private var usesNativeLiquidGlass: Bool {
        guard visualStyle == .transparent, !reduceTransparency else { return false }
        guard #available(macOS 26.0, *) else { return false }
        return true
    }

    private var shape: UnevenRoundedRectangle {
        IslandSurfaceGeometry.moduleContentShape(
            cornerRadius: cornerRadius,
            bottomLeadingRadius: bottomLeadingRadius,
            bottomTrailingRadius: bottomTrailingRadius
        )
    }

    /// Frosted-material translucency: lower lets more desktop through. Input stays densest for
    /// typing legibility. The transparent cases only serve pre-macOS 26 fallbacks, where the
    /// island body is bare, so they run denser than on the already-smoked frosted island.
    private var materialAlpha: CGFloat {
        switch (visualStyle, kind) {
        case (.transparent, .input): 0.66
        case (.transparent, .card): 0.48
        case (.frosted, .input): 0.42
        case (.frosted, .card): 0.30
        }
    }

    /// Tint over the frosted material: white lifts a "raised" pane out of the smoked island;
    /// a light black scrim keeps text readable over bright desktops in the fallback path.
    private var tint: Color {
        switch (visualStyle, kind) {
        case (.transparent, .input): .black.opacity(0.12)
        case (.transparent, .card): .black.opacity(0.08)
        case (.frosted, .input): .white.opacity(0.05)
        case (.frosted, .card): .white.opacity(0.08)
        }
    }

    /// Top-lit highlight stroke simulating a glass edge (same treatment as the lock-screen card).
    private var edgeHighlight: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .white.opacity(kind == .input ? 0.26 : 0.16), location: 0),
                .init(color: .white.opacity(0.07), location: 0.5),
                .init(color: .white.opacity(0.03), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Reduce Transparency: flat fills on the island's opaque fallback surface, no blur.
    private var reducedTransparencyFill: Color {
        switch kind {
        case .card: .fillCard
        case .input: Color.primary.opacity(0.055)
        }
    }
}

extension View {
    func islandGlassSurface(
        _ kind: IslandGlassSurfaceKind,
        cornerRadius: CGFloat,
        bottomLeadingRadius: CGFloat? = nil,
        bottomTrailingRadius: CGFloat? = nil
    ) -> some View {
        modifier(
            IslandGlassSurface(
                kind: kind,
                cornerRadius: cornerRadius,
                bottomLeadingRadius: bottomLeadingRadius,
                bottomTrailingRadius: bottomTrailingRadius
            )
        )
    }
}

/// Glass-look inline field: replaces `.roundedBorder`, whose dark-appearance AppKit bezel renders
/// as a near-black block that pops in and out on the island's glass surfaces.
private struct IslandGlassField: ViewModifier {
    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                Color.primary.opacity(0.07),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            }
    }
}

extension View {
    /// Applies the translucent glass well to a `TextField` shown on the island.
    func islandGlassField() -> some View {
        modifier(IslandGlassField())
    }
}

// MARK: - Hairline divider

/// Unified hairline divider, replacing the scattered `Divider().overlay(Color.primary.opacity(0.06))` pattern.
struct Hairline: View {
    var body: some View {
        Divider().overlay(Color.dividerSubtle)
    }
}

// MARK: - Icon button (unified implementation)

/// Unified visual label for circular icon buttons; can be used directly as `IconButton`'s
/// content or as a `Menu` label for reuse, ensuring identical appearance and active state
/// across all three entry points (toolbar / media control / module switcher).
struct IconButtonLabel: View {
    enum Size {
        case compact
        case regular

        var dimension: CGFloat { self == .compact ? 24 : 28 }
        var symbolSize: CGFloat { self == .compact ? 11 : 13 }
    }

    var symbol: String
    var isActive = false
    var activeColor: Color? = nil
    var size: Size = .regular
    /// When inactive, whether to render in secondary color (for label-style toggles like
    /// the module selector, where only the selected item is highlighted).
    var dimmedWhenInactive = false
    /// Set to false when the container draws the active fill itself
    /// (e.g. the module selector's sliding matchedGeometryEffect capsule).
    var showsActiveBackground = true
    /// Module selectors keep their resting glyphs quiet; toolbar buttons retain their control fill.
    var showsInactiveBackground = true
    /// Selected navigation glyphs get a small positional emphasis while their focus surface moves.
    var emphasizesSelection = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size.symbolSize, weight: .semibold))
            .foregroundStyle(
                isActive ? (activeColor ?? Color.accentColor) : (dimmedWhenInactive ? .secondary : .primary)
            )
            .frame(width: size.dimension, height: size.dimension)
            .background(backgroundFill)
            .clipShape(Circle())
            .contentShape(Circle())
            .clipped()
            .scaleEffect(emphasizesSelection ? (isActive ? 1.08 : 0.88) : 1)
            .opacity(emphasizesSelection && !isActive ? 0.58 : 1)
            .rotationEffect(.degrees(emphasizesSelection && !isActive ? -2 : 0))
            .animation(ZislaMotion.selection, value: isActive)
    }

    private var backgroundFill: Color {
        guard isActive else { return showsInactiveBackground ? Color.fillControl : .clear }
        return showsActiveBackground ? (activeColor ?? Color.accentColor).opacity(0.16) : .clear
    }
}

/// Unified circular icon button.
struct IconButton: View {
    var symbol: String
    var help: String
    var isActive = false
    var activeColor: Color? = nil
    var size: IconButtonLabel.Size = .regular
    var dimmedWhenInactive = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            IconButtonLabel(
                symbol: symbol,
                isActive: isActive,
                activeColor: activeColor,
                size: size,
                dimmedWhenInactive: dimmedWhenInactive
            )
        }
        .buttonStyle(PressableStyle())
        .help(help)
    }
}

// MARK: - Empty state (unified implementation)

/// Compact empty state for the Dynamic Island's dark glass and constrained height.
/// Replaces per-module implementations to ensure consistent icon scale, font, and color.
struct EmptyState: View {
    var symbol: String
    var title: String
    var detail: String? = nil
    /// Overall tint; defaults to secondary, but can be set to accent color for drag-hover and similar states.
    var tint: Color = .secondary

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 25, weight: .medium))
                .symbolRenderingMode(.hierarchical)
            Text(title)
                .font(.system(size: 10, weight: .medium))
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.islandMicro())
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
        }
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
