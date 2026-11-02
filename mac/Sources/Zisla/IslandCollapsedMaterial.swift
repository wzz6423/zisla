import SwiftUI
import ZislaCore

struct IslandCollapsedMaterial: View {
    let style: IslandNotchBackground
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Self.rendering(style: style, reduceTransparency: reduceTransparency)
    }

    @ViewBuilder
    static func rendering(style: IslandNotchBackground, reduceTransparency: Bool) -> some View {
        if reduceTransparency || style == .black {
            Color.black
        } else if style == .frosted {
            VisualEffectBackground(alphaValue: 0.92, material: .popover)
        } else {
            ZStack {
                if #available(macOS 26.0, *) {
                    NativeLiquidGlassShell(isCollapsed: false, material: .clear, cornerRadius: 16)
                } else {
                    VisualEffectBackground(alphaValue: 0.92, material: .popover)
                }
                liquidGlassCrown
            }
        }
    }

    static var liquidGlassCrown: some View {
        LinearGradient(
            stops: [
                .init(color: .black, location: 0),
                .init(color: .black, location: 0.36),
                .init(color: .black.opacity(0.70), location: 0.56),
                .init(color: .clear, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
