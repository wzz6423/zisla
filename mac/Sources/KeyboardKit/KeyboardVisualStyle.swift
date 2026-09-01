import AppKit
import SwiftUI

/// Shared visual language for Keyboard's menu, statistics and editor surfaces.
/// System semantic colors keep the hierarchy legible in both light and dark mode;
/// the lime accent is reserved for state, selection and the primary action.
enum KeyboardVisualStyle {
    private static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private static func adaptiveColor(
        name: String,
        light: NSColor,
        dark: NSColor
    ) -> Color {
        Color(nsColor: NSColor(name: name) { appearance in
            isDark(appearance) ? dark : light
        })
    }

    static let accent = Color(nsColor: NSColor(name: "KeyboardAccent") { appearance in
        return isDark(appearance)
            ? NSColor(srgbRed: 0.72, green: 0.91, blue: 0.30, alpha: 1)
            : NSColor(srgbRed: 0.38, green: 0.57, blue: 0.07, alpha: 1)
    })
    static let accentStrong = Color(nsColor: NSColor(name: "KeyboardAccentStrong") { appearance in
        return isDark(appearance)
            ? NSColor(srgbRed: 0.57, green: 0.79, blue: 0.17, alpha: 1)
            : NSColor(srgbRed: 0.27, green: 0.43, blue: 0.04, alpha: 1)
    })
    /// Darker than the decorative lime so white control labels remain legible.
    static let actionAccent = Color(nsColor: NSColor(name: "KeyboardActionAccent") { appearance in
        return isDark(appearance)
            ? NSColor(srgbRed: 0.29, green: 0.48, blue: 0.04, alpha: 1)
            : NSColor(srgbRed: 0.28, green: 0.47, blue: 0.04, alpha: 1)
    })
    static let accentSoft = accent.opacity(0.13)
    static let cyan = Color(red: 0.25, green: 0.72, blue: 0.82)
    static let violet = Color(red: 0.60, green: 0.50, blue: 0.92)
    static let amber = Color(red: 0.95, green: 0.67, blue: 0.20)

    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let recessed = Color(nsColor: .underPageBackgroundColor)
    // Keep AppKit's semantic color unresolved so an in-app appearance switch
    // updates existing cards instead of retaining the launch-time appearance.
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let separator = Color(nsColor: .separatorColor)

    /// Dense statistics surface that keeps the instrument hierarchy while
    /// adapting its contrast to the selected system appearance.
    static let instrumentSurface = Color(nsColor: NSColor(name: "KeyboardInstrumentSurface") { appearance in
        return isDark(appearance)
            ? NSColor(srgbRed: 0.025, green: 0.030, blue: 0.026, alpha: 0.98)
            : NSColor(srgbRed: 0.965, green: 0.972, blue: 0.955, alpha: 0.98)
    })
    static let instrumentPrimary = Color(nsColor: .labelColor)
    static let instrumentSecondary = Color(nsColor: .secondaryLabelColor)
    static let instrumentSeparator = Color(nsColor: .separatorColor)
    static let instrumentStroke = adaptiveColor(
        name: "KeyboardInstrumentStroke",
        light: NSColor.black.withAlphaComponent(0.10),
        dark: NSColor.white.withAlphaComponent(0.11)
    )
    static let panelShadow = adaptiveColor(
        name: "KeyboardPanelShadow",
        light: NSColor.black.withAlphaComponent(0.10),
        dark: NSColor.black.withAlphaComponent(0.16)
    )
    static let tooltipShadow = adaptiveColor(
        name: "KeyboardTooltipShadow",
        light: NSColor.black.withAlphaComponent(0.16),
        dark: NSColor.black.withAlphaComponent(0.30)
    )
    static let keyboardShadow = adaptiveColor(
        name: "KeyboardKeyboardShadow",
        light: NSColor.black.withAlphaComponent(0.035),
        dark: NSColor.black.withAlphaComponent(0.055)
    )
    static let activeKeyForeground = adaptiveColor(
        name: "KeyboardActiveKeyForeground",
        light: NSColor(srgbRed: 0.13, green: 0.17, blue: 0.11, alpha: 1),
        dark: NSColor.white.withAlphaComponent(0.92)
    )

    static let cardRadius: CGFloat = 14
    static let compactRadius: CGFloat = 10
    static let pagePadding: CGFloat = 20
    static let cardPadding: CGFloat = 16
    /// Empty window regions keep only a light semantic tint; the AppKit visual
    /// effect below supplies the behind-window blur.
    static let glassTintOpacity = 0.14
}

/// Heatmap colors keep Keyboard's original lime/cyan visual language while the
/// statistics model supplies the adaptive, continuous value distribution.
enum KeyboardHeatmapPalette {
    static var sequentialGradient: LinearGradient {
        gradient([
            (KeyboardVisualStyle.accent.opacity(0.10), 0.00),
            (KeyboardVisualStyle.accent.opacity(0.25), 0.33),
            (KeyboardVisualStyle.accent.opacity(0.40), 0.67),
            (KeyboardVisualStyle.accent.opacity(0.56), 1.00),
        ])
    }

    static var yearGradient: LinearGradient {
        gradient([
            (KeyboardVisualStyle.accent.opacity(0.24), 0.00),
            (KeyboardVisualStyle.accent.opacity(0.42), 0.33),
            (KeyboardVisualStyle.accent.opacity(0.66), 0.67),
            (KeyboardVisualStyle.accent.opacity(0.92), 1.00),
        ])
    }

    static var timelineGradient: LinearGradient {
        gradient([
            (KeyboardVisualStyle.cyan.opacity(0.28), 0.00),
            (KeyboardVisualStyle.cyan.opacity(0.55), 0.33),
            (KeyboardVisualStyle.accent.opacity(0.72), 0.67),
            (KeyboardVisualStyle.accentStrong, 1.00),
        ])
    }

    static var rhythmGradient: LinearGradient {
        gradient([
            (KeyboardVisualStyle.accent.opacity(0.16), 0.00),
            (KeyboardVisualStyle.accent.opacity(0.76), 1.00),
        ])
    }

    static var divergingGradient: LinearGradient {
        gradient([
            (KeyboardVisualStyle.cyan.opacity(0.72), 0.00),
            (KeyboardVisualStyle.cyan.opacity(0.14), 0.45),
            (KeyboardVisualStyle.instrumentSeparator.opacity(0.70), 0.50),
            (KeyboardVisualStyle.accent.opacity(0.14), 0.55),
            (KeyboardVisualStyle.accent.opacity(0.76), 1.00),
        ])
    }

    static func keyboardFillColor(at normalizedValue: Double) -> Color {
        KeyboardVisualStyle.accent.opacity(0.10 + normalized(normalizedValue) * 0.46)
    }

    static func keyboardStrokeColor(at normalizedValue: Double) -> Color {
        KeyboardVisualStyle.accent.opacity(0.26 + normalized(normalizedValue) * 0.34)
    }

    static func yearColor(at normalizedValue: Double) -> Color {
        KeyboardVisualStyle.accent.opacity(0.24 + normalized(normalizedValue) * 0.68)
    }

    static func timelineColor(at normalizedValue: Double) -> Color {
        let intensity = normalized(normalizedValue)
        if intensity < 0.25 {
            return KeyboardVisualStyle.cyan.opacity(0.28)
        }
        if intensity < 0.55 {
            return KeyboardVisualStyle.cyan.opacity(0.55)
        }
        if intensity < 0.82 {
            return KeyboardVisualStyle.accent.opacity(0.72)
        }
        return KeyboardVisualStyle.accentStrong
    }

    static func rhythmColor(at normalizedValue: Double) -> Color {
        KeyboardVisualStyle.accent.opacity(0.16 + normalized(normalizedValue) * 0.60)
    }

    /// Accepts the symmetric -1...1 value produced by
    /// `TypingDivergingHeatmapScale.normalized(_:)`.
    static func divergingColor(at normalizedValue: Double) -> Color {
        let value = min(1, max(-1, normalizedValue))
        if value < 0 {
            return KeyboardVisualStyle.cyan.opacity(0.14 + abs(value) * 0.58)
        }
        if value > 0 {
            return KeyboardVisualStyle.accent.opacity(0.14 + value * 0.62)
        }
        return KeyboardVisualStyle.instrumentSeparator.opacity(0.70)
    }

    private static func gradient(_ stops: [(Color, CGFloat)]) -> LinearGradient {
        LinearGradient(
            stops: stops.map { color, location in
                Gradient.Stop(color: color, location: location)
            },
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private static func normalized(_ value: Double) -> Double {
        min(1, max(0, value))
    }
}

enum KeyboardHeatmapLegendPalette {
    case keyboard
    case year
    case timeline
    case rhythm
    case diverging
}

struct KeyboardHeatmapLegend: View {
    @Environment(\.locale) private var locale

    let leadingLabel: String
    let trailingLabel: String
    var palette: KeyboardHeatmapLegendPalette = .keyboard
    var barWidth: CGFloat = 112
    var labelColor: Color = .secondary

    var body: some View {
        HStack(spacing: 6) {
            Text(L10n.tr(leadingLabel))
                .monospacedDigit()

            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(gradient)
                .frame(width: barWidth, height: 9)
                .overlay {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .stroke(KeyboardVisualStyle.instrumentSeparator, lineWidth: 0.5)
                }

            Text(L10n.tr(trailingLabel))
                .monospacedDigit()
        }
        .font(.caption2)
        .foregroundStyle(labelColor)
        .environment(\.locale, locale)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var gradient: LinearGradient {
        switch palette {
        case .keyboard:
            return KeyboardHeatmapPalette.sequentialGradient
        case .year:
            return KeyboardHeatmapPalette.yearGradient
        case .timeline:
            return KeyboardHeatmapPalette.timelineGradient
        case .rhythm:
            return KeyboardHeatmapPalette.rhythmGradient
        case .diverging:
            return KeyboardHeatmapPalette.divergingGradient
        }
    }

    private var accessibilityText: String {
        switch palette {
        case .keyboard, .year, .timeline, .rhythm:
            L10n.format("连续颜色图例，从 %@ 到 %@", leadingLabel, trailingLabel)
        case .diverging:
            L10n.format("连续差异颜色图例，从 %@，经过零，到 %@", leadingLabel, trailingLabel)
        }
    }
}

/// Immediate, app-drawn heatmap detail. This avoids AppKit's intentionally
/// delayed `.help` tooltip while still communicating a click-locked state.
struct KeyboardHeatmapTooltip: View {
    let text: String
    let isPinned: Bool
    var maxWidth: CGFloat = 280

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            if isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(KeyboardVisualStyle.accent)
            }
            Text(text)
                .font(.caption2.weight(.medium))
                .foregroundStyle(KeyboardVisualStyle.instrumentPrimary)
                .monospacedDigit()
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: maxWidth, alignment: .leading)
        .background(
            KeyboardVisualStyle.instrumentSurface,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(
                    isPinned
                        ? KeyboardVisualStyle.accent.opacity(0.55)
                        : KeyboardVisualStyle.instrumentSeparator,
                    lineWidth: 1
                )
        }
        .shadow(color: KeyboardVisualStyle.tooltipShadow, radius: 8, y: 4)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct KeyboardWindowGlass: View {
    var body: some View {
        Rectangle()
            .fill(KeyboardVisualStyle.canvas.opacity(KeyboardVisualStyle.glassTintOpacity))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// AppKit owns the actual backdrop sampling. SwiftUI materials can otherwise
/// resolve as an almost-opaque in-window layer and only leave the titlebar clear.
@MainActor
final class KeyboardGlassHostingController<Content: View>: NSViewController {
    private let hostingController: NSHostingController<Content>

    init(rootView: Content) {
        hostingController = NSHostingController(rootView: rootView)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        let backdrop = NSVisualEffectView()
        backdrop.material = .underWindowBackground
        backdrop.blendingMode = .behindWindow
        backdrop.state = .active
        backdrop.isEmphasized = false

        let hostedView = hostingController.view
        hostedView.translatesAutoresizingMaskIntoConstraints = false
        hostedView.wantsLayer = true
        hostedView.layer?.backgroundColor = NSColor.clear.cgColor

        view = backdrop
        addChild(hostingController)
        backdrop.addSubview(hostedView)
        NSLayoutConstraint.activate([
            hostedView.leadingAnchor.constraint(equalTo: backdrop.leadingAnchor),
            hostedView.trailingAnchor.constraint(equalTo: backdrop.trailingAnchor),
            hostedView.topAnchor.constraint(equalTo: backdrop.topAnchor),
            hostedView.bottomAnchor.constraint(equalTo: backdrop.bottomAnchor),
        ])
    }
}

@MainActor
enum KeyboardWindowChrome {
    static func apply(to window: NSWindow) {
        window.styleMask.insert(.fullSizeContentView)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .line
    }
}

private extension AppAppearancePreference {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

@MainActor
private final class KeyboardPreferenceWindowAccessorView: NSView {
    var appearancePreference: AppAppearancePreference = .system
    var windowTitleKey: String?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyPreferences()
    }

    func applyPreferences() {
        guard let window else { return }
        let desiredAppearance = appearancePreference.nsAppearance
        let appearanceChanged =
            window.appearance?.name != desiredAppearance?.name
            || (window.appearance == nil) != (desiredAppearance == nil)
        if appearanceChanged {
            window.appearance = desiredAppearance
        }
        if let windowTitleKey {
            let localizedTitle = L10n.tr(windowTitleKey)
            if window.title != localizedTitle {
                window.title = localizedTitle
            }
        }
        if appearanceChanged {
            window.invalidateShadow()
        }
    }
}

private struct KeyboardPreferenceWindowAccessor: NSViewRepresentable {
    let appearancePreference: AppAppearancePreference
    let windowTitleKey: String?

    func makeNSView(context: Context) -> KeyboardPreferenceWindowAccessorView {
        let view = KeyboardPreferenceWindowAccessorView()
        view.appearancePreference = appearancePreference
        view.windowTitleKey = windowTitleKey
        return view
    }

    func updateNSView(_ nsView: KeyboardPreferenceWindowAccessorView, context: Context) {
        nsView.appearancePreference = appearancePreference
        nsView.windowTitleKey = windowTitleKey
        nsView.applyPreferences()
    }
}

private struct KeyboardUserPreferencesModifier: ViewModifier {
    @ObservedObject var settings: AppSettings
    let windowTitleKey: String?

    func body(content: Content) -> some View {
        content
            .environment(\.locale, L10n.locale(for: settings.languagePreference))
            .preferredColorScheme(settings.appearancePreference.colorScheme)
            .background {
                KeyboardPreferenceWindowAccessor(
                    appearancePreference: settings.appearancePreference,
                    windowTitleKey: windowTitleKey
                )
                .frame(width: 0, height: 0)
            }
    }
}

private struct KeyboardBehindWindowEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = false
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = .underWindowBackground
        nsView.blendingMode = .behindWindow
        nsView.state = .active
    }
}

private final class KeyboardWindowAccessorView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        Task { @MainActor in
            KeyboardWindowChrome.apply(to: window)
        }
    }
}

private struct KeyboardWindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        KeyboardWindowAccessorView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private struct KeyboardPanelModifier: ViewModifier {
    let radius: CGFloat
    let emphasized: Bool

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(KeyboardVisualStyle.surface)
                    if emphasized {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(KeyboardVisualStyle.accentSoft)
                    }
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(
                        emphasized
                            ? KeyboardVisualStyle.accent.opacity(0.28)
                            : KeyboardVisualStyle.separator.opacity(0.72),
                        lineWidth: 1
                    )
            }
    }
}

private struct KeyboardTintedPanelModifier: ViewModifier {
    let tint: Color
    let tintOpacity: Double
    let radius: CGFloat

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(KeyboardVisualStyle.surface)
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(tint.opacity(tintOpacity))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(tint.opacity(0.22), lineWidth: 1)
            }
    }
}

extension View {
    func keyboardUserPreferences(
        _ settings: AppSettings,
        windowTitleKey: String? = nil
    ) -> some View {
        modifier(
            KeyboardUserPreferencesModifier(
                settings: settings,
                windowTitleKey: windowTitleKey
            )
        )
    }

    func keyboardPanel(
        radius: CGFloat = KeyboardVisualStyle.cardRadius,
        emphasized: Bool = false
    ) -> some View {
        modifier(KeyboardPanelModifier(radius: radius, emphasized: emphasized))
    }

    func keyboardTintedPanel(
        _ tint: Color,
        opacity: Double = 0.08,
        radius: CGFloat = KeyboardVisualStyle.compactRadius
    ) -> some View {
        modifier(
            KeyboardTintedPanelModifier(
                tint: tint,
                tintOpacity: opacity,
                radius: radius
            )
        )
    }

    func keyboardWindowGlass(providesBackdrop: Bool = false) -> some View {
        background {
            ZStack {
                if providesBackdrop {
                    KeyboardBehindWindowEffect()
                }
                KeyboardWindowGlass()
            }
            .ignoresSafeArea()
        }
    }

    func keyboardConfigureContainingWindow() -> some View {
        background(KeyboardWindowAccessor().frame(width: 0, height: 0))
    }
}

struct KeyboardIconTile: View {
    let symbol: String
    var tint: Color = KeyboardVisualStyle.accent
    var size: CGFloat = 38
    var symbolSize: CGFloat = 16

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: symbolSize, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .stroke(tint.opacity(0.18))
            }
    }
}

/// Uses the icon embedded in the running app bundle so the UI always stays in
/// sync when Keyboard's App Icon asset changes.
struct KeyboardApplicationIcon: View {
    @Environment(\.locale) private var locale

    var size: CGFloat = 40

    var body: some View {
        Image(nsImage: NSApplication.shared.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityLabel(L10n.tr("Zisla 应用图标"))
            .environment(\.locale, locale)
    }
}

struct KeyboardStatusPill: View {
    @Environment(\.locale) private var locale

    let title: String
    let symbol: String
    var tint: Color = KeyboardVisualStyle.accentStrong

    var body: some View {
        Label(L10n.tr(title), systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.11), in: Capsule())
            .overlay {
                Capsule().stroke(tint.opacity(0.16))
            }
            .environment(\.locale, locale)
    }
}

struct KeyboardSectionHeading: View {
    @Environment(\.locale) private var locale

    let title: String
    let subtitle: String?
    let symbol: String?

    init(_ title: String, subtitle: String? = nil, symbol: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(KeyboardVisualStyle.accentStrong)
                    .frame(width: 22, height: 22)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.tr(title))
                    .font(.headline)
                if let subtitle {
                    Text(L10n.tr(subtitle))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .environment(\.locale, locale)
    }
}

struct KeyboardCardLabel: View {
    @Environment(\.locale) private var locale

    let title: String
    let symbol: String
    var tint: Color = KeyboardVisualStyle.accentStrong

    var body: some View {
        Label(L10n.tr(title), systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .environment(\.locale, locale)
    }
}
