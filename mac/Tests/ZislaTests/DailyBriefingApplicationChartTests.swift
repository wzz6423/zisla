import AppKit
import SwiftUI
import Testing
import ZislaCore

@testable import Zisla

@MainActor
struct DailyBriefingApplicationChartTests {
    @Test
    func applicationsSortByDurationWithStableBundleIDTies() {
        let applications: [String: DailyBriefingApplication] = [
            "z": .init(name: "Clock", category: .other, seconds: 30),
            "b": .init(name: "Editor", category: .work, seconds: 60),
            "a": .init(name: "Browser", category: .other, seconds: 60),
        ]

        let rows = DailyBriefingApplicationChart.rows(for: applications, language: .english)

        #expect(rows.map(\.id) == [.application("a"), .application("b"), .application("z")])
        #expect(rows.map(\.name) == ["Browser", "Editor", "Clock"])
        #expect(rows.map(\.seconds) == [60, 60, 30])
    }

    @Test(arguments: [0, 1, 8, 9, 32])
    func rankingBoundsTheRowsAndPreservesTheRecordedTotal(count: Int) {
        let applications = sampleApplications(count: count)
        let rows = DailyBriefingApplicationChart.rows(for: applications, language: .simplifiedChinese)

        #expect(rows.count == min(count, 8) + (count > 8 ? 1 : 0))
        #expect(rows.reduce(0) { $0 + $1.seconds } == applications.values.reduce(0) { $0 + $1.seconds })
        if count > 8 {
            #expect(rows.last?.id == .other)
            #expect(rows.last?.name == AppLocalization.string("其他应用", language: .simplifiedChinese))
            #expect(rows.prefix(8).map(\.seconds) == applications.values.map(\.seconds).sorted(by: >).prefix(8).map { $0 })
        }
    }

    @Test
    func invalidAndUnusedApplicationsAreHiddenWhileTinyPositiveDurationsRemain() {
        let applications: [String: DailyBriefingApplication] = [
            "nan": .init(name: "NaN", category: .other, seconds: .nan),
            "infinity": .init(name: "Infinity", category: .other, seconds: .infinity),
            "negative": .init(name: "Negative", category: .other, seconds: -1),
            "zero": .init(name: "Zero", category: .other),
            "tiny": .init(name: "Tiny", category: .other, seconds: .leastNonzeroMagnitude),
        ]

        let rows = DailyBriefingApplicationChart.rows(for: applications, language: .english)

        #expect(rows.count == 1)
        #expect(rows.first?.id == .application("tiny"))
        #expect(rows.first?.seconds == .leastNonzeroMagnitude)
    }

    @Test
    func otherGroupCannotCollideWithAnApplicationIDOrOverflowItsDuration() {
        var applications = sampleApplications(count: 10)
        applications["other"] = .init(name: "Other", category: .other, seconds: .greatestFiniteMagnitude)
        applications["overflow.a"] = .init(name: "A", category: .other, seconds: .greatestFiniteMagnitude)
        applications["overflow.b"] = .init(name: "B", category: .other, seconds: .greatestFiniteMagnitude)
        for index in 0..<10 {
            applications["zz.huge.\(index)"] = .init(name: "Huge", category: .other, seconds: .greatestFiniteMagnitude)
        }

        let rows = DailyBriefingApplicationChart.rows(for: applications, language: .english)

        #expect(rows.count == 9)
        #expect(rows.contains { $0.id == .application("other") })
        #expect(Set(rows.map(\.id)).count == rows.count)
        #expect(rows.allSatisfy { $0.seconds.isFinite && $0.seconds > 0 })
        #expect(rows.last?.seconds == .greatestFiniteMagnitude)
    }

    @Test
    func blankApplicationNamesUseTheirBundleIDs() {
        let rows = DailyBriefingApplicationChart.rows(for: [
            "unknown.app": .init(name: " \n ", category: .other, seconds: 60)
        ], language: .english)

        #expect(rows.first?.name == "unknown.app")
    }

    @Test
    func emptyUsageDoesNotReserveAChartOrHeading() {
        let content = NSHostingController(rootView: DailyBriefingApplicationChart(
            applications: [:], language: .english, accent: .red, ink: .black, formatDuration: { _ in "" }
        ))

        #expect(content.sizeThatFits(in: NSSize(width: 788, height: 2_000)).height == 0)
    }

    @Test
    func aSingleApplicationKeepsTheHeadingAndUsesTheCallersDurationFormatting() throws {
        let applications: [String: DailyBriefingApplication] = [
            "editor": .init(name: "Editor", category: .work, seconds: 120)
        ]
        var formattedValues: [TimeInterval] = []
        let formatted = try render(applications: applications, language: .english, formatDuration: {
            formattedValues.append($0)
            return "Two minutes"
        })
        let blank = try render(applications: applications, language: .english, formatDuration: { _ in "" })
        let formattedPixels = try #require(formatted.dataProvider?.data) as Data
        let blankPixels = try #require(blank.dataProvider?.data) as Data

        #expect(Set(formattedValues) == [120])
        #expect(formattedPixels != blankPixels)
        #expect((65...120).contains(formatted.height))
    }

    @Test(arguments: [AppLanguage.simplifiedChinese, .english, .arabic])
    func longNamesAndManyApplicationsRenderWithinTheProposedWidth(language: AppLanguage) throws {
        var applications = sampleApplications(count: 25)
        applications["long"] = .init(
            name: "برنامج التطبيقات المطولة e\u{301} — A very long application name that must stay inside the poster",
            category: .work,
            seconds: 10_000
        )

        let image = try render(applications: applications, language: language)

        #expect(image.width == 788)
        #expect((300...650).contains(image.height))
        #expect(try accentBars(in: image).count == 9)
    }

    @Test
    func barsUseRelativeDurationsAndMirrorTheirLeadingEdgeInArabic() throws {
        let applications: [String: DailyBriefingApplication] = [
            "a": .init(name: "A", category: .work, seconds: 600),
            "b": .init(name: "B", category: .work, seconds: 300),
        ]
        let image = try render(applications: applications, language: .english)
        let leftToRight = try accentBars(in: image).sorted { $0.width > $1.width }
        let rightToLeft = try accentBars(in: render(applications: applications, language: .arabic)).sorted { $0.width > $1.width }

        #expect(leftToRight.count == 2)
        #expect(rightToLeft.count == 2)
        let longest = try #require(leftToRight.first)
        let shortest = try #require(leftToRight.last)
        let arabicShortest = try #require(rightToLeft.last)
        #expect(abs(longest.width - shortest.width * 2) <= 3)
        #expect(shortest.minX <= 2)
        #expect(arabicShortest.maxX >= 786)
        #expect(arabicShortest.minX > shortest.minX + 300)
        let track = try #require(NSBitmapImageRep(cgImage: image)
            .colorAt(x: 766, y: Int(shortest.midY))?.usingColorSpace(.sRGB))
        #expect(track.redComponent > 0.9 && track.redComponent < 0.98)
        #expect(abs(track.redComponent - track.greenComponent) < 0.01)
        #expect(abs(track.redComponent - track.blueComponent) < 0.01)
    }

    @Test
    func theOtherGroupSharesTheScaleWhenItsCombinedUsageExceedsEveryApp() throws {
        var applications: [String: DailyBriefingApplication] = [:]
        for index in 0..<17 {
            applications["app.\(index)"] = .init(name: "App \(index)", category: .work, seconds: index < 8 ? 1_000 : 500)
        }

        let bars = try accentBars(in: render(applications: applications, language: .english)).sorted { $0.width > $1.width }

        #expect(bars.count == 9)
        let longest = try #require(bars.first)
        let shortest = try #require(bars.last)
        #expect(abs(longest.width / shortest.width - 4.5) < 0.1)
    }

    @Test
    func darkTemplatesUseTheProvidedInkForTheHeading() throws {
        let applications: [String: DailyBriefingApplication] = [
            "editor": .init(name: "Editor", category: .work, seconds: 600)
        ]
        let image = try render(applications: applications, language: .english, ink: .white, background: .black)
        let bitmap = NSBitmapImageRep(cgImage: image)
        var lightPixels = 0
        for y in 0..<min(35, bitmap.pixelsHigh) {
            for x in 0..<bitmap.pixelsWide {
                let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                if color.redComponent > 0.8 && color.greenComponent > 0.8 && color.blueComponent > 0.8 {
                    lightPixels += 1
                }
            }
        }

        #expect(lightPixels > 100)
    }

    @Test
    func extremeFiniteDurationsKeepFiniteProportionalBarGeometry() throws {
        let applications: [String: DailyBriefingApplication] = [
            "a": .init(name: "A", category: .work, seconds: .greatestFiniteMagnitude),
            "b": .init(name: "B", category: .work, seconds: .greatestFiniteMagnitude / 2),
        ]
        let image = try render(applications: applications, language: .english)
        let bars = try accentBars(in: image).sorted { $0.width > $1.width }

        #expect(image.width == 788)
        #expect(bars.count == 2)
        let longest = try #require(bars.first)
        let shortest = try #require(bars.last)
        #expect(abs(longest.width - shortest.width * 2) <= 3)
    }

    private func sampleApplications(count: Int) -> [String: DailyBriefingApplication] {
        Dictionary(uniqueKeysWithValues: (0..<count).map { index in
            ("app.\(index)", DailyBriefingApplication(name: "App \(index)", category: .work, seconds: Double(index + 1) * 60))
        })
    }

    private func render(
        applications: [String: DailyBriefingApplication], language: AppLanguage,
        ink: Color = .black, background: Color = .white,
        formatDuration: @escaping (TimeInterval) -> String = { _ in "Duration" }
    ) throws -> CGImage {
        let chart = DailyBriefingApplicationChart(applications: applications, language: language,
            accent: Color(red: 0.9, green: 0.05, blue: 0.05), ink: ink, formatDuration: formatDuration)
        let renderer = ImageRenderer(content: chart.frame(width: 788).background(background).environment(\.colorScheme, .light))
        renderer.scale = 1
        return try #require(renderer.cgImage)
    }

    private func accentBars(in image: CGImage) throws -> [CGRect] {
        let bitmap = NSBitmapImageRep(cgImage: image)
        var bars: [CGRect] = []
        var previousRowHadAccent = false
        for y in 0..<bitmap.pixelsHigh {
            var firstX: Int?
            var lastX: Int?
            for x in 0..<bitmap.pixelsWide {
                let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                if color.redComponent > 0.8 && color.greenComponent < 0.2 && color.blueComponent < 0.2 {
                    firstX = firstX ?? x
                    lastX = x
                }
            }
            if let firstX, let lastX {
                let row = CGRect(x: firstX, y: y, width: lastX - firstX + 1, height: 1)
                if previousRowHadAccent {
                    bars[bars.count - 1] = bars[bars.count - 1].union(row)
                } else {
                    bars.append(row)
                }
                previousRowHadAccent = true
            } else {
                previousRowHadAccent = false
            }
        }
        return bars
    }
}
