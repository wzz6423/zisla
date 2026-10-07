import AppKit
import SwiftUI
import ZislaCore
import ZislaKit

struct FileShelfShakeView: View {
    @ObservedObject var settingsStore: FeatureSettingsStore
    let onItems: ([FileShelfDropItem]) -> Void
    let onShare: ([TransferDropItem], NSView) -> Void
    @State private var shelfTargeted = false
    @State private var shareTargeted = false
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: 8) {
            dropCard(
                title: "共享", instruction: shareTargeted ? "松开以共享文件" : "拖入文件以共享",
                symbol: shareTargeted ? "square.and.arrow.up.fill" : "square.and.arrow.up",
                isTargeted: shareTargeted, tint: .cyan
            )
            .shareDropTarget(isTargeted: $shareTargeted, onItems: onShare)
            .environment(\.layoutDirection, layoutDirection)

            dropCard(
                title: "中转站", instruction: shelfTargeted ? "松开以添加到中转站" : "拖入文件，暂存到中转站",
                symbol: shelfTargeted ? "tray.and.arrow.down.fill" : "tray.and.arrow.down",
                isTargeted: shelfTargeted, tint: .green
            )
            .shelfDropTarget(isTargeted: $shelfTargeted, onItems: onItems)
            .environment(\.layoutDirection, layoutDirection)
        }
        .environment(\.layoutDirection, .leftToRight)
        .environment(\.islandVisualStyle, settingsStore.settings.islandVisualStyle)
        .environment(\.colorScheme, .dark)
    }

    private func dropCard(title: String, instruction: String, symbol: String, isTargeted: Bool, tint: Color) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(isTargeted ? tint : .primary)
                .accessibilityHidden(true)
            AppLocalizedText(title)
                .font(.system(size: 13, weight: .semibold))
            AppLocalizedText(instruction)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .islandGlassSurface(.card, cornerRadius: 18)
        .background {
            Self.standaloneBacking(style: settingsStore.settings.islandVisualStyle, reduceTransparency: reduceTransparency)
        }
        .overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(tint.opacity(0.8), lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
        .animation(reduceMotion ? nil : ZislaMotion.hover, value: isTargeted)
        .accessibilityElement(children: .combine)
    }

    static func standaloneBacking(style: IslandVisualStyle, reduceTransparency: Bool) -> some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(.black.opacity(reduceTransparency ? 1 : style == .frosted ? 0.88 : 0))
    }
}
