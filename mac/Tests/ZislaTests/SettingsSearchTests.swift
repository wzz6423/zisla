import Foundation
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

struct SettingsSearchTests {
    @Test(arguments: ["", " \n\t\u{3000}", "没有这个设置xyz", ".*", "[invalid]"])
    func emptyAndUnmatchedQueriesHaveNoResults(query: String) {
        #expect(results(query).isEmpty)
    }

    @Test
    func matchesChineseSettingNamesAndDescriptions() {
        #expect(results("界面语言").map(\.title) == ["界面语言"])
        #expect(results("\t界面语言\n").map(\.title) == ["界面语言"])
        #expect(results("开机").map(\.title) == ["登录时启动"])
        #expect(results("语音 录音模式").map(\.title) == ["录音模式"])
    }

    @Test
    func matchesLocalizedNamesWithoutCaseOrWidthSensitivity() {
        #expect(results("  lOgIn \n", locale: .init(identifier: "en")).map(\.title) == ["登录时启动"])
        #expect(results("ＬＯＧＩＮ", locale: .init(identifier: "en")).map(\.title) == ["登录时启动"])
        #expect(results("界面语言", locale: .init(identifier: "en")).map(\.title) == ["界面语言"])
        #expect(results("general", locale: .init(identifier: "fr")).allSatisfy { $0.section == .general })
        #expect(results("general", locale: .init(identifier: "fr")).count == 5)
    }

    @Test(arguments: AppLanguage.allCases)
    func findsSettingInTheRequestedLanguage(language: AppLanguage) {
        let title = AppLocalization.string("界面语言", language: language)
        #expect(results(title, locale: language.locale).contains { $0.section == .general && $0.title == "界面语言" })
    }

    @Test
    func requiresEveryQueryWordAcrossTitleAndCategory() {
        #expect(results("通用 \n 启动").map(\.title) == ["登录时启动"])
        #expect(results("general LANGUAGE", locale: .init(identifier: "en")).map(\.title) == ["界面语言"])
        #expect(results("界面 不存在的关键词").isEmpty)
    }

    @Test
    func exactSettingNamesPrecedeRelatedEntries() {
        var settings = Self.enabledSettings
        settings.clipboardAssistantSearchEngine = .custom
        let matches = results("自定义搜索网址", settings: settings)
        #expect(matches.first?.title == "自定义搜索网址")
        #expect(results("\t自定义搜索网址\n", settings: settings).first?.title == "自定义搜索网址")
        #expect(matches.contains { $0.title == "搜索引擎" })
        #expect(results("文字").first?.anchor == .row("文字"))
        let localizedTitle = AppLocalization.string("自定义搜索网址", language: .english)
        #expect(results(localizedTitle, settings: settings, locale: .init(identifier: "en")).first?.title == "自定义搜索网址")
    }

    @Test
    func disabledFeaturesKeepTheirEnableSwitchSearchable() {
        var settings = Self.enabledSettings
        settings.voiceInputEnabled = false
        settings.clipboardAssistantEnabled = false
        settings.screenshotEnabled = false
        settings.recommendedToolsEnabled = false

        for (query, title) in [("语音", "语音输入"), ("快捷操作", "快捷操作"), ("截图", "启用截图"), ("推荐", "显示推荐工具")] {
            let matches = results(query, settings: settings)
            #expect(matches.contains { $0.section == .features && $0.title == title })
            #expect(matches.allSatisfy { $0.section.isVisible(settings: settings) })
        }
        #expect(!SettingsSearchIndex.items(settings: settings).contains { $0.title == "自动更新推荐工具" })
    }

    @Test
    func conditionalRowsFollowTheirControls() {
        var settings = Self.enabledSettings
        settings.contextNotesEnabled = false
        settings.clipboardAssistantSearchEngine = .google
        settings.lockScreenInfoEnabled = false
        settings.systemMonitorEnabled = false
        let hiddenTitles = ["便签快捷键", "自定义搜索网址", "锁屏文字", "显示农历", "监控样式", "记录历史"]
        #expect(SettingsSearchIndex.items(settings: settings).allSatisfy { !hiddenTitles.contains($0.title) })
        #expect(results("自定义搜索网址", settings: settings).map(\.title) == ["搜索引擎"])

        settings.contextNotesEnabled = true
        settings.clipboardAssistantSearchEngine = .custom
        settings.lockScreenInfoEnabled = true
        settings.systemMonitorEnabled = true
        settings.systemMonitorMenuBarLayout.individualEnabled = true
        let visibleTitles = Set(SettingsSearchIndex.items(settings: settings).map(\.title))
        #expect(Set(hiddenTitles).isSubset(of: visibleTitles))

        settings.systemMonitorMenuBarLayout.individualEnabled = false
        #expect(!SettingsSearchIndex.items(settings: settings).contains { $0.title == "监控样式" })
        #expect(results("合并状态图标", settings: settings).contains { $0.anchor == .group("settings-search-monitor-layout") })
    }

    @Test
    func catalogHasDistinctIdentitiesAndCoversEveryVisibleSection() {
        let settings = Self.enabledSettings
        let items = SettingsSearchIndex.items(settings: settings)
        #expect(Set(items.map(\.id)).count == items.count)
        #expect(Set(items.map(\.section)) == Set(SettingsSection.allCases))
        #expect(items.allSatisfy { !$0.title.isEmpty })
        #expect(items.contains { $0.section == .features && $0.title == "宠物" && $0.anchor == .row("宠物") })
        #expect(items.contains { $0.section == .pet && $0.title == "当前宠物" && $0.anchor == .row("当前宠物") })
    }

    @Test
    func reusesDynamicSettingCatalogs() {
        let items = SettingsSearchIndex.items(settings: Self.enabledSettings)
        for lexicon in VoiceLexicon.allCases {
            #expect(items.contains { $0.section == .voice && $0.anchor == .row(lexicon.title) })
        }
        for tool in ScreenshotTool.allCases {
            #expect(items.contains { $0.section == .screenshot && $0.anchor == .row(tool.title) })
        }
        for tool in ManagedTool.allCases {
            #expect(items.contains { $0.section == .recommendations && $0.anchor == .row(tool.displayName) })
        }
    }

    @Test
    func nestedConfigurationSearchTargetsReachableEntries() {
        #expect(results("自动更新 CLI").contains { $0.section == .ai && $0.anchor == .group("CLI 与 Skills") })
        #expect(results("底部指示样式").contains { $0.section == .info && $0.anchor == .group("settings-search-monitor-layout") })
        #expect(results("添加本地模型").contains { $0.section == .voice && $0.anchor == .group("本地模型") })
        #expect(results("邮件账户").contains { $0.section == .mail && $0.anchor == .group("邮件") })
        #expect(results("辅助功能").contains { $0.section == .clipboardAssistant && $0.anchor == .row("鼠标手势快速复制") })
        #expect(results("输入监控").contains { $0.section == .voice && $0.anchor == .row("快捷键") })
        #expect(results("跨时区").contains { $0.anchor == .row("识别类型") })
    }

    @Test
    func rowAndGroupAnchorsUseTheRenderedLanguage() {
        let locale = Locale(identifier: "en")
        #expect(SettingsSearchAnchor.row("界面语言").localized(locale: locale) == .row("Interface Language"))
        #expect(SettingsSearchAnchor.group("本地模型").localized(locale: locale) == .group(AppLocalization.string("本地模型", locale: locale)))
        #expect(SettingsSearchAnchor.row("Interface Language").localized(locale: locale) == .row("Interface Language"))
    }

    @Test @MainActor
    func selectingSearchResultsResetsSearchAndRevealsVoiceSettings() {
        let input = SettingsInput()
        input.selection = .voice
        input.voicePage = .history
        input.weatherQuery = "上海"
        input.settingsQuery = "录音模式"
        input.select(.voice, searchTarget: .row("录音模式"))

        #expect(input.selection == .voice)
        #expect(!input.isSearching)
        #expect(input.settingsQuery.isEmpty)
        #expect(input.searchTarget == .row("录音模式"))
        #expect(input.voicePage == .settings)
        #expect(input.weatherQuery == "上海")

        input.settingsQuery = "快捷键"
        input.select(.voice, searchTarget: .row("快捷键"))
        #expect(input.searchTarget == .row("快捷键"))
        #expect(input.selection == .voice)
    }

    @Test @MainActor
    func ordinaryNavigationClearsSearchWithoutResettingVoiceHistory() {
        let input = SettingsInput()
        input.selection = .voice
        input.voicePage = .history
        input.settingsQuery = "语音"
        input.select(.voice)

        #expect(input.settingsQuery.isEmpty)
        #expect(input.searchTarget == nil)
        #expect(input.voicePage == .history)
        input.select(.general, searchTarget: .row("界面语言"))
        input.select(.general)
        #expect(input.selection == .general)
        #expect(input.searchTarget == nil)
    }

    @Test @MainActor
    func searchingAnotherSectionPreservesTheVoiceHistoryPage() {
        let input = SettingsInput()
        input.selection = .voice
        input.voicePage = .history
        input.settingsQuery = "界面语言"
        input.select(.general, searchTarget: .row("界面语言"))

        #expect(input.selection == .general)
        #expect(input.searchTarget == .row("界面语言"))
        #expect(input.voicePage == .history)
    }

    @Test @MainActor
    func editingAndClearingSearchDiscardStaleScrollTargets() {
        let input = SettingsInput()
        input.select(.general, searchTarget: .row("界面语言"))
        input.settingsQuery = "启动"
        #expect(input.isSearching)
        #expect(input.searchTarget == nil)
        input.settingsQuery = ""
        #expect(!input.isSearching)
        #expect(input.selection == .general)
        input.settingsQuery = " \t\n\u{3000}"
        #expect(!input.isSearching)
    }

    private func results(
        _ query: String,
        settings: FeatureSettings = Self.enabledSettings,
        locale: Locale = Locale(identifier: "zh-Hans")
    ) -> [SettingsSearchItem] {
        SettingsSearchIndex.results(for: query, settings: settings, locale: locale)
    }

    private static var enabledSettings: FeatureSettings {
        var settings = FeatureSettings.default
        settings.mediaEnabled = true
        settings.systemMonitorEnabled = true
        settings.lockScreenInfoEnabled = true
        settings.sideNoticesEnabled = true
        settings.clipboardAssistantEnabled = true
        settings.screenshotEnabled = true
        settings.aiProgressEnabled = true
        settings.voiceInputEnabled = true
        settings.mailEnabled = true
        settings.keyboardEnabled = true
        settings.downloaderEnabled = true
        settings.weatherEnabled = true
        settings.petEnabled = true
        settings.recommendedToolsEnabled = true
        settings.updateChecksEnabled = true
        return settings
    }
}
