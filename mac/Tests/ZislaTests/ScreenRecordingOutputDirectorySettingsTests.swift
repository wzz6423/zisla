import AppKit
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

struct ScreenRecordingOutputDirectorySettingsTests {
    @Test(arguments: AppLanguage.allCases, [false, true])
    func saveDirectorySearchReachesTheCentralPageRegardlessOfRecordingVisibility(language: AppLanguage, recordingEnabled: Bool) throws {
        var settings = FeatureSettings.default
        settings.screenRecordingEnabled = recordingEnabled
        let items = SettingsSearchIndex.items(settings: settings)
        #expect(!items.contains { $0.section == .recording && $0.title == "保存位置" })
        #expect(items.contains { $0.section == .recording && $0.title == "恢复默认快捷键" } == recordingEnabled)

        settings.downloaderEnabled = false
        let title = AppLocalization.string("保存位置", language: language)
        let results = SettingsSearchIndex.results(for: title, settings: settings, locale: language.locale)
            .filter { $0.section == .saveLocations }
        #expect(Set(results.map(\.title)) == Set(["下载", "PDF 工具", "图片工具", "截图", "录屏", "快捷操作", "每日简报"]))
        for result in results {
            #expect(result.anchor.localized(locale: language.locale)
                == .row(AppLocalization.string(result.title, language: language)))
        }
    }

    @Test @MainActor
    func saveLocationPageIsAlwaysVisibleAndKeepsNavigationHistory() {
        var settings = FeatureSettings.default
        settings.downloaderEnabled = false
        settings.screenshotEnabled = false
        settings.screenRecordingEnabled = false
        settings.clipboardAssistantEnabled = false
        settings.dailyBriefing.enabled = false
        settings.pdfToolsEnabled = false
        settings.imageToolsEnabled = false
        #expect(SettingsSection.saveLocations.group == .others)
        #expect(SettingsSection.saveLocations.isVisible(settings: settings))
        let input = SettingsInput()
        input.select(.saveLocations)
        input.select(.features)
        input.navigate(backward: true, settings: settings)
        #expect(input.selection == .saveLocations)
    }

    @Test(arguments: AppLanguage.allCases)
    func legacyDownloadDirectorySearchTargetsOnlyDownloads(language: AppLanguage) throws {
        var settings = FeatureSettings.default
        settings.downloaderEnabled = false
        let query = AppLocalization.string("默认下载目录", language: language)
        let results = SettingsSearchIndex.results(for: query, settings: settings, locale: language.locale)
        #expect(results.map(\.title) == ["下载"])
        #expect(results.first?.section == .saveLocations)
    }

    @Test(arguments: [SaveLocation.screenshot, .pdfTools, .imageTools]) @MainActor
    func folderSelectionUsesTheCurrentLocationAndCancellationPreservesPreferences(_ location: SaveLocation) throws {
        let fixture = try DirectoryFixture()
        defer { fixture.close() }
        let locations = SaveLocationStore(defaults: fixture.defaults)
        try locations.setDirectory(fixture.directory, for: location)
        let preferences = (fixture.defaults.persistentDomain(forName: fixture.suite) ?? [:])
        let directories = locations.directories
        let panel = DirectoryPanel()
        defer { panel.close() }

        try SettingsView.chooseSaveDirectory(location, locations: locations, panel: panel)

        #expect(panel.directoryURL?.path == fixture.directory.path)
        #expect(!panel.canChooseFiles && panel.canChooseDirectories)
        #expect(panel.canCreateDirectories && !panel.allowsMultipleSelection)
        #expect(locations.directories == directories)
        #expect(NSDictionary(dictionary: (fixture.defaults.persistentDomain(forName: fixture.suite) ?? [:]))
            == NSDictionary(dictionary: preferences))
    }

    @Test(arguments: [SaveLocation.quickActions, .pdfTools, .imageTools]) @MainActor
    func selectedFolderUpdatesOnlyItsDefaultAndMissingOrInvalidSelectionsPreserveIt(_ selected: SaveLocation) throws {
        let fixture = try DirectoryFixture()
        defer { fixture.close() }
        let locations = SaveLocationStore(defaults: fixture.defaults)
        let panel = DirectoryPanel()
        defer { panel.close() }
        panel.response = .OK
        panel.selectedURL = fixture.directory

        try SettingsView.chooseSaveDirectory(selected, locations: locations, panel: panel)

        #expect(locations[selected].path == fixture.directory.path)
        for location in SaveLocation.allCases where location != selected {
            #expect(locations[location] == AppPaths.downloads)
        }
        let preferences = (fixture.defaults.persistentDomain(forName: fixture.suite) ?? [:])
        panel.selectedURL = nil
        try SettingsView.chooseSaveDirectory(selected, locations: locations, panel: panel)
        #expect(locations[selected].path == fixture.directory.path)
        #expect(NSDictionary(dictionary: (fixture.defaults.persistentDomain(forName: fixture.suite) ?? [:]))
            == NSDictionary(dictionary: preferences))
        let file = fixture.directory.appendingPathComponent("existing.txt")
        try Data("existing".utf8).write(to: file)
        panel.selectedURL = file
        #expect(throws: (any Error).self) {
            try SettingsView.chooseSaveDirectory(selected, locations: locations, panel: panel)
        }
        #expect(locations[selected].path == fixture.directory.path)
        #expect(NSDictionary(dictionary: (fixture.defaults.persistentDomain(forName: fixture.suite) ?? [:]))
            == NSDictionary(dictionary: preferences))
        #expect(try Data(contentsOf: file) == Data("existing".utf8))
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
    func saveLocationControlsAreLocalizedInEveryLanguage(language: AppLanguage) throws {
        let tableURL = Self.packageRoot.appendingPathComponent(
            "Resources/Localization/\(language.rawValue).lproj/Localizable.strings")
        let table = try #require(NSDictionary(contentsOf: tableURL) as? [String: String])
        let source = try String(contentsOf: Self.packageRoot.appendingPathComponent("Sources/Zisla/SettingsView.swift"),
                                encoding: .utf8)
        let start = try #require(source.range(of: "private var saveLocationsContent: some View {"))
        let end = try #require(source.range(of: "private var downloadContent: some View {"))
        let content = String(source[start.lowerBound..<end.lowerBound])
        let expression = try NSRegularExpression(pattern: #"(?:settingsGroup|AppLocalization\.(?:text|format))\("([^"]+)""#)
        let directKeys = expression.matches(in: content, range: NSRange(content.startIndex..., in: content))
            .map { String(content[Range($0.range(at: 1), in: content)!]) }
        #expect(directKeys.count == 3, "The visible save-location controls must be scanned for localization")
        let keys = directKeys + SaveLocation.allCases.map(\.title) + [
            SettingsSection.saveLocations.title, SettingsSection.saveLocations.subtitle,
            SettingsSection.download.subtitle,
        ]
        for key in keys {
            let value = try #require(table[key], "\(language.rawValue) is missing \(key)")
            #expect(!value.isEmpty)
            #expect(value.components(separatedBy: "%@").count == key.components(separatedBy: "%@").count)
            #expect(AppLocalization.string(key, language: language) == value)
            if language == .traditionalChinese && ["快捷操作", "PDF 工具"].contains(key) {
                #expect(value == key)
            } else if language != .simplifiedChinese {
                #expect(value != key)
            }
        }
    }

    @Test
    func saveLocationLabelsUseTheRequestedLocale() {
        #expect(AppLanguage.allCases.count == 17)
        #expect(AppLocalization.string(SettingsSection.saveLocations.title, language: .english) == "Save Location")
        #expect(AppLocalization.string("默认保存位置", language: .arabic) == "مواقع الحفظ الافتراضية")
        #expect(AppLocalization.format("更改 %@ 的保存位置", locale: AppLanguage.english.locale, ["Screenshots"])
            == "Change save location for Screenshots")
    }

    private static var packageRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    @MainActor
    private final class DirectoryPanel: NSOpenPanel {
        var response: NSApplication.ModalResponse = .cancel
        var selectedURL: URL?

        override var url: URL? { selectedURL }
        override func runModal() -> NSApplication.ModalResponse { response }
    }

    @MainActor
    private final class DirectoryFixture {
        let suite = "zisla-save-location-panel-\(UUID())"
        let defaults: UserDefaults
        let directory: URL

        init() throws {
            _ = NSApplication.shared
            defaults = try #require(UserDefaults(suiteName: suite))
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        }

        func close() {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
    }
}
