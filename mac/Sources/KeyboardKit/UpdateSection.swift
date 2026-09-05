import SwiftUI
import ZislaCore
import ZislaKit

@MainActor
struct UpdateSection: View {
    @Environment(\.openURL) private var openURL
    @ObservedObject private var controller: UpdateController

    init(controller: UpdateController) {
        _controller = ObservedObject(wrappedValue: controller)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            KeyboardSectionHeading(
                "软件更新".localized,
                subtitle: "从 GitHub Release 检查新版本".localized,
                symbol: "arrow.triangle.2.circlepath"
            )
            preferenceContent
            resultContent
            controls
        }
        .padding(KeyboardVisualStyle.cardPadding)
        .keyboardPanel()
    }

    @ViewBuilder
    private var preferenceContent: some View {
        switch controller.automaticCheckPreference {
        case .undecided:
            VStack(alignment: .leading, spacing: 8) {
                Label(AppLocalization.text("允许打开菜单时检查更新？"), systemImage: "arrow.triangle.2.circlepath")
                    .font(.subheadline.weight(.semibold))
                privacyText
                HStack {
                    Button(AppLocalization.text("开启")) { controller.enableAutomaticChecks() }
                        .buttonStyle(.borderedProminent)
                    Button(AppLocalization.text("暂不开启")) { controller.disableAutomaticChecks() }
                        .buttonStyle(.bordered)
                }
            }

        case .enabled, .disabled:
            VStack(alignment: .leading, spacing: 6) {
                Toggle(AppLocalization.text("打开菜单时自动检查"), isOn: automaticCheckBinding)
                privacyText
            }
        }
    }

    private var privacyText: some View {
        Text(AppLocalization.text("自动请求至少间隔 5 分钟，手动检查至少间隔 65 秒；不会上传按键、输入内容或音色设置。"))
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var resultContent: some View {
        if let release = controller.availableRelease {
            VStack(alignment: .leading, spacing: 6) {
                Label(
                    L10n.format("发现新版本 %@", release.version.description),
                    systemImage: "sparkles"
                )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(KeyboardVisualStyle.accentStrong)
                Button {
                    openURL(release.releaseURL)
                } label: {
                    Label(AppLocalization.text("前往 GitHub 下载"), systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.borderedProminent)
            }
        } else if let snapshot = controller.state.snapshot {
            switch snapshot.result {
            case .updateAvailable:
                EmptyView()
            case let .upToDate(version):
                Label(
                    L10n.format("已是最新版 %@", version.description),
                    systemImage: "checkmark.circle.fill"
                )
                    .foregroundStyle(.secondary)
                    .font(.caption)
            case let .installedVersionIsNewer(latestVersion):
                Label(
                    L10n.format(
                        "当前安装版本高于公开版本 %@",
                        latestVersion.description
                    ),
                    systemImage: "hammer.fill"
                )
                .foregroundStyle(.secondary)
                .font(.caption)
            }
        } else {
            Text(AppLocalization.text("尚未检查更新"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        if case let .failed(failure, _) = controller.state {
            failureLabel(failure)
        }
    }

    private var controls: some View {
        HStack {
            if controller.state.isChecking {
                ProgressView()
                    .controlSize(.small)
                Text(AppLocalization.text("正在检查…"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(AppLocalization.text("检查更新")) { controller.checkManually() }
                .buttonStyle(.bordered)
                .disabled(controller.state.isChecking)
        }
    }

    @ViewBuilder
    private func failureLabel(_ failure: UpdateCheckFailure) -> some View {
        switch failure {
        case .offline:
            Label(AppLocalization.text("当前离线，稍后可重试"), systemImage: "wifi.slash")
                .failureCaptionStyle()
        case .timedOut:
            Label(AppLocalization.text("连接 GitHub 超时，稍后可重试"), systemImage: "clock.badge.exclamationmark")
                .failureCaptionStyle()
        case let .requestedTooSoon(retryAt):
            Label {
                Text(
                    L10n.format(
                        "刚刚检查过，可于 %@ 后再次手动检查",
                        retryAt.formatted(
                            .dateTime.hour().minute().locale(L10n.locale)
                        )
                    )
                )
            } icon: {
                Image(systemName: "clock.arrow.circlepath")
            }
            .failureCaptionStyle()
        case let .rateLimited(retryAt):
            Label {
                Text(
                    L10n.format(
                        "GitHub 暂时限制请求，可于 %@ 后重试",
                        retryAt.formatted(
                            .dateTime.hour().minute().locale(L10n.locale)
                        )
                    )
                )
            } icon: {
                Image(systemName: "hourglass")
            }
            .failureCaptionStyle()
        case .noPublishedRelease:
            Label(AppLocalization.text("GitHub 上暂时没有公开版本"), systemImage: "shippingbox")
                .failureCaptionStyle()
        case .apiVersionRetired:
            Label(AppLocalization.text("更新服务需要升级，请稍后手动查看 GitHub"), systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                .failureCaptionStyle()
        case .invalidInstalledVersion, .invalidResponse:
            Label(AppLocalization.text("版本信息格式异常"), systemImage: "exclamationmark.triangle")
                .failureCaptionStyle()
        case .serverUnavailable:
            Label(AppLocalization.text("暂时无法连接 GitHub，稍后可重试"), systemImage: "network.slash")
                .failureCaptionStyle()
        }
    }

    private var automaticCheckBinding: Binding<Bool> {
        Binding(
            get: { controller.automaticCheckPreference == .enabled },
            set: { enabled in
                if enabled {
                    controller.enableAutomaticChecks()
                } else {
                    controller.disableAutomaticChecks()
                }
            }
        )
    }

}

private extension View {
    func failureCaptionStyle() -> some View {
        font(.caption2)
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
    }
}

#if DEBUG
private let previewRelease = try! ReleaseSummary(
    tagName: "v0.4.0",
    releaseURL: URL(string: "https://github.com/wzz6423/zisla/releases/tag/v0.4.0")!,
    publishedAt: Date()
)

#Preview("首次授权") {
    UpdateSection(
        controller: .preview(
            state: .idle(cached: nil),
            preference: .undecided
        )
    )
    .padding()
    .frame(width: 340)
}

#Preview("发现更新") {
    UpdateSection(
        controller: .preview(
            state: .completed(
                UpdateCheckSnapshot(
                    result: .updateAvailable(previewRelease),
                    checkedAt: Date()
                )
            )
        )
    )
    .padding()
    .frame(width: 340)
}

#Preview("离线") {
    UpdateSection(
        controller: .preview(
            state: .failed(.offline, cached: nil)
        )
    )
    .padding()
    .frame(width: 340)
}
#endif
