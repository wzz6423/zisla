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
    func recommendationControlsAreLocalizedInEveryLanguage() throws {
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
                let value = try #require(table[key], "\(language.rawValue) is missing \(key)")
                #expect(!value.isEmpty)
                #expect(AppLocalization.string(key, language: language) == value)
                if language != .simplifiedChinese { #expect(value != key) }
            }
        }
        #expect(AppLocalization.string("显示推荐工具", language: .english) == "Show Recommended Tools")
    }

    @Test
    func showsOnlyCurrentSettingsSections() {
        #expect(SettingsSection.allCases.map(\.title) == [
            "通用",
            "功能",
            "信息",
            "快捷操作",
            "截图",
            "PDF 工具",
            "AI",
            "语音",
            "邮件",
            "键盘音效",
            "下载",
            "天气",
            "网络",
            "宠物",
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
    func feedbackAndUpdatePageLabelsAreLocalizedInEveryLanguage() {
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
    func featuresSectionRemainsVisibleWhenMailIsDisabled() {
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

    @Test(arguments: [false, true], [false, true])
    func pdfSettingsVisibilityIsIndependentOfVolumeMixer(pdfEnabled: Bool, mixerEnabled: Bool) {
        var settings = FeatureSettings.default
        settings.pdfToolsEnabled = pdfEnabled
        settings.volumeMixerEnabled = mixerEnabled

        #expect(SettingsSection.pdfTools.isVisible(settings: settings) == pdfEnabled)
        #expect(SettingsSection.features.isVisible(settings: settings))
        #expect(settings.pdfToolsEnabled == pdfEnabled)
        #expect(settings.volumeMixerEnabled == mixerEnabled)
    }

    @Test
    func pdfMigrationPreservesAllFourteenOperationsInSettings() {
        #expect(PDFToolOperation.allCases.map(\.rawValue) == [
            "merge", "split", "rotate", "imagesToPDF", "officeToPDF", "render", "extractText",
            "textWatermark", "imageWatermark", "pageNumbers", "crop", "protect", "unlock", "metadata",
        ])
        #expect(!IslandModule.allCases.map(\.rawValue).contains("pdf"))
    }

    @Test
    func sidebarGroupsKeepExistingPagesAndPutPDFWithFileTools() {
        #expect(SettingsSectionGroup.allCases.map(\.title) == ["基础功能", "声音", "文件", "AI 与语音", "网络与其他"])
        #expect(SettingsSection.allCases.filter { $0.group == .basics } == [.general, .features, .info])
        #expect(SettingsSection.allCases.filter { $0.group == .sound } == [.keyboardSound])
        #expect(SettingsSection.allCases.filter { $0.group == .files } == [.clipboardAssistant, .screenshot, .pdfTools, .download])
        #expect(SettingsSection.allCases.filter { $0.group == .aiAndVoice } == [.ai, .voice])
        #expect(SettingsSection.allCases.filter { $0.group == .networkAndOthers } == [.mail, .weather, .networkProxy, .pet, .recommendations, .updates])
    }

    @Test(arguments: AppLanguage.allCases)
    func groupedSettingsAndPDFLabelsUseEveryRequestedLanguage(language: AppLanguage) throws {
        let keys = Set(SettingsSectionGroup.allCases.map(\.title) + [
            SettingsSection.pdfTools.title,
            SettingsSection.pdfTools.subtitle,
            "仅影响 zisla 的窗口与面板，不会更改 macOS 外观。",
            "应用音量混音器",
            "在灵动岛分别调整应用的媒体音量。",
        ])
        let packageRoot = Self.settingsViewSourceURL.deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let tableURL = packageRoot.appendingPathComponent("Resources/Localization/\(language.rawValue).lproj/Localizable.strings")
        let table = try #require(NSDictionary(contentsOf: tableURL) as? [String: String])
        for key in keys {
            let value = try #require(table[key], "\(language.rawValue) is missing \(key)")
            #expect(!value.isEmpty)
            #expect(AppLocalization.string(key, language: language) == value)
            if language == .traditionalChinese && key == "PDF 工具" {
                #expect(value == "PDF 工具")
            } else if language != .simplifiedChinese {
                #expect(value != key, "\(language.rawValue) did not translate \(key)")
            }
        }
    }

    @Test
    func clipboardAssistantConversionLabelsAreLocalizedInEveryLanguage() {
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

}
