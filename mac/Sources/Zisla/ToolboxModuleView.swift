import ZislaCore
import ZislaKit
import SwiftUI

struct ToolboxModuleView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var pomodoro: PomodoroService
    @State private var isDurationPickerPresented = false

    init(model: AppModel) {
        _model = ObservedObject(wrappedValue: model)
        _pomodoro = ObservedObject(wrappedValue: model.pomodoro)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            focusPanel
            toolActions
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var focusPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(pomodoro.mode.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            Spacer(minLength: 12)

            durationDisplay
                .frame(maxWidth: .infinity, alignment: .center)

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                Button {
                    pomodoro.toggleStartPause()
                } label: {
                    Label(
                        startPauseTitle,
                        systemImage: startPauseSymbol
                    )
                    .font(.system(size: 11, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .background(Color.fillCard)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .help(startPauseTitle)

                Button {
                    pomodoro.reset()
                } label: {
                    Label("重置", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .background(Color.fillControl)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .help("重置番茄钟")
            }
        }
        .padding(10)
        .frame(width: 236)
        .frame(maxHeight: .infinity)
        .background(Color.fillCard)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.strokeCard, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var durationDisplay: some View {
        if pomodoro.phase == .idle {
            Button {
                isDurationPickerPresented.toggle()
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(pomodoro.displayClock)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .help("设置时长")
            .popover(isPresented: $isDurationPickerPresented, arrowEdge: .top) {
                HStack(spacing: 8) {
                    durationInput("小时", value: durationHours)
                    Text("小时")
                        .foregroundStyle(.secondary)

                    durationInput("分钟", value: durationMinutes)
                    Text("分")
                        .foregroundStyle(.secondary)

                    durationInput("秒", value: durationSeconds)
                    Text("秒")
                        .foregroundStyle(.secondary)
                }
                .padding(12)
            }
        } else {
            Text(pomodoro.displayClock)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
    }

    private var toolActions: some View {
        VStack(spacing: 24) {
            toolTogglesRow
            cleaningRow
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var currentDuration: TimeInterval {
        let seconds = pomodoro.mode == .focus
            ? pomodoro.focusDuration
            : pomodoro.restDuration
        return max(1, seconds)
    }

    private var durationHours: Binding<Int> {
        Binding(
            get: { Int(currentDuration) / 3_600 },
            set: {
                setDuration(
                    hours: $0,
                    minutes: durationMinutes.wrappedValue,
                    seconds: durationSeconds.wrappedValue
                )
            }
        )
    }

    private var durationMinutes: Binding<Int> {
        Binding(
            get: { Int(currentDuration / 60) % 60 },
            set: {
                setDuration(
                    hours: durationHours.wrappedValue,
                    minutes: $0,
                    seconds: durationSeconds.wrappedValue
                )
            }
        )
    }

    private var durationSeconds: Binding<Int> {
        Binding(
            get: { Int(currentDuration) % 60 },
            set: {
                setDuration(
                    hours: durationHours.wrappedValue,
                    minutes: durationMinutes.wrappedValue,
                    seconds: $0
                )
            }
        )
    }

    private func durationInput(_ title: String, value: Binding<Int>) -> some View {
        TextField(title, value: value, format: .number)
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .frame(width: 44)
    }

    private func setDuration(hours: Int, minutes: Int, seconds: Int) {
        let totalSeconds = max(1, max(0, hours) * 3_600 + max(0, minutes) * 60 + max(0, seconds))
        let duration = TimeInterval(totalSeconds)
        if pomodoro.mode == .focus {
            pomodoro.setFocusDuration(duration)
        } else {
            pomodoro.setRestDuration(duration)
        }
    }

    private var startPauseTitle: String {
        switch pomodoro.phase {
        case .running: "暂停"
        case .idle, .paused: "开始"
        }
    }

    private var startPauseSymbol: String {
        switch pomodoro.phase {
        case .running: "pause.fill"
        case .idle, .paused: "play.fill"
        }
    }

    private var toolTogglesRow: some View {
        HStack(spacing: 8) {
            ToolToggleButton(
                title: "保持亮屏",
                symbol: "sun.max.fill",
                isOn: model.powerAssertions.keepDisplayAwake,
                help: "防止用户闲置导致显示器休眠"
            ) {
                model.powerAssertions.setKeepDisplayAwake(!model.powerAssertions.keepDisplayAwake)
            }

            ToolToggleButton(
                title: "合盖不熄屏",
                symbol: "laptopcomputer",
                isOn: model.powerAssertions.preventIdleSystemSleep,
                help: PowerAssertionController.clamshellLimitationHint
            ) {
                model.powerAssertions.setPreventIdleSystemSleep(!model.powerAssertions.preventIdleSystemSleep)
            }

            ToolToggleButton(
                title: "常驻提醒",
                symbol: "pin.fill",
                isOn: model.settingsStore.settings.toolboxReminderEnabled,
                help: "无媒体占用时，在折叠状态显示番茄钟、亮屏或清洁状态",
                isDisabled: !model.settingsStore.settings.sideNoticesEnabled
            ) {
                model.settingsStore.settings.toolboxReminderEnabled.toggle()
            }
        }
    }

    private var cleaningRow: some View {
        HStack(spacing: 8) {
            Button {
                model.startScreenCleaning()
            } label: {
                Label("清理屏幕", systemImage: "rectangle.dashed")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .background(Color.fillCard)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .help("全屏黑色遮罩；点击中央「退出清屏」按钮或任意处退出")

            Button {
                if model.screenCleaning.isKeyboardCleaning {
                    model.screenCleaning.endKeyboardCleaning()
                } else {
                    model.startKeyboardCleaning()
                }
            } label: {
                Label(
                    model.screenCleaning.isKeyboardCleaning ? "结束清洁" : "清理键盘",
                    systemImage: "keyboard"
                )
                    .font(.system(size: 11, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .background(Color.fillCard)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .help(
                model.screenCleaning.isKeyboardCleaning
                    ? "恢复键盘输入"
                    : "吞掉键盘输入；再次点击结束"
            )
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
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                    .background(isOn ? Color.accentColor.opacity(0.2) : Color.fillControl)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isDisabled)
            .help(help)
        }
    }
}
