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
    @Environment(\.locale) private var locale
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: IslandModuleLayout.shelfColumnSpacing) {
            dropCard(isTargeted: shareTargeted, tint: .cyan) {
                VStack(spacing: 6) {
                    Image(systemName: shareTargeted ? "square.and.arrow.up.fill" : "square.and.arrow.up")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(shareTargeted ? Color.cyan : .primary)
                        .accessibilityHidden(true)
                    AppLocalizedText("共享")
                        .font(.system(size: 11, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(8)
            }
            .help(AppLocalization.string(shareTargeted ? "松开以共享文件" : "拖入文件以共享", locale: locale))
            .shareDropTarget(isTargeted: $shareTargeted, onItems: onShare)
            .frame(width: FileShelfShakeLayout.shareWidth)
            .environment(\.layoutDirection, layoutDirection)

            dropCard(isTargeted: shelfTargeted, tint: .green) {
                VStack(spacing: 10) {
                    Image(systemName: shelfTargeted ? "tray.and.arrow.down.fill" : "tray.and.arrow.down")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(shelfTargeted ? Color.green : .primary)
                        .accessibilityHidden(true)
                    AppLocalizedText("中转站")
                        .font(.system(size: 13, weight: .semibold))
                    AppLocalizedText(shelfTargeted ? "松开以添加到中转站" : "拖入文件，暂存到中转站")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(18)
            }
            .shelfDropTarget(isTargeted: $shelfTargeted, onItems: onItems)
            .environment(\.layoutDirection, layoutDirection)
        }
        .environment(\.layoutDirection, .leftToRight)
        .environment(\.islandVisualStyle, settingsStore.settings.islandVisualStyle)
        .environment(\.colorScheme, .dark)
    }

    private func dropCard<Content: View>(isTargeted: Bool, tint: Color, @ViewBuilder content: () -> Content) -> some View {
        content()
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
