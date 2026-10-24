import SwiftUI

struct SettingsTintedBackground: View {
    var tint: Color = .accentColor
    var cornerRadius: CGFloat = 6
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape
            .fill(tint.opacity(colorScheme == .dark ? 0.18 : 0.10))
            .overlay {
                shape.strokeBorder(tint.opacity(colorScheme == .dark ? 0.42 : 0.24), lineWidth: 0.5)
            }
    }
}

struct SettingsTintedButtonStyle: ButtonStyle {
    @Environment(\.controlSize) private var controlSize
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        PressableStyle(hoverScale: 1.018, pressedScale: 0.965)
            .makeBody(configuration: configuration)
            .font(.system(size: controlSize == .small ? 11 : 13, weight: .medium))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(SettingsTintedBackground())
            .opacity(isEnabled ? 1 : 0.5)
    }
}
