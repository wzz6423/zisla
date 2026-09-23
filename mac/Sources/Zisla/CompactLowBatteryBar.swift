import SwiftUI
import ZislaCore

struct CompactLowBatteryBar: View {
    static let symbolName = "battery.25percent"

    var notice: IslandNotice
    var height: CGFloat

    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: Self.symbolName)
                .font(.system(size: min(18, height * 0.56), weight: .semibold))
                .foregroundStyle(.red)
            Spacer(minLength: 0)
            Text(notice.detail ?? "")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .frame(height: height)
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText))
        .help(accessibilityText)
    }

    private var accessibilityText: String {
        "\(AppLocalization.string(notice.title, locale: locale)) \(notice.detail ?? "")"
    }
}
