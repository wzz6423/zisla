import Foundation
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

struct SettingsSearchTests {
    @Test(arguments: AppLanguage.allCases, [false, true])
    func batterySearchTargetsTheCombinedMonitorToggle(language: AppLanguage, systemEnabled: Bool) {
        let settings = FeatureSettings(systemMonitorEnabled: systemEnabled)
        #expect(!SettingsSearchIndex.items(settings: settings, displayCount: 2).contains { $0.title == "电池监控" })
        let matches = results(AppLocalization.string("电池监控", language: language),
            settings: settings, locale: language.locale)
        #expect(matches.contains {
            $0.section == .features && $0.title == "系统状态与清理" && $0.anchor == .row("系统状态与清理")
        })
    }

    @Test(arguments: AppLanguage.allCases)
    func clipboardHistoryCleanupIsSearchableInEveryLanguage(language: AppLanguage) {
        let title = AppLocalization.string("自动删除剪贴板历史", language: language)
        let matches = results(title, settings: FeatureSettings.default, locale: language.locale)
        #expect(matches.first?.section == .scheduledCleanup)
        #expect(matches.first?.anchor == .row("自动删除剪贴板历史"))
    }

    @Test(arguments: AppLanguage.allCases)
    func quietMDRecommendationIsSearchableByNameAndLocalizedPurpose(language: AppLanguage) {
        let queries = [ManagedTool.quietMD.displayName, AppLocalization.string(ManagedTool.quietMD.purpose, language: language)]
        for query in queries {
            let matches = results(query, locale: language.locale)
            #expect(matches.contains { $0.section == .recommendations && $0.anchor == .row("Quiet.md") })
            #expect(results(query, settings: FeatureSettings(recommendedToolsEnabled: false), locale: language.locale)
                .allSatisfy { $0.anchor != .row("Quiet.md") })
        }
    }

    @Test(arguments: [false, true], [false, true])
    func careAndFloatingInformationSearchEntriesFollowTheirOwnControls(careEnabled: Bool, customPlacement: Bool) {
        var settings = FeatureSettings(userCareEnabled: careEnabled)
        settings.islandLayoutStyle = .pill
        settings.islandPlacement = IslandPlacement(mode: customPlacement ? .custom : .camera)
        let items = SettingsSearchIndex.items(settings: settings, displayCount: 2)
        #expect(items.contains { $0.title == "关怀提醒间隔" } == careEnabled)
        #expect(items.contains { $0.title == "展示更多信息" } == customPlacement)
    }

    @Test(arguments: AppLanguage.allCases)
    func careIntervalSearchReachesNotificationsWhenOtherInfoFeaturesAreOff(language: AppLanguage) {
        var settings = FeatureSettings(userCareEnabled: true)
        settings.mediaEnabled = false
        settings.systemMonitorEnabled = false
        settings.lockScreenInfoEnabled = false
        settings.sideNoticesEnabled = false
        settings.dailyBriefing.enabled = false
        #expect(SettingsSection.notifications.isVisible(settings: settings))
        let matches = results(AppLocalization.string("关怀提醒间隔", language: language), settings: settings, locale: language.locale)
        #expect(matches.first?.section == .notifications)
        #expect(matches.first?.anchor == .row("关怀提醒间隔"))
        settings.userCareEnabled = false
        #expect(SettingsSection.notifications.isVisible(settings: settings))
        #expect(!SettingsSearchIndex.items(settings: settings, displayCount: 2).contains { $0.title == "关怀提醒间隔" })
    }

    @Test(arguments: AppLanguage.allCases) @MainActor
    func migratedInformationSearchDestinationsKeepTheirPageAndAnchor(language: AppLanguage) throws {
        var settings = Self.enabledSettings
        settings.userCareEnabled = true
        settings.islandLayoutStyle = .pill
        settings.islandPlacement.mode = .custom
        settings.systemMonitorMenuBarLayout.individualEnabled = true
        let destinations: [(String, SettingsSection, SettingsSearchAnchor)] = [
            ("灵动岛功能顺序", .info, .group("灵动岛功能顺序")),
            ("显示应用标识", .info, .row("显示应用标识")),
            ("展示更多信息", .info, .row("展示更多信息")),
            ("收起态展示优先级", .info, .group("收起态展示优先级")),
            ("每日简报", .dailyBriefing, .group("每日简报")),
            ("简报内容", .dailyBriefing, .row("简报内容")),
            ("简报模板", .dailyBriefing, .row("简报模板")),
            ("导出时间", .dailyBriefing, .row("导出时间")),
            ("锁屏文字", .notifications, .row("锁屏文字")),
            ("显示农历", .notifications, .row("显示农历")),
            ("活动展示", .notifications, .row("活动展示")),
            ("专注模式展示", .notifications, .row("专注模式展示")),
            ("关怀提醒间隔", .notifications, .row("关怀提醒间隔")),
            ("通知显示器", .notifications, .group("通知显示器")),
            ("播放来源", .workflow, .row("播放来源")),
            ("歌词与歌曲信息", .workflow, .row("歌词与歌曲信息")),
            ("收起态音乐样式", .workflow, .row("收起态音乐样式")),
            ("音乐动效", .workflow, .row("音乐动效")),
            ("机器监控状态显示位置", .workflow, .row("机器监控状态显示位置")),
            ("常驻监控图标", .workflow, .row("常驻监控图标")),
            ("监控样式", .workflow, .row("监控样式")),
            ("合并", .workflow, .group("settings-search-monitor-layout")),
            ("合并状态图标", .workflow, .group("settings-search-monitor-layout")),
            ("记录历史", .workflow, .row("记录历史")),
        ] + SystemMonitorMenuBarMetric.allCases.map { ($0.menuTitle, .workflow, .row($0.menuTitle)) }
        let input = SettingsInput()
        input.weatherQuery = "synthetic location"
        for (title, page, anchor) in destinations {
            let query = AppLocalization.string(title, language: language)
            let result = try #require(results(query, settings: settings, locale: language.locale).first {
                $0.title == title && $0.section == page
            }, "\(title) must reach \(page.rawValue) in \(language.rawValue)")
            #expect(result.anchor == anchor)
            #expect(!results(query, settings: settings, locale: language.locale).contains {
                $0.title == title && $0.section == .info && page != .info
            })
            input.settingsQuery = query
            input.select(result.section, searchTarget: result.anchor)
            #expect(input.selection == page)
            #expect(input.searchTarget == anchor)
            #expect(!input.isSearching)
            #expect(input.weatherQuery == "synthetic location")
        }
    }

    @Test(arguments: AppLanguage.allCases, [0, 1, 2])
    func notificationDisplaySearchMatchesTheEnumerableScreenCount(language: AppLanguage, displayCount: Int) {
        let settings = FeatureSettings(sideNoticesEnabled: false)
        let title = "通知显示器"
        let items = SettingsSearchIndex.items(settings: settings, displayCount: displayCount)
        #expect(items.contains { $0.title == title && $0.section == .notifications } == (displayCount == 2))
        for key in [title, "播放与 AI 活动通知显示在此屏幕"] {
            let matches = results(AppLocalization.string(key, language: language), settings: settings,
                locale: language.locale, displayCount: displayCount)
            #expect(matches.contains { $0.section == .notifications && $0.anchor == .group(title) } == (displayCount == 2))
        }
        #expect(results("活动展示", settings: settings, displayCount: displayCount).contains {
            $0.section == .notifications && $0.anchor == .row("活动展示")
        })
    }

    @Test
    func informationPagesKeepDisabledFeatureConfigurationSearchable() {
        let settings = FeatureSettings(mediaEnabled: false, systemMonitorEnabled: false,
            dailyBriefing: DailyBriefingSettings(enabled: false), lockScreenInfoEnabled: false,
            sideNoticesEnabled: false, userCareEnabled: false)
        for (title, page) in [("简报模板", SettingsSection.dailyBriefing), ("播放来源", .workflow),
                              ("活动展示", .notifications), ("收起态展示优先级", .info)] {
            #expect(results(title, settings: settings).contains { $0.title == title && $0.section == page })
        }
        let hiddenTitles = ["锁屏文字", "显示农历", "关怀提醒间隔", "常驻监控图标", "记录历史"]
        #expect(SettingsSearchIndex.items(settings: settings, displayCount: 1).allSatisfy {
            !hiddenTitles.contains($0.title)
        })
    }

    /// Ordering must remain discoverable by disabled module names without enabling information features.
    @Test(arguments: AppLanguage.allCases)
    func moduleOrderSearchReachesInformationWhenOtherInfoFeaturesAreOff(language: AppLanguage) {
        let settings = FeatureSettings(
            mediaEnabled: false,
            systemMonitorEnabled: false,
            dailyBriefing: DailyBriefingSettings(enabled: false),
            lockScreenInfoEnabled: false,
            sideNoticesEnabled: false,
            userCareEnabled: false
        )
        let title = AppLocalization.string("灵动岛功能顺序", language: language)
        let matches = results(title, settings: settings, locale: language.locale)
        #expect(matches.first?.section == .info)
        #expect(matches.first?.anchor == .group("灵动岛功能顺序"))
        for key in ["恢复默认顺序"] + IslandModuleOrder.defaultOrder.map(\.title) {
            let query = AppLocalization.string(key, language: language)
            #expect(results(query, settings: settings, locale: language.locale).contains {
                $0.section == .info && $0.anchor == .group("灵动岛功能顺序")
            }, "Module order must be searchable by \(key) in \(language.rawValue)")
        }
        #expect(!SettingsSearchIndex.items(settings: settings, displayCount: 2).contains {
            $0.section == .features && $0.anchor == .group("工具")
        })
    }

    @Test(arguments: AppLanguage.allCases, [false, true])
    func userCareOptInIsSearchableBeforeEnablingIt(language: AppLanguage, sideNoticesEnabled: Bool) {
        let title = AppLocalization.string("用户关怀", language: language)
        let matches = results(title, settings: FeatureSettings(sideNoticesEnabled: sideNoticesEnabled,
            userCareEnabled: false), locale: language.locale)
        #expect(matches.contains { $0.section == .features && $0.title == "用户关怀" && $0.anchor == .row("用户关怀") })
    }

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
        #expect(Set(results("general", locale: .init(identifier: "fr")).map(\.title))
            == ["界面语言", "界面外观", "灵动岛样式", "灵动岛展开材质", "灵动岛收起材质", "登录时启动"])
    }

    @Test(arguments: AppLanguage.allCases)
    func findsSettingInTheRequestedLanguage(language: AppLanguage) {
        let title = AppLocalization.string("界面语言", language: language)
        #expect(results(title, locale: language.locale).contains { $0.section == .general && $0.title == "界面语言" })
        let dependencyTitle = AppLocalization.string("依赖组件", language: language)
        let matches = results(dependencyTitle, locale: language.locale)
        let dependencies = matches.filter { $0.section == .download }
        #expect(Set(dependencies.map(\.title)) == Set([ManagedTool.ytDLP, .libreOffice, .libvips, .libavif].map(\.displayName)))
        #expect(matches.filter { $0.section != .download }.allSatisfy {
            $0.section == .features && $0.title == "自动更新依赖组件" && $0.anchor == .row("自动更新依赖组件")
        })
        var disabled = FeatureSettings(downloaderEnabled: false)
        disabled.pdfToolsEnabled = false
        disabled.imageToolsEnabled = false
        #expect(results(dependencyTitle, settings: disabled, locale: language.locale).allSatisfy {
            $0.section == .features && $0.title == "自动更新依赖组件"
        })
    }

    /// Legacy aliases stay attached to dependency rows while any dependent feature is enabled.
    @Test(arguments: AppLanguage.allCases)
    func legacyDownloadTitleStillFindsDependencyComponents(language: AppLanguage) {
        for query in ["下载", "Downloads", AppLocalization.string("下载", language: language)] {
            let dependencies = results(query, locale: language.locale).filter { $0.section == .download }
            #expect(Set(dependencies.map(\.title)) == Set([ManagedTool.ytDLP, .libreOffice, .libvips, .libavif].map(\.displayName)))
            #expect(dependencies.allSatisfy { $0.anchor == .row($0.title) })
            var disabled = FeatureSettings(downloaderEnabled: false)
            disabled.pdfToolsEnabled = false
            disabled.imageToolsEnabled = false
            #expect(results(query, settings: disabled, locale: language.locale)
                .allSatisfy { $0.section != .download })
        }
    }

    @Test(arguments: AppLanguage.allCases)
    func imageDependenciesAreSearchableWithoutDownloaderOrRecommendations(language: AppLanguage) {
        var settings = FeatureSettings.default
        settings.downloaderEnabled = false
        settings.pdfToolsEnabled = false
        settings.imageToolsEnabled = true
        settings.recommendedToolsEnabled = false
        for tool in [ManagedTool.libvips, .libavif] {
            let matches = results(tool.displayName, settings: settings, locale: language.locale)
            #expect(matches.contains { $0.section == .download && $0.anchor == .row(tool.displayName) })
            #expect(matches.allSatisfy { $0.section.isVisible(settings: settings) })
        }
        settings.imageToolsEnabled = false
        #expect(!SettingsSection.download.isVisible(settings: settings))
        #expect(results(ManagedTool.libvips.displayName, settings: settings, locale: language.locale).isEmpty)
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
        #expect(!SettingsSearchIndex.items(settings: settings, displayCount: 2).contains { $0.title == "自动更新推荐工具" })
    }

    @Test
    func conditionalRowsFollowTheirControls() {
        var settings = Self.enabledSettings
        settings.contextNotesEnabled = false
        settings.clipboardAssistantSearchEngine = .google
        settings.lockScreenInfoEnabled = false
        settings.systemMonitorEnabled = false
        let hiddenTitles = ["便签快捷键", "自定义搜索网址", "锁屏文字", "显示农历", "监控样式", "记录历史"]
        #expect(SettingsSearchIndex.items(settings: settings, displayCount: 2).allSatisfy { !hiddenTitles.contains($0.title) })
        #expect(results("自定义搜索网址", settings: settings).map(\.title) == ["搜索引擎"])

        settings.contextNotesEnabled = true
        settings.clipboardAssistantSearchEngine = .custom
        settings.lockScreenInfoEnabled = true
        settings.systemMonitorEnabled = true
        settings.systemMonitorMenuBarLayout.individualEnabled = true
        let visibleTitles = Set(SettingsSearchIndex.items(settings: settings, displayCount: 2).map(\.title))
        #expect(Set(hiddenTitles).isSubset(of: visibleTitles))

        settings.systemMonitorMenuBarLayout.individualEnabled = false
        #expect(!SettingsSearchIndex.items(settings: settings, displayCount: 2).contains { $0.title == "监控样式" })
        #expect(results("合并状态图标", settings: settings).contains { $0.anchor == .group("settings-search-monitor-layout") })
    }

    @Test
    func fixedPillDimensionsAreNotSettingsSearchEntries() {
        var settings = Self.enabledSettings
        settings.islandLayoutStyle = .pill
        let items = SettingsSearchIndex.items(settings: settings, displayCount: 2)
        #expect(items.contains { $0.title == "灵动岛位置" })
        #expect(!items.contains { $0.title == "药丸宽度" })
        #expect(!items.contains { $0.title == "药丸高度" })
        #expect(results("药丸宽度", settings: settings).isEmpty)
        #expect(results("药丸高度", settings: settings).isEmpty)
    }

    @Test
    func catalogHasDistinctIdentitiesAndCoversEveryVisibleSection() {
        let settings = Self.enabledSettings
        let items = SettingsSearchIndex.items(settings: settings, displayCount: 2)
        #expect(Set(items.map(\.id)).count == items.count)
        #expect(Set(items.map(\.section)) == Set(SettingsSection.allCases))
        #expect(items.allSatisfy { !$0.title.isEmpty })
        #expect(items.contains { $0.section == .features && $0.title == "宠物" && $0.anchor == .row("宠物") })
        #expect(items.contains { $0.section == .pet && $0.title == "当前宠物" && $0.anchor == .row("当前宠物") })
    }

    @Test
    func reusesDynamicSettingCatalogs() {
        let items = SettingsSearchIndex.items(settings: Self.enabledSettings, displayCount: 2)
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

    @Test(arguments: AppLanguage.allCases)
    func imageOperationsAreSearchableAndRespectTheirToggle(language: AppLanguage) {
        var settings = FeatureSettings.default
        for operation in ImageToolOperation.allCases {
            let query = AppLocalization.string(operation.title, language: language)
            let matches = results(query, settings: settings, locale: language.locale)
            #expect(matches.contains { $0.section == .imageTools && $0.anchor == .imageOperation(operation) })
        }
        settings.imageToolsEnabled = false
        #expect(!SettingsSection.imageTools.isVisible(settings: settings))
        #expect(results("TinyPNG", settings: settings, locale: language.locale).allSatisfy { $0.section != .imageTools })
        #expect(results(AppLocalization.string("图片工具", language: language), settings: settings, locale: language.locale)
            .contains { $0.section == .features && $0.anchor == .row("图片工具") })
    }

    @Test(arguments: ImageToolOperation.allCases) @MainActor
    func imageSearchSelectsTheRequestedOperation(operation: ImageToolOperation) {
        let input = SettingsInput()
        input.select(.imageTools, searchTarget: .imageOperation(operation))
        #expect(input.selection == .imageTools)
        #expect(input.selectedImageOperation == operation)
        input.select(.pdfTools)
        input.navigate(backward: true, settings: .default)
        #expect(input.selectedImageOperation == operation)
        input.select(.imageTools)
        #expect(input.selectedImageOperation == operation)
        #expect(input.searchTarget == nil)
        input.settingsQuery = "PNG"
        #expect(input.selectedImageOperation == operation)
    }

    @Test(arguments: PDFToolOperation.allCases)
    func pdfToolTitlesAndDescriptionsResolveToTheirOperation(operation: PDFToolOperation) {
        let matches = results(operation.title)
        #expect(matches.first?.section == .pdfTools)
        #expect(matches.first?.anchor == .pdfOperation(operation))
        #expect(results(operation.detail).contains { $0.section == .pdfTools && $0.anchor == .pdfOperation(operation) })
    }

    @Test(arguments: AppLanguage.allCases)
    func localizedPDFSearchRetainsTypedDestinations(language: AppLanguage) {
        for operation in PDFToolOperation.allCases {
            let title = AppLocalization.string(operation.title, language: language)
            let detail = AppLocalization.string(operation.detail, language: language)
            #expect(results(title, locale: language.locale).contains { $0.section == .pdfTools && $0.anchor == .pdfOperation(operation) })
            #expect(results(detail, locale: language.locale).contains { $0.section == .pdfTools && $0.anchor == .pdfOperation(operation) })
            #expect(SettingsSearchAnchor.pdfOperation(operation).localized(locale: language.locale) == .pdfOperation(operation))
        }
    }

    @Test(arguments: AppLanguage.allCases)
    func disablingPDFKeepsItsSwitchAndRemovesProcessingDestinations(language: AppLanguage) {
        var settings = Self.enabledSettings
        settings.pdfToolsEnabled = false
        let items = SettingsSearchIndex.items(settings: settings, displayCount: 2)
        #expect(items.contains { $0.section == .features && $0.title == "PDF 工具" })
        #expect(!items.contains { $0.section == .pdfTools })
        let switchTitle = AppLocalization.string("PDF 工具", language: language)
        #expect(results(switchTitle, settings: settings, locale: language.locale).contains {
            $0.section == .features && $0.anchor == .row("PDF 工具")
        })
        for operation in PDFToolOperation.allCases {
            let title = AppLocalization.string(operation.title, language: language)
            #expect(results(title, settings: settings, locale: language.locale).allSatisfy { $0.section != .pdfTools })
        }
        #expect(items.contains { $0.section == .features && $0.title == "应用音量混音器" })
    }

    @Test @MainActor
    func PDFSearchSelectsOperationAndOrdinaryNavigationRestoresMerge() throws {
        let input = SettingsInput()
        #expect(input.selectedPDFOperation == .merge)
        for operation in PDFToolOperation.allCases {
            input.settingsQuery = operation.title
            let result = try #require(results(operation.title).first { $0.section == .pdfTools })
            input.select(result.section, searchTarget: result.anchor)
            #expect(input.selection == .pdfTools)
            #expect(input.selectedPDFOperation == operation)
            #expect(!input.isSearching)
            #expect(input.settingsQuery.isEmpty)
            input.select(.pdfTools)
            #expect(input.selectedPDFOperation == .merge)
            #expect(input.searchTarget == nil)
        }
        input.select(.general, searchTarget: .row("界面语言"))
        #expect(input.selectedPDFOperation == .merge)
        input.select(.voice, searchTarget: .group("本地模型"))
        #expect(input.selectedPDFOperation == .merge)
    }

    @Test
    func nestedConfigurationSearchTargetsReachableEntries() {
        #expect(results("自动更新 CLI").contains { $0.section == .ai && $0.anchor == .group("CLI 与 Skills") })
        #expect(results("底部指示样式").contains { $0.section == .workflow && $0.anchor == .group("settings-search-monitor-layout") })
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
    func fieldEditorRepeatingClearedTextPreservesTheSelectedDestination() {
        let input = SettingsInput()
        input.settingsQuery = "键盘"
        input.select(.features, searchTarget: .row("键盘音效"))

        input.settingsQuery = ""
        input.settingsQuery = ""

        #expect(input.selection == .features)
        #expect(!input.isSearching)
        #expect(input.searchTarget == .row("键盘音效"))

        input.settingsQuery = "天气"
        #expect(input.searchTarget == nil)
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
        locale: Locale = Locale(identifier: "zh-Hans"),
        displayCount: Int = 2
    ) -> [SettingsSearchItem] {
        SettingsSearchIndex.results(for: query, settings: settings, locale: locale, displayCount: displayCount)
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
