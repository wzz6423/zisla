import AppKit
import ZislaCore
import ZislaKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var settingsStore: FeatureSettingsStore
    @StateObject private var input = SettingsInput()
    @StateObject private var launchAtLogin = LaunchAtLoginController()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var searchFieldFocused: Bool
    @State private var draggedWeatherLocationID: String?
    @State private var sectionSwitchDirection: CGFloat = 1
    @State private var copiedCommand: String?
    @State private var pendingRecommendedToolAction: RecommendedToolAction?
    @State private var isVoiceHistoryClearConfirmationPresented = false
    @Namespace private var sectionSelectionNamespace

    init(model: AppModel) {
        self.model = model
        _settingsStore = ObservedObject(wrappedValue: model.settingsStore)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detail
        }
        .frame(
            width: input.selection.prefersWideLayout ? 980 : 640,
            height: input.selection.prefersWideLayout ? 640 : 560
        )
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            launchAtLogin.refresh()
            model.refreshVoiceInputInputMonitoringAccess()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            launchAtLogin.refresh()
            model.refreshVoiceInputInputMonitoringAccess()
        }
        .alert(
            pendingRecommendedToolAction?.title ?? "",
            isPresented: Binding(
                get: { pendingRecommendedToolAction != nil },
                set: { if !$0 { pendingRecommendedToolAction = nil } }
            )
        ) {
            Button("取消", role: .cancel) {
                pendingRecommendedToolAction = nil
            }
            Button("继续") {
                guard let action = pendingRecommendedToolAction else { return }
                pendingRecommendedToolAction = nil
                Task { await performRecommendedToolAction(action) }
            }
        } message: {
            Text(recommendedToolActionMessage)
        }
        .alert("清空所有语音记录？", isPresented: $isVoiceHistoryClearConfirmationPresented) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) {
                model.removeAllVoiceRecordings()
            }
        } message: {
            Text("本机保存的识别文本和原始录音文件都会被删除，此操作无法撤销。")
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("zisla")
                .font(.system(size: 14, weight: .semibold))
            Text("设置")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(.top, 1)

            VStack(spacing: 2) {
                ForEach(SettingsSection.allCases) { section in
                    Button {
                        selectSettingsSection(section)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: section.symbol)
                                .font(.system(size: 12, weight: .semibold))
                                .frame(width: 17)
                            AppLocalizedText(section.title)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8)
                        .frame(height: 32)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle(hoverScale: 1.018, pressedScale: 0.965))
                    .foregroundStyle(input.selection == section ? Color.primary : Color.secondary)
                    .background {
                        if input.selection == section {
                            SelectionGlassBackground(cornerRadius: 6)
                                .matchedGeometryEffect(
                                    id: "settings-section-selection",
                                    in: sectionSelectionNamespace
                                )
                        }
                    }
                    .accessibilityLabel("\(section.title)设置")
                }
            }
            .padding(.top, 20)
            .animation(reduceMotion ? nil : ZislaMotion.selection, value: input.selection)

            Spacer(minLength: 12)

            HStack(spacing: 6) {
                Text("版本 \(appVersion)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
                IconButton(symbol: "power", help: "退出应用", size: .compact) {
                    NSApp.terminate(nil)
                }
                .accessibilityLabel("退出应用")
            }
            .frame(maxWidth: .infinity)
        }
        .padding(12)
        .frame(width: 148)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color.primary.opacity(colorScheme == .dark ? 0.035 : 0.025))
    }

    private var detail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 3) {
                    AppLocalizedText(input.selection.title)
                        .font(.system(size: 20, weight: .semibold))
                    AppLocalizedText(input.selection.subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                DeferredMount {
                    selectedContent
                }
                    .id(input.selection)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .modulePush(direction: sectionSwitchDirection)
                    )
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .thinScrollChrome()
        .animation(reduceMotion ? nil : ZislaMotion.settingsPageSwitch, value: input.selection)
    }

    private func selectSettingsSection(_ section: SettingsSection) {
        guard section != input.selection else { return }
        if let currentIndex = SettingsSection.allCases.firstIndex(of: input.selection),
           let targetIndex = SettingsSection.allCases.firstIndex(of: section) {
            sectionSwitchDirection = targetIndex > currentIndex ? 1 : -1
        }
        if reduceMotion {
            input.selection = section
        } else {
            withAnimation(ZislaMotion.settingsPageSwitch) {
                input.selection = section
            }
        }
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch input.selection {
        case .general:
            generalContent
        case .features:
            featuresContent
        case .workflow:
            workflowContent
        case .info:
            infoContent
        case .ai:
            aiContent
        case .voice:
            voiceContent
        case .models:
            modelsContent
        case .pet:
            petContent
        case .privacy:
            privacyContent
        case .download:
            downloadContent
        case .weather:
            weatherContent
        case .updates:
            updatesContent
        case .recommendations:
            recommendationsContent
        }
    }

    private var workflowContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingsGroup("工作流模块") {
                settingRow(
                    symbol: "music.note.list",
                    title: "播放来源",
                    detail: model.settingsStore.settings.mediaSource.detail
                ) {
                    Picker(
                        "",
                        selection: Binding(
                            get: { model.settingsStore.settings.mediaSource },
                            set: { model.settingsStore.settings.mediaSource = $0 }
                        )
                    ) {
                        ForEach(MediaSourcePreference.allCases, id: \.self) { source in
                            AppLocalizedText(source.title).tag(source)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .frame(width: 132, alignment: .trailing)
                    .disabled(!model.settingsStore.settings.mediaEnabled)
                }
                rowDivider
                settingRow(
                    symbol: "text.quote",
                    title: "歌词与歌曲信息",
                    detail: "详细模式：图标、歌名、歌手与滚动歌词；关闭为简略模式（仅图标与音浪）"
                ) {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { model.settingsStore.settings.mediaShowLyricsAndInfo },
                            set: { model.settingsStore.settings.mediaShowLyricsAndInfo = $0 }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .disabled(!model.settingsStore.settings.mediaEnabled)
                }
                rowDivider
                settingRow(
                    symbol: "rectangle.topthird.inset.filled",
                    title: "收起态音乐样式",
                    detail: model.settingsStore.settings.mediaCompactStyle.detail
                ) {
                    Picker(
                        "",
                        selection: Binding(
                            get: { model.settingsStore.settings.mediaCompactStyle },
                            set: { model.settingsStore.settings.mediaCompactStyle = $0 }
                        )
                    ) {
                        ForEach(MediaCompactStyle.allCases, id: \.self) { style in
                            AppLocalizedText(style.title).tag(style)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .frame(width: 132, alignment: .trailing)
                    .disabled(!model.settingsStore.settings.mediaEnabled)
                }
                if model.settingsStore.settings.systemMonitorEnabled {
                    rowDivider
                    settingRow(
                        symbol: "menubar.rectangle",
                        title: "菜单栏常驻",
                        detail: "选择一项或多项；点击任一指标直达系统监控"
                    ) {
                        EmptyView()
                    }
                    rowDivider
                    settingRow(
                        symbol: "rectangle.compress.vertical",
                        title: "监控样式",
                        detail: "紧凑模式隐藏图标并减小字号，减少菜单栏占用"
                    ) {
                        IslandOutlinedPicker(
                            selection: Binding(
                                get: { model.settingsStore.settings.systemMonitorMenuBarDisplayStyle },
                                set: { model.settingsStore.settings.systemMonitorMenuBarDisplayStyle = $0 }
                            ),
                            options: Array(SystemMonitorMenuBarDisplayStyle.allCases),
                            title: { $0.menuTitle },
                            selectionID: "system-monitor-menu-bar-display-style-selection",
                            fontSize: 9,
                            width: 128,
                            height: 28
                        )
                    }
                    ForEach(SystemMonitorMenuBarMetric.allCases, id: \.self) { metric in
                        rowDivider
                        settingRow(
                            symbol: metric.symbolName,
                            title: metric.menuTitle,
                            detail: "显示实时监控摘要"
                        ) {
                            Toggle("", isOn: systemMonitorMenuBarBinding(for: metric))
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .controlSize(.small)
                        }
                    }
                }
            }
        }
    }

    private var featuresContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingsGroup("媒体与文件") {
                featureToggle("媒体播放", detail: "显示系统正在播放的音乐或视频", symbol: "play.square.fill", keyPath: \.mediaEnabled)
                rowDivider
                featureToggle("文件中转与分享", detail: "暂存文件并调用 AirDrop 或系统分享", symbol: "tray.full.fill", keyPath: \.fileShelfEnabled)
                rowDivider
                featureToggle("链接下载", detail: "下载视频或音频", symbol: "arrow.down.circle.fill", keyPath: \.downloaderEnabled)
                rowDivider
                featureToggle("剪贴板历史", detail: "仅本机保存文本和图片", symbol: "clipboard", keyPath: \.clipboardHistoryEnabled)
                rowDivider
                featureToggle("剪贴板链接检测", detail: "发现可下载链接时提示", symbol: "clipboard.fill", keyPath: \.clipboardDetectionEnabled)
            }

            settingsGroup("信息与通知") {
                featureToggle("日历日程", detail: "显示接下来的日程与会议", symbol: "calendar", keyPath: \.calendarEnabled)
                rowDivider
                featureToggle("天气", detail: "显示当前或自选地区的天气", symbol: "cloud.sun.fill", keyPath: \.weatherEnabled)
                rowDivider
                featureToggle("邮件", detail: "读取已配置的 Mail.app 账户并提醒新邮件", symbol: "envelope.fill", keyPath: \.mailEnabled)
                rowDivider
                featureToggle("侧翼通知", detail: "在灵动岛肩部显示任务变化", symbol: "bell.badge.fill", keyPath: \.sideNoticesEnabled)
                rowDivider
                featureToggle("锁屏信息", detail: "在系统锁屏页显示状态信息与播放器", symbol: "lock.display", keyPath: \.lockScreenInfoEnabled)
                rowDivider
                featureToggle("专注倒计时", detail: "专注时在收起态灵动岛显示剩余时间", symbol: "clock", keyPath: \.focusCountdownIslandEnabled)
                    .disabled(!model.settingsStore.settings.sideNoticesEnabled)
                rowDivider
                featureToggle("工具箱提醒", detail: "在收起态提示番茄钟、亮屏和清洁状态", symbol: "bell.fill", keyPath: \.toolboxReminderEnabled)
                    .disabled(!model.settingsStore.settings.toolboxEnabled || !model.settingsStore.settings.sideNoticesEnabled)
            }

            settingsGroup("AI 与语音") {
                featureToggle("AI 进度与用量", detail: "汇总桌面端与 CLI 工具的运行状态", symbol: "sparkles", keyPath: \.aiProgressEnabled)
                rowDivider
                featureToggle("AI Agent", detail: "启用 AI Agent 功能模块与后台服务", symbol: "sparkles.square.filled.on.square", keyPath: \.aiAgentEnabled)
                rowDivider
                featureToggle("语音输入", detail: "开启后可通过全局快捷键触发语音输入", symbol: "mic.fill", keyPath: \.voiceInputEnabled)
            }

            settingsGroup("工具与监控") {
                featureToggle("小工具", detail: "番茄钟、亮屏与屏幕清洁", symbol: "wrench.and.screwdriver.fill", keyPath: \.toolboxEnabled)
                rowDivider
                featureToggle("随记", detail: "Markdown 随手记，可发送到系统备忘录", symbol: "note.text", keyPath: \.quickNotesEnabled)
                rowDivider
                featureToggle("PDF 工具", detail: "合并、拆分、加密与转换 PDF", symbol: "doc.text.fill", keyPath: \.pdfToolsEnabled)
                rowDivider
                featureToggle("系统状态与清理", detail: "监控资源并安全清理缓存和日志", symbol: "gauge.with.dots.needle.67percent", keyPath: \.systemMonitorEnabled)
                rowDivider
                featureToggle("电池监控", detail: "显示电池详细信息与健康状态", symbol: "battery.100percent", keyPath: \.batteryMonitorEnabled)
            }

            settingsGroup("灵动岛与下载展示") {
                featureToggle("鼠标移入展开", detail: "鼠标进入屏幕顶部感应区时显示", symbol: "cursorarrow.motionlines", keyPath: \.hoverActivationEnabled)
                rowDivider
                featureToggle("显示 zisla 图标", detail: "关闭后不影响已启用的菜单栏监控项", symbol: "app.badge", keyPath: \.menuBarAppIconEnabled)
                rowDivider
                featureToggle("始终置顶", detail: "收起时保持在其他窗口和菜单栏图标上方", symbol: "rectangle.topthird.inset.filled", keyPath: \.islandCollapsedOnTop)
                rowDivider
                featureToggle("浏览器下载进度", detail: "在灵动岛显示来源图标与百分比", symbol: "arrow.down.circle.fill", keyPath: \.browserDownloadIslandEnabled)
                    .disabled(!model.settingsStore.settings.sideNoticesEnabled)
                rowDivider
                featureToggle("原生下载进度", detail: "下载器工作时显示来源平台图标与百分比", symbol: "arrow.down.square.fill", keyPath: \.videoDownloadIslandEnabled)
                    .disabled(!model.settingsStore.settings.sideNoticesEnabled)
                rowDivider
                featureToggle("静音 Zisla 通知", detail: "不发送番茄钟等由 Zisla 产生的系统通知", symbol: "bell.slash.fill", keyPath: \.notificationsMuted)
            }

            settingsGroup("桌面宠物与更新") {
                featureToggle("桌面宠物", detail: "在灵动岛养一只小宠物", symbol: "pawprint.fill", keyPath: \.petEnabled)
                rowDivider
                featureToggle("自动检查更新", detail: "定期检查当前安装包所属的更新通道", symbol: "arrow.triangle.2.circlepath", keyPath: \.updateChecksEnabled)
                rowDivider
                featureToggle("自动下载更新", detail: "发现新版本时自动下载安装包", symbol: "arrow.down.circle.fill", keyPath: \.automaticDownloadEnabled)
                    .disabled(!model.settingsStore.settings.updateChecksEnabled)
            }
        }
    }

    private var infoContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingsGroup("信息与通知") {
                if model.settingsStore.settings.mailEnabled {
                    mailAccountSettings
                }
                rowDivider
                if model.settingsStore.settings.lockScreenInfoEnabled {
                    rowDivider
                    settingRow(
                        symbol: "text.quote",
                        title: "锁屏文字",
                        detail: "显示在系统时间上方；留空则不显示"
                    ) {
                        TextField(
                            "输入一句话",
                            text: Binding(
                                get: { model.settingsStore.settings.lockScreenMessage },
                                set: { model.settingsStore.settings.lockScreenMessage = $0 }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))
                        .frame(width: 170)
                    }
                    rowDivider
                    settingRow(
                        symbol: "calendar",
                        title: "显示农历",
                        detail: "显示在系统时间上方，可与锁屏文字共存"
                    ) {
                        Toggle(
                            "",
                            isOn: Binding(
                                get: { model.settingsStore.settings.lockScreenShowsLunar },
                                set: { model.settingsStore.settings.lockScreenShowsLunar = $0 }
                            )
                        )
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    }
                }
                rowDivider
                settingRow(
                    symbol: "timer",
                    title: "活动展示",
                    detail: "播放与 AI 任务的折叠时长"
                ) {
                    Picker(
                        "",
                        selection: Binding(
                            get: { model.settingsStore.settings.activityNoticeDisplayDuration },
                            set: { model.settingsStore.settings.activityNoticeDisplayDuration = $0 }
                        )
                    ) {
                        ForEach(ActivityNoticeDisplayDuration.allCases, id: \.self) { duration in
                            AppLocalizedText(duration.menuTitle).tag(duration)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .frame(maxWidth: 96, alignment: .trailing)
                    .disabled(!model.settingsStore.settings.sideNoticesEnabled)
                }
                rowDivider
                settingRow(
                    symbol: "moon.fill",
                    title: "专注模式展示",
                    detail: "开启或切换专注模式时的显示时长"
                ) {
                    Picker(
                        "",
                        selection: Binding(
                            get: { model.settingsStore.settings.focusModeNoticeDisplayDuration },
                            set: { model.settingsStore.settings.focusModeNoticeDisplayDuration = $0 }
                        )
                    ) {
                        ForEach(FocusModeNoticeDisplayDuration.allCases, id: \.self) { duration in
                            AppLocalizedText(duration.menuTitle).tag(duration)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .frame(maxWidth: 96, alignment: .trailing)
                    .disabled(!model.settingsStore.settings.sideNoticesEnabled)
                }
            }

            settingsGroup("收起态展示优先级") {
                let priorities = model.settingsStore.settings.compactStatusPriority
                ForEach(Array(priorities.enumerated()), id: \.element) { index, priority in
                    if index > 0 { rowDivider }
                    settingRow(
                        symbol: compactStatusPrioritySymbol(for: priority),
                        title: priority.title,
                        detail: ""
                    ) {
                        HStack(spacing: 4) {
                            IconButton(
                                symbol: "arrow.up",
                                help: "上移\(priority.title)",
                                size: .compact
                            ) {
                                moveCompactStatusPriority(priority, by: -1)
                            }
                            .disabled(index == priorities.startIndex)

                            IconButton(
                                symbol: "arrow.down",
                                help: "下移\(priority.title)",
                                size: .compact
                            ) {
                                moveCompactStatusPriority(priority, by: 1)
                            }
                            .disabled(index == priorities.index(before: priorities.endIndex))
                        }
                    }
                    .disabled(!model.settingsStore.settings.sideNoticesEnabled)
                }
                rowDivider
                settingRow(
                    symbol: "arrow.counterclockwise",
                    title: "恢复默认顺序",
                    detail: ""
                ) {
                    IconButton(
                        symbol: "arrow.counterclockwise",
                        help: "恢复默认顺序",
                        size: .compact
                    ) {
                        model.settingsStore.settings.compactStatusPriority = CompactStatusPriority.defaultOrder
                    }
                    .disabled(
                        model.settingsStore.settings.compactStatusPriority
                            == CompactStatusPriority.defaultOrder
                    )
                }
                .disabled(!model.settingsStore.settings.sideNoticesEnabled)
            }

            settingsGroup("通知显示器") {
                let displays = activityNoticeDisplays
                if displays.count < 2 {
                    settingRow(
                        symbol: "display",
                        title: displays.first?.name ?? "当前显示器",
                        detail: "连接另一台显示器后可选择通知展示范围"
                    ) {
                        EmptyView()
                    }
                } else {
                    ForEach(Array(displays.enumerated()), id: \.element.id) { index, display in
                        if index > 0 { rowDivider }
                        settingRow(
                            symbol: "display",
                            title: display.name,
                            detail: "播放与 AI 活动通知显示在此屏幕"
                        ) {
                            Toggle(
                                "",
                                isOn: activityNoticeDisplayBinding(
                                    for: display.id,
                                    in: displays
                                )
                            )
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .disabled(!model.settingsStore.settings.sideNoticesEnabled)
                        }
                    }
                }
            }
        }
    }

    /// AI monitoring and agent behavior; model definitions and remote credentials appear only on the Models page.
    private var aiContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingsGroup("AI Agent 行为") {
                AIAgentModuleView(model: model, configurationScope: .agent)
                    .frame(minHeight: 430)
                    .task {
                        guard model.settingsStore.settings.aiAgentEnabled else { return }
                        await model.aiAgent.refreshAll()
                    }
            }
        }
    }

    private var voiceContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            IslandOutlinedPicker(
                selection: $input.voicePage,
                options: Array(VoiceSettingsPage.allCases),
                title: { $0.title },
                selectionID: "voice-settings-page-selection",
                fontSize: 11,
                width: 240,
                height: 28
            )
            .frame(maxWidth: .infinity)

            switch input.voicePage {
            case .settings:
                voiceSettingsContent
            case .history:
                voiceHistoryContent
            }
        }
    }

    private var voiceSettingsContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            voiceInputGroup
            settingsGroup("本地记录") {
                settingRow(
                    symbol: "externaldrive.fill",
                    title: "保留原始录音",
                    detail: "每条原始音频、系统识别文本和 AI 整理文本只保存在本机"
                ) {
                    IconButton(symbol: "folder", help: "打开语音记录目录", size: .compact) {
                        model.openVoiceRecordingsDirectory()
                    }
                }
            }
        }
    }

    private var voiceHistoryContent: some View {
        let statistics = model.voiceHistory.statistics
        return VStack(alignment: .leading, spacing: 20) {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())],
                spacing: 10
            ) {
                voiceStatistic(
                    symbol: "textformat",
                    title: "总识别字词",
                    value: "\(statistics.totalWordCount) 字词"
                )
                voiceStatistic(
                    symbol: "waveform",
                    title: "累计口述时间",
                    value: voiceDurationText(statistics.totalDuration)
                )
                voiceStatistic(
                    symbol: "bolt.fill",
                    title: "输入速度",
                    value: "\(Int(statistics.wordsPerMinute.rounded())) 字词/分"
                )
                voiceStatistic(
                    symbol: "clock",
                    title: "节省时间",
                    value: voiceDurationText(statistics.savedTime)
                )
            }

            settingsGroup("语音记录") {
                HStack(spacing: 8) {
                    Text("全部记录仅保存在本机")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    IconButton(symbol: "folder", help: "打开语音记录目录", size: .compact) {
                        model.openVoiceRecordingsDirectory()
                    }
                    IconButton(symbol: "trash", help: "清空语音记录", size: .compact) {
                        isVoiceHistoryClearConfirmationPresented = true
                    }
                    .disabled(model.voiceHistory.entries.isEmpty)
                }
                .padding(.horizontal, 4)
                .frame(minHeight: 42)

                if model.voiceHistory.entries.isEmpty {
                    rowDivider
                    HStack(spacing: 8) {
                        Image(systemName: "waveform.slash")
                            .foregroundStyle(.secondary)
                        Text("暂无语音记录")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 72)
                } else {
                    ForEach(model.voiceHistory.entries) { entry in
                        rowDivider
                        voiceHistoryRow(entry)
                    }
                }
            }
        }
    }

    private func voiceStatistic(symbol: String, title: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 26, height: 26)
                .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 68)
        .background(Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.035))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func voiceHistoryRow(_ entry: VoiceHistoryEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("\(voiceDurationText(entry.duration)) · \(entry.wordCount) 字词")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                if let processed = entry.processedTranscript {
                    Text("AI 整理：\(processed)")
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(2)
                    Text("原始识别：\(entry.rawTranscript.isEmpty ? "未识别到文字" : entry.rawTranscript)")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else {
                    Text(entry.rawTranscript.isEmpty ? "未识别到文字" : entry.rawTranscript)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(3)
                }
            }
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 4) {
                IconButton(symbol: "play.fill", help: "播放原始录音", size: .compact) {
                    model.playVoiceRecording(id: entry.id)
                }
                IconButton(symbol: "magnifyingglass", help: "在 Finder 中显示", size: .compact) {
                    model.revealVoiceRecording(id: entry.id)
                }
                IconButton(symbol: "trash", help: "删除这条语音记录", size: .compact) {
                    model.removeVoiceRecording(id: entry.id)
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 64)
    }

    private func voiceDurationText(_ duration: TimeInterval) -> String {
        let duration = max(0, duration)
        if duration < 60 {
            return "\(Int(duration.rounded())) 秒"
        }
        if duration < 3_600 {
            return String(format: "%.1f 分钟", duration / 60)
        }
        return String(format: "%.1f 小时", duration / 3_600)
    }

    private var voiceInputGroup: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingsGroup("语音输入") {
                if model.settingsStore.settings.voiceInputEnabled {
                    settingRow(
                        symbol: "rectangle.2.group",
                        title: "录音模式",
                        detail: model.settingsStore.settings.voiceInputMode.detail
                    ) {
                        Picker(
                            "",
                            selection: Binding(
                                get: { model.settingsStore.settings.voiceInputMode },
                                set: { model.settingsStore.settings.voiceInputMode = $0 }
                            )
                        ) {
                            ForEach(VoiceInputMode.allCases, id: \.self) { mode in
                                AppLocalizedText(mode.displayName).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        .frame(maxWidth: 110, alignment: .trailing)
                    }
                    rowDivider
                    settingRow(
                        symbol: "keyboard",
                        title: "快捷键",
                        detail: model.settingsStore.settings.voiceInputMode == .pushToTalk
                            ? "按住说话、松开结束"
                            : "按一下开始、再按一下结束"
                    ) {
                        VoiceInputHotkeyRecorder(
                            hotkey: Binding(
                                get: { model.settingsStore.settings.voiceInputHotkeyPreset },
                                set: { model.settingsStore.settings.voiceInputHotkeyPreset = $0 }
                            )
                        )
                        .frame(width: 142, height: 26)
                    }
                    if model.settingsStore.settings.voiceInputHotkeyPreset.requiresInputMonitoring {
                        rowDivider
                        settingRow(
                            symbol: "lock.shield",
                            title: "输入监控",
                            detail: "左右侧修饰键需要监听全局键盘事件"
                        ) {
                            if model.voiceInputInputMonitoringAccessGranted {
                                Label("已授权", systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.caption)
                            } else {
                                Button("打开设置") {
                                    model.openVoiceInputInputMonitoringSettings()
                                }
                                .controlSize(.small)
                            }
                        }
                    }
                }
            }
        }
    }

    private var modelsContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Model definitions and remote credentials belong only here: define models first, then select them below.
            settingsGroup("本地模型") {
                AIAgentModuleView(model: model, configurationScope: .localModels)
                    .frame(minHeight: 170)
            }

            settingsGroup("远端模型与凭据") {
                AIAgentModuleView(model: model, configurationScope: .remoteModels)
                    .frame(minHeight: 300)
                    .task {
                        guard model.settingsStore.settings.aiAgentEnabled else { return }
                        await model.aiAgent.refreshAll()
                    }
            }

            settingsGroup("语音整理模型") {
                settingRow(
                    symbol: "cpu",
                    title: "使用模型",
                    detail: "从上方已启用的本地或远端模型中选择"
                ) {
                    Picker(
                        "",
                        selection: Binding(
                            get: { model.selectedVoiceModelConfiguration },
                            set: { model.selectVoiceModelConfiguration($0) }
                        )
                    ) {
                        Text("不使用模型整理").tag(Optional<AIModelConfigurationReference>.none)
                        ForEach(model.aiAgent.store.state.localModels.filter(\.isEnabled)) { localModel in
                            Text("本地 · \(localModel.name)")
                                .tag(Optional(AIModelConfigurationReference.local(localModel.id)))
                        }
                        ForEach(model.aiAgent.store.state.channels.filter(\.isEnabled)) { channel in
                            Text("远端 · \(channel.name)")
                                .tag(Optional(AIModelConfigurationReference.channel(channel.id)))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .frame(maxWidth: 220, alignment: .trailing)
                }
                if let configuration = model.selectedVoiceModelConfiguration {
                    rowDivider
                    settingRow(
                        symbol: configuration.source == .channel ? "server.rack" : "desktopcomputer",
                        title: model.voiceModelConfigurationTitle(configuration),
                        detail: model.voiceModelConfigurationDetail(configuration)
                    ) {
                        HStack(spacing: 8) {
                            Text(discoveryStatusText)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            Button {
                                model.discoverModels()
                            } label: {
                                if model.voiceModelDiscoveryState.isTesting {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Text("测试连接")
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(model.voiceModelDiscoveryState.isTesting)
                        }
                    }
                } else {
                    rowDivider
                    settingRow(
                        symbol: "sparkles",
                        title: "尚未选择模型",
                        detail: model.aiAgent.store.state.localModels.filter(\.isEnabled).isEmpty
                            && model.aiAgent.store.state.channels.filter(\.isEnabled).isEmpty
                            ? "在上方添加并启用本地或远端模型后即可选择"
                            : "选择后会对语音转写进行整理"
                    ) {
                        EmptyView()
                    }
                }
            }

            settingsGroup("设备档案与推荐模型") {
                if let profile = model.hardwareProfile {
                    settingRow(
                        symbol: "desktopcomputer",
                        title: "设备",
                        detail: profile.compactHardwareDescription,
                        detailLineLimit: 3
                    ) {
                        EmptyView()
                    }
                    rowDivider
                    settingRow(
                        symbol: "gauge.with.dots.needle.67percent",
                        title: "综合推荐",
                        detail: profile.recommendationDescription,
                        detailLineLimit: 2
                    ) {
                        EmptyView()
                    }
                    ForEach(Array(AIModelRecommendations.recommended(for: profile).enumerated()), id: \.element.id) { index, rec in
                        rowDivider
                        VStack(alignment: .leading, spacing: 8) {
                            settingRow(
                                symbol: "lightbulb.fill",
                                title: "\(rec.name) · \(rec.parameterScale)",
                                detail: rec.reason
                            ) {
                                EmptyView()
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                commandRow(
                                    label: "Ollama 下载",
                                    command: rec.ollamaPullCommand
                                )
                                commandRow(
                                    label: "Ollama 启动",
                                    command: rec.ollamaRunCommand
                                )
                                commandRow(
                                    label: "LM Studio 搜索",
                                    command: rec.lmStudioSearchQuery
                                )
                            }
                            .padding(.leading, 38)
                            .padding(.bottom, 4)
                        }
                    }
                } else {
                    settingRow(
                        symbol: "desktopcomputer",
                        title: "设备档案",
                        detail: "点击下方按钮检测硬件信息"
                    ) {
                        Button("检测") {
                            model.refreshHardwareProfile()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }

        }
        .onAppear {
            model.refreshHardwareProfile()
        }
    }

    private var discoveryStatusText: String {
        switch model.voiceModelDiscoveryState {
        case .idle: "尚未测试连接"
        case .testing: "正在连接…"
        case .success(let count): "已发现 \(count) 个模型"
        case .failed(let message): message
        }
    }

    private var petContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingsGroup("桌面宠物") {
                settingRow(
                    symbol: "shippingbox.fill",
                    title: "当前宠物",
                    detail: "选择内置的宠物形象"
                ) {
                    Picker(
                        "",
                        selection: Binding(
                            get: { model.settingsStore.settings.petID },
                            set: { model.settingsStore.settings.petID = $0 }
                        )
                    ) {
                        ForEach(petEntries, id: \.id) { entry in
                            Text(petDisplayLabel(entry)).tag(entry.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .frame(width: 150, alignment: .trailing)
                    .disabled(!model.settingsStore.settings.petEnabled)
                }
                rowDivider
                settingRow(
                    symbol: "arrow.left.and.right",
                    title: "在岛的哪一侧",
                    detail: "宠物出现在灵动岛内部的左侧或右侧"
                ) {
                    Picker(
                        "",
                        selection: Binding(
                            get: { model.settingsStore.settings.petSide },
                            set: { model.settingsStore.settings.petSide = $0 }
                        )
                    ) {
                        Text("左侧").tag(PetSide.left)
                        Text("右侧").tag(PetSide.right)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .frame(width: 100, alignment: .trailing)
                    .disabled(!model.settingsStore.settings.petEnabled)
                }
            }
        }
    }

    private var petEntries: [PetLibrary.Entry] {
        PetLibrary.entries()
    }

    private func systemMonitorMenuBarBinding(
        for metric: SystemMonitorMenuBarMetric
    ) -> Binding<Bool> {
        Binding(
            get: { model.settingsStore.settings.systemMonitorMenuBarMetrics.contains(metric) },
            set: { enabled in
                var selection = model.settingsStore.settings.systemMonitorMenuBarMetrics
                if enabled {
                    selection.insert(metric)
                } else {
                    selection.remove(metric)
                }
                model.settingsStore.settings.systemMonitorMenuBarMetrics = selection
            }
        )
    }

    private func petDisplayLabel(_ entry: PetLibrary.Entry) -> String {
        switch entry.origin {
        case .builtin: entry.manifest.displayName
        case .imported: "\(entry.manifest.displayName)（已导入）"
        }
    }

    private var activityNoticeDisplays: [ActivityNoticeDisplay] {
        NSScreen.screens.enumerated().compactMap { index, screen in
            let key = NSDeviceDescriptionKey("NSScreenNumber")
            guard let number = screen.deviceDescription[key] as? NSNumber else { return nil }
            let name = screen.localizedName.isEmpty ? "显示器 \(index + 1)" : screen.localizedName
            return ActivityNoticeDisplay(id: number.uint32Value, name: name)
        }
    }

    private func activityNoticeDisplayBinding(
        for displayID: UInt32,
        in displays: [ActivityNoticeDisplay]
    ) -> Binding<Bool> {
        let connectedDisplayIDs = Set(displays.map(\.id))
        return Binding(
            get: {
                let selected = model.settingsStore.settings.activityNoticeDisplayIDs
                    .intersection(connectedDisplayIDs)
                return selected.isEmpty || selected.contains(displayID)
            },
            set: { enabled in
                var selected = model.settingsStore.settings.activityNoticeDisplayIDs
                    .intersection(connectedDisplayIDs)
                if selected.isEmpty { selected = connectedDisplayIDs }
                if enabled {
                    selected.insert(displayID)
                } else if selected.count > 1 {
                    selected.remove(displayID)
                }
                model.settingsStore.settings.activityNoticeDisplayIDs =
                    selected == connectedDisplayIDs ? [] : selected
            }
        )
    }

    private var generalContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingsGroup("外观与语言") {
                settingRow(
                    symbol: "character.bubble",
                    title: "界面语言",
                    detail: "切换后立即应用到支持的界面文本"
                ) {
                    Picker(
                        "",
                        selection: Binding(
                            get: { model.languageStore.language },
                            set: { model.languageStore.language = $0 }
                        )
                    ) {
                        ForEach(AppLanguage.allCases, id: \.self) { language in
                            Text(languageDisplayName(language)).tag(language)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .frame(width: 180, alignment: .trailing)
                }
                rowDivider
                settingRow(
                    symbol: "circle.lefthalf.filled",
                    title: "界面外观",
                    detail: ""
                ) {
                    IslandOutlinedPicker(
                        selection: Binding(
                            get: { model.settingsStore.settings.appearanceMode },
                            set: { model.settingsStore.settings.appearanceMode = $0 }
                        ),
                        options: Array(AppearanceMode.allCases),
                        title: { $0.menuTitle },
                        selectionID: "appearance-mode-selection",
                        fontSize: 9,
                        width: 216,
                        height: 28
                    )
                }
                rowDivider
                settingRow(
                    symbol: "rectangle.on.rectangle.angled",
                    title: "灵动岛样式",
                    detail: model.settingsStore.settings.islandVisualStyle.detail,
                    detailLineLimit: nil
                ) {
                    IslandVisualStylePicker(
                        selection: Binding(
                            get: { model.settingsStore.settings.islandVisualStyle },
                            set: { model.settingsStore.settings.islandVisualStyle = $0 }
                        )
                    )
                }
                rowDivider
                settingRow(
                    symbol: "rectangle.topthird.inset.filled",
                    title: "刘海背景",
                    detail: model.settingsStore.settings.islandNotchBackground.detail
                ) {
                    IslandNotchBackgroundPicker(
                        selection: Binding(
                            get: { model.settingsStore.settings.islandNotchBackground },
                            set: { model.settingsStore.settings.islandNotchBackground = $0 }
                        )
                    )
                }
            }

            settingsGroup("启动") {
                settingRow(
                    symbol: "power.circle.fill",
                    title: "登录时启动",
                    detail: launchAtLogin.statusMessage ?? "开机或登录后自动在后台运行"
                ) {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { launchAtLogin.isEnabled },
                            set: { launchAtLogin.setEnabled($0) }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }

                if launchAtLogin.showsOpenLoginItemsButton {
                    rowDivider
                    settingRow(
                        symbol: "gearshape.fill",
                        title: "需要系统批准",
                        detail: "在登录项中允许 zisla 后即可生效"
                    ) {
                        Button("打开登录项…") {
                            launchAtLogin.openLoginItemsSettings()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                if let errorMessage = launchAtLogin.errorMessage {
                    rowDivider
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text(errorMessage)
                            .lineLimit(2)
                    }
                    .font(.system(size: 9))
                    .foregroundStyle(Color.zislaError)
                    .padding(.horizontal, 4)
                    .frame(minHeight: 36, alignment: .leading)
                }
            }

        }
    }

    private var privacyContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingsGroup("剪贴板数据管理") {
                settingRow(
                    symbol: "info.circle",
                    title: "数据存储",
                    detail: "剪贴板历史仅保存在本机，不会上传"
                ) {
                    EmptyView()
                }
            }
        }
    }

    private var downloadContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingsGroup("下载目录") {
                settingRow(
                    symbol: "folder.fill",
                    title: "默认下载目录",
                    detail: model.downloadDirectory.path(percentEncoded: false)
                ) {
                    Button("选择…") { chooseDownloadDirectory() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }

            settingsGroup("组件") {
                managedToolRow(.ytDLP, symbol: "terminal.fill")
                rowDivider
                managedToolRow(.libreOffice, symbol: "doc.richtext")
            }
        }
        .task {
            await model.managedTools.refreshInstalledVersions()
            // The inline "Update to X" label depends on the latest version; query silently to avoid offline interruptions.
            for tool in ManagedTool.allCases {
                await model.managedTools.checkLatest(tool, quietly: true)
            }
        }
    }

    /// Components follow their declared source so the UI never misrepresents a Homebrew cask as a GitHub binary.
    @ViewBuilder
    private func managedToolRow(_ tool: ManagedTool, symbol: String) -> some View {
        let state = model.managedTools.states[tool] ?? ManagedToolState()
        settingRow(
            symbol: symbol,
            title: tool.displayName,
            detail: managedToolDetail(tool, state: state)
        ) {
            HStack(spacing: 8) {
                if case .downloading(let fraction) = state.phase, fraction > 0 {
                    ProgressView(value: fraction)
                        .frame(width: 52)
                        .controlSize(.small)
                } else if state.isBusy {
                    ProgressView().controlSize(.small)
                } else if state.isInstalled {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.zislaSuccess)
                }

                Button(state.isInstalled ? "更新" : "安装") {
                    Task { await model.managedTools.install(tool) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(state.isBusy)
                .help(
                    state.isInstalled
                        ? tool.updateHelp
                        : tool.installHelp
                )
            }
        }
    }

    private func managedToolDetail(_ tool: ManagedTool, state: ManagedToolState) -> String {
        if let errorMessage = state.errorMessage { return errorMessage }
        switch state.phase {
        case .checking: return "正在查询最新版本…"
        case .downloading(let fraction):
            return fraction > 0 ? "正在下载 \(Int(fraction * 100))%" : "正在下载…"
        case .installing: return "正在安装…"
        case .idle: break
        }
        guard let location = state.location else {
            return "未安装 · \(tool.purpose) · \(tool.installDetail)"
        }
        let version = state.installedVersion ?? "版本未知"
        if state.hasUpdate, let latest = state.latestVersion {
            return "\(version) · \(location.label) · 可更新到 \(latest)"
        }
        return "\(version) · \(location.label) · \(tool.purpose)"
    }

    private var recommendationsContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingsGroup("一键管理") {
                HStack(spacing: 8) {
                    Text("\(recommendedTools.count) 个推荐工具")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    recommendationActionButton(
                        symbol: "arrow.clockwise",
                        help: "重新检测推荐工具",
                        disabled: recommendedToolsAreBusy
                    ) {
                        Task { await refreshRecommendedTools() }
                    }
                    recommendationActionButton(
                        symbol: "arrow.down.circle",
                        help: "一键下载所有未安装的推荐工具",
                        disabled: recommendedToolsAreBusy || missingRecommendedTools.isEmpty
                    ) {
                        pendingRecommendedToolAction = .install
                    }
                    recommendationActionButton(
                        symbol: "arrow.up.circle",
                        help: "一键更新所有已安装的推荐工具",
                        disabled: recommendedToolsAreBusy || installedRecommendedTools.isEmpty
                    ) {
                        pendingRecommendedToolAction = .update
                    }
                }
                .padding(.horizontal, 4)
                .frame(minHeight: 48)
            }

            recommendedToolGroup(
                ManagedToolRecommendationGroup.terminalEfficiency.title,
                tools: recommendedTools(in: .terminalEfficiency)
            )
            recommendedToolGroup(
                ManagedToolRecommendationGroup.networkAndData.title,
                tools: recommendedTools(in: .networkAndData)
            )
            recommendedToolGroup(
                ManagedToolRecommendationGroup.developmentToolchain.title,
                tools: recommendedTools(in: .developmentToolchain)
            )
            recommendedToolGroup(
                ManagedToolRecommendationGroup.utility.title,
                tools: recommendedTools(in: .utility)
            )
            recommendedToolGroup(
                ManagedToolRecommendationGroup.desktopApplication.title,
                tools: recommendedTools(in: .desktopApplication)
            )
        }
        .task { await refreshRecommendedTools() }
    }

    private var recommendedTools: [ManagedTool] {
        ManagedTool.allCases
    }

    private func recommendedTools(in group: ManagedToolRecommendationGroup) -> [ManagedTool] {
        recommendedTools.filter { $0.recommendationGroup == group }
    }

    private var missingRecommendedTools: [ManagedTool] {
        recommendedTools.filter { !(model.managedTools.states[$0]?.isInstalled ?? false) }
    }

    private var installedRecommendedTools: [ManagedTool] {
        recommendedTools.filter { model.managedTools.states[$0]?.isInstalled == true }
    }

    private var recommendedToolsAreBusy: Bool {
        recommendedTools.contains { model.managedTools.states[$0]?.isBusy == true }
    }

    private func recommendedToolGroup(_ title: String, tools: [ManagedTool]) -> some View {
        settingsGroup(title) {
            ForEach(Array(tools.enumerated()), id: \.element.id) { index, tool in
                if index > 0 { rowDivider }
                recommendedToolRow(tool)
            }
        }
    }

    private func recommendedToolRow(_ tool: ManagedTool) -> some View {
        let state = model.managedTools.states[tool] ?? ManagedToolState()
        return settingRow(
            symbol: recommendedToolSymbol(for: tool),
            title: tool.displayName,
            detail: managedToolDetail(tool, state: state)
        ) {
            HStack(spacing: 8) {
                if case .downloading(let fraction) = state.phase, fraction > 0 {
                    ProgressView(value: fraction)
                        .frame(width: 52)
                        .controlSize(.small)
                } else if state.isBusy {
                    ProgressView().controlSize(.small)
                } else if state.isInstalled {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.zislaSuccess)
                }

                recommendationActionButton(
                    symbol: state.isInstalled ? "arrow.up.circle" : "arrow.down.circle",
                    help: state.isInstalled ? "更新 \(tool.displayName)" : "下载并安装 \(tool.displayName)",
                    disabled: state.isBusy
                ) {
                    Task { await model.managedTools.install(tool) }
                }
            }
        }
    }

    private func recommendationActionButton(
        symbol: String,
        help: String,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
        }
        .buttonStyle(.borderless)
        .disabled(disabled)
        .help(help)
        .accessibilityLabel(help)
    }

    private func recommendedToolSymbol(for tool: ManagedTool) -> String {
        switch tool {
        case .fzf: "line.3.horizontal.decrease.circle"
        case .ripgrep: "magnifyingglass"
        case .lazygit: "arrow.triangle.branch"
        case .neovim: "doc.text"
        case .yazi: "folder.fill"
        case .starship: "text.cursor"
        case .tldr: "book.closed"
        case .jq: "curlybraces.square"
        case .tree: "point.3.connected.trianglepath.dotted"
        case .ytDLP: "arrow.down.circle.fill"
        case .libreOffice: "doc.richtext"
        case .kaku: "terminal.fill"
        case .markdownPreview: "doc.text.magnifyingglass"
        case .keka: "archivebox.fill"
        case .kero: "terminal"
        default:
            switch tool.recommendationGroup {
            case .terminalEfficiency: "terminal"
            case .networkAndData: "network"
            case .developmentToolchain: "hammer"
            case .utility: "wrench.and.screwdriver"
            case .desktopApplication: "macwindow"
            }
        }
    }

    private func refreshRecommendedTools() async {
        await model.managedTools.refreshInstalledVersions()
        for tool in recommendedTools {
            await model.managedTools.checkLatest(tool, quietly: true)
        }
    }

    private func performRecommendedToolAction(_ action: RecommendedToolAction) async {
        let tools = switch action {
        case .install: missingRecommendedTools
        case .update: installedRecommendedTools
        }
        for tool in tools {
            await model.managedTools.install(tool)
        }
    }

    private var recommendedToolActionMessage: String {
        guard let action = pendingRecommendedToolAction else { return "" }
        let itemCount = switch action {
        case .install: missingRecommendedTools.count
        case .update: installedRecommendedTools.count
        }
        return action.message(itemCount: itemCount)
    }

    private var weatherContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingsGroup("地点") {
                ForEach(Array(model.weatherLocations.locations.enumerated()), id: \.element.id) {
                    index, location in
                    if index > 0 { rowDivider }
                    if location.kind == .saved {
                        weatherLocationRow(location)
                            .onDrop(
                                of: WeatherLocationReorderDropDelegate.supportedTypes,
                                delegate: WeatherLocationReorderDropDelegate(
                                    destinationID: location.id,
                                    draggingID: $draggedWeatherLocationID
                                ) { sourceID, destinationID in
                                    model.moveWeatherLocation(id: sourceID, to: destinationID)
                                }
                            )
                    } else {
                        weatherLocationRow(location)
                    }
                }

                rowDivider
                weatherSearchRow

                if case .failed(let message) = model.weatherLocationState {
                    rowDivider
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text(message)
                            .lineLimit(2)
                    }
                    .font(.system(size: 9))
                    .foregroundStyle(Color.zislaError)
                    .padding(.horizontal, 4)
                    .frame(minHeight: 36, alignment: .leading)
                }

                rowDivider

                settingRow(
                    symbol: "cloud.sun.fill",
                    title: "天气数据",
                    detail: "刷新当前位置与全部自选地区"
                ) {
                    Button {
                        model.refreshWeather()
                    } label: {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private func weatherLocationRow(_ location: WeatherLocation) -> some View {
        settingRow(
            symbol: location.kind == .current ? "location.fill" : "mappin.and.ellipse",
            title: location.displayName,
            detail: weatherLocationDetail(location)
        ) {
            if location.kind == .current, model.weatherLocationState.isBusy {
                ProgressView().controlSize(.small)
            } else if location.kind == .saved {
                HStack(spacing: 2) {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                        .onDrag {
                            draggedWeatherLocationID = location.id
                            return NSItemProvider(object: location.id as NSString)
                        }
                        .help("拖动调整 \(location.displayName) 的展示顺序")

                    Button {
                        model.removeWeatherLocation(id: location.id)
                    } label: {
                        Image(systemName: "trash")
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("删除 \(location.displayName)")
                }
            }
        }
    }

    private func weatherLocationDetail(_ location: WeatherLocation) -> String {
        if let snapshot = model.weatherSnapshot(for: location.id) {
            return "\(snapshot.condition.summary) · \(Int(snapshot.temperature.rounded()))°"
        }
        if location.kind == .current { return "默认显示当前所在地" }
        guard let coordinate = location.coordinate else { return "等待刷新" }
        return String(format: "%.2f, %.2f", coordinate.latitude, coordinate.longitude)
    }

    private var updatesContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingsGroup("更新策略") {
                settingRow(
                    symbol: "arrow.triangle.branch",
                    title: "手动检查通道",
                    detail: "\(model.settingsStore.settings.updateChannel.detail)；仅用于手动检查"
                ) {
                    IslandOutlinedPicker(
                        selection: Binding(
                            get: { model.settingsStore.settings.updateChannel },
                            set: { model.settingsStore.settings.updateChannel = $0 }
                        ),
                        options: Array(UpdateChannel.allCases),
                        title: { $0.menuTitle },
                        selectionID: "update-channel-selection",
                        fontSize: 9,
                        width: 150,
                        height: 28
                    )
                }
            }

            settingsGroup("更新下载目录") {
                settingRow(
                    symbol: "folder.fill",
                    title: "默认下载目录",
                    detail: model.downloadDirectory.path(percentEncoded: false)
                ) {
                    Button("选择…") { chooseDownloadDirectory() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }

            settingsGroup("版本") {
                settingRow(
                    symbol: "checkmark.seal.fill",
                    title: "zisla \(appVersion)",
                    detail: updateStatusText
                ) {
                    updateStatusAccessory
                }
                rowDivider
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Spacer()
                        Button {
                            model.checkForUpdates(
                                manual: true,
                                channel: model.settingsStore.settings.updateChannel
                            )
                        } label: {
                            Label(
                                "检查 \(model.settingsStore.settings.updateChannel.menuTitle)",
                                systemImage: "arrow.clockwise"
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }

                    HStack(spacing: 8) {
                        repositoryLink(
                            "GitHub",
                            symbol: "chevron.left.forwardslash.chevron.right",
                            tint: .primary,
                            destination: ZislaKitInfo.repositoryURL,
                            brandIconAsset: "github-mark.svg"
                        )
                        repositoryLink(
                            "Gitee",
                            symbol: "g.circle.fill",
                            tint: Color(red: 0.83, green: 0.20, blue: 0.14),
                            destination: ZislaKitInfo.giteeRepositoryURL
                        )
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 6)
            }
        }
    }

    private var weatherSearchRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
            HStack(spacing: 6) {
                TextField("城市、区县或地区", text: $input.weatherQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .focused($searchFieldFocused)
                    .onSubmit { searchWeatherLocation() }
                if !input.weatherQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button {
                        input.weatherQuery = ""
                        searchFieldFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("清除")
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        searchFieldFocused
                            ? Color.accentColor.opacity(0.6)
                            : Color.primary.opacity(0.12),
                        lineWidth: searchFieldFocused ? 1 : 0.5
                    )
            )
            .animation(.easeInOut(duration: 0.15), value: searchFieldFocused)
            Button(action: searchWeatherLocation) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .frame(width: 36, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
            )
            .help("搜索地区")
            .disabled(input.weatherQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 4)
        .frame(height: 46)
    }

    private func featureToggle(
        _ title: String,
        detail: String,
        symbol: String,
        keyPath: WritableKeyPath<FeatureSettings, Bool>
    ) -> some View {
        settingRow(symbol: symbol, title: title, detail: detail) {
            Toggle("", isOn: Binding(
                get: { model.settingsStore.settings[keyPath: keyPath] },
                set: { model.settingsStore.settings[keyPath: keyPath] = $0 }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private var mailAccountSettings: some View {
        settingRow(
            symbol: "rectangle.split.2x1",
            title: "新邮件展示",
            detail: model.settingsStore.settings.mailCompactStyle.detail
        ) {
            Picker(
                "",
                selection: Binding(
                    get: { model.settingsStore.settings.mailCompactStyle },
                    set: { model.settingsStore.settings.mailCompactStyle = $0 }
                )
            ) {
                ForEach(MailCompactStyle.allCases, id: \.self) { style in
                    Text(style.title).tag(style)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .frame(maxWidth: 108, alignment: .trailing)
        }
        rowDivider
        mailAppAccountSettings
    }

    @ViewBuilder
    private var mailAppAccountSettings: some View {
        let accounts = model.mail.accounts
        if accounts.isEmpty {
            settingRow(
                symbol: "person.crop.circle.badge.questionmark",
                title: "邮件账户",
                detail: "尚未读取到系统 Mail.app 账户"
            ) {
                Button("刷新") {
                    Task { await model.refreshMail() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        } else {
            ForEach(Array(accounts.enumerated()), id: \.element.id) { index, account in
                if index > 0 { rowDivider }
                settingRow(
                    symbol: "envelope",
                    title: account.displayName,
                    detail: account.id == account.displayName ? "系统 Mail.app 账户" : account.id
                ) {
                    Toggle("", isOn: mailAccountBinding(for: account.id, availableAccounts: accounts))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .disabled(isOnlySelectedMailAccount(account.id))
                }
            }
        }
    }

    private func mailAccountBinding(
        for accountName: String,
        availableAccounts: [MailAccount]
    ) -> Binding<Bool> {
        Binding(
            get: {
                let selected = model.settingsStore.settings.mailAccountNames
                return selected.isEmpty || selected.contains(accountName)
            },
            set: { isEnabled in
                var selected = model.settingsStore.settings.mailAccountNames
                if selected.isEmpty {
                    selected = Set(availableAccounts.map(\.id))
                }
                if isEnabled {
                    selected.insert(accountName)
                } else if selected.count > 1 {
                    selected.remove(accountName)
                }
                model.settingsStore.settings.mailAccountNames = selected
            }
        )
    }

    private func isOnlySelectedMailAccount(_ accountName: String) -> Bool {
        let selected = model.settingsStore.settings.mailAccountNames
        return selected.count == 1 && selected.contains(accountName)
    }

    private func moveCompactStatusPriority(_ priority: CompactStatusPriority, by offset: Int) {
        var priorities = model.settingsStore.settings.compactStatusPriority
        guard let index = priorities.firstIndex(of: priority) else { return }
        let destination = priorities.index(index, offsetBy: offset)
        guard priorities.indices.contains(destination) else { return }
        priorities.swapAt(index, destination)
        model.settingsStore.settings.compactStatusPriority = priorities
    }

    private func compactStatusPrioritySymbol(for priority: CompactStatusPriority) -> String {
        switch priority {
        case .transient: "bolt.fill"
        case .updateAvailable: "arrow.triangle.2.circlepath"
        case .mail: "envelope.fill"
        case .videoDownload: "arrow.down.square.fill"
        case .browserDownload: "arrow.down.circle.fill"
        case .focusCountdown: "timer"
        case .toolboxReminder: "wrench.and.screwdriver.fill"
        case .aiActivity: "sparkles"
        case .media: "music.note"
        case .focusMode: "moon.fill"
        }
    }

    private func settingRow<Trailing: View>(
        symbol: String,
        title: String,
        detail: String,
        detailLineLimit: Int? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                AppLocalizedText(title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if !detail.isEmpty {
                    AppLocalizedText(detail)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(detailLineLimit)
                }
            }
            .layoutPriority(1)
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, minHeight: 48)
    }

    private func repositoryLink(
        _ title: String,
        symbol: String,
        tint: Color,
        destination: URL,
        brandIconAsset: String? = nil
    ) -> some View {
        Button {
            NSWorkspace.shared.open(destination)
        } label: {
            HStack(spacing: 6) {
                if let brandIconAsset,
                   let image = brandIcon(named: brandIconAsset)
                {
                    Image(nsImage: image)
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .frame(width: 14, height: 14)
                        .frame(width: 16)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 16)
                }
                AppLocalizedText(title)
                    .font(.system(size: 10, weight: .semibold))
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .semibold))
            }
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, minHeight: 34)
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(tint)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(tint.opacity(colorScheme == .dark ? 0.18 : 0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(tint.opacity(colorScheme == .dark ? 0.42 : 0.24), lineWidth: 0.5)
        )
        .help("在浏览器中打开 \(title)")
        .accessibilityLabel("在浏览器中打开 \(title)")
    }

    private func settingsGroup<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            AppLocalizedText(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            VStack(spacing: 0) {
                content()
            }
            .overlay(alignment: .top) { Divider() }
            .overlay(alignment: .bottom) { Divider() }
        }
    }

    private var rowDivider: some View {
        Divider().padding(.leading, 38)
    }

    @ViewBuilder
    private var updateStatusAccessory: some View {
        if model.productUpdateAvailable {
            IconButton(
                symbol: "arrow.triangle.2.circlepath",
                help: "查看更新",
                isActive: true,
                size: .compact
            ) {
                model.checkForUpdates(
                    manual: true,
                    channel: model.settingsStore.settings.updateChannel
                )
            }
        } else {
        switch model.updateState {
        case .checking:
            ProgressView().controlSize(.small)
        case .current:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.zislaSuccess)
        case .available:
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(Color.zislaInfo)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.zislaWarning)
        case .idle:
            EmptyView()
        }
        }
    }

    private var updateStatusText: String {
        if model.productUpdateAvailable { return "发现可用新版本" }
        return switch model.updateState {
        case .idle: "尚未检查更新"
        case .checking: "正在检查更新"
        case .current: "已是最新版本"
        case .available(let release, let source): "发现 \(source.displayName) 新版本 \(release.tagName)"
        case .failed(let message): message
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.3"
    }

    private func searchWeatherLocation() {
        model.selectWeatherLocation(named: input.weatherQuery)
    }

    private func chooseDownloadDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = model.downloadDirectory
        WindowPlacement.prepareModal(panel, on: WindowPlacement.screenUnderMouse())
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.downloadDirectory = url
        if let bookmark = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            UserDefaults.standard.set(bookmark, forKey: "download-directory-bookmark")
        }
    }

    private func brandIcon(named name: String) -> NSImage? {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let candidates = [
            Bundle.main.resourceURL,
            sourceRoot.appendingPathComponent("Resources", isDirectory: true),
        ].compactMap { $0 }

        return candidates
            .map { $0.appendingPathComponent("BrandIcons/\(name)", isDirectory: false) }
            .lazy
            .compactMap(NSImage.init(contentsOf:))
            .first
    }

    private func commandRow(label: String, command: String) -> some View {
        HStack(spacing: 8) {
            AppLocalizedText(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 88, alignment: .leading)
            Text(command)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            IconButton(
                symbol: copiedCommand == command ? "checkmark" : "doc.on.doc",
                help: copiedCommand == command ? "已复制" : "复制\(label)",
                size: .compact
            ) {
                copyToClipboard(command)
            }
        }
        .frame(height: 20)
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copiedCommand = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if copiedCommand == text {
                copiedCommand = nil
            }
        }
    }

    private func languageDisplayName(_ language: AppLanguage) -> String {
        switch language {
        case .simplifiedChinese: return "简体中文"
        case .traditionalChinese: return "繁體中文"
        case .english: return "English"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        case .french: return "Français"
        case .german: return "Deutsch"
        case .spanish: return "Español"
        case .brazilianPortuguese: return "Português (Brasil)"
        case .italian: return "Italiano"
        case .dutch: return "Nederlands"
        case .russian: return "Русский"
        case .arabic: return "العربية"
        case .thai: return "ไทย"
        case .indonesian: return "Bahasa Indonesia"
        case .vietnamese: return "Tiếng Việt"
        case .turkish: return "Türkçe"
        }
    }

}

private struct ActivityNoticeDisplay: Identifiable {
    let id: UInt32
    let name: String
}

private struct VoiceInputHotkeyRecorder: NSViewRepresentable {
    @Binding var hotkey: VoiceInputHotkeyPreset

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> VoiceInputHotkeyRecorderButton {
        let button = VoiceInputHotkeyRecorderButton(hotkey: hotkey)
        button.onRecord = context.coordinator.record
        return button
    }

    func updateNSView(_ nsView: VoiceInputHotkeyRecorderButton, context: Context) {
        nsView.hotkey = hotkey
    }

    @MainActor
    final class Coordinator {
        private var parent: VoiceInputHotkeyRecorder

        init(_ parent: VoiceInputHotkeyRecorder) {
            self.parent = parent
        }

        func record(_ hotkey: VoiceInputHotkeyPreset) {
            parent.hotkey = hotkey
        }
    }
}

@MainActor
private final class VoiceInputHotkeyRecorderButton: NSButton {
    var hotkey: VoiceInputHotkeyPreset {
        didSet {
            if !isRecording {
                updateTitle()
            }
        }
    }
    var onRecord: ((VoiceInputHotkeyPreset) -> Void)?

    private var isRecording = false {
        didSet {
            if !isRecording {
                recordingModifierSides.removeAll()
                sawMultipleModifiers = false
            }
            updateTitle()
        }
    }
    private var recordingModifierSides: Set<VoiceInputModifier> = []
    private var sawMultipleModifiers = false

    init(hotkey: VoiceInputHotkeyPreset) {
        self.hotkey = hotkey
        super.init(frame: .zero)
        bezelStyle = .rounded
        font = .monospacedSystemFont(ofSize: 10, weight: .medium)
        lineBreakMode = .byTruncatingTail
        toolTip = "点击后按下快捷键，支持单键和区分左/右⌥、⌘、⇧"
        updateTitle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard !isRecording else { return }
        recordingModifierSides.removeAll()
        sawMultipleModifiers = false
        isRecording = true
        window?.makeFirstResponder(self)
    }

    override func flagsChanged(with event: NSEvent) {
        guard isRecording else {
            super.flagsChanged(with: event)
            return
        }
        guard let modifier = VoiceInputModifier(keyCode: UInt32(event.keyCode)) else { return }

        let previousModifierSides = recordingModifierSides
        let modifiers = carbonModifiers(from: event.modifierFlags)
        if modifiers & modifier.carbonModifier == 0 {
            recordingModifierSides.remove(modifier)
        } else if let opposite = opposite(of: modifier),
                  recordingModifierSides.contains(modifier),
                  recordingModifierSides.contains(opposite) {
            recordingModifierSides.remove(modifier)
        } else {
            recordingModifierSides.insert(modifier)
        }
        if recordingModifierSides.count > 1 {
            sawMultipleModifiers = true
        }
        if previousModifierSides == [modifier],
           recordingModifierSides.isEmpty,
           !sawMultipleModifiers {
            record(
                VoiceInputHotkeyPreset(
                    keyCode: modifier.keyCode,
                    carbonModifiers: modifier.carbonModifier,
                    keyDisplayName: modifier.displayName,
                    modifierSides: [modifier]
                )
            )
            return
        }
        updateTitle()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        let modifiers = carbonModifiers(from: event.modifierFlags)
        if event.keyCode == 53, modifiers == 0 {
            isRecording = false
            return
        }
        record(VoiceInputHotkeyPreset(
            keyCode: UInt32(event.keyCode),
            carbonModifiers: modifiers,
            keyDisplayName: keyDisplayName(for: event),
            modifierSides: recordingModifierSides.isEmpty ? nil : recordingModifierSides
        ))
    }

    private func record(_ recordedHotkey: VoiceInputHotkeyPreset) {
        hotkey = recordedHotkey
        isRecording = false
        onRecord?(recordedHotkey)
        window?.makeFirstResponder(nil)
    }

    override func cancelOperation(_ sender: Any?) {
        if isRecording {
            isRecording = false
        } else {
            super.cancelOperation(sender)
        }
    }

    override func resignFirstResponder() -> Bool {
        let didResign = super.resignFirstResponder()
        if didResign, isRecording {
            isRecording = false
        }
        return didResign
    }

    private func updateTitle() {
        guard isRecording else {
            title = hotkey.displayName
            return
        }
        let modifierNames = VoiceInputModifier.allCases
            .filter(recordingModifierSides.contains)
            .map(\.displayName)
        title = modifierNames.isEmpty
            ? "按下组合键..."
            : "\(modifierNames.joined(separator: " + ")) + ..."
    }

    private func opposite(of modifier: VoiceInputModifier) -> VoiceInputModifier? {
        switch modifier {
        case .leftControl: .rightControl
        case .rightControl: .leftControl
        case .leftOption: .rightOption
        case .rightOption: .leftOption
        case .leftCommand: .rightCommand
        case .rightCommand: .leftCommand
        case .leftShift: .rightShift
        case .rightShift: .leftShift
        }
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        let flags = flags.intersection(.deviceIndependentFlagsMask)
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= 0x0100 }
        if flags.contains(.shift) { modifiers |= 0x0200 }
        if flags.contains(.option) { modifiers |= 0x0800 }
        if flags.contains(.control) { modifiers |= 0x1000 }
        return modifiers
    }

    private func keyDisplayName(for event: NSEvent) -> String {
        switch event.keyCode {
        case 36: "回车"
        case 48: "Tab"
        case 49: "空格"
        case 51: "删除"
        case 53: "Esc"
        case 115: "Home"
        case 116: "Page Up"
        case 117: "向前删除"
        case 119: "End"
        case 121: "Page Down"
        case 123: "←"
        case 124: "→"
        case 125: "↓"
        case 126: "↑"
        default:
            event.charactersIgnoringModifiers?.uppercased() ?? "键码 \(event.keyCode)"
        }
    }
}

enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case features
    case workflow
    case info
    case ai
    case voice
    case models
    case pet
    case privacy
    case download
    case weather
    case recommendations
    case updates

    var id: Self { self }

    /// AI, voice history, and model configuration need room for their dense content.
    var prefersWideLayout: Bool {
        self == .ai || self == .voice || self == .models
    }

    var title: String {
        switch self {
        case .general: "通用"
        case .features: "功能"
        case .workflow: "工作流"
        case .info: "信息"
        case .ai: "AI"
        case .voice: "语音"
        case .models: "模型"
        case .pet: "桌面宠物"
        case .privacy: "隐私"
        case .download: "下载"
        case .weather: "天气"
        case .updates: "更新"
        case .recommendations: "推荐"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .features: "switch.2"
        case .workflow: "square.grid.2x2.fill"
        case .info: "info.circle.fill"
        case .ai: "sparkles"
        case .voice: "mic.fill"
        case .models: "cpu"
        case .pet: "pawprint.fill"
        case .privacy: "hand.raised.fill"
        case .download: "arrow.down.circle.fill"
        case .weather: "cloud.sun.fill"
        case .updates: "arrow.up.circle"
        case .recommendations: "sparkles"
        }
    }

    var subtitle: String {
        switch self {
        case .general: "调整语言、外观、启动与展开方式。"
        case .features: "集中开启或关闭所有功能模块。"
        case .workflow: "管理灵动岛中的工作流模块。"
        case .info: "配置日历、邮件、锁屏与通知显示。"
        case .ai: "AI 进度，以及连接、自动化、CLI 与 Skills 等 Agent 行为。"
        case .voice: "管理语音输入，并查看保存在本机的原始录音、识别文本与统计。"
        case .models: "配置本地模型、远端模型与凭据，并选择语音整理使用的模型。"
        case .pet: "设置灵动岛内部的宠物形象。"
        case .privacy: "管理剪贴板访问与本机数据。"
        case .download: "管理下载目录、下载通知与所需组件。"
        case .weather: "管理天气显示、地点和刷新。"
        case .updates: "管理版本检查与自动更新。"
        case .recommendations: "一键下载和更新精选效率、网络、开发与桌面工具。"
        }
    }
}

@MainActor
private final class SettingsInput: ObservableObject {
    @Published var selection: SettingsSection = .general
    @Published var voicePage: VoiceSettingsPage = .settings
    @Published var weatherQuery = ""
}

private enum VoiceSettingsPage: String, CaseIterable, Identifiable {
    case settings
    case history

    var id: Self { self }

    var title: String {
        switch self {
        case .settings: "语音设置"
        case .history: "语音记录"
        }
    }
}

private enum RecommendedToolAction {
    case install
    case update

    var title: String {
        switch self {
        case .install: "下载缺失推荐工具？"
        case .update: "更新已安装推荐工具？"
        }
    }

    func message(itemCount: Int) -> String {
        switch self {
        case .install:
            "将通过官方安装来源下载并安装 \(itemCount) 项缺失工具。工具较多时可能需要一些时间。"
        case .update:
            "将通过官方安装来源更新 \(itemCount) 项已安装工具。工具较多时可能需要一些时间。"
        }
    }
}

private struct WeatherLocationReorderDropDelegate: DropDelegate {
    static let supportedTypes = [
        UTType.utf8PlainText.identifier,
        UTType.plainText.identifier,
    ]

    let destinationID: String
    @Binding var draggingID: String?
    var move: @MainActor @Sendable (String, String) -> Bool

    func validateDrop(info: DropInfo) -> Bool {
        draggingID != nil
            && draggingID != destinationID
            && info.hasItemsConforming(to: Self.supportedTypes)
    }

    func dropEntered(info: DropInfo) {
        guard let draggingID else { return }
        _ = move(draggingID, destinationID)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingID = nil
        return true
    }
}
