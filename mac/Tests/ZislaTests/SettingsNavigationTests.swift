import AppKit
import Foundation
import SwiftUI
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

struct SettingsNavigationTests {
    @Test(arguments: [ColorScheme.light, .dark]) @MainActor
    func categoryIconsUseAppleSystemColors(colorScheme: ColorScheme) throws {
        let appearance = try #require(NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua))
        appearance.performAsCurrentDrawingAppearance {
            var environment = EnvironmentValues()
            environment.colorScheme = colorScheme
            let systemColors: [NSColor] = [.systemGray, .systemBlue, .systemIndigo, .systemRed,
                                          .systemGreen, .systemOrange, .systemCyan]
            let allowedColors = systemColors.map { Color(nsColor: $0).resolve(in: environment) }
            for category in SettingsSection.allCases {
                let color = category.iconColor.resolve(in: environment)
                #expect(allowedColors.contains(color),
                        "The \(category.rawValue) icon must use Apple's unmodified system palette in \(colorScheme)")
            }
        }
    }

    @Test
    func keyboardSoundRowsUseTheKeyboardCategoryColor() {
        for symbol in ["waveform", "speaker.wave.2", "arrow.uturn.backward", "waveform.path.ecg", "chart.bar.xaxis"] {
            #expect(SettingsSection.keyboardSound.iconColor(for: symbol) == SettingsSection.keyboardSound.iconColor,
                    "The \(symbol) keyboard setting must keep the keyboard category color")
        }
    }

    @Test
    func settingIconsKeepTheirCategoryColorsAcrossPages() {
        for page in SettingsSection.allCases {
            for category in SettingsSection.allCases {
                #expect(page.iconColor(for: category.symbol) == category.iconColor,
                        "The \(category.rawValue) icon must keep its identity on the \(page.rawValue) page")
            }
            #expect(page.iconColor(for: "") == page.iconColor)
            #expect(page.iconColor(for: "future.setting.symbol") == page.iconColor)
            #expect(page.iconColor(for: "camera.fill") == SettingsSection.screenshot.iconColor)
            #expect(page.iconColor(for: "doc.viewfinder") == SettingsSection.pdfTools.iconColor)
            for symbol in ["power.circle.fill", "battery.100percent", "calendar", "music.note.list", "folder",
                           "camera.fill", "doc.viewfinder", "rectangle.stack", "terminal.fill", "cpu",
                           "character.bubble", "capsule", "shippingbox.fill"] {
                #expect(page.iconColor(for: symbol) == SettingsSection.general.iconColor(for: symbol),
                        "The \(symbol) setting must keep its semantic color across pages")
            }
        }
    }

    @Test(arguments: [false, true], [false, true])
    func combinedMonitorNavigationFollowsTheSystemToggleWithLegacyBatterySettings(systemEnabled: Bool, batteryEnabled: Bool) throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "systemMonitorEnabled": systemEnabled,
            "batteryMonitorEnabled": batteryEnabled,
        ])
        var settings = try JSONDecoder().decode(FeatureSettings.self, from: data)
        settings.moduleOrder = [.battery, .mail, .system]

        let modules = IslandModule.enabledOrder(settings)
        #expect(modules.contains(.system) == systemEnabled)
        #expect(IslandModule.battery.isEnabled(in: settings) == systemEnabled)
        #expect(!modules.contains(.battery))
        #expect(modules.filter { $0 == .system }.count <= 1)
        if systemEnabled {
            #expect(modules.first == .system)
        }
        #expect(settings.systemMonitorEnabled == systemEnabled)
    }

    @Test
    func legacyBatteryNavigationTargetsTheCombinedMonitor() {
        #expect(IslandModule.battery.navigationTarget == .system)
        for module in IslandModule.allCases where module != .battery {
            #expect(module.navigationTarget == module)
        }
    }

    @Test
    func combinedMonitorFeatureRowHasNoSeparateBatteryToggleAndIsLocalized() throws {
        let source = try String(contentsOf: Self.settingsViewSourceURL, encoding: .utf8)
        #expect(!source.contains(#"featureToggle("电池监控""#))
        let row = try NSRegularExpression(pattern:
            #"featureToggle\("系统状态与清理", detail: "([^"]+)", symbol: "[^"]+", keyPath: \\.systemMonitorEnabled\)"#)
        let match = try #require(row.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)))
        let range = try #require(Range(match.range(at: 1), in: source))
        let detail = String(source[range])
        #expect(detail == "监控系统资源与电池，并安全清理缓存和日志")
        let packageRoot = Self.settingsViewSourceURL.deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        for language in AppLanguage.allCases {
            let tableURL = packageRoot.appendingPathComponent("Resources/Localization/\(language.rawValue).lproj/Localizable.strings")
            let table = try #require(NSDictionary(contentsOf: tableURL) as? [String: String])
            for key in ["系统状态与清理", detail] {
                let value = try #require(table[key], "\(language.rawValue) is missing \(key)")
                #expect(!value.isEmpty)
                #expect(AppLocalization.string(key, language: language) == value)
                if language != .simplifiedChinese { #expect(value != key) }
            }
        }
        #expect(AppLocalization.string(detail, language: .english)
            == "Monitor system resources and batteries, and safely clean caches and logs")
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
            "灵动岛布局",
            "每日简报",
            "通知与关怀",
            "工作流",
            "快捷操作",
            "邮件",
            "天气",
            "截图",
            "录屏",
            "PDF 工具",
            "图片工具",
            "音频工具",
            "AI",
            "语音",
            "键盘音效",
            "系统状态与清理",
            "保存位置",
            "依赖组件",
            "网络",
            "宠物",
            "权限",
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
    func infoKeepsModuleOrderVisibleWhenMediaAndSystemMonitorAreOff() {
        var settings = FeatureSettings(
            mediaEnabled: false,
            systemMonitorEnabled: false,
            dailyBriefing: DailyBriefingSettings(enabled: false),
            lockScreenInfoEnabled: false,
            mailEnabled: false,
            sideNoticesEnabled: false,
            userCareEnabled: false
        )
        #expect(SettingsSection.info.isVisible(settings: settings))

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
            dailyBriefing: DailyBriefingSettings(enabled: otherInfoFeaturesEnabled),
            lockScreenInfoEnabled: otherInfoFeaturesEnabled,
            mailEnabled: false,
            sideNoticesEnabled: otherInfoFeaturesEnabled,
            userCareEnabled: otherInfoFeaturesEnabled
        )
        #expect(!mailSection.isVisible(settings: settings))
        #expect(SettingsSection.info.isVisible(settings: settings))

        settings.mailEnabled = true
        #expect(mailSection.isVisible(settings: settings))
        #expect(SettingsSection.info.isVisible(settings: settings))

        settings.mailEnabled = false
        #expect(!mailSection.isVisible(settings: settings))
        #expect(SettingsSection.info.isVisible(settings: settings))
    }

    @Test
    func defaultSettingsShowAllInformationConfigurationPages() {
        let settings = FeatureSettings()
        let visibleSections = SettingsSection.allCases.filter { $0.isVisible(settings: settings) }

        #expect(visibleSections == SettingsSection.allCases)
        #expect(visibleSections.map(\.rawValue).contains("info"))
        #expect(visibleSections.map(\.rawValue).contains("mail"))
        for page in [SettingsSection.dailyBriefing, .notifications, .workflow] {
            #expect(visibleSections.contains(page))
        }
        #expect(settings.mediaEnabled)
        #expect(settings.systemMonitorEnabled)
        #expect(settings.mailEnabled)
        #expect(settings.lockScreenInfoEnabled)
        #expect(settings.sideNoticesEnabled)
        #expect(settings.mailAccountNames.isEmpty)
    }

    @Test(arguments: Array(0..<64))
    func informationConfigurationRemainsReachableWithItsFeaturesDisabled(combination: Int) {
        let settings = FeatureSettings(
            mediaEnabled: combination & 1 != 0,
            systemMonitorEnabled: combination & 2 != 0,
            dailyBriefing: DailyBriefingSettings(enabled: combination & 4 != 0),
            lockScreenInfoEnabled: combination & 8 != 0,
            sideNoticesEnabled: combination & 16 != 0,
            userCareEnabled: combination & 32 != 0
        )
        for page in [SettingsSection.info, .dailyBriefing, .notifications, .workflow] {
            #expect(page.isVisible(settings: settings), "The \(page.rawValue) configuration must stay reachable")
        }
        #expect(SettingsSection(rawValue: "info") == .info)
    }

    @Test(arguments: [0, 1, 2]) @MainActor
    func notificationDisplayChoicesRequireTwoEnumerableScreens(screenCount: Int) {
        let screens = (0..<screenCount).map { SettingsTestScreen(number: $0 + 11, name: "Screen \($0 + 1)") }
        let choices = SettingsView.activityNoticeDisplays(on: screens, locale: Locale(identifier: "en"))
        #expect(choices.map(\.id) == (screenCount == 2 ? [11, 12] : []))
        #expect(choices.map(\.name) == (screenCount == 2 ? ["Screen 1", "Screen 2"] : []))
    }

    @Test @MainActor
    func displayChangesRemoveUnenumerableChoicesAndRestoreTheirLocalizedNames() {
        let missing = SettingsTestScreen(number: nil, name: "Missing ID")
        let primary = SettingsTestScreen(number: 11, name: "")
        let external = SettingsTestScreen(number: 22, name: "External")
        let locale = Locale(identifier: "en")
        #expect(SettingsView.activityNoticeDisplays(on: [missing, primary], locale: locale).isEmpty)
        let connected = SettingsView.activityNoticeDisplays(on: [primary, missing, external], locale: locale)
        #expect(connected.map(\.id) == [11, 22])
        #expect(connected.map(\.name) == ["Display 1", "External"])
        #expect(SettingsView.activityNoticeDisplays(on: [primary], locale: locale).isEmpty)
        #expect(SettingsView.activityNoticeDisplays(on: [], locale: locale).isEmpty)
        let reconnected = SettingsView.activityNoticeDisplays(on: [external, primary], locale: locale)
        #expect(reconnected.map(\.id) == [22, 11])
        #expect(reconnected.map(\.name) == ["External", "Display 2"])
        let third = SettingsTestScreen(number: 33, name: "Third")
        #expect(SettingsView.activityNoticeDisplays(on: [external, primary, third], locale: locale).map(\.id)
            == [22, 11, 33])
    }

    @Test
    func informationPagesAndMailNavigationAreLocalizedInEveryLanguage() throws {
        let mailSection = try #require(SettingsSection(rawValue: "mail"))
        #expect(SettingsSection.info.subtitle == "调整灵动岛功能顺序、模式与收起态展示优先级。")
        #expect(mailSection.title == "邮件")
        #expect(mailSection.subtitle == "读取已配置的 Mail.app 账户并提醒新邮件")
        #expect(mailSection.symbol == "envelope.fill")
        let englishSubtitle = "Adjust Dynamic Island feature order, mode, and compact status priority."
        #expect(AppLocalization.string(SettingsSection.info.subtitle, language: .english) == englishSubtitle)
        let keys = [SettingsSection.info, .dailyBriefing, .notifications, .workflow, mailSection]
            .flatMap { [$0.title, $0.subtitle] }
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
    func informationGroupImmediatelyFollowsBasics() throws {
        let groups = SettingsSectionGroup.allCases
        let basicsIndex = try #require(groups.firstIndex(of: .basics))
        #expect(groups.dropFirst(basicsIndex + 1).first == .information)
    }

    @Test
    func featuresSectionRemainsVisibleWhenMailIsDisabled() {
        #expect(SettingsSection.features.isVisible(settings: FeatureSettings(mailEnabled: false)))
    }

    @Test
    func captureAndClipboardVisibilityFollowFeatureToggles() {
        var settings = FeatureSettings(clipboardAssistantEnabled: false, screenshotEnabled: false,
                                       screenRecordingEnabled: false)
        #expect(!SettingsSection.clipboardAssistant.isVisible(settings: settings))
        #expect(!SettingsSection.screenshot.isVisible(settings: settings))
        #expect(!SettingsSection.recording.isVisible(settings: settings))

        settings.clipboardAssistantEnabled = true
        settings.screenshotEnabled = true
        settings.screenRecordingEnabled = true
        #expect(SettingsSection.clipboardAssistant.isVisible(settings: settings))
        #expect(SettingsSection.screenshot.isVisible(settings: settings))
        #expect(SettingsSection.recording.isVisible(settings: settings))
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
    func sidebarGroupsSeparatePDFAndCaptureAndCollectTheOtherPages() {
        #expect(SettingsSectionGroup.allCases.map(\.title) == [
            "基础功能", "信息", "文件", "截图与录屏", "AI 与语音", "声音", "其他", "权限", "推荐与反馈更新",
        ])
        #expect(SettingsSection.allCases.filter { $0.group == .basics } == [.general, .features])
        #expect(SettingsSection.allCases.filter { $0.group == .information }
            == [.info, .dailyBriefing, .notifications, .workflow, .clipboardAssistant, .mail, .weather])
        #expect(SettingsSection.allCases.filter { $0.group == .sound } == [.keyboardSound])
        #expect(SettingsSection.allCases.filter { $0.group == .files } == [.pdfTools, .imageTools, .audioTools])
        #expect(SettingsSection.allCases.filter { $0.group == .capture } == [.screenshot, .recording])
        #expect(SettingsSection.allCases.filter { $0.group == .aiAndVoice } == [.ai, .voice])
        #expect(SettingsSection.allCases.filter { $0.group == .others } == [.scheduledCleanup, .saveLocations, .download, .networkProxy, .pet])
        #expect(SettingsSection.allCases.filter { $0.group == .recommendationsAndUpdates } == [.recommendations, .updates])
    }

    @Test(arguments: [0, 1, 2, 3], [false, true])
    func otherSettingsKeepTheirOrderAcrossFeatureToggles(dependencySource: Int, petEnabled: Bool) {
        var settings = FeatureSettings.default
        settings.downloaderEnabled = dependencySource == 1
        settings.pdfToolsEnabled = dependencySource == 2
        settings.imageToolsEnabled = dependencySource == 3
        settings.systemMonitorEnabled = petEnabled
        settings.networkProxyEnabled = petEnabled
        settings.petEnabled = petEnabled

        var expectedSections: [SettingsSection] = [.scheduledCleanup, .saveLocations]
        if dependencySource != 0 { expectedSections.append(.download) }
        expectedSections.append(.networkProxy)
        if petEnabled { expectedSections.append(.pet) }

        let visibleSections = SettingsSection.allCases.filter { $0.isVisible(settings: settings) }
            .filter { $0.group == .others }
        #expect(visibleSections == expectedSections,
                "The other settings must keep their order for dependency source \(dependencySource) and pet enabled \(petEnabled)")
    }

    @Test
    func soundGroupImmediatelyFollowsAIAndVoice() throws {
        let groups = SettingsSectionGroup.allCases
        let aiAndVoiceIndex = try #require(groups.firstIndex(of: .aiAndVoice))
        #expect(groups.dropFirst(aiAndVoiceIndex + 1).first == .sound,
                "The sound settings group must immediately follow AI and voice")
    }

    @Test(arguments: [false, true], [false, true])
    func recommendationGroupTitleFollowsTheRecommendationToggle(recommendationsEnabled: Bool, updatesEnabled: Bool) {
        var settings = FeatureSettings.default
        settings.recommendedToolsEnabled = recommendationsEnabled
        settings.updateChecksEnabled = updatesEnabled
        #expect(SettingsSectionGroup.recommendationsAndUpdates.title(settings: settings)
            == (recommendationsEnabled ? "推荐与反馈更新" : "反馈更新"))
        for group in SettingsSectionGroup.allCases where group != .recommendationsAndUpdates {
            #expect(group.title(settings: settings) == group.title)
        }
    }

    /// Bundle lookup silently falls back to Chinese keys, so catalog presence and rendered values need separate assertions.
    @Test(arguments: AppLanguage.allCases)
    func groupedSettingsAndPDFLabelsUseEveryRequestedLanguage(language: AppLanguage) throws {
        let dependencyGuidance = try #require(YTDLPResolverError.executableNotFound(searched: []).errorDescription)
        let keys = Set(SettingsSectionGroup.allCases.map(\.title) + [
            "反馈更新",
            "灵动岛功能顺序",
            SettingsSection.pdfTools.title,
            SettingsSection.pdfTools.subtitle,
            SettingsSection.download.title,
            SettingsSection.download.subtitle,
            dependencyGuidance,
            "仅影响 zisla 的窗口与面板，不会更改 macOS 外观。",
            "应用音量混音器",
            "在灵动岛分别调整应用的媒体音量。",
        ])
        let packageRoot = Self.settingsViewSourceURL.deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let tableURL = packageRoot.appendingPathComponent("Resources/Localization/\(language.rawValue).lproj/Localizable.strings")
        let table = try #require(NSDictionary(contentsOf: tableURL) as? [String: String])
        let source = try String(contentsOf: tableURL, encoding: .utf8)
        for key in keys {
            let value = try #require(table[key], "\(language.rawValue) is missing \(key)")
            #expect(!value.isEmpty)
            #expect(AppLocalization.string(key, language: language) == value)
            #expect(AppLocalization.string(key, locale: language.locale) == value)
            let expression = try NSRegularExpression(
                pattern: "^\\s*\"" + NSRegularExpression.escapedPattern(for: key) + "\"\\s*=",
                options: .anchorsMatchLines
            )
            #expect(expression.numberOfMatches(in: source, range: NSRange(source.startIndex..., in: source)) == 1)
            if language == .traditionalChinese && ["PDF 工具", "其他"].contains(key) {
                #expect(value == key)
            } else if language != .simplifiedChinese {
                #expect(value != key, "\(language.rawValue) did not translate \(key)")
            }
        }
        let dependencyTitle = try #require(table[SettingsSection.download.title])
        #expect(table[dependencyGuidance]?.contains(dependencyTitle) == true)
        if language == .english {
            #expect(table["灵动岛功能顺序"] == "Dynamic Island Feature Order")
            #expect(dependencyTitle == "Dependency Components")
            #expect(table["截图与录屏"] == "Screenshots & Recording")
            #expect(table["推荐与反馈更新"] == "Recommendations, Feedback & Updates")
            #expect(table["反馈更新"] == "Feedback & Updates")
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
    func infoKeepsModuleOrderVisibleWhenLockScreenAndSideNoticesAreOff() {
        var settings = FeatureSettings(
            mediaEnabled: false,
            systemMonitorEnabled: false,
            dailyBriefing: DailyBriefingSettings(enabled: false),
            lockScreenInfoEnabled: false,
            mailEnabled: false,
            sideNoticesEnabled: false,
            userCareEnabled: false
        )
        #expect(SettingsSection.info.isVisible(settings: settings))

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
        settings.pdfToolsEnabled = false
        settings.imageToolsEnabled = false
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

    @Test(arguments: Array(0..<8))
    func dependenciesRemainAvailableForEnabledFileToolsWithoutDownloadOrRecommendations(combination: Int) {
        var settings = FeatureSettings.default
        settings.downloaderEnabled = combination & 1 != 0
        settings.pdfToolsEnabled = combination & 2 != 0
        settings.imageToolsEnabled = combination & 4 != 0
        settings.recommendedToolsEnabled = false
        #expect(SettingsSection.download.isVisible(settings: settings) == (combination != 0))
        #expect(SettingsSection.pdfTools.isVisible(settings: settings) == settings.pdfToolsEnabled)
        #expect(SettingsSection.imageTools.isVisible(settings: settings) == settings.imageToolsEnabled)
        #expect(!SettingsSection.recommendations.isVisible(settings: settings))
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

@MainActor
private final class SettingsTestScreen: NSScreen {
    private let number: Int?
    private let name: String

    init(number: Int?, name: String) {
        self.number = number
        self.name = name
        super.init()
    }

    override var deviceDescription: [NSDeviceDescriptionKey: Any] {
        number.map { [NSDeviceDescriptionKey("NSScreenNumber"): NSNumber(value: $0)] } ?? [:]
    }

    override var localizedName: String { name }
}
