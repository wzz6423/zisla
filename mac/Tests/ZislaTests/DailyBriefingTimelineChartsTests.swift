import AppKit
import SwiftUI
import Testing
import ZislaCore

@testable import Zisla

@MainActor
struct DailyBriefingTimelineChartsTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private var day: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 4))! }

    private func keyChart(_ counts: [Int64?]?, language: AppLanguage = .english) -> DailyBriefingKeyPressChart {
        DailyBriefingKeyPressChart(hourlyCounts: counts, language: language, accent: .blue, ink: .black)
    }

    private func powerChart(_ samples: [DailyBriefingPowerSample]?, language: AppLanguage = .english) -> DailyBriefingPowerChart {
        DailyBriefingPowerChart(samples: samples, day: day, calendar: calendar, language: language, accent: .blue, ink: .black)
    }

    @Test
    func keyboardDistinguishesUnavailableFromRecordedZeroAndPreservesEveryHour() throws {
        #expect(keyChart(nil).points == nil)
        #expect(!keyChart(nil).hasData)
        #expect(keyChart([]).points == nil)
        #expect(keyChart(Array(repeating: 0, count: 23)).points == nil)
        #expect(keyChart(Array(repeating: -1, count: 24)).points == nil)
        let zero = try #require(keyChart(Array(repeating: 0, count: 24)).points)
        #expect(keyChart(Array(repeating: 0, count: 24)).hasData)
        #expect(zero.count == 24)
        #expect(zero.map(\.hour) == (0..<24).map(Double.init))
        #expect(zero.allSatisfy { $0.value == 0 && $0.segment == 0 })

        var counts = Array<Int64?>(repeating: 0, count: 24)
        counts[0] = 12
        counts[14] = 52_000
        counts[23] = Int64.max
        let points = try #require(keyChart(counts).points)
        #expect(points[0].value == 12)
        #expect(points[14].value == 52_000)
        #expect(points[23].value == Double(Int64.max))
        #expect(points.allSatisfy { $0.value.isFinite })
    }

    @Test
    func keyboardOmitsUnobservedHoursAndSplitsBeforeDuringAndAfterMonitoring() throws {
        var counts = Array<Int64?>(repeating: nil, count: 24)
        counts[5] = 0
        counts[6] = 20
        counts[9] = 0
        counts[11] = 30
        counts[12] = 50
        let chart = keyChart(counts)
        let points = try #require(chart.points)

        #expect(chart.hasData)
        #expect(points.map(\.hour) == [5, 6, 9, 11, 12])
        #expect(points.map(\.value) == [0, 20, 0, 30, 50])
        #expect(points.map(\.segment) == [0, 0, 1, 2, 2])
        counts[13] = -1
        #expect(keyChart(counts).points == nil)
    }

    @Test
    func keyboardDrawsAnIsolatedKnownZeroAndHidesAnEntirelyUnknownDay() throws {
        var counts = Array<Int64?>(repeating: nil, count: 24)
        #expect(!keyChart(counts).hasData)
        #expect(keyChart(counts).points == [])
        let unknown = try rendered(keyChart(counts), width: 360)
        #expect(unknown.height == 4)

        counts[14] = 0
        let chart = keyChart(counts)
        #expect(chart.hasData)
        #expect(chart.points == [.init(hour: 14, value: 0, segment: 0)])
        let zero = try rendered(chart, width: 360)
        #expect((190...260).contains(zero.height))
        #expect(try containsColor(in: zero) { $0.blueComponent - $0.redComponent > 0.4 })
    }

    @Test
    func keyboardLeavesTheRenderedGapBetweenUnobservedHoursEmpty() throws {
        var referenceCounts = Array<Int64?>(repeating: 50, count: 24)
        referenceCounts[23] = 100
        let reference = NSBitmapImageRep(cgImage: try rendered(keyChart(referenceCounts), width: 788))
        var left: Int?
        var right: Int?
        for y in 0..<reference.pixelsHigh {
            for x in 0..<reference.pixelsWide {
                let color = try #require(reference.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                if color.blueComponent - color.redComponent > 0.4 {
                    left = min(left ?? x, x)
                    right = max(right ?? x, x)
                }
            }
        }
        let first = try #require(left)
        let last = try #require(right)
        let span = Double(last - first)
        let gap = Int(Double(first) + span * 7.75 / 23)..<Int(Double(first) + span * 8.25 / 23)
        var partial = Array<Int64?>(repeating: nil, count: 24)
        for hour in [5, 6, 9, 11, 12] { partial[hour] = 50 }
        partial[23] = 100
        let image = try rendered(keyChart(partial), width: 788)

        #expect(try containsColor(in: image) { $0.blueComponent - $0.redComponent > 0.4 })
        #expect(try containsColor(in: image, columns: gap) { $0.blueComponent - $0.redComponent > 0.4 } == false)
    }

    @Test
    func powerSortsSamplesAndLeavesMissingBucketsDisconnected() throws {
        let samples = [
            DailyBriefingPowerSample(date: day.addingTimeInterval(1_500), averageWatts: 100),
            DailyBriefingPowerSample(date: day, averageWatts: 0),
            DailyBriefingPowerSample(date: day.addingTimeInterval(600), averageWatts: 48),
            DailyBriefingPowerSample(date: day.addingTimeInterval(300), averageWatts: 36),
        ]
        let points = try #require(powerChart(samples).points)
        #expect(points.map(\.hour) == [0, 300, 600, 1_500].map { Double($0) / 3600 })
        #expect(points.map(\.value) == [0, 36, 48, 100])
        #expect(points.map(\.segment) == [0, 0, 0, 1])
        #expect(samples.first?.averageWatts == 100)
    }

    @Test
    func powerKeepsSingleZeroSampleAndExcludesOtherDays() throws {
        #expect(powerChart(nil).points == nil)
        #expect(powerChart([]).points == [])
        let emptyImage = try rendered(powerChart([]), width: 360)
        #expect(emptyImage.height == 4)
        #expect(try containsColor(in: emptyImage) { $0.blueComponent - $0.redComponent > 0.4 } == false)
        let chart = powerChart([
            .init(date: day.addingTimeInterval(-300), averageWatts: 99),
            .init(date: day.addingTimeInterval(300), averageWatts: 0),
            .init(date: day.addingTimeInterval(86_400), averageWatts: 99),
        ])
        let points = try #require(chart.points)
        #expect(points.count == 1)
        #expect(points.first?.value == 0)
        #expect(points.first?.segment == 0)
        #expect(chart.hasData)
        #expect(chart.domain == 0...24)
        #expect(chart.ticks == [0, 6, 12, 18, 24])
    }

    @Test(arguments: [(month: 3, date: 8, hours: 23.0), (month: 11, date: 1, hours: 25.0)])
    func powerDomainFollowsDaylightSavingTime(value: (month: Int, date: Int, hours: Double)) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: value.month, day: value.date)))
        let last = start.addingTimeInterval(value.hours * 3600 - 300)
        let chart = DailyBriefingPowerChart(samples: [.init(date: last, averageWatts: 64)], day: start,
            calendar: calendar, language: .english, accent: .blue, ink: .black)

        #expect(chart.domain == 0...value.hours)
        #expect(chart.ticks.last == value.hours)
        #expect(chart.ticks.dropLast().map { calendar.component(.hour, from: start.addingTimeInterval($0 * 3600)) } == [0, 6, 12, 18])
        #expect(chart.timeLabel(0) == powerChart(nil).timeLabel(0))
        let point = try #require(chart.points?.first)
        #expect(point.hour == value.hours - 300.0 / 3600)
        #expect(calendar.isDate(start.addingTimeInterval(chart.domain.upperBound * 3600), inSameDayAs: start) == false)
    }

    @Test(arguments: [AppLanguage.simplifiedChinese, .english, .arabic], [296.0, 788.0])
    func chartsRenderAtParentWidthsInBothWritingDirections(language: AppLanguage, width: Double) throws {
        let counts = (0..<24).map { Optional(Int64($0 * 100)) }
        let samples = stride(from: 0, through: 3_600, by: 300).map { second in
            DailyBriefingPowerSample(date: day.addingTimeInterval(Double(second)), averageWatts: Double(second / 60))
        }
        let keyboard = try rendered(keyChart(counts, language: language), width: width)
        let power = try rendered(powerChart(samples, language: language), width: width)
        for image in [keyboard, power] {
            #expect(image.width == Int(width))
            #expect((190...260).contains(image.height))
            #expect(try containsColor(in: image) { $0.blueComponent - $0.redComponent > 0.4 })
        }
    }

    @Test(arguments: [false, true])
    func powerRendersIsolatedSamplesAndUnknownState(isUnknown: Bool) throws {
        let image = try rendered(powerChart(isUnknown ? nil : [.init(date: day, averageWatts: 0)]), width: 360)
        #expect(image.width == 360)
        #expect(isUnknown ? image.height == 4 : (190...260).contains(image.height))
        #expect(try containsColor(in: image) { $0.blueComponent - $0.redComponent > 0.4 } == !isUnknown)
    }

    @Test
    func unavailableChartsLeaveNoTitleOrLayoutSpace() throws {
        let encoded = try JSONEncoder().encode(DailyBriefingPowerSample(date: day, averageWatts: 25))
        var zeroCount = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        zeroCount["sampleCount"] = 0
        let invalidCount = try JSONDecoder().decode(DailyBriefingPowerSample.self,
            from: JSONSerialization.data(withJSONObject: zeroCount))
        let invalidPower = powerChart([
            .init(date: day, averageWatts: .infinity),
            .init(date: day, averageWatts: .nan),
            .init(date: day, averageWatts: -10),
            invalidCount,
        ])
        try #require(!invalidPower.hasData)
        for view in [AnyView(keyChart(nil)), AnyView(keyChart([])), AnyView(keyChart(Array(repeating: nil, count: 24))), AnyView(powerChart(nil)),
                     AnyView(powerChart([])), AnyView(invalidPower)] {
            let host = NSHostingController(rootView: view)
            #expect(host.sizeThatFits(in: NSSize(width: 360, height: 900)).height == 0)
        }
        let zeroImage = try rendered(keyChart(Array(repeating: 0, count: 24)), width: 360)
        #expect((190...260).contains(zeroImage.height))
        #expect(try containsColor(in: zeroImage) { $0.blueComponent - $0.redComponent > 0.4 })
    }

    @Test
    func bothDenseLinesAndIsolatedPointsUseTheTemplateAccent() throws {
        let accent = Color(red: 0.9, green: 0.1, blue: 0.8)
        let keyboard = DailyBriefingKeyPressChart(hourlyCounts: (0..<24).map { Optional(Int64($0 * 100)) },
            language: .english, accent: accent, ink: .black)
        let power = DailyBriefingPowerChart(samples: [.init(date: day, averageWatts: 25)], day: day,
            calendar: calendar, language: .english, accent: accent, ink: .black)
        for image in [try rendered(keyboard, width: 360), try rendered(power, width: 360)] {
            #expect(try containsColor(in: image) { $0.redComponent - $0.greenComponent > 0.5 && $0.blueComponent - $0.greenComponent > 0.45 })
        }
    }

    private func rendered(_ view: some View, width: Double) throws -> CGImage {
        let renderer = ImageRenderer(content: view.frame(width: width).padding(.vertical, 2).background(Color.white))
        renderer.scale = 1
        return try #require(renderer.cgImage)
    }

    private func containsColor(in image: CGImage, columns: Range<Int>? = nil, matching: (NSColor) -> Bool) throws -> Bool {
        let bitmap = NSBitmapImageRep(cgImage: image)
        for y in 0..<bitmap.pixelsHigh {
            for x in columns ?? 0..<bitmap.pixelsWide {
                let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                if matching(color) { return true }
            }
        }
        return false
    }
}
