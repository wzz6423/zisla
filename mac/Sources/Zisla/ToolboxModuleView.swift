import ZislaCore
import ZislaKit
import SwiftUI

struct ToolboxModuleView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var pomodoro: PomodoroService
    @ObservedObject private var settingsStore: FeatureSettingsStore

    private enum Metrics {
        static let controlHeight: CGFloat = 40
        static let toolContentHeight: CGFloat = 136
    }

    init(model: AppModel) {
        _model = ObservedObject(wrappedValue: model)
        _pomodoro = ObservedObject(wrappedValue: model.pomodoro)
        _settingsStore = ObservedObject(wrappedValue: model.settingsStore)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            focusPanel
            toolActions
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var focusPanelShape: UnevenRoundedRectangle {
        IslandSurfaceGeometry.moduleContentShape(
            bottomLeadingRadius: IslandSurfaceGeometry.moduleOuterBottomCornerRadius
        )
    }

    private var openClockButtonShape: UnevenRoundedRectangle {
        IslandSurfaceGeometry.moduleContentShape(
            bottomLeadingRadius: IslandSurfaceGeometry.nestedBottomCornerRadius(inset: 10)
        )
    }

    private var focusPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Text(AppLocalization.text("专注倒计时"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }

            Spacer(minLength: 0)
            Group {
                if pomodoro.phase == .idle {
                    Image(systemName: "timer")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                } else {
                    Text(pomodoro.displayClock)
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                }
            }
            .font(.system(size: 26, weight: .semibold, design: .rounded))
            .frame(maxWidth: .infinity, alignment: .center)
            Spacer(minLength: 0)

            Button {
                Task {
                    do {
                        try await SystemClockService.open(.timer)
                    } catch {
                        model.transientMessage = error.localizedDescription
                    }
                }
            } label: {
                Text(AppLocalization.text("打开时钟"))
                    .font(.system(size: 11, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: Metrics.controlHeight)
                    .contentShape(openClockButtonShape)
            }
            .buttonStyle(.plain)
            .background(Color.fillCard)
            .clipShape(openClockButtonShape)
            .help(AppLocalization.text("打开系统「时钟」App"))
        }
        .padding(10)
        .frame(width: 236, height: Metrics.toolContentHeight)
        .background(Color.fillCard)
        .clipShape(focusPanelShape)
        .overlay {
            focusPanelShape
                .strokeBorder(Color.strokeCard, lineWidth: 1)
        }
    }

    private var toolActions: some View {
        VStack(spacing: 8) {
            toolTogglesRow

            HStack(spacing: 8) {
                Button {
                    model.startScreenCleaning()
                } label: {
                    Label(AppLocalization.text("清理屏幕"), systemImage: "rectangle.dashed")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: Metrics.controlHeight)
                        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .background(Color.fillCard)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .help(AppLocalization.text("全屏黑色遮罩；点击中央「退出清屏」按钮或任意处退出"))

                Button {
                    if model.screenCleaning.isKeyboardCleaning {
                        model.screenCleaning.endKeyboardCleaning()
                    } else {
                        model.startKeyboardCleaning()
                    }
                } label: {
                    Label(
                        model.screenCleaning.isKeyboardCleaning ? AppLocalization.text("结束清洁") : AppLocalization.text("清理键盘"),
                        systemImage: "keyboard"
                    )
                        .font(.system(size: 11, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: Metrics.controlHeight)
                        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .background(Color.fillCard)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .help(
                    model.screenCleaning.isKeyboardCleaning
                        ? AppLocalization.text("恢复键盘输入")
                        : AppLocalization.text("吞掉键盘输入；再次点击结束")
                )

                ToolShortcutButton(
                    title: AppLocalization.text("闹钟"),
                    symbol: "alarm",
                    help: AppLocalization.text("打开系统「时钟」App")
                ) {
                    Task {
                        do {
                            try await SystemClockService.open(.alarm)
                        } catch {
                            model.transientMessage = error.localizedDescription
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                ToolShortcutButton(
                    title: AppLocalization.text("提词器"),
                    symbol: "text.viewfinder",
                    help: AppLocalization.text("打开提词器")
                ) {
                    model.presentTeleprompter()
                }

                ToolShortcutButton(
                    title: AppLocalization.text("镜子"),
                    symbol: "camera.viewfinder",
                    help: AppLocalization.text("打开摄像头镜子")
                ) {
                    model.presentMirror()
                }

                ToolShortcutButton(
                    title: AppLocalization.text("废纸篓"),
                    symbol: "trash",
                    help: AppLocalization.text("清空废纸篓（不可撤销，会先确认）"),
                    bottomTrailingRadius: IslandSurfaceGeometry.moduleOuterBottomCornerRadius
                ) {
                    model.emptyTrash()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var toolTogglesRow: some View {
        HStack(spacing: 8) {
            ToolToggleButton(
                title: AppLocalization.text("保持亮屏"),
                symbol: "sun.max.fill",
                isOn: model.powerAssertions.keepDisplayAwake,
                help: AppLocalization.text("防止用户闲置导致显示器休眠")
            ) {
                model.powerAssertions.setKeepDisplayAwake(!model.powerAssertions.keepDisplayAwake)
            }

            ToolToggleButton(
                title: AppLocalization.text("防止空闲休眠"),
                symbol: "laptopcomputer",
                isOn: model.powerAssertions.preventIdleSystemSleep,
                help: AppLocalization.text("防止用户闲置导致系统休眠；合盖、低电量或用户主动休眠仍会让 Mac 进入睡眠")
            ) {
                model.powerAssertions.setPreventIdleSystemSleep(!model.powerAssertions.preventIdleSystemSleep)
            }

        }
    }

    private struct ToolToggleButton: View {
        let title: String
        let symbol: String
        let isOn: Bool
        let help: String
        let isDisabled: Bool
        let action: () -> Void

        init(
            title: String,
            symbol: String,
            isOn: Bool,
            help: String,
            isDisabled: Bool = false,
            action: @escaping () -> Void
        ) {
            self.title = title
            self.symbol = symbol
            self.isOn = isOn
            self.help = help
            self.isDisabled = isDisabled
            self.action = action
        }

        var body: some View {
            Button(action: action) {
                Label(title, systemImage: symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(
                        isDisabled
                            ? Color.secondary.opacity(0.5)
                            : (isOn ? Color.primary : Color.secondary)
                    )
                    .fitsSingleLine()
                    .frame(maxWidth: .infinity)
                    .frame(height: Metrics.controlHeight)
                    .background(isOn ? Color.accentColor.opacity(0.2) : Color.fillControl)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isDisabled)
            .help(help)
        }
    }

    private struct ToolShortcutButton: View {
        let title: String
        let symbol: String
        let help: String
        let bottomTrailingRadius: CGFloat
        let action: () -> Void

        init(
            title: String,
            symbol: String,
            help: String,
            bottomTrailingRadius: CGFloat = IslandSurfaceGeometry.moduleInnerCornerRadius,
            action: @escaping () -> Void
        ) {
            self.title = title
            self.symbol = symbol
            self.help = help
            self.bottomTrailingRadius = bottomTrailingRadius
            self.action = action
        }

        private var shape: UnevenRoundedRectangle {
            IslandSurfaceGeometry.moduleContentShape(bottomTrailingRadius: bottomTrailingRadius)
        }

        var body: some View {
            Button(action: action) {
                Label(title, systemImage: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: Metrics.controlHeight)
                    .contentShape(shape)
            }
            .buttonStyle(.plain)
            .background(Color.fillCard)
            .clipShape(shape)
            .accessibilityLabel(title)
            .help(help)
        }
    }
}
