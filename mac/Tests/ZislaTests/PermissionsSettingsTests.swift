import Foundation
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

struct PermissionsSettingsTests {
    @Test
    func permissionsHaveAnAlwaysVisibleGroupBeforeRecommendations() throws {
        let section = try #require(SettingsSection(rawValue: "permissions"))
        let groups = SettingsSectionGroup.allCases
        let index = try #require(groups.firstIndex(of: section.group))
        #expect(groups[index + 1] == .recommendationsAndUpdates)
        #expect(SettingsSection.allCases.filter { $0.group == section.group } == [section])

        var settings = FeatureSettings.default
        settings.recommendedToolsEnabled = false
        settings.updateChecksEnabled = false
        settings.keyboardEnabled = false
        settings.voiceInputEnabled = false
        settings.dailyBriefing.enabled = false
        #expect(section.isVisible(settings: settings))
    }

    @Test(arguments: AppLanguage.allCases)
    func everyPermissionIsSearchableWithoutEnablingItsFeature(language: AppLanguage) throws {
        let section = try #require(SettingsSection(rawValue: "permissions"))
        var settings = FeatureSettings.default
        settings.keyboardEnabled = false
        settings.voiceInputEnabled = false
        settings.clipboardAssistantEnabled = false
        settings.screenshotEnabled = false
        settings.screenRecordingEnabled = false
        settings.mailEnabled = false
        settings.weatherEnabled = false
        settings.dailyBriefing.enabled = false

        for permission in OnboardingPermissionID.allCases {
            let results = SettingsSearchIndex.results(
                for: AppLocalization.string(permission.titleKey, language: language),
                settings: settings, locale: language.locale
            )
            #expect(results.contains {
                $0.section == section && $0.anchor == .row(permission.titleKey)
            }, "Missing permission destination: \(language.rawValue)/\(permission)")
        }
        #expect(SettingsSearchIndex.items(settings: settings).filter { $0.section == section }.count == 15)
    }

    @Test
    func featureSettingsDoNotExposeSeparatePermissionActions() throws {
        let settings = try source("SettingsView.swift")
        for action in ["openVoiceInputInputMonitoringSettings()", "openAssistantAccessibilitySettings()",
                       "openInputMonitoringSettings()", "AccessibilityPermission.promptIfNeeded()"] {
            #expect(!settings.contains(action), "Permission actions belong on the permissions page: \(action)")
        }
        let briefing = try source("DailyBriefingSettingsView.swift")
        #expect(!briefing.contains("Privacy_AllFiles"))
        #expect(!briefing.contains(#"AppLocalizedText("完全磁盘访问")"#))
        #expect(briefing.contains("$settingsStore.settings.dailyBriefing.readsSystemScreenTime"))
    }

    @Test
    func functionalPanelsDoNotExposeSeparatePermissionActions() throws {
        let files = ["AgendaModuleView.swift", "CalendarItemEditor.swift", "MailModuleView.swift", "DownloadModuleView.swift",
                     "WiFiNetworkPanelView.swift", "ScreenRecordingCaptureBar.swift"]
        for file in files {
            let content = try source(file)
            for action in ["Privacy_", "handleAuthorizationAction", "openAutomationSettings",
                           "openFullDiskAccessSettings", "requestLocationAuthorization()",
                           "controller.openSettings(.location)", "model.requestScreenAccess"] {
                #expect(!content.contains(action), "\(file) still exposes a separate permission action: \(action)")
            }
        }
        let keyboard = try String(contentsOf: Self.packageRoot.appendingPathComponent("Sources/KeyboardKit/MenuBarView.swift"), encoding: .utf8)
        #expect(!keyboard.contains("model.requestInputMonitoring()"))
        #expect(!keyboard.contains("model.openInputMonitoringSettings()"))
    }

    @Test(arguments: AppLanguage.allCases)
    func navigationHintsAndPermissionRowsUseEveryRequestedLanguage(language: AppLanguage) throws {
        let permissionSection = try #require(SettingsSection(rawValue: "permissions"))
        var keys = Set([permissionSection.title, permissionSection.subtitle, permissionSection.group.title])
        keys.formUnion(OnboardingPermissionID.allCases.flatMap { [$0.titleKey, $0.bodyKey] })
        keys.formUnion([OnboardingPermissionStatus.notDetermined, .denied, .restricted, .granted,
                        .requesting, .manual, .unavailable].map(\.localizationKey))
        keys.formUnion(["onboarding.open_settings", "onboarding.grant", "onboarding.retry", "输入统计"])
        let pattern = #"AppLocalizedText\("([^"]+)""#
        let expression = try NSRegularExpression(pattern: pattern)
        for file in ["PermissionsSettingsView.swift", "PermissionListView.swift", "AgendaModuleView.swift",
                     "MailModuleView.swift", "DownloadModuleView.swift", "WiFiNetworkPanelView.swift"] {
            let contents = try source(file)
            for match in expression.matches(in: contents, range: NSRange(contents.startIndex..., in: contents)) {
                keys.insert(String(contents[try #require(Range(match.range(at: 1), in: contents))]))
            }
        }
        let url = Self.packageRoot.appendingPathComponent("Resources/Localization/\(language.rawValue).lproj/Localizable.strings")
        let table = try #require(NSDictionary(contentsOf: url) as? [String: String])
        let contents = try String(contentsOf: url, encoding: .utf8)
        for key in keys {
            let value = try #require(table[key], "Missing \(language.rawValue) translation for \(key)")
            #expect(!value.isEmpty && !value.contains("TODO"))
            #expect(!value.contains("%"), "Permission copy must not introduce format placeholders")
            #expect(AppLocalization.string(key, language: language) == value)
            #expect(AppLocalization.string(key, locale: language.locale) == value)
            let occurrences = try NSRegularExpression(
                pattern: "^\\s*\"" + NSRegularExpression.escapedPattern(for: key) + "\"\\s*=",
                options: .anchorsMatchLines
            )
            #expect(occurrences.numberOfMatches(in: contents, range: NSRange(contents.startIndex..., in: contents)) == 1)
        }
        if language == .english {
            #expect(table[permissionSection.title] == "Permissions")
            #expect(table[OnboardingPermissionID.fullDiskAccess.bodyKey]?.contains("Screen Time") == true)
        }
        if language == .arabic { #expect(table[permissionSection.title] == "الأذونات") }
    }

    private func source(_ name: String) throws -> String {
        try String(contentsOf: Self.packageRoot.appendingPathComponent("Sources/Zisla/" + name), encoding: .utf8)
    }

    private static var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }
}
