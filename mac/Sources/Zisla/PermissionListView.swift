import SwiftUI
import ZislaCore
import ZislaKit

struct PermissionListView: View {
    let performAction: (OnboardingPermissionItem) -> Void
    @ObservedObject var coordinator: OnboardingPermissionCoordinator
    var settingsOpenFailure: OnboardingPermissionID?
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(coordinator.permissions) { item in
                VStack(alignment: .leading, spacing: 10) {
                    AppLocalizedText(item.titleKey)
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    AppLocalizedText(item.bodyKey)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ViewThatFits(in: .horizontal) {
                        HStack { status(item); Spacer(); action(item) }
                        VStack(alignment: .leading, spacing: 8) { status(item); action(item) }
                    }
                    if settingsOpenFailure == item.id {
                        AppLocalizedText("无法打开系统设置，请手动打开。")
                            .font(.callout)
                            .foregroundStyle(Color.zislaWarning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.fillControl, in: RoundedRectangle(cornerRadius: 12))
                .settingsSearchAnchor(.row(AppLocalization.string(item.titleKey, locale: locale)))
            }
        }
    }

    private func status(_ item: OnboardingPermissionItem) -> some View {
        HStack(spacing: 6) {
            if item.status == .requesting {
                ProgressView().controlSize(.small)
                    .accessibilityHidden(true)
            } else if item.status == .granted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.zislaSuccess)
                    .accessibilityHidden(true)
            }
            AppLocalizedText(item.status.localizationKey)
        }
        .font(.callout)
    }

    @ViewBuilder
    private func action(_ item: OnboardingPermissionItem) -> some View {
        if item.status != .granted {
            Button(AppLocalization.string(item.actionKey, locale: locale)) {
                performAction(item)
            }
            .disabled(coordinator.requesting != nil)
            .accessibilityIdentifier("permission-\(item.id.rawValue)")
            .accessibilityLabel(Text(
                AppLocalization.string(item.actionKey, locale: locale) + " · " +
                    AppLocalization.string(item.titleKey, locale: locale)
            ))
        }
    }
}
