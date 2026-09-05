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
    @StateObject private var networkProxyMonitor = NetworkProxyAvailabilityMonitor()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var searchFieldFocused: Bool
    @State private var draggedWeatherLocationID: String?
    @State private var sectionSwitchDirection: CGFloat = 1
    @State private var pendingRecommendedToolAction: RecommendedToolAction?
    @State private var isVoiceHistoryClearConfirmationPresented = false
    @State private var isVoiceHistoryBatchDeleteConfirmationPresented = false
    @State private var voiceHistorySelectionMode = false
    @State private var selectedVoiceHistoryIDs: Set<UUID> = []
    @State private var customVoiceHotword = ""
    @State private var screenshotHotkeyValidationMessage: String?
    @State private var expandedClipboardAssistantKind: ClipboardAssistantKind?
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
            height: 640
        )
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            launchAtLogin.refresh()
            model.refreshVoiceInputInputMonitoringAccess()
            model.refreshAssistantAccessibility()
            ensureSelectionIsVisible()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            launchAtLogin.refresh()
            model.refreshVoiceInputInputMonitoringAccess()
            model.refreshAssistantAccessibility()
            model.backgroundSounds.refresh()
        }
        .onChange(of: settingsStore.settings) { _, _ in
            ensureSelectionIsVisible()
        }
        .alert(
            pendingRecommendedToolAction?.title ?? "",
            isPresented: Binding(
                get: { pendingRecommendedToolAction != nil },
                set: { if !$0 { pendingRecommendedToolAction = nil } }
            )
        ) {
            Button(AppLocalization.text("取消"), role: .cancel) {
                pendingRecommendedToolAction = nil
            }
            Button(AppLocalization.text("继续")) {
                guard let action = pendingRecommendedToolAction else { return }
                pendingRecommendedToolAction = nil
                Task { await performRecommendedToolAction(action) }
            }
        } message: {
            Text(recommendedToolActionMessage)
        }
        .alert(AppLocalization.text("清空所有语音记录？"), isPresented: $isVoiceHistoryClearConfirmationPresented) {
            Button(AppLocalization.text("取消"), role: .cancel) {}
            Button(AppLocalization.text("清空"), role: .destructive) {
                model.removeAllVoiceRecordings()
            }
        } message: {
            Text(AppLocalization.text("本机保存的识别文本和原始录音文件都会被删除，但累计统计数据（总字词、时长等）会保留。此操作无法撤销。"))
        }
        .alert(AppLocalization.text("删除选中的语音记录？"), isPresented: $isVoiceHistoryBatchDeleteConfirmationPresented) {
            Button(AppLocalization.text("取消"), role: .cancel) {}
            Button(AppLocalization.text("删除"), role: .destructive) {
                deleteSelectedVoiceHistoryEntries()
            }
        } message: {
            Text(AppLocalization.text("选中的识别文本和原始录音文件都会被删除，但累计统计数据（总字词、时长等）会保留。此操作无法撤销。"))
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("zisla")
                .font(.system(size: 14, weight: .semibold))
            Text(AppLocalization.text("设置"))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(.top, 1)

            VStack(spacing: 2) {
                ForEach(visibleSections) { section in
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
                    .accessibilityLabel(AppLocalization.text("%@设置", AppLocalization.text(section.title)))
                }
            }
            .padding(.top, 20)
            .animation(reduceMotion ? nil : ZislaMotion.selection, value: input.selection)

            Spacer(minLength: 12)

            HStack(spacing: 6) {
                Text(AppLocalization.text("版本 %@", appVersion))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
                Button {
                    NSApp.terminate(nil)
                } label: {
                    HStack(spacing: 6) {
                        IconButtonLabel(
                            symbol: "power",
                            size: .compact,
                            showsInactiveBackground: false
                        )
                        Text(AppLocalization.text("退出"))
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .padding(.trailing, 7)
                    .background(Color.fillControl)
                    .clipShape(Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle(hoverScale: 1.018, pressedScale: 0.965))
                .help(AppLocalization.text("退出应用"))
                .accessibilityLabel(AppLocalization.text("退出应用"))
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
                        .id(input.selection)
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .settingsPagePush(direction: sectionSwitchDirection)
                        )
                }
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

    private var visibleSections: [SettingsSection] {
        SettingsSection.allCases.filter { $0.isVisible(settings: settingsStore.settings) }
    }

    private func ensureSelectionIsVisible() {
        guard !input.selection.isVisible(settings: settingsStore.settings) else { return }
        selectSettingsSection(.features)
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch input.selection {
        case .general:
            generalContent
        case .features:
            featuresContent
        case .keyboardSound:
            keyboardSoundContent
        case .clipboardAssistant, .screenshot:
            featuresContent
        case .workflow:
            workflowContent
        case .info:
            infoContent
        case .ai:
            aiContent
        case .voice:
            voiceContent
        case .pet:
            petContent
        case .download:
            downloadContent
        case .networkProxy:
            networkProxyContent
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
                        detail: "紧凑模式隐藏图标并减小字号，减少菜单栏占用",
                        isNested: true
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
                            detail: "显示实时监控摘要",
                            isNested: true
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
            if input.selection == .features {
                settingsGroup("媒体与文件") {
                    featureToggle("媒体播放", detail: "显示系统正在播放的音乐或视频", symbol: "play.square.fill", keyPath: \.mediaEnabled)
                    rowDivider
                    featureToggle(
                        AppLocalization.text("Mac 未使用时关闭背景音"),
                        detail: "锁屏、屏保启动或显示器休眠时，自动关闭背景音",
                        symbol: "lock.display",
                        keyPath: \.systemBackgroundSoundStopsWhenUnused
                    )
                    rowDivider
                    featureToggle("文件中转与分享", detail: "暂存文件并调用 AirDrop 或系统分享", symbol: "tray.full.fill", keyPath: \.fileShelfEnabled)
                    rowDivider
                    featureToggle("链接下载", detail: "下载视频或音频", symbol: "arrow.down.circle.fill", keyPath: \.downloaderEnabled)
                    rowDivider
                    featureToggle(AppLocalization.text("剪贴板历史"), detail: "仅本机保存文本和图片", symbol: "clipboard", keyPath: \.clipboardHistoryEnabled)
                    rowDivider
                    featureToggle(AppLocalization.text("剪贴板链接检测"), detail: "发现可下载链接时提示", symbol: "clipboard.fill", keyPath: \.clipboardDetectionEnabled)
                }
            }

            if input.selection == .features {
                settingsGroup("复制助手") {
                    featureToggle(
                        "复制助手",
                        detail: "复制后弹出识别结果和下一步操作",
                        symbol: "sparkles.rectangle.stack",
                        keyPath: \.clipboardAssistantEnabled
                    )
                }
            }
            if input.selection == .clipboardAssistant {
                settingsGroup("复制助手") {
                    settingRow(
                        symbol: "keyboard",
                        title: "快速触发快捷键",
                        detail: clipboardAssistantHotkeyDetail
                    ) {
                        HStack(spacing: 4) {
                            HotkeyRecorder(
                                hotkey: Binding(
                                    get: { model.settingsStore.settings.clipboardAssistantTriggerConfiguration.hotkey },
                                    set: { newValue in
                                        model.settingsStore.settings.clipboardAssistantTriggerConfiguration =
                                            newValue.map(ClipboardAssistantTriggerConfiguration.hotkey) ?? .none
                                    }
                                )
                            )
                            .frame(width: 142, height: 26)
                            if model.settingsStore.settings.clipboardAssistantTriggerConfiguration.hotkey != nil {
                                Button {
                                    model.settingsStore.settings.clipboardAssistantTriggerConfiguration = .none
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help(loc("清除快捷键"))
                            }
                        }
                    }
                    if clipboardAssistantTriggersRequireInputMonitoring {
                        rowDivider
                        settingRow(
                            symbol: "lock.shield",
                            title: "输入监控",
                            detail: "单独修饰键或鼠标侧键需要监听全局事件",
                            isNested: true
                        ) {
                            if model.voiceInputInputMonitoringAccessGranted {
                                Label {
                                    AppLocalizedText("已授权")
                                } icon: {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                                .font(.caption)
                            } else {
                                Button {
                                    model.openVoiceInputInputMonitoringSettings()
                                } label: {
                                    AppLocalizedText("去授权")
                                }
                                .controlSize(.small)
                            }
                        }
                    }
                    rowDivider
                    settingRow(
                        symbol: "computermouse",
                        title: "鼠标侧键",
                        detail: "提示可见时按下侧键触发主动作"
                    ) {
                        Picker(
                            "",
                            selection: Binding(
                                get: { ClipboardAssistantMouseTriggerOption(
                                    buttonNumber: model.settingsStore.settings.clipboardAssistantMouseButton
                                ) },
                                set: { model.settingsStore.settings.clipboardAssistantMouseButton = $0.buttonNumber }
                            )
                        ) {
                            ForEach(ClipboardAssistantMouseTriggerOption.allCases, id: \.self) { option in
                                AppLocalizedText(option.label).tag(option)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        .frame(width: 150, alignment: .trailing)
                    }
                    rowDivider
                    settingRow(
                        symbol: "hand.tap",
                        title: "鼠标手势快速复制",
                        detail: "按住左键点右键复制选中文本，默认关闭"
                    ) {
                        Toggle("", isOn: Binding(
                            get: { model.settingsStore.settings.clipboardAssistantMouseGestureEnabled },
                            set: { enabled in
                                model.settingsStore.settings.clipboardAssistantMouseGestureEnabled = enabled
                                if enabled, !model.assistantAccessibilityGranted {
                                    AccessibilityPermission.promptIfNeeded()
                                }
                            }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    }
                    if model.settingsStore.settings.clipboardAssistantMouseGestureEnabled
                        && !model.assistantAccessibilityGranted {
                        rowDivider
                        settingRow(
                            symbol: "lock.shield",
                            title: "辅助功能",
                            detail: "模拟 Command-C 复制选中内容需要辅助功能权限",
                            isNested: true
                        ) {
                            Button {
                                model.openAssistantAccessibilitySettings()
                            } label: {
                                AppLocalizedText("去授权")
                            }
                            .controlSize(.small)
                        }
                    }
                    rowDivider
                    featureToggle(
                        "轻量提醒模式",
                        detail: "提示更简洁，点击整条执行主动作",
                        symbol: "sparkle",
                        keyPath: \.clipboardAssistantLightweightMode
                    )
                    rowDivider
                    settingRow(
                        symbol: "timer",
                        title: "存在时长",
                        detail: "提示自动关闭前的时间；永不则仅手动关闭"
                    ) {
                        Picker(
                            "",
                            selection: Binding(
                                get: { model.settingsStore.settings.clipboardAssistantDisplayDuration },
                                set: { model.settingsStore.settings.clipboardAssistantDisplayDuration = $0 }
                            )
                        ) {
                            ForEach(ClipboardAssistantDisplayDuration.allCases, id: \.self) { duration in
                                AppLocalizedText(duration.menuTitle).tag(duration)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        .frame(width: 150, alignment: .trailing)
                    }
                    rowDivider
                    featureToggle(
                        AppLocalization.text("每次保存图片时选择位置"),
                        detail: "关闭时保存到“下载”中的默认下载目录",
                        symbol: "folder",
                        keyPath: \.clipboardAssistantPromptsForImageSaveLocation
                    )
                    rowDivider
                    settingRow(
                        symbol: "magnifyingglass.circle",
                        title: "搜索引擎",
                        detail: "文本搜索使用的搜索引擎"
                    ) {
                        Picker(
                            "",
                            selection: Binding(
                                get: { model.settingsStore.settings.clipboardAssistantSearchEngine },
                                set: { model.settingsStore.settings.clipboardAssistantSearchEngine = $0 }
                            )
                        ) {
                            ForEach(ClipboardAssistantSearchEngine.allCases, id: \.self) { engine in
                                AppLocalizedText(engine.displayName).tag(engine)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        .frame(width: 150, alignment: .trailing)
                    }
                    if model.settingsStore.settings.clipboardAssistantSearchEngine == .custom {
                        rowDivider
                        settingRow(
                            symbol: "link",
                            title: "自定义搜索网址",
                            detail: "使用 {query} 填入搜索词；未使用时自动添加 q 参数",
                            detailLineLimit: 2,
                            isNested: true
                        ) {
                            TextField(
                                "https://example.com/search?q={query}",
                                text: Binding(
                                    get: { model.settingsStore.settings.clipboardAssistantCustomSearchURL },
                                    set: { model.settingsStore.settings.clipboardAssistantCustomSearchURL = $0 }
                                )
                            )
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 10, design: .monospaced))
                            .frame(width: 220)
                            .accessibilityLabel(AppLocalization.text("自定义搜索网址"))
                        }
                    }
                    if let conflictMessage = clipboardAssistantHotkeyConflictMessage {
                        rowDivider
                        Label(conflictMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.zislaWarning)
                            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                    }
                    rowDivider
                    settingRow(
                        symbol: "app.badge.checkmark",
                        title: "应用黑名单",
                        detail: "这些应用中的复制不弹提示"
                    ) {
                        Button {
                            addApplicationToAssistantBlacklist()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus")
                                AppLocalizedText("添加")
                            }
                        }
                        .controlSize(.small)
                    }
                    ForEach(assistantBlacklistEntries, id: \.bundleIdentifier) { entry in
                        rowDivider
                        assistantBlacklistRow(entry)
                    }
                    rowDivider
                    settingRow(
                        symbol: "slider.horizontal.3",
                        title: "识别类型",
                        detail: "控制哪些内容会触发提示"
                    ) {
                        EmptyView()
                    }
                    ForEach(ClipboardAssistantKind.allCases, id: \.self) { kind in
                        rowDivider
                        settingRow(
                            symbol: kind.symbolName,
                            title: assistantKindTitle(kind),
                            detail: "",
                            isNested: true
                        ) {
                            Toggle("", isOn: Binding(
                                get: {
                                    model.settingsStore.settings.clipboardAssistantEnabledKinds.isEmpty
                                        || model.settingsStore.settings.clipboardAssistantEnabledKinds.contains(kind)
                                },
                                set: { enabled in
                                    var kinds = model.settingsStore.settings.clipboardAssistantEnabledKinds
                                    if kinds.isEmpty {
                                        if enabled { return }
                                        kinds = Set(ClipboardAssistantKind.allCases)
                                    }
                                    if enabled {
                                        kinds.insert(kind)
                                    } else {
                                        kinds.remove(kind)
                                    }
                                    model.settingsStore.settings.clipboardAssistantEnabledKinds = kinds
                                }
                            ))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                        }
                    }
                }
                settingsGroup("复制助手") {
                    ForEach(ClipboardAssistantKind.allCases, id: \.self) { kind in
                        let actions = clipboardAssistantActionOrder(for: kind)
                        if kind != ClipboardAssistantKind.allCases.first { rowDivider }
                        settingRow(
                            symbol: kind.symbolName,
                            title: assistantKindTitle(kind),
                            detail: ""
                        ) {
                            HStack(spacing: 4) {
                                Menu {
                                    ForEach(actions, id: \.self) { action in
                                        Button {
                                            setPrimaryClipboardAssistantAction(action, for: kind)
                                        } label: {
                                            Label(
                                                clipboardAssistantActionTitle(action),
                                                systemImage: action == actions.first ? "checkmark" : action.symbolName
                                            )
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "star.fill")
                                        AppLocalizedText(
                                            actions.first.map(clipboardAssistantActionTitle) ?? "恢复默认顺序"
                                        )
                                    }
                                }
                                .menuStyle(.borderlessButton)
                                .fixedSize()

                                IconButton(
                                    symbol: expandedClipboardAssistantKind == kind
                                        ? "chevron.up.circle.fill"
                                        : "chevron.down.circle",
                                    help: expandedClipboardAssistantKind == kind ? AppLocalization.text("收起") : AppLocalization.text("展开"),
                                    isActive: expandedClipboardAssistantKind == kind,
                                    size: .compact
                                ) {
                                    expandedClipboardAssistantKind =
                                        expandedClipboardAssistantKind == kind ? nil : kind
                                }
                            }
                        }
                        if expandedClipboardAssistantKind == kind {
                            ForEach(Array(actions.dropFirst().enumerated()), id: \.element) { offset, action in
                                rowDivider
                                settingRow(
                                    symbol: action.symbolName,
                                    title: clipboardAssistantActionTitle(action),
                                    detail: "",
                                    isNested: true
                                ) {
                                    HStack(spacing: 4) {
                                        IconButton(
                                            symbol: "arrow.up",
                                            help: AppLocalization.text("上移%@", AppLocalization.text(clipboardAssistantActionTitle(action))),
                                            size: .compact
                                        ) {
                                            moveClipboardAssistantAction(action, for: kind, by: -1)
                                        }
                                        .disabled(offset == 0)

                                        IconButton(
                                            symbol: "arrow.down",
                                            help: AppLocalization.text("下移%@", AppLocalization.text(clipboardAssistantActionTitle(action))),
                                            size: .compact
                                        ) {
                                            moveClipboardAssistantAction(action, for: kind, by: 1)
                                        }
                                        .disabled(offset == actions.dropFirst().count - 1)
                                    }
                                }
                            }
                            rowDivider
                            settingRow(
                                symbol: "arrow.counterclockwise",
                                title: "恢复默认顺序",
                                detail: "",
                                isNested: true
                            ) {
                                IconButton(
                                    symbol: "arrow.counterclockwise",
                                    help: AppLocalization.text("恢复默认顺序"),
                                    size: .compact
                                ) {
                                    resetClipboardAssistantActionOrder(for: kind)
                                }
                                .disabled(actions == ClipboardAssistantActionOrder.defaults(for: kind))
                            }
                        }
                    }
                }
            }

            if input.selection == .features {
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
                    rowDivider
                    featureToggle("键盘音效", detail: "全局播放键盘音效并记录输入统计", symbol: "keyboard.badge.ellipsis", keyPath: \.keyboardEnabled)
                }
            }

            if input.selection == .features || input.selection == .screenshot {
                settingsGroup("截图") {
                    if input.selection == .features {
                        featureToggle(
                            AppLocalization.text("启用截图"),
                            detail: "启用截图、钉图与全局快捷键",
                            symbol: "camera.viewfinder",
                            keyPath: \.screenshotEnabled
                        )
                    } else {
                        settingRow(
                            symbol: "camera.fill",
                            title: "截图快捷键",
                            detail: "触发截图功能"
                        ) {
                            HotkeyRecorder(
                                hotkey: Binding(
                                    get: { model.settingsStore.settings.screenshotHotkey },
                                    set: { newValue in
                                        guard let newValue else { return }
                                        updateScreenshotHotkey(newValue, action: .capture)
                                    }
                                )
                            )
                            .frame(width: 142, height: 26)
                        }
                        rowDivider
                        settingRow(
                            symbol: "pin.fill",
                            title: "钉图快捷键",
                            detail: "钉住已截取的图片"
                        ) {
                            HotkeyRecorder(
                                hotkey: Binding(
                                    get: { model.settingsStore.settings.screenshotPinHotkey },
                                    set: { newValue in
                                        guard let newValue else { return }
                                        updateScreenshotHotkey(newValue, action: .pin)
                                    }
                                )
                            )
                            .frame(width: 142, height: 26)
                        }
                        rowDivider
                        featureToggle(
                            AppLocalization.text("显示钉图控制条"),
                            detail: "隐藏后仍支持快捷键、手势和鼠标操作",
                            symbol: "rectangle.bottomhalf.inset.filled",
                            keyPath: \.screenshotPinnedToolbarVisible
                        )
                        rowDivider
                        settingRow(
                            symbol: "cursorarrow.motionlines",
                            title: "鼠标操作",
                            detail: "按住图片拖动位置；拖动四角调整大小",
                            detailLineLimit: 2,
                            isNested: true
                        ) {
                            EmptyView()
                        }
                        rowDivider
                        settingRow(
                            symbol: "hand.draw.fill",
                            title: "触控板手势",
                            detail: "双指捏合缩放；双指上滑增加不透明度，下滑降低不透明度",
                            detailLineLimit: 2,
                            isNested: true
                        ) {
                            EmptyView()
                        }
                        if let message = screenshotHotkeyValidationMessage ?? currentScreenshotHotkeyConflict {
                            rowDivider
                            Label(message, systemImage: "exclamationmark.triangle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.zislaWarning)
                                .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                        }
                        if screenshotHotkeysRequireInputMonitoring {
                            rowDivider
                            settingRow(
                                symbol: "lock.shield",
                                title: "输入监控",
                                detail: "单独修饰键需要监听全局键盘事件",
                                isNested: true
                            ) {
                                if model.voiceInputInputMonitoringAccessGranted {
                                    Label(AppLocalization.text("已授权"), systemImage: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                        .font(.caption)
                                } else {
                                    Button(AppLocalization.text("打开设置")) {
                                        model.openVoiceInputInputMonitoringSettings()
                                    }
                                    .controlSize(.small)
                                }
                            }
                        }
                    }
                }
            }

            if input.selection == .features {
                settingsGroup("灵动岛与下载展示") {
                    featureToggle("鼠标移入展开", detail: "鼠标进入屏幕顶部感应区时显示", symbol: "cursorarrow.motionlines", keyPath: \.hoverActivationEnabled)
                    rowDivider
                    featureToggle("显示 zisla 图标", detail: "关闭后不影响已启用的菜单栏监控项", symbol: "app.badge", keyPath: \.menuBarAppIconEnabled)
                    rowDivider
                    featureToggle(AppLocalization.text("始终置顶"), detail: "收起时保持在其他窗口和菜单栏图标上方", symbol: "rectangle.topthird.inset.filled", keyPath: \.islandCollapsedOnTop)
                    rowDivider
                    featureToggle("浏览器下载进度", detail: "在灵动岛显示来源图标与百分比", symbol: "arrow.down.circle.fill", keyPath: \.browserDownloadIslandEnabled)
                        .disabled(!model.settingsStore.settings.sideNoticesEnabled)
                    rowDivider
                    featureToggle("原生下载进度", detail: "下载器工作时显示来源平台图标与百分比", symbol: "arrow.down.square.fill", keyPath: \.videoDownloadIslandEnabled)
                        .disabled(!model.settingsStore.settings.sideNoticesEnabled)
                    rowDivider
                    featureToggle(AppLocalization.text("静音 Zisla 通知"), detail: "不发送番茄钟等由 Zisla 产生的系统通知", symbol: "bell.slash.fill", keyPath: \.notificationsMuted)
                }

                settingsGroup("宠物与更新") {
                    featureToggle("宠物", detail: "在灵动岛养一只小宠物", symbol: "pawprint.fill", keyPath: \.petEnabled)
                    rowDivider
                    featureToggle(AppLocalization.text("自动检查更新"), detail: "定期检查当前安装包所属的更新通道", symbol: "arrow.triangle.2.circlepath", keyPath: \.updateChecksEnabled)
                    rowDivider
                    featureToggle(AppLocalization.text("自动下载更新"), detail: "发现新版本后下载，并在退出或重启时完成安装", symbol: "arrow.down.circle.fill", keyPath: \.automaticDownloadEnabled)
                        .disabled(!model.settingsStore.settings.updateChecksEnabled)
                }
            }
        }
    }

    private var keyboardSoundContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingsGroup("全局音效") {
                settingRow(symbol: "waveform", title: "键盘音色", detail: "选择 20 种内置机械键盘音色") {
                    HStack(spacing: 6) {
                        Picker("", selection: Binding(
                            get: { model.settingsStore.settings.keyboardSelectedProfileID },
                            set: { model.settingsStore.settings.keyboardSelectedProfileID = $0 }
                        )) {
                            ForEach(model.keyboardSound.keyboardProfiles) { profile in
                                Text(profile.name).tag(profile.id)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        .frame(width: 150, alignment: .trailing)

                        Button(AppLocalization.text("试听键盘音")) { model.keyboardSound.preview() }
                            .controlSize(.small)
                            .disabled(!model.settingsStore.settings.keyboardEnabled)
                    }
                    .disabled(!model.settingsStore.settings.keyboardEnabled)
                }
                rowDivider
                settingRow(symbol: "speaker.wave.2", title: "键盘音量", detail: "调整主音量") {
                    Slider(value: Binding(
                        get: { model.settingsStore.settings.keyboardVolume },
                        set: { model.settingsStore.settings.keyboardVolume = $0 }
                    ), in: 0...1)
                    .frame(width: 150)
                    .disabled(!model.settingsStore.settings.keyboardEnabled)
                }
                rowDivider
                featureToggle("播放键盘回弹音", detail: "为支持的音色播放释放音", symbol: "arrow.uturn.backward", keyPath: \.keyboardPlaysReleaseSound, isNested: true)
                    .disabled(!model.settingsStore.settings.keyboardEnabled)
                rowDivider
                featureToggle(AppLocalization.text("自然音高变化"), detail: "在连续击键间使用轻微音量与音高变化", symbol: "waveform.path.ecg", keyPath: \.keyboardUsesPitchVariation, isNested: true)
                    .disabled(!model.settingsStore.settings.keyboardEnabled)
            }

            settingsGroup("统计与权限") {
                featureToggle("记录本地输入统计", detail: "仅保存字符数、按键次数、应用与时间聚合，不保存输入内容", symbol: "chart.bar.xaxis", keyPath: \.keyboardTypingStatsEnabled)
                rowDivider
                settingRow(symbol: "lock.shield", title: "输入监控权限", detail: model.keyboardSound.monitoringStateText) {
                    if model.keyboardSound.isInputMonitoringGranted {
                        Label(AppLocalization.text("已授权"), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    } else {
                        Button(AppLocalization.text("打开设置")) { model.keyboardSound.openInputMonitoringSettings() }
                            .controlSize(.small)
                    }
                }
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
                            AppLocalization.text("输入一句话"),
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
                                help: AppLocalization.text("上移%@", AppLocalization.text(priority.title)),
                                size: .compact
                            ) {
                                moveCompactStatusPriority(priority, by: -1)
                            }
                            .disabled(index == priorities.startIndex)

                            IconButton(
                                symbol: "arrow.down",
                                help: AppLocalization.text("下移%@", AppLocalization.text(priority.title)),
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
                        help: AppLocalization.text("恢复默认顺序"),
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

    /// CLI and Skills management stays separate from the voice model configuration.
    private var aiContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingsGroup("CLI 与 Skills") {
                AIAgentModuleView(model: model, configurationScope: .tools)
                    .task {
                        await model.aiAgent.refreshSkills()
                        await model.aiAgent.refreshCLIs()
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

            settingsGroup("本地模型") {
                AIAgentModuleView(model: model, configurationScope: .localModels)
            }

            settingsGroup("远端模型与凭据") {
                AIAgentModuleView(model: model, configurationScope: .remoteModels)
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
                        Text(AppLocalization.text("不使用模型整理")).tag(Optional<AIModelConfigurationReference>.none)
                        ForEach(model.aiAgent.store.state.localModels.filter(\.isEnabled)) { localModel in
                            let reference = AIModelConfigurationReference.local(localModel.id)
                            Text(AppLocalization.text("本地 · %@", model.voiceModelConfigurationTitle(reference)))
                                .tag(Optional(reference))
                        }
                        ForEach(model.aiAgent.store.state.channels.filter(\.isEnabled)) { channel in
                            let reference = AIModelConfigurationReference.channel(channel.id)
                            Text(AppLocalization.text("远端 · %@", model.voiceModelConfigurationTitle(reference)))
                                .tag(Optional(reference))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .frame(maxWidth: 220, alignment: .trailing)
                }
                rowDivider
                settingRow(
                    symbol: "list.number",
                    title: "格式化整理",
                    detail: "将明确列举的事项整理为编号列表"
                ) {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { model.settingsStore.settings.voiceStructuredFormattingEnabled },
                            set: { model.settingsStore.settings.voiceStructuredFormattingEnabled = $0 }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
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
                                    Text(AppLocalization.text("测试连接"))
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

            settingsGroup("本地记录") {
                settingRow(
                    symbol: "externaldrive.fill",
                    title: "保留原始录音",
                    detail: "关闭后，新录音只保留识别文本和 AI 整理文本"
                ) {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { model.settingsStore.settings.voiceRecordingRetentionEnabled },
                            set: { model.settingsStore.settings.voiceRecordingRetentionEnabled = $0 }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
                rowDivider
                settingRow(
                    symbol: "calendar.badge.clock",
                    title: "自动清理录音",
                    detail: "按所选周期删除过期音频，文字记录继续保留"
                ) {
                    Picker(
                        "",
                        selection: Binding(
                            get: { model.settingsStore.settings.voiceRecordingCleanupPolicy },
                            set: { model.settingsStore.settings.voiceRecordingCleanupPolicy = $0 }
                        )
                    ) {
                        ForEach(VoiceRecordingCleanupPolicy.allCases, id: \.self) { policy in
                            Text(AppLocalization.text(policy.menuTitle)).tag(policy)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .frame(width: 120, alignment: .trailing)
                }
                rowDivider
                settingRow(
                    symbol: "folder",
                    title: "记录目录",
                    detail: "原始音频和文字记录只保存在本机"
                ) {
                    IconButton(symbol: "folder", help: AppLocalization.text("打开语音记录目录"), size: .compact) {
                        model.openVoiceRecordingsDirectory()
                    }
                }
            }

            settingsGroup("识别词库") {
                ForEach(Array(VoiceLexicon.allCases.enumerated()), id: \.element.id) { index, lexicon in
                    if index > 0 { rowDivider }
                    settingRow(
                        symbol: lexicon.symbol,
                        title: lexicon.title,
                        detail: lexicon.detail
                    ) {
                        Toggle("", isOn: voiceLexiconBinding(for: lexicon))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                }
                rowDivider
                settingRow(
                    symbol: "text.badge.plus",
                    title: "自定义热词",
                    detail: "用于语音识别和语音整理模型"
                ) {
                    HStack(spacing: 6) {
                        TextField(AppLocalization.text("输入热词"), text: $customVoiceHotword)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 150)
                            .onSubmit(addCustomVoiceHotword)
                        Button(AppLocalization.text("添加"), action: addCustomVoiceHotword)
                            .controlSize(.small)
                            .disabled(
                                customVoiceHotword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            )
                    }
                }
                ForEach(model.settingsStore.settings.voiceCustomHotwords, id: \.self) { hotword in
                    rowDivider
                    settingRow(
                        symbol: "text.badge.checkmark",
                        title: hotword,
                        detail: ""
                    ) {
                        IconButton(symbol: "trash", help: AppLocalization.text("删除%@", hotword), size: .compact) {
                            removeCustomVoiceHotword(hotword)
                        }
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
                    value: AppLocalization.text("%ld 字词", statistics.totalWordCount)
                )
                voiceStatistic(
                    symbol: "waveform",
                    title: "累计口述时间",
                    value: voiceDurationText(statistics.totalDuration)
                )
                voiceStatistic(
                    symbol: "bolt.fill",
                    title: "输入速度",
                    value: AppLocalization.text("%ld 字词/分", Int(statistics.wordsPerMinute.rounded()))
                )
                voiceStatistic(
                    symbol: "clock",
                    title: "节省时间",
                    value: voiceDurationText(statistics.savedTime)
                )
            }

            settingsGroup("语音记录") {
                HStack(spacing: 8) {
                    Text(AppLocalization.text("全部记录仅保存在本机"))
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    if voiceHistorySelectionMode {
                        IconButton(symbol: "xmark", help: AppLocalization.text("退出选择模式"), size: .compact) {
                            voiceHistorySelectionMode = false
                            selectedVoiceHistoryIDs.removeAll()
                        }
                    } else {
                        IconButton(symbol: "checkmark.circle", help: AppLocalization.text("选择多条记录"), size: .compact) {
                            voiceHistorySelectionMode = true
                            selectedVoiceHistoryIDs.removeAll()
                        }
                        .disabled(model.voiceHistory.entries.isEmpty)
                        IconButton(symbol: "folder", help: AppLocalization.text("打开语音记录目录"), size: .compact) {
                            model.openVoiceRecordingsDirectory()
                        }
                        IconButton(symbol: "trash", help: AppLocalization.text("清空语音记录"), size: .compact) {
                            isVoiceHistoryClearConfirmationPresented = true
                        }
                        .disabled(model.voiceHistory.entries.isEmpty)
                    }
                }
                .padding(.horizontal, 4)
                .frame(minHeight: 42)

                if voiceHistorySelectionMode && !model.voiceHistory.entries.isEmpty {
                    rowDivider
                    HStack(spacing: 8) {
                        Button(selectedVoiceHistoryIDs.count == model.voiceHistory.entries.count ? AppLocalization.text("取消全选") : AppLocalization.text("全选")) {
                            if selectedVoiceHistoryIDs.count == model.voiceHistory.entries.count {
                                selectedVoiceHistoryIDs.removeAll()
                            } else {
                                selectedVoiceHistoryIDs = Set(model.voiceHistory.entries.map(\.id))
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Spacer(minLength: 8)

                        if !selectedVoiceHistoryIDs.isEmpty {
                            Text(AppLocalization.text("已选 %ld 条", selectedVoiceHistoryIDs.count))
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)

                            Button(AppLocalization.text("删除选中")) {
                                isVoiceHistoryBatchDeleteConfirmationPresented = true
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .foregroundStyle(.red)
                        }
                    }
                    .padding(.horizontal, 4)
                    .frame(minHeight: 42)
                }

                if model.voiceHistory.entries.isEmpty {
                    rowDivider
                    HStack(spacing: 8) {
                        Image(systemName: "waveform.slash")
                            .foregroundStyle(.secondary)
                        Text(AppLocalization.text("暂无语音记录"))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 72)
                } else {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(model.voiceHistory.entries) { entry in
                            rowDivider
                            voiceHistoryRow(entry)
                        }
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
            if voiceHistorySelectionMode {
                Button {
                    if selectedVoiceHistoryIDs.contains(entry.id) {
                        selectedVoiceHistoryIDs.remove(entry.id)
                    } else {
                        selectedVoiceHistoryIDs.insert(entry.id)
                    }
                } label: {
                    Image(systemName: selectedVoiceHistoryIDs.contains(entry.id) ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(selectedVoiceHistoryIDs.contains(entry.id) ? Color.accentColor : Color.secondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(AppLocalization.text("%@ · %ld 字词", voiceDurationText(entry.duration), entry.wordCount))
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                if let processed = entry.processedTranscript {
                    Text(AppLocalization.text("AI 整理：%@", processed))
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(2)
                    Text(AppLocalization.text("原始识别：%@", entry.rawTranscript.isEmpty ? "未识别到文字" : entry.rawTranscript))
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else {
                    Text(entry.rawTranscript.isEmpty ? AppLocalization.text("未识别到文字") : entry.rawTranscript)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(3)
                }
            }
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)

            if !voiceHistorySelectionMode {
                HStack(spacing: 4) {
                    if model.voiceHistory.audioURL(for: entry) != nil {
                        IconButton(symbol: "play.fill", help: AppLocalization.text("播放原始录音"), size: .compact) {
                            model.playVoiceRecording(id: entry.id)
                        }
                        IconButton(symbol: "magnifyingglass", help: AppLocalization.text("在 Finder 中显示"), size: .compact) {
                            model.revealVoiceRecording(id: entry.id)
                        }
                    }
                    IconButton(symbol: "trash", help: AppLocalization.text("删除这条语音记录"), size: .compact) {
                        model.removeVoiceRecording(id: entry.id)
                    }
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
            return AppLocalization.text("%ld 秒", Int(duration.rounded()))
        }
        if duration < 3_600 {
            return AppLocalization.text("%.1f 分钟", duration / 60)
        }
        return AppLocalization.text("%.1f 小时", duration / 3_600)
    }

    private func deleteSelectedVoiceHistoryEntries() {
        guard !selectedVoiceHistoryIDs.isEmpty else { return }
        model.removeVoiceRecordings(ids: selectedVoiceHistoryIDs)
        selectedVoiceHistoryIDs.removeAll()
        voiceHistorySelectionMode = false
    }

    private var discoveryStatusText: String {
        switch model.voiceModelDiscoveryState {
        case .idle: "尚未测试连接"
        case .testing: "正在连接…"
        case .success(let count): AppLocalization.text("已发现 %ld 个模型", count)
        case .failed(let message): message
        }
    }

    private var voiceInputGroup: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingsGroup("语音输入") {
                if model.settingsStore.settings.voiceInputEnabled {
                    settingRow(
                        symbol: "record.circle",
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
                        HotkeyRecorder(
                            hotkey: Binding(
                                get: { model.settingsStore.settings.voiceInputHotkeyPreset },
                                set: { newValue in
                                    guard let newValue else { return }
                                    model.settingsStore.settings.voiceInputHotkeyPreset = newValue
                                }
                            )
                        )
                        .frame(width: 142, height: 26)
                    }
                    if model.settingsStore.settings.voiceInputHotkeyPreset.requiresInputMonitoring {
                        rowDivider
                        settingRow(
                            symbol: "lock.shield",
                            title: "输入监控",
                            detail: "左右侧修饰键需要监听全局键盘事件",
                            isNested: true
                        ) {
                            if model.voiceInputInputMonitoringAccessGranted {
                                Label(AppLocalization.text("已授权"), systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.caption)
                            } else {
                                Button(AppLocalization.text("打开设置")) {
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

    private var petContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingsGroup("宠物") {
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
                        Text(AppLocalization.text("左侧")).tag(PetSide.left)
                        Text(AppLocalization.text("右侧")).tag(PetSide.right)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .frame(width: 150, alignment: .trailing)
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

    private func voiceLexiconBinding(for lexicon: VoiceLexicon) -> Binding<Bool> {
        Binding(
            get: { model.settingsStore.settings.voiceEnabledLexicons.contains(lexicon) },
            set: { enabled in
                var selection = model.settingsStore.settings.voiceEnabledLexicons
                if enabled {
                    selection.insert(lexicon)
                } else {
                    selection.remove(lexicon)
                }
                model.settingsStore.settings.voiceEnabledLexicons = selection
            }
        )
    }

    private func addCustomVoiceHotword() {
        let newHotword = customVoiceHotword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newHotword.isEmpty else { return }
        let updated = VoiceLexicon.normalizedCustomTerms(
            model.settingsStore.settings.voiceCustomHotwords + [newHotword]
        )
        customVoiceHotword = ""
        guard updated != model.settingsStore.settings.voiceCustomHotwords else { return }
        model.settingsStore.settings.voiceCustomHotwords = updated
    }

    private func removeCustomVoiceHotword(_ hotword: String) {
        model.settingsStore.settings.voiceCustomHotwords.removeAll { $0 == hotword }
    }

    private func petDisplayLabel(_ entry: PetLibrary.Entry) -> String {
        switch entry.origin {
        case .builtin: entry.manifest.displayName
        case .imported: AppLocalization.text("%@（已导入）", entry.manifest.displayName)
        }
    }

    private var activityNoticeDisplays: [ActivityNoticeDisplay] {
        NSScreen.screens.enumerated().compactMap { index, screen in
            let key = NSDeviceDescriptionKey("NSScreenNumber")
            guard let number = screen.deviceDescription[key] as? NSNumber else { return nil }
            let name = screen.localizedName.isEmpty ? AppLocalization.text("显示器 %ld", index + 1) : screen.localizedName
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

    private enum ScreenshotHotkeyAction: Equatable {
        case capture
        case pin
    }

    private var screenshotHotkeysRequireInputMonitoring: Bool {
        let settings = model.settingsStore.settings
        return settings.screenshotEnabled
            && (settings.screenshotHotkey.requiresInputMonitoring
                || settings.screenshotPinHotkey.requiresInputMonitoring)
    }

    private var currentScreenshotHotkeyConflict: String? {
        let settings = model.settingsStore.settings
        if settings.screenshotHotkey.conflicts(with: settings.screenshotPinHotkey) {
            return "截图与钉图快捷键冲突，请修改其中一个"
        }
        if settings.voiceInputEnabled,
           settings.screenshotHotkey.conflicts(with: settings.voiceInputHotkeyPreset) {
            return "截图快捷键与语音输入冲突"
        }
        if settings.voiceInputEnabled,
           settings.screenshotPinHotkey.conflicts(with: settings.voiceInputHotkeyPreset) {
            return "钉图快捷键与语音输入冲突"
        }
        return nil
    }

    private func updateScreenshotHotkey(
        _ hotkey: VoiceInputHotkeyPreset,
        action: ScreenshotHotkeyAction
    ) {
        var settings = model.settingsStore.settings
        let other = action == .capture ? settings.screenshotPinHotkey : settings.screenshotHotkey
        let actionName = AppLocalization.text(action == .capture ? "截图" : "钉图")
        let otherName = AppLocalization.text(action == .capture ? "钉图" : "截图")
        guard !hotkey.conflicts(with: other) else {
            screenshotHotkeyValidationMessage = AppLocalization.text("%@快捷键与%@冲突，未保存", actionName, otherName)
            return
        }
        guard !settings.voiceInputEnabled
            || !hotkey.conflicts(with: settings.voiceInputHotkeyPreset)
        else {
            screenshotHotkeyValidationMessage = AppLocalization.text("%@快捷键与语音输入冲突，未保存", actionName)
            return
        }
        switch action {
        case .capture:
            settings.screenshotHotkey = hotkey
        case .pin:
            settings.screenshotPinHotkey = hotkey
        }
        screenshotHotkeyValidationMessage = nil
        model.settingsStore.settings = settings
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
                            Text(language.nativeDisplayName).tag(language)
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
                        Button(AppLocalization.text("打开登录项…")) {
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

    private var networkProxyStatusText: String {
        switch networkProxyMonitor.availability {
        case .disabled: "已关闭"
        case .notConfigured: "未配置"
        case .invalid: "链接无效"
        case .checking: "检测中…"
        case .available: "可用"
        case .unavailable: "不可用"
        }
    }

    private var networkProxyStatusDetail: String {
        switch networkProxyMonitor.availability {
        case .disabled: "启用后可检测代理端口"
        case .notConfigured: "填写代理链接后检测端口连通性"
        case .invalid: "支持 http、https、socks5 或 socks5h 链接"
        case .checking: "正在连接代理主机和端口"
        case .available: "代理主机和端口可建立连接"
        case .unavailable: "无法连接代理主机和端口，请检查代理是否运行"
        }
    }

    private var networkProxyStatusSymbol: String {
        switch networkProxyMonitor.availability {
        case .disabled, .notConfigured: "network"
        case .invalid, .unavailable: "exclamationmark.triangle"
        case .checking: "arrow.triangle.2.circlepath"
        case .available: "checkmark.circle"
        }
    }

    private var networkProxyStatusColor: Color {
        switch networkProxyMonitor.availability {
        case .available: Color.zislaSuccess
        case .invalid, .unavailable: Color.zislaError
        case .checking: Color.zislaInfo
        case .disabled, .notConfigured: .secondary
        }
    }

    private func checkNetworkProxy() {
        networkProxyMonitor.check(
            urlString: model.settingsStore.settings.networkProxyURL,
            enabled: model.settingsStore.settings.networkProxyEnabled
        )
    }

    private var downloadContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingsGroup("下载目录") {
                settingRow(
                    symbol: "folder.fill",
                    title: "默认下载目录",
                    detail: model.downloadDirectory.path(percentEncoded: false)
                ) {
                    Button(AppLocalization.text("选择默认下载目录")) { chooseDownloadDirectory() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .fixedSize(horizontal: true, vertical: false)
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

                Button(state.isInstalled ? AppLocalization.text("更新") : AppLocalization.text("安装")) {
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
        case .checking: return AppLocalization.text("正在查询最新版本…")
        case .downloading(let fraction):
            return fraction > 0
                ? AppLocalization.text("正在下载 %ld%%", Int(fraction * 100))
                : AppLocalization.text("正在下载…")
        case .installing: return AppLocalization.text("正在安装…")
        case .idle: break
        }
        guard let location = state.location else {
            return AppLocalization.text("未安装 · %@ · %@", AppLocalization.text(tool.purpose), tool.installDetail)
        }
        let version = state.installedVersion ?? AppLocalization.text("版本未知")
        if state.hasUpdate, let latest = state.latestVersion {
            return AppLocalization.text("%@ · %@ · 可更新到 %@", version, AppLocalization.text(location.label), latest)
        }
        return "\(version) · \(AppLocalization.text(location.label)) · \(AppLocalization.text(tool.purpose))"
    }

    private var recommendationsContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingsGroup("一键管理") {
                HStack(spacing: 8) {
                    Text(AppLocalization.text("%ld 个推荐工具", recommendedTools.count))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    recommendationActionButton(
                        symbol: "arrow.clockwise",
                        help: AppLocalization.text("重新检测推荐工具"),
                        disabled: recommendedToolsAreBusy
                    ) {
                        Task { await refreshRecommendedTools() }
                    }
                    recommendationActionButton(
                        symbol: "arrow.down.circle",
                        help: AppLocalization.text("一键下载所有未安装的推荐工具"),
                        disabled: recommendedToolsAreBusy || missingRecommendedTools.isEmpty
                    ) {
                        pendingRecommendedToolAction = .install
                    }
                    recommendationActionButton(
                        symbol: "arrow.up.circle",
                        help: AppLocalization.text("一键更新所有已安装的推荐工具"),
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
                    help: state.isInstalled
                        ? AppLocalization.text("更新 %@", tool.displayName)
                        : AppLocalization.text("下载并安装 %@", tool.displayName),
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
                        Label(AppLocalization.text("刷新"), systemImage: "arrow.clockwise")
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
                        .help(AppLocalization.text("拖动调整 %@ 的展示顺序", location.displayName))

                    Button {
                        model.removeWeatherLocation(id: location.id)
                    } label: {
                        Image(systemName: "trash")
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help(AppLocalization.text("删除 %@", location.displayName))
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
                    title: "更新通道",
                    detail: AppLocalization.text("%@；用于自动与手动更新", AppLocalization.text(model.settingsStore.settings.updateChannel.detail))
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
                                AppLocalization.text("检查 %@", AppLocalization.text(model.settingsStore.settings.updateChannel.menuTitle)),
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

    private var networkProxyContent: some View {
        settingsGroup("代理设置") {
            settingRow(
                symbol: "network",
                title: "代理链接",
                detail: "用于 CLI 安装/更新和媒体下载"
            ) {
                TextField(
                    "http://127.0.0.1:7897",
                    text: Binding(
                        get: { model.settingsStore.settings.networkProxyURL },
                        set: { model.settingsStore.settings.networkProxyURL = $0 }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
            }
            rowDivider
            settingRow(
                symbol: "power",
                title: "启用本地代理",
                detail: "关闭后 CLI 安装/更新和媒体下载不使用此代理"
            ) {
                Toggle(
                    "",
                    isOn: Binding(
                        get: { model.settingsStore.settings.networkProxyEnabled },
                        set: { model.settingsStore.settings.networkProxyEnabled = $0 }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }
            rowDivider
            settingRow(
                symbol: networkProxyStatusSymbol,
                title: "代理状态",
                detail: networkProxyStatusDetail
            ) {
                HStack(spacing: 8) {
                    Text(networkProxyStatusText)
                        .font(.system(size: 10))
                        .foregroundStyle(networkProxyStatusColor)
                    IconButton(symbol: "arrow.clockwise", help: AppLocalization.text("重新检测代理"), size: .compact) {
                        checkNetworkProxy()
                    }
                    .disabled(networkProxyMonitor.availability == .checking)
                }
            }
        }
        .onAppear { checkNetworkProxy() }
        .onChange(of: model.settingsStore.settings.networkProxyURL) { _, _ in checkNetworkProxy() }
        .onChange(of: model.settingsStore.settings.networkProxyEnabled) { _, _ in checkNetworkProxy() }
    }

    private var weatherSearchRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
            HStack(spacing: 6) {
                TextField(AppLocalization.text("城市、区县或地区"), text: $input.weatherQuery)
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
                    .help(AppLocalization.text("清除"))
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
            .help(AppLocalization.text("搜索地区"))
            .disabled(input.weatherQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 4)
        .frame(height: 46)
    }

    private func featureToggle(
        _ title: String,
        detail: String,
        symbol: String,
        keyPath: WritableKeyPath<FeatureSettings, Bool>,
        isNested: Bool = false
    ) -> some View {
        settingRow(symbol: symbol, title: title, detail: detail, isNested: isNested) {
            Toggle("", isOn: Binding(
                get: { model.settingsStore.settings[keyPath: keyPath] },
                set: { model.settingsStore.settings[keyPath: keyPath] = $0 }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
        }
    }

    // MARK: - Clipboard assistant blacklist

    /// Localized string for dynamic contexts (tooltips, formatted details).
    private func loc(_ key: String) -> String {
        AppLocalization.string(key, language: model.languageStore.language)
    }

    /// Localization key for each recognition kind shown in Settings.
    private func assistantKindTitle(_ kind: ClipboardAssistantKind) -> String {
        switch kind {
        case .url: "链接"
        case .filePath: "文件路径"
        case .email: "邮箱"
        case .phone: "电话号码"
        case .color: "颜色值"
        case .math: "算式"
        case .dateTime: "日期时间"
        case .code: "代码"
        case .nonSystemLanguageText: "非当前系统语言文本"
        case .text: "文本"
        case .image: "图片"
        case .file: "文件"
        }
    }

    private struct AssistantBlacklistEntry {
        let bundleIdentifier: String
        let name: String
        let icon: NSImage?
    }

    private var clipboardAssistantHotkeyDetail: String {
        if let hotkey = model.settingsStore.settings.clipboardAssistantTriggerConfiguration.hotkey {
            return hotkey.isModifierOnly
                ? loc("提示可见时连按 %@ 触发主动作").replacingOccurrences(of: "%@", with: hotkey.settingsDisplayName)
                : loc("提示可见时按下 %@ 触发主动作").replacingOccurrences(of: "%@", with: hotkey.settingsDisplayName)
        }
        return loc("未配置；点击右侧录制")
    }

    private var clipboardAssistantTriggersRequireInputMonitoring: Bool {
        model.settingsStore.settings.clipboardAssistantTriggerConfiguration.hotkey?.requiresInputMonitoring == true
            || model.settingsStore.settings.clipboardAssistantMouseButton != nil
            || model.settingsStore.settings.clipboardAssistantMouseGestureEnabled
    }

    /// Warns when the assistant trigger collides with the other global hotkeys.
    private var clipboardAssistantHotkeyConflictMessage: String? {
        guard let hotkey = model.settingsStore.settings.clipboardAssistantTriggerConfiguration.hotkey else {
            return nil
        }
        let settings = model.settingsStore.settings
        let conflicts: [String] = [
            settings.voiceInputEnabled && hotkey.conflicts(with: settings.voiceInputHotkeyPreset) ? loc("语音输入") : nil,
            settings.screenshotEnabled && hotkey.conflicts(with: settings.screenshotHotkey) ? loc("截图") : nil,
            settings.screenshotEnabled && hotkey.conflicts(with: settings.screenshotPinHotkey) ? loc("钉图") : nil,
        ].compactMap { $0 }
        guard !conflicts.isEmpty else { return nil }
        return loc("快速触发快捷键与%@快捷键冲突，请更换其中一个")
            .replacingOccurrences(of: "%@", with: conflicts.joined(separator: AppLocalization.text("、")))
    }

    private var assistantBlacklistEntries: [AssistantBlacklistEntry] {
        model.settingsStore.settings.clipboardAssistantBlacklist
            .sorted()
            .map { bundleIdentifier in
                AssistantBlacklistEntry(
                    bundleIdentifier: bundleIdentifier,
                    name: Self.appDisplayName(forBundleIdentifier: bundleIdentifier),
                    icon: Self.appIcon(forBundleIdentifier: bundleIdentifier)
                )
            }
    }

    private static func appDisplayName(forBundleIdentifier bundleIdentifier: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier),
           let bundle = Bundle(url: url),
           let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String,
           !name.isEmpty {
            return name
        }
        return bundleIdentifier
    }

    private static func appIcon(forBundleIdentifier bundleIdentifier: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    private func assistantBlacklistRow(_ entry: AssistantBlacklistEntry) -> some View {
        HStack(spacing: 10) {
            Group {
                if let icon = entry.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "app")
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            .frame(width: 24, height: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(entry.bundleIdentifier)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .layoutPriority(1)
            Spacer(minLength: 8)
            Button {
                var blacklist = model.settingsStore.settings.clipboardAssistantBlacklist
                blacklist.remove(entry.bundleIdentifier)
                model.settingsStore.settings.clipboardAssistantBlacklist = blacklist
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(Color.zislaError.opacity(0.8))
            }
            .buttonStyle(.plain)
            .help(loc("移出黑名单"))
        }
        .padding(.leading, 28)
        .padding(.trailing, 4)
        .frame(maxWidth: .infinity, minHeight: 40)
    }

    private static let applicationsDirectoryURL = URL(
        fileURLWithPath: "/Applications",
        isDirectory: true
    )

    static func isApplicationBundleInApplicationsDirectory(_ url: URL) -> Bool {
        let applicationURL = url.standardizedFileURL.resolvingSymlinksInPath()
        let applicationsPath = applicationsDirectoryURL
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
        return applicationURL.pathExtension.lowercased() == "app"
            && applicationURL.path.hasPrefix(applicationsPath + "/")
    }

    private func addApplicationToAssistantBlacklist() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.treatsFilePackagesAsDirectories = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = Self.applicationsDirectoryURL
        panel.prompt = loc("添加")
        WindowPlacement.prepareModal(panel, on: WindowPlacement.screenUnderMouse())

        guard panel.runModal() == .OK,
              let url = panel.url,
              Self.isApplicationBundleInApplicationsDirectory(url),
              let bundleIdentifier = Bundle(url: url)?.bundleIdentifier,
              !bundleIdentifier.isEmpty else {
            return
        }
        var blacklist = model.settingsStore.settings.clipboardAssistantBlacklist
        guard blacklist.insert(bundleIdentifier).inserted else { return }
        model.settingsStore.settings.clipboardAssistantBlacklist = blacklist
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
                    Text(AppLocalization.text(style.title)).tag(style)
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
                Button(AppLocalization.text("刷新")) {
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
                    detail: account.id == account.displayName ? AppLocalization.text("系统 Mail.app 账户") : account.id
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

    private func clipboardAssistantActionOrder(
        for kind: ClipboardAssistantKind
    ) -> [ClipboardAssistantActionKind] {
        ClipboardAssistantActionOrder.normalized(
            model.settingsStore.settings.clipboardAssistantActionOrders[kind]
                ?? ClipboardAssistantActionOrder.defaults(for: kind),
            for: kind
        )
    }

    private func setPrimaryClipboardAssistantAction(
        _ action: ClipboardAssistantActionKind,
        for kind: ClipboardAssistantKind
    ) {
        var order = clipboardAssistantActionOrder(for: kind)
        order.removeAll { $0 == action }
        order.insert(action, at: 0)
        model.settingsStore.settings.clipboardAssistantActionOrders[kind] = order
    }

    private func moveClipboardAssistantAction(
        _ action: ClipboardAssistantActionKind,
        for kind: ClipboardAssistantKind,
        by offset: Int
    ) {
        var order = clipboardAssistantActionOrder(for: kind)
        guard let index = order.firstIndex(of: action), index > 0 else { return }
        let destination = index + offset
        guard destination > order.startIndex, order.indices.contains(destination) else { return }
        order.swapAt(index, destination)
        model.settingsStore.settings.clipboardAssistantActionOrders[kind] = order
    }

    private func resetClipboardAssistantActionOrder(for kind: ClipboardAssistantKind) {
        model.settingsStore.settings.clipboardAssistantActionOrders[kind] =
            ClipboardAssistantActionOrder.defaults(for: kind)
    }

    private func clipboardAssistantActionTitle(_ action: ClipboardAssistantActionKind) -> String {
        switch action {
        case .openURL: "打开链接"
        case .openDownload: "下载"
        case .revealInFinder: "在 Finder 中显示"
        case .search: "搜索"
        case .translate: "翻译"
        case .composeMail: "写邮件"
        case .copyText: "复制结果"
        case .copyFullExpression: "复制完整算式"
        case .compress: "压缩为 ZIP"
        case .share: "系统共享"
        case .callPhone: "拨打电话"
        case .addToQuickNote: "发送到随记"
        case .sendToTeleprompter: "发送到提词器"
        case .saveImage: "保存图片"
        case .saveText: "保存文本"
        case .createCalendarEvent: "新建日程"
        }
    }

    private func compactStatusPrioritySymbol(for priority: CompactStatusPriority) -> String {
        switch priority {
        case .transient: "bolt.fill"
        case .updateAvailable: "arrow.up.circle"
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
        isNested: Bool = false,
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
        .padding(.leading, isNested ? 24 : 4)
        .padding(.trailing, 4)
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
        .help(AppLocalization.text("在浏览器中打开 %@", title))
        .accessibilityLabel(AppLocalization.text("在浏览器中打开 %@", title))
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
                symbol: "arrow.up.circle",
                help: AppLocalization.text("查看更新"),
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
            Image(systemName: "arrow.up.circle.fill")
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
        case .available: "发现可用新版本"
        case .failed(let message): message
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.7"
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
}

private struct ActivityNoticeDisplay: Identifiable {
    let id: UInt32
    let name: String
}

/// Search engine options for the clipboard assistant's text search action.
extension ClipboardAssistantSearchEngine {
    /// Display name; language-neutral brand names except Baidu, which is localized as a key.
    var displayName: String {
        switch self {
        case .google: "Google"
        case .bing: "Bing"
        case .baidu: "百度"
        case .sogou: "搜狗"
        case .quark: "夸克"
        case .so360: "360搜索"
        case .duckduckgo: "DuckDuckGo"
        case .brave: "Brave Search"
        case .yandex: "Yandex"
        case .custom: "自定义"
        }
    }
}

/// Mouse side-button options for the clipboard assistant quick trigger; rawValue is the
/// CGEvent button number.
private enum ClipboardAssistantMouseTriggerOption: Int, CaseIterable, Identifiable {
    case off = 0
    case sideBack = 3
    case sideForward = 4

    var id: Self { self }

    var label: String {
        switch self {
        case .off: "关闭"
        case .sideBack: "侧键（后退）"
        case .sideForward: "侧键（前进）"
        }
    }

    var buttonNumber: Int? {
        self == .off ? nil : rawValue
    }

    init(buttonNumber: Int?) {
        self = buttonNumber.flatMap(Self.init(rawValue:)) ?? .off
    }
}

private extension VoiceInputModifier {
    var settingsDisplayName: String {
        switch self {
        case .leftControl: "L⌃"
        case .rightControl: "R⌃"
        case .leftOption: "L⌥"
        case .rightOption: "R⌥"
        case .leftCommand: "L⌘"
        case .rightCommand: "R⌘"
        case .leftShift: "L⇧"
        case .rightShift: "R⇧"
        }
    }
}

private extension VoiceInputHotkeyPreset {
    var settingsDisplayName: String {
        if isModifierOnly, let modifier = modifierSides?.first {
            return modifier.settingsDisplayName
        }
        return displayName
    }
}

private struct HotkeyRecorder: NSViewRepresentable {
    @Binding var hotkey: VoiceInputHotkeyPreset?
    @Environment(\.locale) private var locale

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> HotkeyRecorderButton {
        let button = HotkeyRecorderButton(hotkey: hotkey, locale: locale)
        button.onRecord = context.coordinator.record
        return button
    }

    func updateNSView(_ nsView: HotkeyRecorderButton, context: Context) {
        nsView.hotkey = hotkey
        nsView.locale = locale
    }

    @MainActor
    final class Coordinator {
        private var parent: HotkeyRecorder

        init(_ parent: HotkeyRecorder) {
            self.parent = parent
        }

        func record(_ hotkey: VoiceInputHotkeyPreset) {
            parent.hotkey = hotkey
        }
    }
}

@MainActor
private final class HotkeyRecorderButton: NSButton {
    var hotkey: VoiceInputHotkeyPreset? {
        didSet {
            if !isRecording {
                updateTitle()
            }
        }
    }
    var locale: Locale {
        didSet {
            updateTitle()
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

    init(hotkey: VoiceInputHotkeyPreset?, locale: Locale) {
        self.hotkey = hotkey
        self.locale = locale
        super.init(frame: .zero)
        bezelStyle = .rounded
        font = .monospacedSystemFont(ofSize: 10, weight: .medium)
        lineBreakMode = .byTruncatingTail
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
                    keyDisplayName: modifier.settingsDisplayName,
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
            title = hotkey?.settingsDisplayName ?? loc("点击录制")
            return
        }
        let modifierNames = VoiceInputModifier.allCases
            .filter(recordingModifierSides.contains)
            .map(\.settingsDisplayName)
        title = modifierNames.isEmpty
            ? loc("按下组合键...")
            : "\(modifierNames.joined(separator: " + ")) + ..."
    }

    private func loc(_ key: String) -> String {
        AppLocalization.string(key, locale: locale)
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
        case 36: "↩"
        case 48: "⇥"
        case 49: "␣"
        case 51: "⌫"
        case 53: "⎋"
        case 115: "↖"
        case 116: "⇞"
        case 117: "⌦"
        case 119: "↘"
        case 121: "⇟"
        case 123: "←"
        case 124: "→"
        case 125: "↓"
        case 126: "↑"
        default:
            event.charactersIgnoringModifiers?.uppercased() ?? "\(event.keyCode)"
        }
    }
}

enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case features
    case clipboardAssistant
    case screenshot
    case workflow
    case info
    case ai
    case voice
    case keyboardSound
    case pet
    case download
    case weather
    case networkProxy
    case recommendations
    case updates

    var id: Self { self }

    /// AI and voice settings need room for their dense content.
    var prefersWideLayout: Bool {
        self == .ai || self == .voice
    }

    var title: String {
        switch self {
        case .general: "通用"
        case .features: "功能"
        case .keyboardSound: "键盘音效"
        case .clipboardAssistant: "复制助手"
        case .screenshot: "截图"
        case .workflow: "工作流"
        case .info: "信息"
        case .ai: "AI"
        case .voice: "语音"
        case .pet: "宠物"
        case .download: "下载"
        case .networkProxy: "网络"
        case .weather: "天气"
        case .updates: "更新"
        case .recommendations: "推荐"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .features: "switch.2"
        case .keyboardSound: "keyboard.badge.ellipsis"
        case .clipboardAssistant: "sparkles.rectangle.stack"
        case .screenshot: "camera.viewfinder"
        case .workflow: "square.grid.2x2.fill"
        case .info: "info.circle.fill"
        case .ai: "sparkles"
        case .voice: "mic.fill"
        case .pet: "pawprint.fill"
        case .download: "arrow.down.circle.fill"
        case .networkProxy: "network"
        case .weather: "cloud.sun.fill"
        case .updates: "arrow.up.circle"
        case .recommendations: "sparkles"
        }
    }

    var subtitle: String {
        switch self {
        case .general: "调整语言、外观、启动与展开方式。"
        case .features: "集中开启或关闭所有功能模块。"
        case .keyboardSound: "键盘音效与输入统计。"
        case .clipboardAssistant: "复制后弹出识别结果和下一步操作"
        case .screenshot: "启用截图、钉图与全局快捷键"
        case .workflow: "管理灵动岛中的工作流模块。"
        case .info: "配置日历、邮件、锁屏与通知显示。"
        case .ai: "管理 AI CLI 与 Skills。"
        case .voice: "配置语音输入、整理模型与本机记录。"
        case .pet: "设置灵动岛内部的宠物形象。"
        case .download: "管理下载目录、下载通知与所需组件。"
        case .networkProxy: "配置本地代理，用于更新、安装、下载与 GitHub 访问。"
        case .weather: "管理天气显示、地点和刷新。"
        case .updates: "管理版本检查与自动更新。"
        case .recommendations: "一键下载和更新精选效率、网络、开发与桌面工具。"
        }
    }

    func isVisible(settings: FeatureSettings) -> Bool {
        switch self {
        case .general, .features, .networkProxy, .recommendations:
            return true
        case .keyboardSound:
            return settings.keyboardEnabled
        case .clipboardAssistant:
            return settings.clipboardAssistantEnabled
        case .screenshot:
            return settings.screenshotEnabled
        case .workflow:
            return settings.mediaEnabled || settings.systemMonitorEnabled
        case .info:
            return settings.mailEnabled || settings.lockScreenInfoEnabled || settings.sideNoticesEnabled
        case .ai:
            return settings.aiProgressEnabled
        case .voice:
            return settings.voiceInputEnabled
        case .pet:
            return settings.petEnabled
        case .download:
            return settings.downloaderEnabled
        case .weather:
            return settings.weatherEnabled
        case .updates:
            return settings.updateChecksEnabled
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
            AppLocalization.text("将通过官方安装来源下载并安装 %ld 项缺失工具。工具较多时可能需要一些时间。", itemCount)
        case .update:
            AppLocalization.text("将通过官方安装来源更新 %ld 项已安装工具。工具较多时可能需要一些时间。", itemCount)
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
