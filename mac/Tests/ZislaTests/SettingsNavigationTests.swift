import Foundation
import Testing
import ZislaCore

@testable import Zisla

struct SettingsNavigationTests {
    @Test(arguments: [false, true], [false, true])
    func combinedMonitorNavigationPreservesIndependentFeatureToggles(systemEnabled: Bool, batteryEnabled: Bool) {
        var settings = FeatureSettings.default
        settings.systemMonitorEnabled = systemEnabled
        settings.batteryMonitorEnabled = batteryEnabled
        settings.moduleOrder = [.battery, .mail, .system]

        let modules = IslandModule.enabledOrder(settings)
        #expect(modules.contains(.system) == (systemEnabled || batteryEnabled))
        #expect(IslandModule.battery.isEnabled(in: settings) == (systemEnabled || batteryEnabled))
        #expect(!modules.contains(.battery))
        #expect(modules.filter { $0 == .system }.count <= 1)
        if systemEnabled || batteryEnabled {
            #expect(modules.first == .system)
        }
        #expect(settings.systemMonitorEnabled == systemEnabled)
        #expect(settings.batteryMonitorEnabled == batteryEnabled)
    }

    @Test
    func legacyBatteryNavigationTargetsTheCombinedMonitor() {
        #expect(IslandModule.battery.navigationTarget == .system)
        for module in IslandModule.allCases where module != .battery {
            #expect(module.navigationTarget == module)
        }
    }

    @Test
    func windowPreviewSettingIsLocalizedInEveryLanguage() throws {
        let keys = [
            "窗口",
            "窗口预览",
            "悬停 Dock 或使用 Command-Tab 时预览窗口；需要辅助功能和屏幕录制权限",
        ]
        let packageRoot = Self.settingsViewSourceURL.deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        for language in AppLanguage.allCases {
            let tableURL = packageRoot.appendingPathComponent("Resources/Localization/\(language.rawValue).lproj/Localizable.strings")
            let table = try #require(NSDictionary(contentsOf: tableURL) as? [String: String])
            for key in keys {
                let value = try #require(table[key], "\(language.rawValue) is missing \(key)")
                #expect(!value.isEmpty)
                #expect(AppLocalization.string(key, language: language) == value)
                if language != .simplifiedChinese { #expect(value != key) }
            }
        }
    }

    @Test
    func recommendationVisibilityFollowsItsFeatureToggle() {
        var settings = FeatureSettings()
        #expect(SettingsSection.recommendations.isVisible(settings: settings))
        settings.recommendedToolsEnabled = false
        settings.recommendedToolsAutomaticUpdatesEnabled = true
        #expect(!SettingsSection.recommendations.isVisible(settings: settings))
    }

    @Test
    func recommendationControlsAreConditionalAndLocalizedInEveryLanguage() throws {
        let source = try String(contentsOf: Self.settingsViewSourceURL, encoding: .utf8)
        let controlsStart = try #require(source.range(of: "settingsGroup(\"推荐\")"))
        let controlsEnd = try #require(source.range(of: "settingsGroup(\"媒体与文件\")", range: controlsStart.upperBound..<source.endIndex))
        let controls = source[controlsStart.lowerBound..<controlsEnd.lowerBound]
        #expect(controls.contains("if model.settingsStore.settings.recommendedToolsEnabled {"))
        #expect(controls.contains("keyPath: \\.recommendedToolsAutomaticUpdatesEnabled"))
        let keys = [
            "显示推荐工具", "在设置中显示推荐工具和管理入口",
            "自动更新推荐工具", "每天更新已安装的推荐工具；不会安装未安装的工具",
        ]
        let packageRoot = Self.settingsViewSourceURL.deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        for language in AppLanguage.allCases {
            let tableURL = packageRoot.appendingPathComponent("Resources/Localization/\(language.rawValue).lproj/Localizable.strings")
            let table = try #require(NSDictionary(contentsOf: tableURL) as? [String: String])
            for key in keys {
                #expect(controls.contains("\"\(key)\""))
                let value = try #require(table[key], "\(language.rawValue) is missing \(key)")
                #expect(!value.isEmpty)
                #expect(AppLocalization.string(key, language: language) == value)
                if language != .simplifiedChinese { #expect(value != key) }
            }
        }
        #expect(AppLocalization.string("显示推荐工具", language: .english) == "Show Recommended Tools")
    }

    @Test
    func downloadCompletionToggleIsNestedUnderRecognitionTypes() throws {
        let source = try String(contentsOf: Self.settingsViewSourceURL, encoding: .utf8)
        let heading = try #require(source.range(of: "title: \"识别类型\""))
        let firstKind = try #require(source.range(
            of: "ForEach(ClipboardAssistantKind.allCases, id: \\.self)",
            range: heading.upperBound..<source.endIndex
        ))
        let toggle = try #require(source.range(of: "AppLocalization.text(\"下载与 AirDrop 完成提示\")"))

        #expect(toggle.lowerBound > heading.upperBound)
        #expect(toggle.lowerBound < firstKind.lowerBound)
        let row = source[toggle.lowerBound..<firstKind.lowerBound]
        #expect(row.contains("keyPath: \\.downloadCompletionFolderActionEnabled"))
        #expect(row.contains("isNested: true"))
    }

    @Test
    func settingsContentTransitionTargetsMountedContent() throws {
        let source = try String(contentsOf: Self.settingsViewSourceURL, encoding: .utf8)
        let detailRange = try #require(source.range(of: "    private var detail: some View {"))
        let detailEnd = try #require(source.range(of: "\n    private func selectSettingsSection", range: detailRange.lowerBound..<source.endIndex))
        let detail = String(source[detailRange.lowerBound..<detailEnd.lowerBound])
        let compactDetail = detail.components(separatedBy: .whitespacesAndNewlines).joined()

        #expect(compactDetail.contains("DeferredMount{selectedContent.id(input.selection).transition("))
        #expect(compactDetail.contains(".settingsPagePush(direction:sectionSwitchDirection)"))
    }

    @Test
    func settingsPageTransitionAvoidsBlur() throws {
        let source = try String(contentsOf: Self.motionDesignSourceURL, encoding: .utf8)
        let transitionStart = try #require(source.range(of: "    static func settingsPagePush(direction: CGFloat) -> AnyTransition {"))
        let transitionEnd = try #require(source.range(of: "\n    }\n}", range: transitionStart.lowerBound..<source.endIndex))
        let transition = String(source[transitionStart.lowerBound..<transitionEnd.lowerBound])

        #expect(transition.contains("blurRadius: 0"))
        #expect(!transition.contains("blurRadius: 5"))
    }

    @Test
    func moduleSelectionDoesNotAnimateNavigationGlyphGeometry() throws {
        let source = try String(contentsOf: Self.islandRootViewSourceURL, encoding: .utf8)
        let selectorStart = try #require(source.range(of: "private struct ModuleSelector: View {"))
        let selector = String(source[selectorStart.lowerBound...])

        #expect(selector.contains("MotionFocusLens(cornerRadius: 8)"))
        #expect(selector.contains(".frame(width: 28, height: 30)"))
        #expect(!selector.contains("emphasizesSelection: true"))
    }

    @Test
    func moduleRailDoesNotInheritSurfaceResizeAnimation() throws {
        let source = try String(contentsOf: Self.islandRootViewSourceURL, encoding: .utf8)
        let toolRailUse = try #require(source.range(of: "                            toolRail\n"))
        let moduleContentEnd = try #require(
            source[toolRailUse.upperBound...].range(of: "                            Group {")
        )
        let moduleContent = source[toolRailUse.lowerBound..<moduleContentEnd.lowerBound]

        #expect(moduleContent.contains(".transaction { transaction in"))
        #expect(moduleContent.contains("transaction.animation = nil"))
        #expect(source.contains(".animation(reduceMotion ? nil : ZislaMotion.selection, value: model.selectedModule)"))
    }

    @Test
    func updateChannelAppliesToAutomaticAndManualChecks() throws {
        let source = try String(contentsOf: Self.settingsViewSourceURL, encoding: .utf8)

        #expect(source.contains("title: \"更新通道\""))
        #expect(source.contains("用于自动与手动更新"))
        #expect(!source.contains("仅用于手动检查"))
    }

    @Test
    func showsOnlyCurrentSettingsSections() {
        #expect(SettingsSection.allCases.map(\.title) == [
            "通用",
            "功能",
            "快捷操作",
            "截图",
            "信息",
            "邮件",
            "AI",
            "语音",
            "键盘音效",
            "宠物",
            "下载",
            "天气",
            "网络",
            "推荐",
            "反馈与更新",
        ])
        #expect(SettingsSection.general.subtitle == "调整语言、外观、启动与展开方式。")
        #expect(SettingsSection.clipboardAssistant.subtitle == "复制、浏览器下载或 AirDrop 接收完成后显示下一步操作")
        #expect(SettingsSection.ai.subtitle == "管理 AI CLI 与 Skills。")
        #expect(SettingsSection.voice.subtitle == "配置语音输入、整理模型与本机记录。")
        #expect(SettingsSection.keyboardSound.subtitle == "键盘音效与输入统计。")
        #expect(!SettingsSection.keyboardSound.prefersWideLayout)
        #expect(SettingsSection.networkProxy.subtitle == "配置本地代理，用于更新、安装、下载与 GitHub 访问。")
        #expect(SettingsSection.updates.subtitle == "提交问题反馈、管理版本检查与自动更新。")
    }

    @Test
    func feedbackAndUpdatePageLinksToIssueChooserInEveryLanguage() throws {
        let source = try String(contentsOf: Self.settingsViewSourceURL, encoding: .utf8)

        #expect(source.contains("case .updates: \"反馈与更新\""))
        #expect(source.contains("case .updates: \"提交问题反馈、管理版本检查与自动更新。\""))
        #expect(source.contains("\"反馈问题\""))
        #expect(source.contains("destination: ZislaKitInfo.newIssueURL"))

        for key in ["反馈与更新", "提交问题反馈、管理版本检查与自动更新。", "反馈问题"] {
            for language in AppLanguage.allCases {
                let translation = AppLocalization.string(key, language: language)
                #expect(!translation.isEmpty, "\(language.rawValue) missing \(key)")
                if language != .simplifiedChinese {
                    #expect(translation != key, "\(language.rawValue) did not translate \(key)")
                }
            }
        }
    }

    @Test
    func islandDoesNotExposeAIAgentModule() {
        #expect(!IslandModule.allCases.map(\.rawValue).contains("aiAgent"))
    }

    @Test
    func toolAndStatusOrderSettingsUseTheSharedDragAndResetControls() throws {
        let source = try String(contentsOf: Self.settingsViewSourceURL, encoding: .utf8)

        #expect(source.contains("settingsGroup(\"工具\")"))
        #expect(source.contains("settingsGroup(\"收起态展示优先级\")"))
        #expect(source.contains("ReorderDropDelegate<IslandModuleOrder>"))
        #expect(source.contains("ReorderDropDelegate<CompactStatusPriority>"))
        #expect(source.contains("moduleOrder = IslandModuleOrder.defaultOrder"))
        #expect(source.contains("compactStatusPriority = CompactStatusPriority.defaultOrder"))
    }

    @Test
    func alwaysVisibleSections() {
        let settings = FeatureSettings()
        #expect(SettingsSection.general.isVisible(settings: settings))
        #expect(SettingsSection.features.isVisible(settings: settings))
        #expect(SettingsSection.keyboardSound.isVisible(settings: settings))
        #expect(SettingsSection.networkProxy.isVisible(settings: settings))
        #expect(SettingsSection.recommendations.isVisible(settings: settings))

        var disabledSettings = settings
        disabledSettings.keyboardEnabled = false
        #expect(!SettingsSection.keyboardSound.isVisible(settings: disabledSettings))
    }

    @Test
    func keyboardSettingsDoNotExposePointerOrLaunchItemControls() throws {
        let source = try String(contentsOf: Self.settingsViewSourceURL, encoding: .utf8)
        let contentStart = try #require(source.range(of: "    private var keyboardSoundContent: some View {"))
        let contentEnd = try #require(source.range(of: "\n    private var infoContent", range: contentStart.upperBound..<source.endIndex))
        let content = String(source[contentStart.lowerBound..<contentEnd.lowerBound])

        #expect(!content.contains("鼠标与触控板"))
        #expect(!content.contains("启动项"))
        #expect(!content.contains("启用键盘与点击音效"))
        #expect(content.contains("试听键盘音"))
        #expect(!content.contains("settingsGroup(\"输入统计\")"))
        #expect(!content.contains("KeyboardTypingStatsDashboardView"))
        #expect(!content.contains("keyboardTypingStatsContent"))
        #expect(!content.contains("refreshTypingStats()"))
        #expect(source.contains("featureToggle(\"键盘音效\", detail: \"全局播放键盘音效并记录输入统计\""))
        #expect(source.contains("featureToggle(\"合盖动画\", detail: \"合上兼容 MacBook 屏幕时显示景深过渡动画\""))
    }

    @Test
    func infoVisibilityIncludesMediaAndSystemMonitor() {
        var settings = FeatureSettings(
            mediaEnabled: false,
            systemMonitorEnabled: false,
            lockScreenInfoEnabled: false,
            mailEnabled: false,
            sideNoticesEnabled: false
        )
        #expect(!SettingsSection.info.isVisible(settings: settings))

        settings.mediaEnabled = true
        #expect(SettingsSection.info.isVisible(settings: settings))

        settings.mediaEnabled = false
        settings.systemMonitorEnabled = true
        #expect(SettingsSection.info.isVisible(settings: settings))

        settings.mediaEnabled = true
        settings.systemMonitorEnabled = true
        #expect(SettingsSection.info.isVisible(settings: settings))
    }

    @Test(arguments: [false, true])
    func mailVisibilityOnlyDependsOnMailToggle(otherInfoFeaturesEnabled: Bool) throws {
        let mailSection = try #require(SettingsSection(rawValue: "mail"))
        var settings = FeatureSettings(
            mediaEnabled: otherInfoFeaturesEnabled,
            systemMonitorEnabled: otherInfoFeaturesEnabled,
            lockScreenInfoEnabled: otherInfoFeaturesEnabled,
            mailEnabled: false,
            sideNoticesEnabled: otherInfoFeaturesEnabled
        )
        #expect(!mailSection.isVisible(settings: settings))
        #expect(SettingsSection.info.isVisible(settings: settings) == otherInfoFeaturesEnabled)

        settings.mailEnabled = true
        #expect(mailSection.isVisible(settings: settings))
        #expect(SettingsSection.info.isVisible(settings: settings) == otherInfoFeaturesEnabled)

        settings.mailEnabled = false
        #expect(!mailSection.isVisible(settings: settings))
        #expect(SettingsSection.info.isVisible(settings: settings) == otherInfoFeaturesEnabled)
    }

    @Test
    func defaultSettingsShowInfoAndMailWithoutWorkflowNavigation() {
        let settings = FeatureSettings()
        let visibleSections = SettingsSection.allCases.filter { $0.isVisible(settings: settings) }

        #expect(visibleSections == SettingsSection.allCases)
        #expect(visibleSections.map(\.rawValue).contains("info"))
        #expect(visibleSections.map(\.rawValue).contains("mail"))
        #expect(!visibleSections.map(\.rawValue).contains("workflow"))
        #expect(settings.mediaEnabled)
        #expect(settings.systemMonitorEnabled)
        #expect(settings.mailEnabled)
        #expect(settings.lockScreenInfoEnabled)
        #expect(settings.sideNoticesEnabled)
        #expect(settings.mailAccountNames.isEmpty)
    }

    @Test
    func infoAndMailNavigationAreLocalizedInEveryLanguage() throws {
        let mailSection = try #require(SettingsSection(rawValue: "mail"))
        #expect(SettingsSection.info.subtitle == "配置媒体、系统监控、锁屏与通知显示。")
        #expect(mailSection.title == "邮件")
        #expect(mailSection.subtitle == "读取已配置的 Mail.app 账户并提醒新邮件")
        #expect(mailSection.symbol == "envelope.fill")
        let englishSubtitle = "Configure media, system monitoring, lock screen, and notifications."
        #expect(AppLocalization.string(SettingsSection.info.subtitle, language: .english) == englishSubtitle)
        let keys = [SettingsSection.info.title, SettingsSection.info.subtitle, mailSection.title, mailSection.subtitle]
        let packageRoot = Self.settingsViewSourceURL.deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        #expect(AppLanguage.allCases.count == 17)

        for language in AppLanguage.allCases {
            let tableURL = packageRoot.appendingPathComponent("Resources/Localization/\(language.rawValue).lproj/Localizable.strings")
            let table = try #require(NSDictionary(contentsOf: tableURL) as? [String: String])
            for key in keys {
                let value = try #require(table[key], "\(language.rawValue) is missing \(key)")
                #expect(!value.isEmpty)
                #expect(AppLocalization.string(key, language: language) == value)
                if language != .simplifiedChinese { #expect(value != key) }
            }
            if language != .english {
                #expect(table[SettingsSection.info.subtitle] != englishSubtitle)
            }
        }
    }

    @Test
    func mailControlsOnlyAppearOnTheDedicatedMailPage() throws {
        let source = try String(contentsOf: Self.settingsViewSourceURL, encoding: .utf8)
        let infoStart = try #require(source.range(of: "    private var infoContent: some View {"))
        let mailStart = try #require(source.range(of: "\n    private var mailContent: some View {", range: infoStart.upperBound..<source.endIndex))
        let mailEnd = try #require(source.range(of: "\n    private var aiContent: some View {", range: mailStart.upperBound..<source.endIndex))
        let infoContent = source[infoStart.lowerBound..<mailStart.lowerBound]
        let mailContent = source[mailStart.lowerBound..<mailEnd.lowerBound]

        #expect(source.contains("case .mail:\n            mailContent"))
        #expect(mailContent.contains("settingsGroup(\"邮件\")"))
        #expect(mailContent.contains("mailAccountSettings"))
        #expect(!infoContent.contains("mailAccountSettings"))
        #expect(!infoContent.contains("mailEnabled"))
        #expect(source.components(separatedBy: "mailAccountSettings").count == 3)

        let accountsStart = try #require(source.range(of: "    private var mailAccountSettings: some View {"))
        let accountsEnd = try #require(source.range(of: "\n    private func mailAccountBinding", range: accountsStart.upperBound..<source.endIndex))
        let accountsContent = source[accountsStart.lowerBound..<accountsEnd.lowerBound]
        #expect(accountsContent.contains("model.settingsStore.settings.mailCompactStyle"))
        #expect(accountsContent.contains("mailAppAccountSettings"))
        #expect(accountsContent.contains("model.refreshMail()"))
        #expect(accountsContent.contains("mailAccountBinding(for: account.id, availableAccounts: accounts)"))
        #expect(accountsContent.contains("isOnlySelectedMailAccount(account.id)"))
    }

    @Test
    func infoPageKeepsWorkflowAndNonMailControls() throws {
        let source = try String(contentsOf: Self.settingsViewSourceURL, encoding: .utf8)
        let infoStart = try #require(source.range(of: "    private var infoContent: some View {"))
        let infoEnd = try #require(source.range(of: "\n    private var mailContent: some View {", range: infoStart.upperBound..<source.endIndex))
        let infoContent = source[infoStart.lowerBound..<infoEnd.lowerBound]
        #expect(infoContent.contains("workflowContent"))
        for control in [
            "lockScreenMessage", "lockScreenShowsLunar", "activityNoticeDisplayDuration",
            "focusModeNoticeDisplayDuration", "compactStatusPriority", "activityNoticeDisplayBinding",
        ] {
            #expect(infoContent.contains(control), "Info page lost \(control)")
        }

        let workflowStart = try #require(source.range(of: "    private var workflowContent: some View {"))
        let workflowEnd = try #require(source.range(of: "\n    private var featuresContent: some View {", range: workflowStart.upperBound..<source.endIndex))
        let workflowContent = source[workflowStart.lowerBound..<workflowEnd.lowerBound]
        for control in ["mediaSource", "mediaShowLyricsAndInfo", "mediaCompactStyle", "systemMetricsHistoryEnabled"] {
            #expect(workflowContent.contains(control), "Workflow controls lost \(control)")
        }
    }

    @Test
    func disablingMailUsesTheExistingVisibleSelectionFallback() throws {
        let source = try String(contentsOf: Self.settingsViewSourceURL, encoding: .utf8)
        let selectionStart = try #require(source.range(of: "    private func ensureSelectionIsVisible() {"))
        let selectionEnd = try #require(source.range(of: "\n    @ViewBuilder", range: selectionStart.upperBound..<source.endIndex))
        let selection = source[selectionStart.lowerBound..<selectionEnd.lowerBound]
        #expect(selection.contains("guard !input.selection.isVisible(settings: settingsStore.settings) else { return }"))
        #expect(selection.contains("selectSettingsSection(.features)"))
        let compactSource = source.components(separatedBy: .whitespacesAndNewlines).joined()
        #expect(compactSource.contains(".onChange(of:settingsStore.settings){_,_inensureSelectionIsVisible()}"))
        #expect(SettingsSection.features.isVisible(settings: FeatureSettings(mailEnabled: false)))
    }

    @Test
    func clipboardAssistantAndScreenshotVisibilityFollowFeatureToggles() {
        var settings = FeatureSettings(clipboardAssistantEnabled: false, screenshotEnabled: false)
        #expect(!SettingsSection.clipboardAssistant.isVisible(settings: settings))
        #expect(!SettingsSection.screenshot.isVisible(settings: settings))

        settings.clipboardAssistantEnabled = true
        settings.screenshotEnabled = true
        #expect(SettingsSection.clipboardAssistant.isVisible(settings: settings))
        #expect(SettingsSection.screenshot.isVisible(settings: settings))
    }

    @Test
    func clipboardAssistantConversionSettingShowsCopyableExamplesInEveryLanguage() throws {
        let source = try String(contentsOf: Self.settingsViewSourceURL, encoding: .utf8)
        let examplesStart = try #require(source.range(of: "private var clipboardAssistantConversionExamples"))
        let examplesEnd = try #require(source[examplesStart.upperBound...].range(of: "private struct AssistantBlacklistEntry"))
        let examples = source[examplesStart.lowerBound..<examplesEnd.lowerBound]

        #expect(source.contains("if kind == .conversion"))
        #expect(source.contains("case .conversion: \"换算\""))
        #expect(examples.contains(".textSelection(.enabled)"))
        #expect(examples.contains("copyClipboardAssistantConversionExample(example)"))
        #expect(examples.contains(".padding(.leading, 12)"))
        for example in [
            "10 ft = m", "100 kg = lb", "5 km = mi",
            "100 USD = CNY", "100$ = ¥", "100dollar = CNY",
            "2026-09-17 - 2026-10-01", "2026/09/17 - 2026/10/01", "2026.09.17 - 2026.10.01",
            "2026-09-17 09:30 Asia/Shanghai = America/New_York",
            "09:30 UTC+08:00 = UTC",
            "2026-09-17 09:30 America/New_York = Europe/London",
        ] {
            #expect(examples.contains(example))
        }

        for key in ["换算", "单位换算", "汇率换算", "日期间隔", "跨时区时间"] {
            for language in AppLanguage.allCases {
                let translation = AppLocalization.string(key, language: language)
                #expect(!translation.isEmpty, "\(language.rawValue) missing \(key)")
                if language != .simplifiedChinese {
                    #expect(translation != key, "\(language.rawValue) did not translate \(key)")
                }
            }
        }
    }

    @Test
    func infoVisibilityRetainsLockScreenAndSideNoticesButExcludesMail() {
        var settings = FeatureSettings(
            mediaEnabled: false,
            systemMonitorEnabled: false,
            lockScreenInfoEnabled: false,
            mailEnabled: false,
            sideNoticesEnabled: false
        )
        #expect(!SettingsSection.info.isVisible(settings: settings))

        settings.mailEnabled = true
        #expect(!SettingsSection.info.isVisible(settings: settings))

        settings.mailEnabled = false
        settings.lockScreenInfoEnabled = true
        #expect(SettingsSection.info.isVisible(settings: settings))

        settings.mailEnabled = false
        settings.lockScreenInfoEnabled = false
        settings.sideNoticesEnabled = true
        #expect(SettingsSection.info.isVisible(settings: settings))
    }

    @Test
    func individualSectionsBindToFeatureToggles() {
        var settings = FeatureSettings(
            aiProgressEnabled: false,
            downloaderEnabled: false,
            weatherEnabled: false,
            lockScreenInfoEnabled: false,
            mailEnabled: false,
            updateChecksEnabled: false,
            sideNoticesEnabled: false,
            petEnabled: false,
            voiceInputEnabled: false
        )
        #expect(!SettingsSection.ai.isVisible(settings: settings))
        #expect(!SettingsSection.voice.isVisible(settings: settings))
        #expect(!SettingsSection.pet.isVisible(settings: settings))
        #expect(!SettingsSection.download.isVisible(settings: settings))
        #expect(!SettingsSection.weather.isVisible(settings: settings))
        #expect(!SettingsSection.updates.isVisible(settings: settings))

        settings.aiProgressEnabled = true
        #expect(SettingsSection.ai.isVisible(settings: settings))

        settings.voiceInputEnabled = true
        #expect(SettingsSection.voice.isVisible(settings: settings))

        settings.petEnabled = true
        #expect(SettingsSection.pet.isVisible(settings: settings))

        settings.downloaderEnabled = true
        #expect(SettingsSection.download.isVisible(settings: settings))

        settings.weatherEnabled = true
        #expect(SettingsSection.weather.isVisible(settings: settings))

        settings.updateChecksEnabled = true
        #expect(SettingsSection.updates.isVisible(settings: settings))
    }

    @Test
    func petSectionTitleIsShort() {
        #expect(SettingsSection.pet.title == "宠物")
    }

    @Test @MainActor
    func clipboardBlacklistAcceptsOnlyApplicationsDirectoryBundles() {
        #expect(SettingsView.isApplicationBundleInApplicationsDirectory(
            URL(fileURLWithPath: "/Applications/Example.app")
        ))
        #expect(!SettingsView.isApplicationBundleInApplicationsDirectory(
            URL(fileURLWithPath: "/System/Applications/Example.app")
        ))
        #expect(!SettingsView.isApplicationBundleInApplicationsDirectory(
            URL(fileURLWithPath: "/Applications/Example.txt")
        ))
    }

    private static var settingsViewSourceURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Zisla/SettingsView.swift")
    }

    private static var motionDesignSourceURL: URL {
        settingsViewSourceURL
            .deletingLastPathComponent()
            .appendingPathComponent("MotionDesign.swift")
    }

    private static var islandRootViewSourceURL: URL {
        settingsViewSourceURL
            .deletingLastPathComponent()
            .appendingPathComponent("IslandRootView.swift")
    }
}
