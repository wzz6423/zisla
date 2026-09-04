import AppKit
import SwiftUI
import ZislaCore
import ZislaKit

struct MenuBarView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @ObservedObject private var model: KeyboardAppModel
    private let settings: AppSettings
    @ObservedObject private var permission: InputMonitoringPermissionManager

    init(model: KeyboardAppModel) {
        _model = ObservedObject(wrappedValue: model)
        settings = model.settings
        _permission = ObservedObject(wrappedValue: model.permission)
    }

    var body: some View {
        VStack(spacing: 0) {
            MenuBarHeader(model: model, settings: settings)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

            KeyboardVisualStyle.separator.opacity(0.65).frame(height: 1)

            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(spacing: 12) {
                        Color.clear
                            .frame(height: 1)
                            .id("keyboard-menu-top")

                if !permission.isGranted {
                    permissionCard
                }

                if let message = monitoringFailureMessage {
                    monitoringFailureCard(message)
                }

                if !audioFailures.isEmpty {
                    audioFailureCard(audioFailures)
                }

                TypingStatsSummarySection(
                    model: model.typingStats,
                    settings: settings
                ) {
                    model.openTypingStats()
                    dismiss()
                }

                KeyboardSoundSection(
                    model: model,
                    settings: settings,
                    onOpenEditor: {
                        model.openSoundPackEditor()
                        dismiss()
                    }
                )
                PointerSoundSection(settings: settings)
                InterfacePreferencesSection(settings: settings)
                LaunchAtLoginSection(
                    settings: settings,
                    controller: model.launchAtLogin,
                    onRetry: model.retryLaunchAtLogin,
                    onOpenSettings: {
                        model.openLoginItemsSettings()
                        dismiss()
                    }
                )
                UpdateSection(controller: model.updates)
                    }
                    .padding(14)
                }
                .onAppear {
                    model.launchAtLogin.refresh()
                    DispatchQueue.main.async {
                        proxy.scrollTo("keyboard-menu-top", anchor: .top)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                        proxy.scrollTo("keyboard-menu-top", anchor: .top)
                    }
                }
            }

            KeyboardVisualStyle.separator.opacity(0.65).frame(height: 1)

            MenuBarFooter(model: model) {
                dismiss()
            }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        .keyboardWindowGlass()
        .frame(width: 360)
        // MenuBarExtra can propose a near-zero height to a root ScrollView.
        // Keep a real sizing range so AppKit cannot collapse the popover to
        // only its scroller when the content becomes taller.
        .frame(minHeight: 560, idealHeight: 760, maxHeight: 820)
        .tint(KeyboardVisualStyle.actionAccent)
        .environment(\.locale, locale)
    }

    private func monitoringFailureCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(AppLocalization.text("键盘与点击监听未启动"), systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
            Text(L10n.tr(message))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(AppLocalization.text("重试输入监听")) { model.retryKeyboardMonitor() }
                .buttonStyle(.bordered)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .keyboardTintedPanel(.red, radius: 12)
    }

    private func audioFailureCard(_ failures: [(module: String, message: String)]) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(AppLocalization.text("声音暂时不可用"), systemImage: "speaker.slash.fill")
                .font(.subheadline.weight(.semibold))
            ForEach(failures, id: \.module) { failure in
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.tr(failure.module))
                        .font(.caption.weight(.semibold))
                    Text(L10n.tr(failure.message))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .keyboardTintedPanel(.orange, radius: 12)
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(AppLocalization.text("需要输入监控权限"), systemImage: "keyboard.badge.eye")
                .font(.subheadline.weight(.semibold))
            Text(AppLocalization.text("Keyboard 使用按键编号播放声音，并可在你主动开启后于本机统计字符数量、物理按键次数和前台应用；不读取或保存文字、点击位置或输入内容。"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(AppLocalization.text("如果系统开关已经打开但这里仍显示等待，请选中旧的 Zisla 条目，点列表下方“−”删除，再重新添加 /Applications/Zisla.app。完成后退出并重新打开应用。"))
                .font(.caption2)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(AppLocalization.text("请求授权")) {
                    model.requestInputMonitoring()
                    if !permission.isGranted {
                        model.openInputMonitoringSettings()
                    }
                    dismiss()
                }
                    .buttonStyle(.borderedProminent)
                Button(AppLocalization.text("打开系统设置")) {
                    model.openInputMonitoringSettings()
                    dismiss()
                }
                    .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .keyboardTintedPanel(.orange, opacity: 0.10, radius: 12)
    }

    private var monitoringFailureMessage: String? {
        guard case let .failed(message) = model.monitoringState else { return nil }
        return message
    }

    private var audioFailures: [(module: String, message: String)] {
        var failures: [(module: String, message: String)] = []
        if let message = model.audioError {
            failures.append(("键盘声音", message))
        }
        if let message = model.pointerSoundError {
            failures.append(("鼠标与触控板", message))
        }
        if let message = model.soundPackError {
            failures.append(("DIY 音色包", message))
        }
        return failures
    }

}

private struct MenuBarHeader: View {
    @ObservedObject var model: KeyboardAppModel
    @ObservedObject var settings: AppSettings

    var body: some View {
        HStack(spacing: 10) {
            KeyboardApplicationIcon(size: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text("Keyboard")
                    .font(.headline.weight(.semibold))
                Text(L10n.tr(statusText))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .overlay(Circle().stroke(statusColor.opacity(0.25), lineWidth: 4))
                .help(L10n.tr(statusText))
        }
        .padding(.horizontal, 2)
        .padding(.bottom, 2)
    }

    private var statusText: String {
        switch model.monitoringState {
        case .running:
            if !settings.isTypingStatsEnabled {
                switch (settings.isEnabled, settings.isPointerSoundEnabled) {
                case (true, true): return "正在监听键盘与点击 · 统计已暂停"
                case (true, false): return "正在监听键盘 · 统计已暂停"
                case (false, true): return "点击音已开启 · 统计已暂停"
                case (false, false): return "声音与统计均已暂停"
                }
            }
            switch (settings.isEnabled, settings.isPointerSoundEnabled) {
            case (true, true): return "正在监听键盘与点击 · 统计已开启"
            case (true, false): return "正在监听键盘 · 统计已开启"
            case (false, true): return "正在统计输入 · 点击音已开启"
            case (false, false): return "正在统计输入 · 声音已暂停"
            }
        case .waitingForPermission: return "等待输入监控授权"
        case .failed: return "键盘与点击监听启动失败"
        case .stopped: return "键盘与点击监听已停止"
        }
    }

    private var statusColor: Color {
        switch model.monitoringState {
        case .running: KeyboardVisualStyle.accentStrong
        case .waitingForPermission: .orange
        case .failed: .red
        case .stopped: .secondary
        }
    }
}

private struct KeyboardSoundSection: View {
    @ObservedObject var model: KeyboardAppModel
    @ObservedObject var settings: AppSettings
    let onOpenEditor: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                KeyboardSectionHeading(
                    "键盘声音".localized,
                    subtitle: L10n.tr(model.selectedSoundPack.tone),
                    symbol: "keyboard.fill"
                )
                Spacer()
                Toggle(AppLocalization.text("启用键盘声音"), isOn: $settings.isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .accessibilityLabel(AppLocalization.text("启用键盘声音"))
                    .help(AppLocalization.text("启用或暂停键盘声音"))
            }

            Picker(AppLocalization.text("轴体音色"), selection: $settings.selectedProfileID) {
                ForEach(model.soundPacks) { soundPack in
                    Text(L10n.format("%@ · %@", soundPack.name, L10n.tr(soundPack.family)))
                        .tag(soundPack.id)
                }
            }
            .pickerStyle(.menu)
            .disabled(!settings.isEnabled)

            HStack(spacing: 8) {
                Button {
                    model.preview()
                } label: {
                    Label(AppLocalization.text("试听"), systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!settings.isEnabled)

                Button(action: onOpenEditor) {
                    Label(AppLocalization.text("DIY 音色"), systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.bordered)

                Spacer()

                Text(L10n.tr(model.selectedSoundPack.family))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(AppLocalization.text("键盘音量"))
                    Spacer()
                    Text("\(Int(settings.volume * 100))%")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(value: $settings.volume, in: 0...1, step: 0.01)
                    .accessibilityLabel(AppLocalization.text("键盘音量"))
            }
            .disabled(!settings.isEnabled)

            Toggle(AppLocalization.text("播放键盘回弹音"), isOn: $settings.playsReleaseSound)
                .disabled(!settings.isEnabled)
            Toggle(AppLocalization.text("自然音色变化（键盘轮换 / 点击音高）"), isOn: $settings.usesPitchVariation)
                .help(AppLocalization.text("键盘在四种轻微变化间轮换；点击音使用轻微随机音高"))
        }
        .font(.subheadline)
        .padding(KeyboardVisualStyle.cardPadding)
        .keyboardPanel()
    }
}

private struct MenuBarFooter: View {
    @Environment(\.locale) private var locale
    @ObservedObject var model: KeyboardAppModel
    let onDismiss: () -> Void

    var body: some View {
        let status = statusPresentation
        HStack {
            Label(L10n.tr(status.text), systemImage: status.symbol)
                .font(.caption2)
                .foregroundStyle(status.color)

            Spacer()
            Button(AppLocalization.text("收起"), action: onDismiss)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            Button(AppLocalization.text("退出")) { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .environment(\.locale, locale)
    }

    private var statusPresentation: (text: String, symbol: String, color: Color) {
        switch model.monitoringState {
        case .running:
            return ("输入监控正在运行", "checkmark.shield.fill", .secondary)
        case .waitingForPermission:
            return ("等待授权", "exclamationmark.shield.fill", .orange)
        case .failed:
            return ("监听启动失败", "xmark.shield.fill", .red)
        case .stopped:
            return ("监听已停止", "pause.circle.fill", .secondary)
        }
    }
}

private struct InterfacePreferencesSection: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            KeyboardSectionHeading(
                "界面",
                subtitle: "语言与外观",
                symbol: "paintbrush.pointed"
            )

            Text(AppLocalization.text("首次安装默认跟随系统，可在这里单独覆盖语言和外观。"))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            preferenceRow("语言") {
                Picker(AppLocalization.text("语言"), selection: $settings.languagePreference) {
                    ForEach(AppLanguagePreference.allCases) { preference in
                        Text(preference.displayName).tag(preference)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 156)
                .accessibilityLabel(L10n.tr("语言"))
            }

            preferenceRow("外观") {
                Picker(AppLocalization.text("外观"), selection: $settings.appearancePreference) {
                    ForEach(AppAppearancePreference.allCases) { preference in
                        Text(L10n.tr(preference.displayNameKey)).tag(preference)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 156)
                .accessibilityLabel(L10n.tr("外观"))
            }
        }
        .font(.subheadline)
        .padding(KeyboardVisualStyle.cardPadding)
        .keyboardPanel()
    }

    private func preferenceRow<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 12) {
            Text(L10n.tr(title))
            Spacer(minLength: 12)
            content()
        }
    }
}

private struct LaunchAtLoginSection: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var controller: LaunchAtLoginController
    let onRetry: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                KeyboardSectionHeading(
                    "启动".localized,
                    subtitle: "跟随用户登录".localized,
                    symbol: "power"
                )
                Spacer()
                Toggle(AppLocalization.text("登录时自动启动"), isOn: $settings.isLaunchAtLoginEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .accessibilityLabel(AppLocalization.text("登录时自动启动"))
            }

            Label(L10n.tr(statusText), systemImage: statusSymbol)
                .font(.caption)
                .foregroundStyle(statusColor)
                .fixedSize(horizontal: false, vertical: true)

            if shouldShowActions {
                HStack(spacing: 8) {
                    if shouldShowRetry {
                        Button(AppLocalization.text("重试")) { onRetry() }
                            .buttonStyle(.bordered)
                    }
                    if shouldShowSystemSettings {
                        Button(AppLocalization.text("打开登录项设置")) { onOpenSettings() }
                            .buttonStyle(.bordered)
                    }
                }
            }
        }
        .font(.subheadline)
        .padding(KeyboardVisualStyle.cardPadding)
        .keyboardPanel()
    }

    private var statusText: String {
        switch controller.state {
        case .disabled:
            return "已关闭；重新登录后不会自动启动。"
        case .enabled:
            return "已加入系统登录项，下次登录会自动启动。"
        case .requiresApproval:
            return "已经登记，但仍需在系统设置的“登录项”中允许。"
        case .notRegistered:
            return "尚未成功加入系统登录项，请重试。"
        case .needsApplicationInstall:
            return "请先把 Keyboard 移到“应用程序”文件夹，再打开应用完成自动登记。"
        case let .failed(message):
            return message
        }
    }

    private var statusSymbol: String {
        switch controller.state {
        case .enabled: return "checkmark.circle.fill"
        case .disabled: return "minus.circle"
        case .requiresApproval: return "exclamationmark.circle.fill"
        case .notRegistered, .needsApplicationInstall, .failed: return "xmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch controller.state {
        case .enabled, .disabled: return .secondary
        case .requiresApproval, .needsApplicationInstall: return .orange
        case .notRegistered, .failed: return .red
        }
    }

    private var shouldShowRetry: Bool {
        switch controller.state {
        case .notRegistered, .failed: true
        default: false
        }
    }

    private var shouldShowSystemSettings: Bool {
        switch controller.state {
        case .requiresApproval, .failed: true
        default: false
        }
    }

    private var shouldShowActions: Bool {
        shouldShowRetry || shouldShowSystemSettings
    }
}

private struct PointerSoundSection: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                KeyboardSectionHeading(
                    "鼠标与触控板".localized,
                    subtitle: settings.selectedPointerProfile.tone.localized,
                    symbol: "computermouse.fill"
                )
                Spacer()
                Toggle(AppLocalization.text("启用点击音"), isOn: $settings.isPointerSoundEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .accessibilityLabel(AppLocalization.text("启用鼠标与触控板点击音"))
            }

            Picker(AppLocalization.text("点击音色"), selection: $settings.selectedPointerProfileID) {
                ForEach(PointerSoundProfile.allCases) { profile in
                    Text(L10n.format("%@ · %@", profile.displayName, profile.family))
                        .tag(profile.rawValue)
                }
            }
            .pickerStyle(.menu)
            .disabled(!settings.isPointerSoundEnabled)

            HStack {
                Text(settings.selectedPointerProfile.family.localized)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle(AppLocalization.text("播放抬起音"), isOn: $settings.playsPointerReleaseSound)
                    .disabled(!settings.isPointerSoundEnabled)
                    .toggleStyle(.checkbox)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(AppLocalization.text("点击音量"))
                    Spacer()
                    Text("\(Int(settings.pointerVolume * 100))%")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(value: $settings.pointerVolume, in: 0...1, step: 0.01)
                    .accessibilityLabel(AppLocalization.text("鼠标与触控板点击音量"))
                    .disabled(!settings.isPointerSoundEnabled)
            }

            Text(AppLocalization.text("触控板轻点、物理点按和鼠标点击共用此配置；点击音量独立于键盘音量。"))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.subheadline)
        .padding(KeyboardVisualStyle.cardPadding)
        .keyboardPanel()
    }
}

#Preview {
    MenuBarView(model: KeyboardAppModel(startsServices: false))
}
