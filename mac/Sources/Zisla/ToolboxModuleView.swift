import ZislaCore
import ZislaKit
import SwiftUI

struct ToolboxModuleView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var pomodoro: PomodoroService
    @ObservedObject private var immediateCleanup: ImmediateCleanupController

    private enum Metrics {
        static let controlHeight: CGFloat = 40
        static let toolContentHeight: CGFloat = 136
    }

    init(model: AppModel) {
        _model = ObservedObject(wrappedValue: model)
        _pomodoro = ObservedObject(wrappedValue: model.pomodoro)
        _immediateCleanup = ObservedObject(wrappedValue: model.immediateCleanup)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            timerPanel
            toolActions
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var timerPanel: some View {
        ToolboxTimerPanel(service: pomodoro)
            .frame(height: Metrics.toolContentHeight)
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
                    title: AppLocalization.text("清理垃圾"),
                    symbol: "arrow.3.trianglepath",
                    help: AppLocalization.text("立即清理")
                ) {
                    immediateCleanup.start(settings: model.settingsStore.settings)
                }
                .disabled(immediateCleanup.isRunning || !ImmediateCleanupController.canCleanNow(settings: model.settingsStore.settings))

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

    private var toolTogglesRow: some View {
        HStack(spacing: 8) {
            ToolToggleButton(
                title: AppLocalization.text(model.powerAssertions.isChangingDisplayAwake ? "正在处理…" : "保持亮屏"),
                symbol: "sun.max.fill",
                isOn: model.powerAssertions.keepDisplayAwake,
                help: AppLocalization.text("包括合盖时保持亮屏；需要管理员授权，关闭后恢复原有休眠设置。"),
                isDisabled: model.powerAssertions.isChangingDisplayAwake
            ) {
                Task {
                    await model.powerAssertions.setKeepDisplayAwakeIncludingLidClose(!model.powerAssertions.keepDisplayAwake)
                }
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
                    .fitsSingleLine()
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

struct ToolboxTimerPanel: View {
    @ObservedObject var service: PomodoroService
    private var timerIDs: [UUID?] { [nil] + service.countdowns.map { $0.id } }

    var body: some View {
        let timerIDs = self.timerIDs
        ScrollView(.vertical) {
            LazyVStack(spacing: 6) {
                ForEach(Array(stride(from: 0, to: timerIDs.count, by: 2)), id: \.self) { index in
                    HStack(spacing: 6) {
                        ForEach(timerIDs[index..<min(index + 2, timerIDs.count)], id: \.self) { timerID in
                            ToolboxTimerCard(service: service, timerID: timerID, compact: timerIDs.count > 1)
                        }
                    }
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .thinScrollChrome(scrollerStyle: .overlay)
        .accessibilityIdentifier("toolbox.timers")
        .frame(width: 236)
        .overlay(alignment: .topTrailing) {
            IconButton(symbol: "plus", help: AppLocalization.text("添加计时器"), size: .compact) {
                service.addCountdown()
            }
            .accessibilityLabel(AppLocalization.text("添加计时器"))
            .accessibilityIdentifier("toolbox.addTimer")
            .padding(6)
        }
    }
}

struct ToolboxTimerCard: View {
    @ObservedObject var service: PomodoroService
    let timerID: UUID?
    let compact: Bool
    @State private var isDurationPickerPresented = false
    @State private var isEditingName = false
    @State private var draftName = ""
    @FocusState private var nameIsFocused: Bool

    private var countdown: CountdownTimer? { service.countdowns.first { $0.id == timerID } }
    private var engine: PomodoroEngine { countdown?.engine ?? service.engine }
    private var clock: String { countdown?.displayClock ?? service.displayClock }
    private var name: String { countdown?.name ?? service.name }
    private var title: String { name.isEmpty ? AppLocalization.text(timerID == nil ? engine.mode.title : "计时器") : name }
    private var toggleTitle: String { AppLocalization.text(engine.phase == .running ? "暂停" : engine.phase == .paused ? "继续" : "开始") }
    private var identifier: String { timerID?.uuidString ?? "pomodoro" }
    private var shape: UnevenRoundedRectangle {
        IslandSurfaceGeometry.moduleContentShape(
            bottomLeadingRadius: compact ? IslandSurfaceGeometry.moduleInnerCornerRadius : IslandSurfaceGeometry.moduleOuterBottomCornerRadius
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            nameField
                .padding(.trailing, 24)
            Spacer(minLength: 0)
            durationDisplay
                .frame(maxWidth: .infinity, alignment: .center)
            Spacer(minLength: 0)
            if compact {
                controls
                    .frame(maxWidth: .infinity, minHeight: 40)
            } else {
                HStack(spacing: 8) {
                    Button(action: toggle) {
                        Image(systemName: engine.phase == .running ? "pause.fill" : "play.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(Color.fillCard)
                    .clipShape(IslandSurfaceGeometry.moduleContentShape(
                        bottomLeadingRadius: IslandSurfaceGeometry.nestedBottomCornerRadius(inset: 10)
                    ))
                    .help(toggleTitle)
                    .accessibilityLabel(toggleTitle)
                    .accessibilityIdentifier("toolbox.toggleTimer.\(identifier)")
                    Button(action: cancel) {
                        Text(AppLocalization.text("取消"))
                            .font(.system(size: 11, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(Color.fillControl)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .help(AppLocalization.text("取消"))
                    .accessibilityIdentifier("toolbox.cancelTimer.\(identifier)")
                }
            }
        }
        .padding(compact ? 8 : 10)
        .frame(maxWidth: .infinity)
        .frame(height: 136)
        .background(Color.fillCard)
        .clipShape(shape)
        .overlay { shape.strokeBorder(Color.strokeCard, lineWidth: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("toolbox.timer.\(identifier)")
    }

    @ViewBuilder
    private var nameField: some View {
        if isEditingName {
            TextField(AppLocalization.text("计时器名称"), text: $draftName)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .focused($nameIsFocused)
                .onSubmit(commitName)
                .onExitCommand { isEditingName = false }
                .onChange(of: nameIsFocused) { _, focused in
                    if !focused && isEditingName { commitName() }
                }
                .accessibilityIdentifier("toolbox.timerName.\(identifier)")
        } else {
            Button {
                draftName = name
                isEditingName = true
                nameIsFocused = true
            } label: {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(AppLocalization.text("计时器名称"))
            .accessibilityIdentifier("toolbox.renameTimer.\(identifier)")
        }
    }

    private func commitName() {
        if let timerID { service.renameCountdown(id: timerID, name: draftName) }
        else { service.setName(draftName) }
        isEditingName = false
    }

    private var controls: some View {
        HStack(spacing: 2) {
            IconButton(symbol: engine.phase == .running ? "pause.fill" : "play.fill", help: toggleTitle, size: .compact, action: toggle)
                .accessibilityLabel(toggleTitle)
                .accessibilityIdentifier("toolbox.toggleTimer.\(identifier)")
            IconButton(symbol: "xmark", help: AppLocalization.text("取消"), size: .compact, action: cancel)
                .accessibilityLabel(AppLocalization.text("取消"))
                .accessibilityIdentifier("toolbox.cancelTimer.\(identifier)")
        }
    }

    private func toggle() {
        if let timerID { service.toggleCountdown(id: timerID) }
        else { service.toggleStartPause() }
    }

    private func cancel() {
        if let timerID { service.cancelCountdown(id: timerID) }
        else { service.reset() }
    }

    @ViewBuilder
    private var durationDisplay: some View {
        if engine.phase == .idle {
            Button { isDurationPickerPresented.toggle() } label: {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    timeText
                    if !compact {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .help(AppLocalization.text("设置时长"))
            .popover(isPresented: $isDurationPickerPresented, arrowEdge: .top) {
                HStack(spacing: 8) {
                    durationInput("小时", value: durationHours)
                    Text(AppLocalization.text("小时")).foregroundStyle(.secondary)
                    durationInput("分钟", value: durationMinutes)
                    Text(AppLocalization.text("分")).foregroundStyle(.secondary)
                    durationInput("秒", value: durationSeconds)
                    Text(AppLocalization.text("秒")).foregroundStyle(.secondary)
                }
                .padding(12)
            }
        } else { timeText }
    }

    private var timeText: some View {
        Text(clock)
            .font(.system(size: 26, weight: .bold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .foregroundStyle(.primary)
            .accessibilityLabel(clock)
            .accessibilityIdentifier("toolbox.timerClock.\(identifier)")
    }

    private var currentDuration: TimeInterval {
        let seconds = engine.mode == .focus
            ? engine.focusDuration
            : engine.restDuration
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
        TextField(AppLocalization.text(title), value: value, format: .number)
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .frame(width: 44)
    }

    private func setDuration(hours: Int, minutes: Int, seconds: Int) {
        let duration = TimeInterval(ToolboxModuleView.durationSeconds(
            hours: hours,
            minutes: minutes,
            seconds: seconds
        ))
        if let timerID {
            service.setCountdownDuration(id: timerID, duration: duration)
        } else if engine.mode == .focus {
            service.setFocusDuration(duration)
        } else {
            service.setRestDuration(duration)
        }
    }

}
