import AppKit
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

@MainActor
struct DailyBriefingContentRenderingTests {
    private let date = Date(timeIntervalSince1970: 1_800_000_000)

    private func poster(_ report: DailyBriefingReport, template: DailyBriefingTemplate = .minimal) -> DailyBriefingPoster {
        DailyBriefingPoster(report: report, template: template, language: .english)
    }

    private func pixels(_ image: CGImage) throws -> Data {
        let bytes = try #require(image.dataProvider?.data) as Data
        let rowSize = image.width * image.bitsPerPixel / 8
        var result = Data(capacity: rowSize * image.height)
        for row in 0..<image.height {
            let start = row * image.bytesPerRow
            result.append(contentsOf: bytes[start..<(start + rowSize)])
        }
        return result
    }

    @Test
    func exampleProvidesEveryDefaultContentAndConsistentApplicationTotals() {
        let report = DailyBriefingReport.example(at: date)
        #expect(report.selectedContent == DailyBriefingContent.defaultSelection)
        #expect(poster(report).displayedContent == DailyBriefingContent.defaultSelection)
        #expect(report.day.applications.values.reduce(0) { $0 + $1.seconds } == report.day.activeSeconds)
        #expect(report.day.hasValidTimeSeries)
        #expect(report.day.powerSamples?.isEmpty == false)
        #expect((report.day.hourlyKeyPresses?.compactMap { $0 }.reduce(0, +) ?? 0) > (report.typing?.characters ?? 0))
    }

    @Test(arguments: DailyBriefingContent.allCases, DailyBriefingTemplate.allCases)
    func eachContentCanBeSelectedWithoutEnablingOtherItems(content: DailyBriefingContent, template: DailyBriefingTemplate) throws {
        let report = DailyBriefingReport.example(at: date, selectedContent: [content])
        #expect(poster(report, template: template).displayedContent == [content])
        let image = try DailyBriefingRenderer.image(report: report, template: template, language: .english, scale: 0.25)
        let empty = try DailyBriefingRenderer.image(report: .example(at: date, selectedContent: []), template: template, language: .english, scale: 0.25)
        #expect(image.width == 225)
        let charts: Set<DailyBriefingContent> = [.hourlyUsage, .applicationUsage, .keyPressTrend, .powerTrend]
        #expect(image.height - empty.height >= (charts.contains(content) ? 40 : 12),
            "The chosen content must allocate its visible content, beyond container spacing")
    }

    @Test(arguments: DailyBriefingTemplate.allCases)
    func unavailableDataAndEmptySelectionUseTheSameCompactLayout(template: DailyBriefingTemplate) throws {
        var day = DailyBriefingDay(date: date, calendar: DailyBriefingDay.calendar)
        day.activity = nil
        let unknown = DailyBriefingReport(day: day, generatedAt: date, typing: nil, allDeviceSeconds: nil)
        var deselected = DailyBriefingReport.example(at: date)
        deselected.selectedContent = []
        #expect(poster(unknown, template: template).displayedContent.isEmpty)
        #expect(poster(deselected, template: template).displayedContent.isEmpty)
        let missingImage = try DailyBriefingRenderer.image(report: unknown, template: template, language: .english, scale: 1)
        let emptyImage = try DailyBriefingRenderer.image(report: deselected, template: template, language: .english, scale: 1)
        #expect(missingImage.height == emptyImage.height)
        #expect(missingImage.height < 400, "Empty cards or columns must not reserve poster height")
        let baseline = try DailyBriefingRenderer.image(report: deselected, template: .minimal, language: .english, scale: 1)
        if template == .paper {
            #expect((0...24).contains(emptyImage.height - baseline.height))
        } else {
            #expect(abs(emptyImage.height - baseline.height) <= 8)
        }
    }

    @Test
    func knownZeroValuesAreDisplayedAndMissingOptionalValuesAreHidden() {
        var day = DailyBriefingDay(date: date, calendar: DailyBriefingDay.calendar)
        day.observedFrom = day.date
        day.hourlyKeyPresses = Array(repeating: 0, count: 24)
        day.powerSamples = [.init(date: day.date, averageWatts: 0)]
        let selected: Set<DailyBriefingContent> = [.localUsage, .workTime, .notificationCount,
            .clipboardCaptured, .completedFocusTime, .keyPressTrend, .powerTrend, .peakFan, .allDevicesUsage]
        let report = DailyBriefingReport(day: day, generatedAt: date, typing: nil,
            allDeviceSeconds: 0, notificationCount: 0, selectedContent: selected)
        let view = poster(report)
        #expect(view.displayedContent == selected.subtracting([.peakFan]))
        #expect(view.value(for: .notificationCount) == "0")
        #expect(view.value(for: .clipboardCaptured) == "0")
        #expect(view.value(for: .completedFocusTime) == "0 min")
        #expect(view.value(for: .peakFan) == nil)
    }

    @Test
    func systemUsageCanProvideDataBeforeTheFirstLocalSamplingInterval() {
        var day = DailyBriefingDay(date: date, calendar: DailyBriefingDay.calendar)
        day.hourlySeconds[9] = 60
        day.applications = ["editor": .init(name: "Editor", category: .work, seconds: 60)]
        let selection: Set<DailyBriefingContent> = [.localUsage, .hourlyUsage, .workTime]
        let report = DailyBriefingReport(day: day, generatedAt: date, typing: nil, allDeviceSeconds: nil, selectedContent: selection)
        #expect(report.day.observedFrom == nil)
        #expect(poster(report).displayedContent == selection)
    }

    @Test
    func knownActivityDoesNotInventUsageAndPreservesLegitimateZeroCounts() {
        let day = DailyBriefingDay(date: date, calendar: DailyBriefingDay.calendar)
        let report = DailyBriefingReport(day: day, generatedAt: date, typing: nil, allDeviceSeconds: nil,
            selectedContent: [.localUsage, .workTime, .islandOpenings, .clipboardCaptured, .completedFocusTime])
        #expect(poster(report).displayedContent == [.islandOpenings, .clipboardCaptured, .completedFocusTime])

        var archived = report
        archived.day.activity = nil
        archived.day.expansionCount = 4
        #expect(poster(archived).displayedContent == [.islandOpenings])
        #expect(poster(archived).value(for: .islandOpenings) == "4")
    }

    @Test
    func aPartialBatteryRangeIsOmittedUntilBothValuesAreAvailable() {
        var report = DailyBriefingReport.example(at: date, selectedContent: [.batteryRange])
        report.day.minimumBattery = nil
        #expect(poster(report).displayedContent.isEmpty)
        report.day.minimumBattery = 0
        report.day.maximumBattery = nil
        #expect(poster(report).displayedContent.isEmpty)
        report.day.maximumBattery = 0
        #expect(poster(report).displayedContent == [.batteryRange])
        #expect(poster(report).value(for: .batteryRange) == "0% – 0%")
    }

    @Test(arguments: [Double.nan, .infinity, -1])
    func invalidDurationSourcesAreOmitted(seconds: Double) {
        var report = DailyBriefingReport.example(at: date, selectedContent: [.allDevicesUsage, .listeningTime])
        report.allDeviceSeconds = seconds
        report.day.listeningSeconds = seconds
        #expect(poster(report).displayedContent.isEmpty)
    }

    @Test
    func malformedHourlyDataCannotAllocateAChartOrUsageSummary() throws {
        var report = DailyBriefingReport.example(at: date, selectedContent: [.hourlyUsage, .localUsage])
        report.day.hourlySeconds = []
        #expect(poster(report).displayedContent.isEmpty)
        let image = try DailyBriefingRenderer.image(report: report, template: .minimal, language: .english, scale: 1)
        #expect(image.height < 400)
    }

    @Test(arguments: [Double.nan, .infinity, -1])
    func invalidHourlyValuesCannotCreateUsageContent(seconds: Double) {
        var report = DailyBriefingReport.example(at: date, selectedContent: [.hourlyUsage, .localUsage, .workTime])
        report.day.hourlySeconds[9] = seconds
        #expect(poster(report).displayedContent.isEmpty)
    }

    @Test
    func unavailableTypingDetailsDoNotCreateBlankMetrics() {
        var report = DailyBriefingReport.example(at: date)
        report.typing = .init(characters: 0, topApplication: "  ", peakHour: nil)
        report.selectedContent = [.characters, .topTypingApplication, .peakTypingHour]
        #expect(poster(report).displayedContent == [.characters])
        #expect(poster(report).value(for: .characters) == "0")
    }

    @Test
    func activityMetricsUseTheirMatchingRecordedEvents() {
        let view = poster(.example(at: date))
        let expected: [DailyBriefingContent: String] = [.clipboardCaptured: "34", .clipboardReused: "12",
            .shelfItemsAdded: "9", .shelfItemsCopied: "6", .pomodoroStarted: "5", .pomodoroCompleted: "3",
            .noteCreated: "3", .noteSaved: "7", .noteDeleted: "1", .quickNoteCreated: "2",
            .quickNoteSaved: "4", .quickNoteDeleted: "1", .unlockCount: "8"]
        for (content, value) in expected { #expect(view.value(for: content) == value) }
    }

    @Test(arguments: [Set<DailyBriefingContent>([.notificationCount]), [.localUsage]])
    func deselectedDataCannotChangeTheRenderedImage(selection: Set<DailyBriefingContent>) throws {
        var report = DailyBriefingReport.example(at: date, selectedContent: selection)
        let baseline = try DailyBriefingRenderer.image(report: report, template: .coastal, language: .english, scale: 1)
        report.typing = .init(characters: 999_999, topApplication: "UNSELECTED_APP_SENTINEL", peakHour: 3)
        report.day.firstActivity = date.addingTimeInterval(-10_000)
        report.day.peakPower = .init(value: 999, date: date)
        report.day.activity = nil
        let image = try DailyBriefingRenderer.image(report: report, template: .coastal, language: .english, scale: 1)
        #expect(image.width == baseline.width && image.height == baseline.height)
        #expect(try pixels(image) == pixels(baseline))
    }

    @Test
    func aSingleLongMetricUsesTheFullContentWidth() throws {
        var report = DailyBriefingReport.example(at: date, selectedContent: [.topTypingApplication])
        report.typing = .init(characters: 1, topApplication: String(repeating: "Wide application name ", count: 8), peakHour: nil)
        let image = try DailyBriefingRenderer.image(report: report, template: .coastal, language: .english, scale: 1)
        let bitmap = NSBitmapImageRep(cgImage: image)
        var foundText = false
        for y in Int(Double(image.height) * 0.45)..<Int(Double(image.height) * 0.7) {
            for x in 500..<800 {
                let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                if max(color.redComponent, color.greenComponent, color.blueComponent) < 0.5 {
                    foundText = true
                    break
                }
            }
            if foundText { break }
        }
        #expect(foundText, "A lone metric must not remain confined to a spare grid column")
    }

    @Test
    func completedFocusTimeUsesTheRecordedDuration() {
        let report = DailyBriefingReport.example(at: date, selectedContent: [.completedFocusTime])
        #expect(poster(report).value(for: .completedFocusTime) == "1 hr, 15 min")
    }

    @Test(arguments: DailyBriefingTemplate.allCases, [AppLanguage.simplifiedChinese, .english, .arabic])
    func sparseMixedContentProducesACompleteImage(template: DailyBriefingTemplate, language: AppLanguage) throws {
        let selection: Set<DailyBriefingContent> = [.allDevicesUsage, .workTime, .clipboardReused, .powerTrend]
        let report = DailyBriefingReport.example(at: date, selectedContent: selection)
        #expect(DailyBriefingPoster(report: report, template: template, language: language).displayedContent == selection)
        let sparse = try DailyBriefingRenderer.image(report: report, template: template, language: language, scale: 1)
        let full = try DailyBriefingRenderer.image(report: .example(at: date), template: template, language: language, scale: 1)
        #expect(sparse.width == 900)
        #expect(sparse.height < full.height)
        #expect(sparse.height < 1100)
    }
}
