import Foundation
import Testing
import ZislaCore

@testable import Zisla

struct SettingsNavigationTests {
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
            "复制助手",
            "截图",
            "工作流",
            "信息",
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
    func workflowVisibilityDependsOnMediaOrSystemMonitor() {
        var settings = FeatureSettings(mediaEnabled: false, systemMonitorEnabled: false)
        #expect(!SettingsSection.workflow.isVisible(settings: settings))

        settings.mediaEnabled = true
        #expect(SettingsSection.workflow.isVisible(settings: settings))

        settings.mediaEnabled = false
        settings.systemMonitorEnabled = true
        #expect(SettingsSection.workflow.isVisible(settings: settings))

        settings.mediaEnabled = true
        settings.systemMonitorEnabled = true
        #expect(SettingsSection.workflow.isVisible(settings: settings))
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
    func infoVisibilityDependsOnMailOrLockScreenOrSideNotices() {
        var settings = FeatureSettings(lockScreenInfoEnabled: false, mailEnabled: false, sideNoticesEnabled: false)
        #expect(!SettingsSection.info.isVisible(settings: settings))

        settings.mailEnabled = true
        #expect(SettingsSection.info.isVisible(settings: settings))

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
