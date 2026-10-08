import SwiftUI
import ZislaCore

struct CompactLowBatteryBar: View {
    static let symbolName = "battery.25percent"

    var notice: IslandNotice
    var height: CGFloat
    var centerInset: CGFloat = 0

    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: Self.symbolName)
                    .font(.system(size: min(18, height * 0.56), weight: .semibold))
                    .foregroundStyle(.red)
                if let deviceName = notice.batteryLevels?.first?.label {
                    Text(verbatim: deviceName)
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(.white)
                }
            }
            Spacer(minLength: 0)
                .frame(width: centerInset)
            Text(notice.detail ?? "")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .frame(height: height)
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText(locale: locale)))
        .help(accessibilityText(locale: locale))
    }

    func accessibilityText(locale: Locale) -> String {
        let identity = notice.batteryLevels?.first.map { "\($0.label) " } ?? ""
        return "\(AppLocalization.string(notice.title, locale: locale)) \(identity)\(notice.detail ?? "")"
    }
}
