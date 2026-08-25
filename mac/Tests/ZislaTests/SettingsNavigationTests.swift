import Foundation
import Testing
import ZislaCore

@testable import Zisla

struct SettingsNavigationTests {
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
            "宠物",
            "下载",
            "天气",
            "网络",
            "推荐",
            "更新",
        ])
        #expect(SettingsSection.general.subtitle == "调整语言、外观、启动与展开方式。")
        #expect(SettingsSection.ai.subtitle == "管理 AI CLI 与 Skills。")
        #expect(SettingsSection.voice.subtitle == "配置语音输入、整理模型与本机记录。")
        #expect(SettingsSection.networkProxy.subtitle == "配置本地代理，用于更新、安装、下载与 GitHub 访问。")
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
        #expect(SettingsSection.networkProxy.isVisible(settings: settings))
        #expect(SettingsSection.recommendations.isVisible(settings: settings))
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
}
