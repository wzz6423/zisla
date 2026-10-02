import SwiftUI
import ZislaKit

struct FileShelfShakeView: View {
    @ObservedObject var settingsStore: FeatureSettingsStore
    let onItems: ([FileShelfDropItem]) -> Void
    @State private var isTargeted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: isTargeted ? "tray.and.arrow.down.fill" : "tray.and.arrow.down")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(isTargeted ? Color.green : .primary)
                .accessibilityHidden(true)
            AppLocalizedText("中转站")
                .font(.system(size: 13, weight: .semibold))
            AppLocalizedText(isTargeted ? "松开以添加到中转站" : "拖入文件，暂存到中转站")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .islandGlassSurface(.card, cornerRadius: 18)
        .overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.green.opacity(0.8), lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
        .environment(\.islandVisualStyle, settingsStore.settings.islandVisualStyle)
        .environment(\.colorScheme, .dark)
        .animation(reduceMotion ? nil : ZislaMotion.hover, value: isTargeted)
        .accessibilityElement(children: .combine)
        .shelfDropTarget(isTargeted: $isTargeted, onItems: onItems)
    }
}
