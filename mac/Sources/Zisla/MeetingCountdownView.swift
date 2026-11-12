import SwiftUI
import ZislaCore
import ZislaKit

struct CompactMeetingCountdownBar: View {
    let notice: IslandNotice
    let height: CGFloat
    var centerWidth: CGFloat = 0
    let onJoin: () -> Void

    var body: some View {
        Button(action: onJoin) {
            GeometryReader { proxy in
                let wingWidth = max(0, (proxy.size.width - centerWidth) / 2)
                HStack(spacing: 0) {
                    Image(systemName: "video.fill")
                        .frame(width: wingWidth, alignment: .leading)
                    Color.clear.frame(width: centerWidth)
                    Text(notice.detail ?? "")
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .frame(width: wingWidth, alignment: .trailing)
                        .clipped()
                }
                .frame(height: proxy.size.height)
            }
            .font(.system(size: min(14, height * 0.52), weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
        .help(accessibilityText)
    }

    private var accessibilityText: String {
        AppLocalization.text("加入会议：%@ · %@", notice.title, notice.detail ?? "")
    }
}
