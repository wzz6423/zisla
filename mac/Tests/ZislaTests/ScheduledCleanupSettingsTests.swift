import Foundation
import Testing
import ZislaCore

@testable import Zisla

struct ScheduledCleanupSettingsTests {
    @Test(arguments: [false, true], [false, true])
    func systemStatusCleanupPageStaysInOtherSettingsWhenRelatedFeaturesAreDisabled(systemEnabled: Bool, clipboardEnabled: Bool) {
        let settings = FeatureSettings(systemMonitorEnabled: systemEnabled, clipboardHistoryEnabled: clipboardEnabled)
        #expect(SettingsSection.scheduledCleanup.group == .others)
        #expect(SettingsSection.scheduledCleanup.title == "系统状态与清理")
        #expect(SettingsSection.scheduledCleanup.isVisible(settings: settings))
        #expect(!SettingsSection.scheduledCleanup.prefersWideLayout)
        let items = SettingsSearchIndex.items(settings: settings)
        let movedTitles: Set<String> = ["自动清理系统垃圾", "清理范围", "剪贴板历史", "自动删除剪贴板历史"]
        #expect(items.filter { movedTitles.contains($0.title) }.allSatisfy { $0.section == .scheduledCleanup })
        #expect(items.contains { $0.title == "剪贴板历史" })
        #expect(items.contains { $0.title == "自动删除剪贴板历史" })
        #expect(items.contains { $0.title == "定时倾倒废纸篓" })
        #expect(items.contains { $0.title == "自动清理系统垃圾" } == systemEnabled)
        #expect(items.contains { $0.title == "清理范围" } == systemEnabled)
    }

    @Test(arguments: AppLanguage.allCases, [false, true])
    func clipboardAndTrashSearchReachTheirRowsOnTheCleanupPage(language: AppLanguage, clipboardEnabled: Bool) {
        let settings = FeatureSettings(systemMonitorEnabled: false, clipboardHistoryEnabled: clipboardEnabled)
        for key in ["剪贴板历史", "自动删除剪贴板历史", "定时倾倒废纸篓"] {
            let matches = SettingsSearchIndex.results(for: AppLocalization.string(key, locale: language.locale),
                settings: settings, locale: language.locale)
            #expect(matches.first?.section == .scheduledCleanup)
            #expect(matches.first?.anchor == .row(key))
        }
        let pageMatches = SettingsSearchIndex.results(
            for: AppLocalization.string(SettingsSection.scheduledCleanup.title, locale: language.locale),
            settings: settings, locale: language.locale
        )
        #expect(!pageMatches.isEmpty)
        #expect(pageMatches.contains { $0.section == .scheduledCleanup })
        #expect(pageMatches.contains { $0.section == .features && $0.title == "系统状态与清理" })
    }

    @Test @MainActor
    func searchNavigationRestoresTheCleanupRowAfterGoingBackAndForward() {
        let input = SettingsInput()
        let settings = FeatureSettings(systemMonitorEnabled: false, clipboardHistoryEnabled: false)
        input.select(.scheduledCleanup, searchTarget: .row("定时倾倒废纸篓"))
        input.select(.features)
        input.navigate(backward: true, settings: settings)
        #expect(input.selection == .scheduledCleanup)
        #expect(input.searchTarget == .row("定时倾倒废纸篓"))
        input.navigate(backward: true, settings: settings)
        #expect(input.selection == .general)
        input.navigate(backward: false, settings: settings)
        #expect(input.selection == .scheduledCleanup)
        #expect(input.searchTarget == .row("定时倾倒废纸篓"))
        input.navigate(backward: false, settings: settings)
        #expect(input.selection == .features)
        #expect(input.searchTarget == nil)
    }

    @Test(arguments: [VoiceRecordingCleanupPolicy.sevenDays, .fifteenDays, .thirtyDays]) @MainActor
    func enablingTrashCleanupRequiresConfirmationAndCancelKeepsExistingSettings(policy: VoiceRecordingCleanupPolicy) {
        let input = SettingsInput()
        var settings = FeatureSettings(systemCleanupPolicy: .fifteenDays, clipboardHistoryCleanupPolicy: .sevenDays)
        let original = settings
        input.requestTrashCleanupPolicy(policy, settings: &settings)
        #expect(input.pendingTrashCleanupPolicy == policy)
        #expect(settings == original)
        input.pendingTrashCleanupPolicy = nil
        input.confirmTrashCleanupPolicy(settings: &settings)
        #expect(settings == original)
        input.requestTrashCleanupPolicy(policy, settings: &settings)
        input.confirmTrashCleanupPolicy(settings: &settings)
        #expect(input.pendingTrashCleanupPolicy == nil)
        var expected = original
        expected.trashCleanupPolicy = policy
        #expect(settings == expected)
    }

    @Test(arguments: VoiceRecordingCleanupPolicy.allCases) @MainActor
    func changingAnEnabledTrashPolicyDoesNotRequestAnotherConfirmation(policy: VoiceRecordingCleanupPolicy) {
        let input = SettingsInput()
        var settings = FeatureSettings(trashCleanupPolicy: .sevenDays)
        input.requestTrashCleanupPolicy(policy, settings: &settings)
        #expect(settings.trashCleanupPolicy == policy)
        #expect(input.pendingTrashCleanupPolicy == nil)
    }

    @Test @MainActor
    func choosingNeverClearsPendingConfirmationWithoutEnablingCleanup() {
        let input = SettingsInput()
        var settings = FeatureSettings.default
        input.requestTrashCleanupPolicy(.thirtyDays, settings: &settings)
        input.requestTrashCleanupPolicy(.never, settings: &settings)
        #expect(input.pendingTrashCleanupPolicy == nil)
        #expect(settings.trashCleanupPolicy == .never)
        input.confirmTrashCleanupPolicy(settings: &settings)
        #expect(settings.trashCleanupPolicy == .never)
    }

    @Test(arguments: AppLanguage.allCases)
    func systemStatusCleanupPageAndIrreversibleWarningRenderInEveryLanguage(language: AppLanguage) throws {
        let source = try String(contentsOf: Self.packageRoot.appendingPathComponent("Sources/Zisla/SettingsView.swift"), encoding: .utf8)
        let start = try #require(source.range(of: "private var scheduledCleanupContent:"))
        let end = try #require(source.range(of: "private var workflowContent:", range: start.upperBound..<source.endIndex))
        let page = String(source[start.lowerBound..<end.lowerBound])
        let literals = try NSRegularExpression(pattern: #"//[^\n]*|/\*[\s\S]*?\*/|"(?:[^"\\]|\\.)*""#)
        var keys = Set([SettingsSection.scheduledCleanup.title, SettingsSection.scheduledCleanup.subtitle])
        for match in literals.matches(in: page, range: NSRange(page.startIndex..., in: page)) {
            let literal = String(page[try #require(Range(match.range, in: page))])
            if literal.first == "\"", literal.range(of: #"[\u4E00-\u9FFF]"#, options: .regularExpression) != nil {
                keys.insert(String(literal.dropFirst().dropLast()))
            }
        }
        let newKeys: Set<String> = ["系统状态与清理", "管理电源模式与系统垃圾、剪贴板历史和废纸篓的定时清理。", "定时倾倒废纸篓",
            "按所选间隔永久删除废纸篓中的所有项目，无法恢复", "启用定时倾倒废纸篓？"]
        #expect(newKeys.isSubset(of: keys))
        keys.formUnion(VoiceRecordingCleanupPolicy.allCases.map(\.menuTitle))
        keys.formUnion(BatteryPowerMode.allCases.map(\.menuTitle))
        let tableURL = Self.packageRoot.appendingPathComponent("Resources/Localization/\(language.rawValue).lproj/Localizable.strings")
        let table = try #require(NSDictionary(contentsOf: tableURL) as? [String: String])
        let resourceSource = try String(contentsOf: tableURL, encoding: .utf8)
        #expect(AppLanguage.allCases.count == 17)
        let placeholderPattern = try NSRegularExpression(pattern: #"%(?:\d+\$)?(?:ld|lu|lld|llu|@|\d*\.?\d*[fd])"#)
        for key in keys {
            let value = try #require(table[key], "\(language.rawValue) is missing \(key)")
            #expect(!value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(placeholderPattern.numberOfMatches(in: value, range: NSRange(value.startIndex..., in: value)) == 0,
                    "Settings text must not introduce format placeholders: \(key)")
            #expect(AppLocalization.string(key, locale: language.locale) == value)
            if newKeys.contains(key) {
                let expression = try NSRegularExpression(pattern: "^\\s*\"" + NSRegularExpression.escapedPattern(for: key) + "\"\\s*=", options: .anchorsMatchLines)
                #expect(expression.numberOfMatches(in: resourceSource, range: NSRange(resourceSource.startIndex..., in: resourceSource)) == 1)
                if language != .simplifiedChinese { #expect(value != key) }
                if language != .simplifiedChinese && language != .traditionalChinese && language != .english {
                    #expect(value != AppLocalization.string(key, language: .english))
                }
            }
        }
        #expect(AppLocalization.string("定时倾倒废纸篓", language: .english) == "Automatically empty the Trash")
        #expect(AppLocalization.string("定时倾倒废纸篓", language: .arabic) == "إفراغ المهملات تلقائيًا")
        #expect(AppLanguage.allCases.filter(\.isRightToLeft) == [.arabic])
    }

    private static var packageRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }
}
