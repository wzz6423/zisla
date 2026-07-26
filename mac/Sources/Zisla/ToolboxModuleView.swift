import ZislaCore
import ZislaKit
import SwiftUI

struct ToolboxModuleView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var pomodoro: PomodoroService
    @ObservedObject private var settingsStore: FeatureSettingsStore
    @State private var isDurationPickerPresented = false
    @State private var isAlarmEditorPresented = false

    private enum Metrics {
        static let controlHeight: CGFloat = 40
        static let shortcutWidth: CGFloat = 64
        static let shortcutHeight: CGFloat = 88
        static let toolContentHeight = shortcutHeight * 2 + 8
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
        .frame(width: 236, height: Metrics.toolContentHeight)
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
        HStack(alignment: .top, spacing: 8) {
            VStack(spacing: 8) {
                toolTogglesRow
                islandBehaviorRow
                cleaningRow
                desktopRow
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    ToolShortcutButton(
                        title: "提词器",
                        symbol: "text.viewfinder",
                        help: "打开提词器"
                    ) {
                        model.presentTeleprompter()
                    }

                    ToolShortcutButton(
                        title: "闹钟",
                        symbol: "alarm",
                        help: "管理闹钟"
                    ) {
                        isAlarmEditorPresented = true
                    }
                    .popover(isPresented: $isAlarmEditorPresented, arrowEdge: .bottom) {
                        AlarmEditorView(service: model.alarms)
                    }
                }

                HStack(spacing: 8) {
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
                        help: "清空废纸篓（不可撤销，会先确认）"
                    ) {
                        model.emptyTrash()
                    }
                }
            }
            .frame(width: 136)
        }
        .frame(maxWidth: .infinity, alignment: .top)
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
                title: "防止空闲休眠",
                symbol: "laptopcomputer",
                isOn: model.powerAssertions.preventIdleSystemSleep,
                help: "防止用户闲置导致系统休眠；合盖、低电量或用户主动休眠仍会让 Mac 进入睡眠"
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
        }
    }

    /// Collapsed-state window level and notification muting: both write directly to settings; AppModel / ZislaApp subscribes and applies.
    private var islandBehaviorRow: some View {
        HStack(spacing: 8) {
            ToolToggleButton(
                title: model.settingsStore.settings.islandCollapsedOnTop ? "收起置顶" : "收起置底",
                symbol: model.settingsStore.settings.islandCollapsedOnTop
                    ? "square.3.layers.3d.top.filled"
                    : "square.3.layers.3d.bottom.filled",
                isOn: model.settingsStore.settings.islandCollapsedOnTop,
                help: "收起态压在其他窗口之上（置顶），或被其他窗口和菜单栏图标覆盖（置底）"
            ) {
                model.settingsStore.settings.islandCollapsedOnTop.toggle()
            }

            ToolToggleButton(
                title: "屏蔽通知",
                symbol: model.settingsStore.settings.notificationsMuted
                    ? "bell.slash.fill"
                    : "bell.fill",
                isOn: model.settingsStore.settings.notificationsMuted,
                help: "临时不再推送 Zisla 的系统通知；关闭后恢复正常推送（闹钟不受影响）"
            ) {
                model.settingsStore.settings.notificationsMuted.toggle()
            }
        }
    }

    private var desktopRow: some View {
        HStack(spacing: 8) {
            ToolActionButton(
                title: "整理桌面",
                symbol: "square.grid.3x3",
                help: "按网格对齐桌面图标；已开启「叠放」时不动任何文件"
            ) {
                model.tidyDesktop()
            }

            ToolActionButton(
                title: "更新",
                subtitle: "App Store 应用",
                symbol: "arrow.down.app",
                help: "批量升级 App Store 应用；未安装 mas 时打开 App Store 更新页"
            ) {
                model.updateAppStoreApps()
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

    /// One-shot action button matching the style of `cleaningRow` buttons — no toggle state.
    private struct ToolActionButton: View {
        let title: String
        let subtitle: String?
        let symbol: String
        let help: String
        let action: () -> Void

        init(
            title: String,
            subtitle: String? = nil,
            symbol: String,
            help: String,
            action: @escaping () -> Void
        ) {
            self.title = title
            self.subtitle = subtitle
            self.symbol = symbol
            self.help = help
            self.action = action
        }

        var body: some View {
            Button(action: action) {
                HStack(spacing: 6) {
                    Image(systemName: symbol)
                    if let subtitle {
                        VStack(alignment: .center, spacing: 0) {
                            Text(title)
                            Text(subtitle)
                        }
                        .lineLimit(1)
                        .multilineTextAlignment(.center)
                    } else {
                        Text(title)
                            .lineLimit(1)
                    }
                }
                    .font(.system(size: 11, weight: .semibold))
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity)
                    .frame(height: Metrics.controlHeight)
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .background(Color.fillCard)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .help(help)
        }
    }

    private struct ToolShortcutButton: View {
        let title: String
        let symbol: String
        let help: String
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                VStack(spacing: 5) {
                    Image(systemName: symbol)
                        .font(.system(size: 18, weight: .semibold))
                    Text(title)
                        .font(.islandMicro(weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(width: Metrics.shortcutWidth, height: Metrics.shortcutHeight)
                .background(Color.fillCard)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.strokeCard, lineWidth: 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .help(help)
        }
    }
}
