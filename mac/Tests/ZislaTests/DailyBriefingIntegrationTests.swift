import AppKit
import Foundation
import Testing
import ZislaCore
import ZislaKit
@testable import Zisla

@MainActor
struct DailyBriefingIntegrationTests {
    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-briefing-integration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test
    func scheduledExportRetriesFailureAndDeduplicatesAfterRestart() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("history.json")
        let store = DailyBriefingStore(fileURL: file)
        let calendar = DailyBriefingDay.calendar
        let morning = calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 9))!
        let settings = DailyBriefingSettings(enabled: true, readsSystemScreenTime: false)
        let due = settings.exportDate(on: morning, calendar: calendar)
        var attempts = 0
        let controller = DailyBriefingController(store: store,
            observation: { .init(date: $0, applicationID: "editor", applicationName: "Editor", category: .work, isActive: true, isListening: false) },
            typing: { _ in throw CocoaError(.fileReadNoPermission) },
            readScreenTime: { _ in Issue.record("Disabled system reading must not access system data"); return .init() },
            export: { report, template, language, folder in
                attempts += 1
                #expect(report.typing == nil)
                #expect(template == .minimal)
                #expect(language == .english)
                #expect(folder == directory)
                if attempts == 1 { throw CocoaError(.fileWriteOutOfSpace) }
                return folder.appendingPathComponent("result.png")
            })
        controller.configure(settings: settings, directory: directory, language: .english, startsTimer: false)
        await controller.tick(at: morning)
        #expect(attempts == 0)
        await controller.tick(at: due)
        #expect(attempts == 1)
        #expect(controller.errorMessage != nil)
        #expect(!controller.isExporting)
        await controller.tick(at: due.addingTimeInterval(30))
        #expect(attempts == 2)
        #expect(controller.errorMessage == nil)
        #expect(controller.lastExportURL?.lastPathComponent == "result.png")
        await controller.tick(at: due.addingTimeInterval(60))
        #expect(attempts == 2)
        let pending = try await DailyBriefingStore(fileURL: file).pendingExports(at: due, settings: settings, calendar: calendar)
        #expect(pending.isEmpty)
    }

    @Test
    func manualExportKeepsTheDailyScheduleAndDisabledFeatureDoesNoWork() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("history.json")
        let store = DailyBriefingStore(fileURL: file)
        let calendar = DailyBriefingDay.calendar
        let morning = calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 9))!
        var attempts = 0
        let controller = DailyBriefingController(store: store,
            observation: { .init(date: $0, applicationID: "editor", applicationName: "Editor", category: .work, isActive: true, isListening: nil) },
            typing: { _ in nil }, readScreenTime: { _ in .init() },
            export: { _, _, _, folder in attempts += 1; return folder.appendingPathComponent("manual.png") })
        await controller.tick(at: morning)
        await controller.exportToday(at: morning)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(attempts == 0)
        let settings = DailyBriefingSettings(enabled: true, readsSystemScreenTime: false)
        controller.configure(settings: settings, directory: directory, language: .english, startsTimer: false)
        await controller.tick(at: morning)
        await controller.exportToday(at: morning.addingTimeInterval(30))
        #expect(attempts == 1)
        let pending = try await store.pendingExports(at: morning.addingTimeInterval(14 * 3600), settings: settings, calendar: calendar)
        #expect(pending.count == 1)
        controller.configure(settings: .init(), directory: directory, language: .english, startsTimer: false)
        await controller.exportToday(at: morning)
        #expect(attempts == 1)
    }

    @Test
    func changingTimeTemplateLanguageAndFolderUsesTheNormalPNGExportPath() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("exports")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let calendar = DailyBriefingDay.calendar
        let morning = calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 9))!
        let controller = DailyBriefingController(store: DailyBriefingStore(fileURL: directory.appendingPathComponent("history.json")),
            observation: { .init(date: $0, applicationID: "editor", applicationName: "Editor", category: .work, isActive: true, isListening: true) },
            typing: { _ in .init(characters: 15, topApplication: "Editor", peakHour: 9) },
            readScreenTime: { _ in .init() })
        controller.configure(settings: .init(enabled: true, readsSystemScreenTime: false), directory: directory, language: .english, startsTimer: false)
        await controller.tick(at: morning)
        controller.configure(settings: .init(enabled: true, minuteOfDay: 9 * 60 + 1, template: .terminal, readsSystemScreenTime: false),
            directory: output, language: .arabic, startsTimer: false)
        await controller.tick(at: morning.addingTimeInterval(30))
        #expect(controller.lastExportURL == nil)
        await controller.tick(at: morning.addingTimeInterval(60))
        let url = try #require(controller.lastExportURL)
        #expect(url.deletingLastPathComponent().standardizedFileURL == output.standardizedFileURL)
        #expect(url.lastPathComponent == DailyBriefingPNGExport.fileName(for: morning, language: .arabic, calendar: calendar))
        let image = try #require(NSBitmapImageRep(data: Data(contentsOf: url)))
        #expect(image.pixelsWide == 1800)
        #expect(!controller.isExporting)
        #expect(controller.errorMessage == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: output.path).count == 1)
    }

    @Test
    func systemUsageReplacesOnlyActivityAndKeepsLocallyRecordedMetrics() {
        var report = DailyBriefingReport.example()
        let date = report.calendar.date(bySettingHour: 10, minute: 30, second: 0, of: report.day.date)!
        let listening = report.day.listeningSeconds
        let power = report.day.peakPower
        let observedFrom = report.day.observedFrom
        let observedThrough = report.day.observedThrough
        DailyBriefingController.applySystemUsage([
            .init(deviceID: "local", bundleID: "com.example.uninstalled", start: date, end: date.addingTimeInterval(3600))
        ], to: &report)
        #expect(report.day.activeSeconds == 3600)
        #expect(report.day.hourlySeconds[10] == 1800)
        #expect(report.day.hourlySeconds[11] == 1800)
        #expect(report.day.applications["com.example.uninstalled"]?.name == "com.example.uninstalled")
        #expect(report.day.firstActivity == date)
        #expect(report.day.lastActivity == date.addingTimeInterval(3600))
        #expect(report.day.observedFrom == observedFrom)
        #expect(report.day.observedThrough == observedThrough)
        #expect(report.day.listeningSeconds == listening)
        #expect(report.day.peakPower == power)
        #expect(report.day.expansionCount == 42)
    }

    @Test
    func settingsRemainDiscoverableWithoutOtherInformationFeatures() {
        var settings = FeatureSettings()
        settings.mediaEnabled = false
        settings.systemMonitorEnabled = false
        settings.lockScreenInfoEnabled = false
        settings.sideNoticesEnabled = false
        settings.dailyBriefing.enabled = true
        #expect(SettingsSection.info.isVisible(settings: settings))
        let results = SettingsSearchIndex.results(for: "daily briefing", settings: settings, locale: Locale(identifier: "en"))
        #expect(results.contains { $0.section == .info && $0.title == "每日简报" })
        #expect(results.contains { $0.section == .features })
    }

    @Test(arguments: DailyBriefingTemplate.allCases, [AppLanguage.simplifiedChinese, .english, .arabic])
    func templatesRenderCompleteLocalizedImages(template: DailyBriefingTemplate, language: AppLanguage) throws {
        let image = try DailyBriefingRenderer.image(report: .example(), template: template, language: language, scale: 1)
        #expect(image.width == 900)
        #expect((900...2200).contains(image.height), "Unexpected poster height \(image.height) for \(template) / \(language)")
        #expect(image.dataProvider?.data != nil)
    }

    @Test
    func newLightTemplatesHaveDistinctBackgroundsAndLayouts() throws {
        let report = DailyBriefingReport.example(at: Date(timeIntervalSince1970: 1_800_000_000))
        var heights: [Int] = []
        let backgrounds = try [DailyBriefingTemplate.minimal, .coastal, .blossom].map { template in
            let image = try DailyBriefingRenderer.image(report: report, template: template, language: .english, scale: 0.1)
            heights.append(image.height)
            let bitmap = NSBitmapImageRep(cgImage: image)
            return try #require(bitmap.colorAt(x: 0, y: 0)?.usingColorSpace(.sRGB))
        }
        #expect(Set(heights).count == 3)
        let minimal = backgrounds[0]
        let coastal = backgrounds[1]
        let blossom = backgrounds[2]
        #expect(coastal.redComponent > 0.9 && coastal.greenComponent > 0.9 && coastal.blueComponent > 0.9)
        #expect(blossom.redComponent > 0.9 && blossom.greenComponent > 0.9 && blossom.blueComponent > 0.9)
        #expect(coastal.blueComponent - coastal.redComponent > 0.04)
        #expect(blossom.redComponent - blossom.greenComponent > 0.04)
        #expect(coastal.redComponent < blossom.redComponent - 0.04)
        #expect(coastal.redComponent < minimal.redComponent - 0.04)
        #expect(blossom.greenComponent < minimal.greenComponent - 0.04)
    }

    @Test(arguments: [DailyBriefingTemplate.coastal, .blossom])
    func newTemplatesUseTheirMatchingChartAccents(template: DailyBriefingTemplate) throws {
        let report = DailyBriefingReport.example(at: Date(timeIntervalSince1970: 1_800_000_000))
        let image = try DailyBriefingRenderer.image(report: report, template: template, language: .english, scale: 0.25)
        let bitmap = NSBitmapImageRep(cgImage: image)
        var foundAccent = false
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                let matches = template == .coastal
                    ? color.blueComponent - color.redComponent > 0.3
                    : color.redComponent - color.greenComponent > 0.25
                if matches {
                    foundAccent = true
                    break
                }
            }
            if foundAccent { break }
        }
        #expect(foundAccent, "The template must render its blue or rose chart accent")
    }

    @Test(arguments: DailyBriefingTemplate.allCases)
    func exportIsARealPNGAndHandlesEmptyStatistics(template: DailyBriefingTemplate) throws {
        let report = DailyBriefingReport(day: DailyBriefingDay(date: Date(timeIntervalSince1970: 1_800_000_000), calendar: DailyBriefingDay.calendar),
            generatedAt: Date(timeIntervalSince1970: 1_800_000_000), typing: nil, allDeviceSeconds: nil)
        let png = try DailyBriefingRenderer.png(report: report, template: template, language: .english)
        #expect(png.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]))
        let decoded = try #require(NSBitmapImageRep(data: png))
        #expect(decoded.pixelsWide == 1800)
        #expect(decoded.pixelsHigh > 1800)
        if let output = ProcessInfo.processInfo.environment["ZISLA_BRIEFING_PREVIEW_DIR"] {
            let directory = URL(fileURLWithPath: output, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let sample = try DailyBriefingRenderer.png(report: .example(), template: template, language: .english)
            try sample.write(to: directory.appendingPathComponent(template.rawValue + ".png"))
        }
    }

    @Test
    func settingsAndPostersOmitRemovedExplanationsAndDownloadPath() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let settings = try String(contentsOf: root.appendingPathComponent("Sources/Zisla/DailyBriefingSettingsView.swift"), encoding: .utf8)
        for key in [
            "开启后记录本机活跃情况，按所选时间导出 PNG 到下载目录。休眠或退出后，下次运行补导已记录的日期。",
            "系统数据需要完全磁盘访问及跨设备共享。不可用时使用 Zisla 本机记录。",
            "输入字符需开启本地输入统计并授予输入监控权限。记录仅保存在本机，保留最近 35 份日记录。",
            "下载目录",
        ] {
            #expect(!settings.contains("\"\(key)\""), "Removed settings text must stay hidden: \(key)")
        }
        #expect(!settings.contains("model.downloadDirectory"))
        #expect(settings.contains(#"AppLocalizedText("完全磁盘访问")"#))
        #expect(settings.contains("x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"))

        let poster = try String(contentsOf: root.appendingPathComponent("Sources/Zisla/DailyBriefingPoster.swift"), encoding: .utf8)
        for key in [
            "本机时长来自系统屏幕使用时间",
            "本机时长来自 Zisla 活跃记录",
            "仅含已记录或已同步的数据。工作与娱乐按应用分类，浏览器归入其他。未获取的指标不计为零。",
            "记录时段",
        ] {
            #expect(!poster.contains("\"\(key)\""), "Removed poster text must stay hidden: \(key)")
        }
        #expect(poster.contains(#"localized("截至")"#))
        #expect(poster.contains("time(report.generatedAt)"))
    }

    @Test
    func everyRuntimeKeyHasAllSeventeenTranslations() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let pattern = #"(?:localized|metric|category|AppLocalizedText|AppLocalization\.string)\("([^"]+)""#
        let regex = try NSRegularExpression(pattern: pattern)
        var keys = Set(DailyBriefingTemplate.allCases.map(\.title))
        for file in ["DailyBriefingPoster.swift", "DailyBriefingSettingsView.swift", "DailyBriefingController.swift"] {
            let source = try String(contentsOf: root.appendingPathComponent("Sources/Zisla/" + file), encoding: .utf8)
            let range = NSRange(source.startIndex..., in: source)
            for match in regex.matches(in: source, range: range) {
                let keyRange = try #require(Range(match.range(at: 1), in: source))
                keys.insert(String(source[keyRange]))
            }
        }
        #expect(keys.count >= 36)
        #expect(AppLanguage.allCases.count == 17)
        for language in AppLanguage.allCases {
            let tableURL = root.appendingPathComponent("Resources/Localization/\(language.rawValue).lproj/Localizable.strings")
            let table = try #require(NSDictionary(contentsOf: tableURL) as? [String: String])
            for key in keys {
                let value = try #require(table[key], "Missing \(language.rawValue) translation for \(key)")
                #expect(!value.isEmpty)
                #expect(!value.contains("TODO"))
                #expect(AppLocalization.string(key, language: language) == value)
            }
        }
        #expect(AppLocalization.string("每日简报", language: .english) == "Daily Briefing")
        #expect(AppLocalization.string("每日简报", language: .arabic) == "التقرير اليومي")
        #expect(AppLocalization.string(DailyBriefingTemplate.coastal.title, language: .english) == "Sea Salt")
        #expect(AppLocalization.string(DailyBriefingTemplate.blossom.title, language: .english) == "Cherry Blossom")
        #expect(AppLocalization.string(DailyBriefingTemplate.coastal.title, language: .arabic) == "ملح البحر")
        #expect(AppLocalization.string(DailyBriefingTemplate.blossom.title, language: .arabic) == "أزهار الكرز")
    }
}
