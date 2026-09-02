import ZislaCore
import ZislaKit
import SwiftUI

struct ToolboxModuleView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var pomodoro: PomodoroService
    @ObservedObject private var settingsStore: FeatureSettingsStore
    private let onTransientInteractionChanged: (Bool) -> Void
    @State private var isDurationPickerPresented = false
    @State private var isAlarmEditorPresented = false

    private enum Metrics {
        static let controlHeight: CGFloat = 40
        static let toolContentHeight: CGFloat = 136
    }

    init(
        model: AppModel,
        onTransientInteractionChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        _model = ObservedObject(wrappedValue: model)
        _pomodoro = ObservedObject(wrappedValue: model.pomodoro)
        _settingsStore = ObservedObject(wrappedValue: model.settingsStore)
        self.onTransientInteractionChanged = onTransientInteractionChanged
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

    private var startPauseButtonShape: UnevenRoundedRectangle {
        IslandSurfaceGeometry.moduleContentShape(
            bottomLeadingRadius: IslandSurfaceGeometry.nestedBottomCornerRadius(inset: 10)
        )
    }

    private var focusPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Text(pomodoro.mode.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }

            Spacer(minLength: 0)
            durationDisplay
                .frame(maxWidth: .infinity, alignment: .center)
            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Button {
                    pomodoro.toggleStartPause()
                } label: {
                    Text(startPauseTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: Metrics.controlHeight)
                        .contentShape(startPauseButtonShape)
                }
                .buttonStyle(.plain)
                .background(Color.fillCard)
                .clipShape(startPauseButtonShape)
                .help(startPauseTitle)

                Button {
                    pomodoro.reset()
                } label: {
                    Text("重置")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: Metrics.controlHeight)
                        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .background(Color.fillControl)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .help("重置番茄钟")
            }
            .frame(maxWidth: .infinity)
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
        VStack(spacing: 8) {
            toolTogglesRow

            HStack(spacing: 8) {
                Button {
                    model.startScreenCleaning()
                } label: {
                    Label("清理屏幕", systemImage: "rectangle.dashed")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: Metrics.controlHeight)
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
                        .frame(height: Metrics.controlHeight)
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

                ToolShortcutButton(
                    title: "闹钟",
                    symbol: "alarm",
                    help: "管理闹钟"
                ) {
                    onTransientInteractionChanged(true)
                    isAlarmEditorPresented = true
                }
                .popover(isPresented: $isAlarmEditorPresented, arrowEdge: .bottom) {
                    AlarmEditorView(service: model.alarms)
                }
            }

            HStack(spacing: 8) {
                ToolShortcutButton(
                    title: "提词器",
                    symbol: "text.viewfinder",
                    help: "打开提词器"
                ) {
                    model.presentTeleprompter()
                }

                ToolShortcutButton(
                    title: "镜子",
                    symbol: "camera.viewfinder",
                    help: "打开摄像头镜子"
                ) {
                    model.presentMirror()
                }

                ToolShortcutButton(
                    title: "废纸篓",
                    symbol: "trash",
                    help: "清空废纸篓（不可撤销，会先确认）",
                    bottomTrailingRadius: IslandSurfaceGeometry.moduleOuterBottomCornerRadius
                ) {
                    model.emptyTrash()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .onChange(of: isAlarmEditorPresented) { _, presented in
            if !presented {
                onTransientInteractionChanged(false)
            }
        }
        .onDisappear {
            onTransientInteractionChanged(false)
        }
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
        let duration = TimeInterval(Self.durationSeconds(
            hours: hours,
            minutes: minutes,
            seconds: seconds
        ))
        if pomodoro.mode == .focus {
            pomodoro.setFocusDuration(duration)
        } else {
            pomodoro.setRestDuration(duration)
        }
    }

    static let maximumDurationSeconds = Int.max / 2

    static func durationSeconds(hours: Int, minutes: Int, seconds: Int) -> Int {
        let (hourSeconds, hourOverflow) = max(0, hours).multipliedReportingOverflow(by: 3_600)
        let (minuteSeconds, minuteOverflow) = max(0, minutes).multipliedReportingOverflow(by: 60)
        let (hourAndMinutes, hourAndMinutesOverflow) = hourSeconds.addingReportingOverflow(minuteSeconds)
        let (totalSeconds, totalOverflow) = hourAndMinutes.addingReportingOverflow(max(0, seconds))
        guard !hourOverflow, !minuteOverflow, !hourAndMinutesOverflow, !totalOverflow else {
            return maximumDurationSeconds
        }
        return min(maximumDurationSeconds, max(1, totalSeconds))
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
                title: "防止空闲休眠",
                symbol: "laptopcomputer",
                isOn: model.powerAssertions.preventIdleSystemSleep,
                help: "防止用户闲置导致系统休眠；合盖、低电量或用户主动休眠仍会让 Mac 进入睡眠"
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
                    .lineLimit(1)
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
