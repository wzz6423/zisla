import Foundation
import Testing
import ZislaCore

@testable import Zisla

struct ScreenRecordingOutputDirectorySettingsTests {
    @Test(arguments: AppLanguage.allCases, [false, true])
    func saveDirectorySearchReachesDownloadsWithoutARecordingPreference(language: AppLanguage, recordingEnabled: Bool) throws {
        var settings = FeatureSettings.default
        settings.screenRecordingEnabled = recordingEnabled
        let items = SettingsSearchIndex.items(settings: settings)
        #expect(!items.contains { $0.section == .recording && $0.title == "保存位置" })
        #expect(items.contains { $0.section == .recording && $0.title == "恢复默认快捷键" } == recordingEnabled)

        let title = AppLocalization.string("默认下载目录", language: language)
        let result = try #require(SettingsSearchIndex.results(for: title, settings: settings, locale: language.locale)
            .first { $0.section == .download && $0.title == "默认下载目录" })
        #expect(result.anchor.localized(locale: language.locale) == .row(title))
        let legacyTitle = AppLocalization.string("保存位置", language: language)
        #expect(SettingsSearchIndex.results(for: legacyTitle, settings: settings, locale: language.locale)
            .allSatisfy { $0.section != .recording })
    }

    @Test
    func recordingSettingsKeepTheStudioAndShortcutsWithoutADirectoryPicker() throws {
        let source = try String(contentsOf: Self.packageRoot.appendingPathComponent("Sources/Zisla/SettingsView.swift"),
                                encoding: .utf8)
        let start = try #require(source.range(of: "if input.selection == .features || input.selection == .recording {"))
        let end = try #require(source.range(of: "if input.selection == .features || input.selection == .screenshot {",
                                           range: start.upperBound..<source.endIndex))
        let recording = source[start.lowerBound..<end.lowerBound]
        #expect(recording.contains("title: \"录屏工作室\""))
        #expect(recording.contains("ForEach(RecordingShortcutAction.allCases)"))
        #expect(!recording.contains("保存位置"))
        #expect(!recording.contains("ScreenRecordingOutputDirectorySettingsView"))
    }

    @Test(arguments: AppLanguage.allCases)
    func sharedDownloadControlsAreLocalizedInEveryLanguage(language: AppLanguage) throws {
        let tableURL = Self.packageRoot.appendingPathComponent(
            "Resources/Localization/\(language.rawValue).lproj/Localizable.strings")
        let table = try #require(NSDictionary(contentsOf: tableURL) as? [String: String])
        for key in ["默认下载目录", "选择默认下载目录"] {
            let value = try #require(table[key], "\(language.rawValue) is missing \(key)")
            #expect(!value.isEmpty)
            #expect(AppLocalization.string(key, language: language) == value)
            if language != .simplifiedChinese { #expect(value != key) }
        }
    }

    private static var packageRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }
}
