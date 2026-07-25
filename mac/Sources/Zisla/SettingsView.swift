import AppKit
import ZislaCore
import ZislaKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @StateObject private var input = SettingsInput()
    @StateObject private var launchAtLogin = LaunchAtLoginController()
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var searchFieldFocused: Bool
    @State private var draggedWeatherLocationID: String?

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detail
        }
        .frame(width: 548, height: 510)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            launchAtLogin.refresh()
            model.refreshVoiceInputInputMonitoringAccess()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            launchAtLogin.refresh()
            model.refreshVoiceInputInputMonitoringAccess()
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

            VStack(spacing: 4) {
                ForEach(SettingsSection.allCases) { section in
                    Button {
                        input.selection = section
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: section.symbol)
                                .font(.system(size: 12, weight: .semibold))
                                .frame(width: 17)
                            Text(section.title)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8)
                        .frame(height: 34)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(input.selection == section ? Color.primary : Color.secondary)
                    .background(
                        input.selection == section ? Color.accentColor.opacity(0.14) : Color.clear
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .accessibilityLabel("\(section.title)设置")
                }
            }
            .padding(.top, 20)

            Spacer(minLength: 12)

            Text("版本 \(appVersion)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.tertiary)
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
                    Text(input.selection.title)
                        .font(.system(size: 20, weight: .semibold))
                    Text(input.selection.subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                selectedContent
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch input.selection {
        case .workflow:
            workflowContent
        case .info:
            infoContent
        case .aiMonitor:
            aiMonitorContent
        case .voice:
            voiceContent
        case .pet:
            petContent
        case .interaction:
            interactionContent
        case .services:
            servicesContent
        case .updates:
            updatesContent
        }
    }

    private var workflowContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingsGroup("工作流模块") {
                featureToggle(
                    "媒体播放",
                    detail: "显示系统正在播放的音乐或视频",
                    symbol: "play.square.fill",
                    keyPath: \.mediaEnabled
                )
                rowDivider
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
                            Text(source.title).tag(source)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .frame(width: 132)
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
                featureToggle(
                    "文件中转与分享",
                    detail: "暂存文件并调用 AirDrop 或系统分享",
                    symbol: "tray.full.fill",
                    keyPath: \.fileShelfEnabled
                )
                rowDivider
                featureToggle(
                    "链接下载",
                    detail: "下载视频或音频",
                    symbol: "arrow.down.circle.fill",
                    keyPath: \.downloaderEnabled
                )
                rowDivider
                featureToggle(
                    "小工具",
                    detail: "番茄钟、亮屏与屏幕清洁",
                    symbol: "wrench.and.screwdriver.fill",
                    keyPath: \.toolboxEnabled
                )
                rowDivider
                featureToggle(
                    "随记",
                    detail: "Markdown 随手记，可发送到系统备忘录",
                    symbol: "note.text",
                    keyPath: \.quickNotesEnabled
                )
                rowDivider
                featureToggle(
                    "系统状态与清理",
                    detail: "监控资源并安全清理缓存和日志",
                    symbol: "gauge.with.dots.needle.67percent",
                    keyPath: \.systemMonitorEnabled
                )
                rowDivider
                settingRow(
                    symbol: "app.badge",
                    title: "显示 zisla 图标",
                    detail: "关闭后不影响已启用的菜单栏监控项"
                ) {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { model.settingsStore.settings.menuBarAppIconEnabled },
                            set: { model.settingsStore.settings.menuBarAppIconEnabled = $0 }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
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
                        Picker(
                            "",
                            selection: Binding(
                                get: { model.settingsStore.settings.systemMonitorMenuBarDisplayStyle },
                                set: { model.settingsStore.settings.systemMonitorMenuBarDisplayStyle = $0 }
                            )
                        ) {
                            ForEach(SystemMonitorMenuBarDisplayStyle.allCases, id: \.self) { style in
                                Text(style.menuTitle).tag(style)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .controlSize(.small)
                        .frame(width: 128)
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

    private var infoContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingsGroup("信息与通知") {
                featureToggle(
                    "日历日程",
                    detail: "显示接下来的日程与会议",
                    symbol: "calendar",
                    keyPath: \.calendarEnabled
                )
                rowDivider
                featureToggle(
                    "天气",
                    detail: "显示当前或自选地区的天气",
                    symbol: "cloud.sun.fill",
                    keyPath: \.weatherEnabled
                )
                rowDivider
                featureToggle(
                    "邮件",
                    detail: "读取已配置的 Mail.app 账户并提醒新邮件",
                    symbol: "envelope.fill",
                    keyPath: \.mailEnabled
                )
                if model.settingsStore.settings.mailEnabled {
                    rowDivider
                    mailAccountSettings
                }
                rowDivider
                featureToggle(
                    "锁屏信息",
                    detail: "在系统锁屏页显示状态信息与播放器",
                    symbol: "lock.display",
                    keyPath: \.lockScreenInfoEnabled
                )
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
                featureToggle(
                    "侧翼通知",
                    detail: "在灵动岛肩部显示任务变化",
                    symbol: "bell.badge.fill",
                    keyPath: \.sideNoticesEnabled
                )
                rowDivider
                featureToggle(
                    "岛上倒计时",
                    detail: "专注时在收起态灵动岛显示剩余时间",
                    symbol: "clock",
                    keyPath: \.focusCountdownIslandEnabled
                )
                .disabled(!model.settingsStore.settings.sideNoticesEnabled)
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
                            Text(duration.menuTitle).tag(duration)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .frame(maxWidth: 96)
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
                            Text(duration.menuTitle).tag(duration)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .frame(maxWidth: 96)
                    .disabled(!model.settingsStore.settings.sideNoticesEnabled)
                }
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

    private var aiMonitorContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingsGroup("通知与用量") {
                featureToggle(
                    "AI 进度与用量",
                    detail: "汇总桌面端与 CLI 工具的运行状态",
                    symbol: "sparkles",
                    keyPath: \.aiProgressEnabled
                )
            }
        }
    }

    private var voiceContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            // ── 语音输入 ──
            settingsGroup("语音输入") {
                featureToggle(
                    "启用语音输入",
                    detail: "开启后可通过全局快捷键触发语音输入",
                    symbol: "mic.fill",
                    keyPath: \.voiceInputEnabled
                )
                if model.settingsStore.settings.voiceInputEnabled {
                    rowDivider
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
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        .frame(maxWidth: 110)
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

            // ── 模型端点 ──
            settingsGroup("模型端点") {
                settingRow(
                    symbol: "network",
                    title: "运行位置",
                    detail: model.settingsStore.settings.voiceModelEndpointMode.detail
                ) {
                    Picker(
                        "",
                        selection: Binding(
                            get: { model.settingsStore.settings.voiceModelEndpointMode },
                            set: { (newValue: VoiceModelEndpointMode) in
                                model.settingsStore.settings.voiceModelEndpointMode = newValue
                                model.discoveredModels = []
                                model.voiceModelDiscoveryState = .idle
                            }
                        )
                    ) {
                        ForEach(VoiceModelEndpointMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .frame(width: 138)
                }
                rowDivider
                if model.settingsStore.settings.voiceModelEndpointMode == .local {
                    settingRow(
                        symbol: "server.rack",
                        title: "服务类型",
                        detail: "选择本地运行的模型服务"
                    ) {
                        Picker(
                            "",
                            selection: Binding(
                                get: { model.settingsStore.settings.voiceModelEndpointKind },
                                set: { (newValue: AIEndpointKind) in
                                    model.settingsStore.settings.voiceModelEndpointKind = newValue
                                    model.settingsStore.settings.voiceModelBaseURL = newValue.defaultBaseURL
                                    model.discoveredModels = []
                                    model.voiceModelDiscoveryState = .idle
                                }
                            )
                        ) {
                            ForEach(AIEndpointKind.allCases, id: \.self) { kind in
                                Text(kind.displayName).tag(kind)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        .frame(maxWidth: 160)
                    }
                    rowDivider
                    settingRow(
                        symbol: "link",
                        title: "服务地址",
                        detail: "模型的 API 基础地址"
                    ) {
                        TextField(
                            "http://127.0.0.1:1234/v1",
                            text: Binding(
                                get: { model.settingsStore.settings.voiceModelBaseURL },
                                set: { model.settingsStore.settings.voiceModelBaseURL = $0 }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 200)
                    }
                    rowDivider
                    settingRow(
                        symbol: "cpu",
                        title: "模型名称",
                        detail: "填写服务端使用的模型 ID"
                    ) {
                        TextField(
                            "例如 qwen3:8b",
                            text: Binding(
                                get: { model.currentVoiceModelName },
                                set: { model.updateCurrentVoiceModelName($0) }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 200)
                    }
                } else if let remoteEndpoint = model.selectedVoiceModelRemoteEndpoint {
                    settingRow(
                        symbol: "server.rack",
                        title: "当前端点",
                        detail: model.settingsStore.settings.voiceModelRemoteLoadBalancingEnabled
                            ? "LB 开启，连接测试会轮询已启用端点"
                            : "LB 关闭，手动选择 URL、Key 和模型"
                    ) {
                        HStack(spacing: 6) {
                            Picker(
                                "",
                                selection: Binding(
                                    get: { remoteEndpoint.id },
                                    set: { model.selectVoiceModelRemoteEndpoint($0) }
                                )
                            ) {
                                ForEach(model.settingsStore.settings.voiceModelRemoteEndpoints) { endpoint in
                                    Text(endpoint.name).tag(endpoint.id)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .controlSize(.small)
                            .frame(width: 138)

                            Button {
                                model.addVoiceModelRemoteEndpoint()
                            } label: {
                                Image(systemName: "plus")
                            }
                            .buttonStyle(.borderless)
                            .help("添加端点")

                            Button {
                                model.removeSelectedVoiceModelRemoteEndpoint()
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("删除当前端点")
                        }
                    }
                    rowDivider
                    settingRow(
                        symbol: "tag",
                        title: "端点名称",
                        detail: "仅用于区分不同 URL 组"
                    ) {
                        TextField(
                            "远端端点",
                            text: Binding(
                                get: { remoteEndpoint.name },
                                set: { value in
                                    model.updateSelectedVoiceModelRemoteEndpoint { $0.name = value }
                                }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                    }
                    rowDivider
                    settingRow(
                        symbol: "link",
                        title: "服务地址",
                        detail: "此端点的 OpenAI 兼容 API 基础地址"
                    ) {
                        TextField(
                            "https://api.example.com/v1",
                            text: Binding(
                                get: { remoteEndpoint.baseURL },
                                set: { value in
                                    model.updateSelectedVoiceModelRemoteEndpoint { $0.baseURL = value }
                                }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 200)
                    }
                    rowDivider
                    settingRow(
                        symbol: "cpu",
                        title: "模型名称",
                        detail: "填写此端点要使用的模型 ID"
                    ) {
                        TextField(
                            "例如 gpt-4.1-mini",
                            text: Binding(
                                get: { remoteEndpoint.modelName },
                                set: { value in
                                    model.updateSelectedVoiceModelRemoteEndpoint { $0.modelName = value }
                                }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 200)
                    }
                    rowDivider
                    settingRow(
                        symbol: "key",
                        title: "API Key",
                        detail: "仅保存到此 Mac 的 zisla 设置文件"
                    ) {
                        SecureField(
                            "sk-...",
                            text: Binding(
                                get: { remoteEndpoint.apiKey ?? "" },
                                set: { model.updateVoiceModelRemoteAPIKey($0) }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 200)
                    }
                    rowDivider
                    settingRow(
                        symbol: "checkmark.circle",
                        title: "启用端点",
                        detail: "关闭后不会参与手动使用或 LB"
                    ) {
                        Toggle("", isOn: Binding(
                            get: { remoteEndpoint.isEnabled },
                            set: { enabled in
                                model.updateSelectedVoiceModelRemoteEndpoint { $0.isEnabled = enabled }
                            }
                        ))
                        .labelsHidden()
                        .controlSize(.small)
                    }
                    rowDivider
                    settingRow(
                        symbol: "arrow.triangle.2.circlepath",
                        title: "负载均衡",
                        detail: "开启后在全部已启用端点间轮询"
                    ) {
                        Toggle("", isOn: Binding(
                            get: { model.settingsStore.settings.voiceModelRemoteLoadBalancingEnabled },
                            set: { model.setVoiceModelRemoteLoadBalancingEnabled($0) }
                        ))
                        .labelsHidden()
                        .controlSize(.small)
                    }
                } else {
                    settingRow(
                        symbol: "server.rack",
                        title: "远端端点",
                        detail: "添加一个 URL、API Key 和模型配置"
                    ) {
                        Button {
                            model.addVoiceModelRemoteEndpoint()
                        } label: {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.borderless)
                        .help("添加端点")
                    }
                }
                rowDivider
                settingRow(
                    symbol: "magnifyingglass.circle",
                    title: "连接测试",
                    detail: discoveryStatusText
                ) {
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

            // ── 模型选择 ──
            if !model.discoveredModels.isEmpty {
                settingsGroup("已发现模型") {
                    ForEach(Array(model.discoveredModels.enumerated()), id: \.element.id) { index, discovered in
                        if index > 0 { rowDivider }
                        let isSelected = model.currentVoiceModelName == discovered.name
                        settingRow(
                            symbol: isSelected ? "checkmark.circle.fill" : "cpu",
                            title: discovered.name,
                            detail: isSelected ? "当前使用" : "点击选择此模型"
                        ) {
                            if !isSelected {
                                Button("选择") {
                                    model.updateCurrentVoiceModelName(discovered.name)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                }
            }

            // ── 硬件档案与推荐 ──
            settingsGroup("设备档案与推荐模型") {
                if let profile = model.hardwareProfile {
                    settingRow(
                        symbol: "desktopcomputer",
                        title: profile.machineName,
                        detail: profile.displayDescription
                    ) {
                        EmptyView()
                    }
                    ForEach(Array(AIModelRecommendations.recommended(for: profile).enumerated()), id: \.element.id) { index, rec in
                        rowDivider
                        settingRow(
                            symbol: "lightbulb.fill",
                            title: "\(rec.name) · \(rec.parameterScale)",
                            detail: rec.reason
                        ) {
                            EmptyView()
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

            // ── 提示信息 ──
            settingsGroup("使用说明") {
                VStack(alignment: .leading, spacing: 6) {
                    Label("本地模式先启动 LM Studio 或 Ollama", systemImage: "1.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Label("远端模式可添加多组 URL、API Key 和模型", systemImage: "2.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Label("关闭 LB 手动选端点；开启后轮询已启用端点", systemImage: "3.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Label("点击「测试连接」发现模型，或直接输入模型名称", systemImage: "4.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 8)
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
                featureToggle(
                    "岛上宠物伙伴",
                    detail: "在灵动岛养一只小宠物",
                    symbol: "pawprint.fill",
                    keyPath: \.petEnabled
                )
                rowDivider
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
                    .frame(maxWidth: 150)
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
                    .frame(maxWidth: 100)
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

    private var interactionContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingsGroup("外观") {
                settingRow(
                    symbol: "circle.lefthalf.filled",
                    title: "界面外观",
                    detail: ""
                ) {
                    Picker(
                        "",
                        selection: Binding(
                            get: { model.settingsStore.settings.appearanceMode },
                            set: { model.settingsStore.settings.appearanceMode = $0 }
                        )
                    ) {
                        ForEach(AppearanceMode.allCases, id: \.self) { mode in
                            Text(mode.menuTitle).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .frame(width: 216)
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

            settingsGroup("展开方式") {
                featureToggle(
                    "鼠标移入展开",
                    detail: "鼠标进入屏幕顶部感应区时显示",
                    symbol: "cursorarrow.motionlines",
                    keyPath: \.hoverActivationEnabled
                )
            }

            settingsGroup("隐私") {
                featureToggle(
                    "记录剪贴板历史",
                    detail: "仅本机保存文本和图片，默认关闭",
                    symbol: "clipboard",
                    keyPath: \.clipboardHistoryEnabled
                )
                rowDivider
                featureToggle(
                    "检测剪贴板链接",
                    detail: "发现可下载链接时提示，默认关闭",
                    symbol: "clipboard.fill",
                    keyPath: \.clipboardDetectionEnabled
                )
            }
        }
    }

    private var servicesContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingsGroup("下载") {
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

            settingsGroup("天气位置") {
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
                featureToggle(
                    "检查更新",
                    detail: "定期查询项目的最新发布版本",
                    symbol: "arrow.triangle.2.circlepath",
                    keyPath: \.updateChecksEnabled
                )
                rowDivider
                featureToggle(
                    "自动安装更新",
                    detail: "",
                    symbol: "shippingbox.and.arrow.backward.fill",
                    keyPath: \.automaticUpdatesEnabled
                )
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
                    Button {
                        model.checkForUpdates(manual: true)
                    } label: {
                        Label("立即检查", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    HStack(spacing: 8) {
                        repositoryLink(
                            "GitHub",
                            symbol: "chevron.left.forwardslash.chevron.right",
                            tint: .primary,
                            destination: ZislaKitInfo.repositoryURL
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

    private func settingRow<Trailing: View>(
        symbol: String,
        title: String,
        detail: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .layoutPriority(1)
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 4)
        .frame(minHeight: 48)
    }

    private func repositoryLink(
        _ title: String,
        symbol: String,
        tint: Color,
        destination: URL
    ) -> some View {
        Button {
            NSWorkspace.shared.open(destination)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 16)
                Text(title)
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
            Text(title)
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

    private var updateStatusText: String {
        switch model.updateState {
        case .idle: "尚未检查更新"
        case .checking: "正在检查更新"
        case .current: "已是最新版本"
        case .available(let release, let source): "发现 \(source.displayName) 新版本 \(release.tagName)"
        case .failed(let message): message
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
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
        WindowPlacement.center(panel, on: WindowPlacement.screenUnderMouse())
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

private enum SettingsSection: String, CaseIterable, Identifiable {
    case workflow
    case info
    case aiMonitor
    case voice
    case pet
    case interaction
    case services
    case updates

    var id: Self { self }

    var title: String {
        switch self {
        case .workflow: "工作流"
        case .info: "信息"
        case .aiMonitor: "AI 监控"
        case .voice: "语音与模型"
        case .pet: "桌面宠物"
        case .interaction: "交互"
        case .services: "下载与天气"
        case .updates: "更新"
        }
    }

    var symbol: String {
        switch self {
        case .workflow: "square.grid.2x2.fill"
        case .info: "info.circle.fill"
        case .aiMonitor: "chart.xyaxis.line"
        case .voice: "mic.and.waveform"
        case .pet: "pawprint.fill"
        case .interaction: "cursorarrow.motionlines"
        case .services: "arrow.down.circle.fill"
        case .updates: "arrow.triangle.2.circlepath"
        }
    }

    var subtitle: String {
        switch self {
        case .workflow: "管理灵动岛中的工作流模块。"
        case .info: "配置日历、天气、邮件与通知显示。"
        case .aiMonitor: "管理 AI 进度监控的显示。"
        case .voice: "配置语音输入快捷键与本地小模型端点。"
        case .pet: "设置灵动岛内部的宠物形象。"
        case .interaction: "调整外观、展开方式与隐私行为。"
        case .services: "管理下载目录和天气数据位置。"
        case .updates: "管理版本检查与自动更新。"
        }
    }
}

@MainActor
private final class SettingsInput: ObservableObject {
    @Published var selection: SettingsSection = .workflow
    @Published var weatherQuery = ""
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
