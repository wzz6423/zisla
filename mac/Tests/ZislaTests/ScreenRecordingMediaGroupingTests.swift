import Foundation
import Testing
import ZislaCore
@testable import Zisla

struct ScreenRecordingMediaGroupingTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

    private func asset(_ kind: RecordingMediaKind = .image, imported: String? = nil, captured: String? = nil) -> RecordingMediaAsset {
        .init(name: kind.rawValue, file: UUID().uuidString + ".png", kind: kind, duration: 2, width: 64, height: 48,
            importedAt: imported.map(date), capturedAt: captured.map(date))
    }

    @Test func noGroupingPreservesLibraryOrderAndEmptyGroupsAreAbsent() {
        let assets = [asset(.audio), asset(.image), asset(.video)]
        for granularity in RecordingMediaTimeGranularity.allCases {
            let groups = RecordingMediaLibraryGrouping.groups(assets: assets, grouping: .none, granularity: granularity)
            #expect(groups.count == 1 && groups[0].title == nil && groups[0].date == nil && groups[0].assets == assets)
        }
        for grouping in RecordingMediaGrouping.allCases {
            #expect(RecordingMediaLibraryGrouping.groups(assets: [], grouping: grouping, granularity: .hour).isEmpty)
        }
    }

    @Test func typeGroupsPreserveEveryAssetAndStableOrder() {
        let assets = [asset(.audio), asset(.image), asset(.video), asset(.image)]
        let groups = RecordingMediaLibraryGrouping.groups(assets: assets, grouping: .type, granularity: .day)
        #expect(groups.map(\.id) == ["video", "image", "audio"])
        #expect(groups.map(\.title) == ["视频", "图片", "音频"])
        #expect(groups[1].assets.map(\.id) == [assets[1].id, assets[3].id])
        #expect(Set(groups.flatMap(\.assets).map(\.id)) == Set(assets.map(\.id)))
    }

    @Test(arguments: [RecordingMediaGrouping.importedAt, .capturedAt], RecordingMediaTimeGranularity.allCases)
    func allTimeGranularitiesUseTheirCalendarBucketsWithUnknownLast(_ grouping: RecordingMediaGrouping,
                                                                  granularity: RecordingMediaTimeGranularity) {
        let times = ["2025-12-31T23:59:00Z", "2026-01-01T00:01:00Z", "2026-01-01T01:01:00Z",
                     "2026-01-02T00:00:00Z", "2026-02-01T00:00:00Z", "2026-02-01T00:15:00Z"]
        let unknown = asset()
        let known = times.map { asset(imported: $0, captured: $0) }
        let assets = [unknown] + known
        let before = assets
        let groups = RecordingMediaLibraryGrouping.groups(assets: assets, grouping: grouping,
            granularity: granularity, calendar: calendar)
        let expected: [String]
        switch granularity {
        case .hour: expected = [times[4], times[3], "2026-01-01T01:00:00Z", "2026-01-01T00:00:00Z", "2025-12-31T23:00:00Z"]
        case .day: expected = [times[4], times[3], "2026-01-01T00:00:00Z", "2025-12-31T00:00:00Z"]
        case .month: expected = [times[4], "2026-01-01T00:00:00Z", "2025-12-01T00:00:00Z"]
        case .year: expected = ["2026-01-01T00:00:00Z", "2025-01-01T00:00:00Z"]
        }
        #expect(groups.compactMap(\.date) == expected.map(date))
        #expect(groups.last?.id == "unknown" && groups.last?.assets == [unknown])
        #expect(groups.last?.title == (grouping == .importedAt ? "未知导入时间" : "未知拍摄时间"))
        #expect(groups[0].assets.map(\.id).suffix(2) == known.suffix(2).map(\.id))
        #expect(Set(groups.flatMap(\.assets).map(\.id)) == Set(assets.map(\.id)))
        #expect(assets == before && Set(groups.map(\.id)).count == groups.count)
    }

    @Test func importAndCaptureDatesStayIndependentAndRepeatedDSTHoursAreDistinct() {
        let first = asset(imported: "2026-01-01T00:00:00Z", captured: "2025-01-01T00:00:00Z")
        let second = asset(imported: "2025-01-01T00:00:00Z", captured: "2026-01-01T00:00:00Z")
        #expect(RecordingMediaLibraryGrouping.groups(assets: [first, second], grouping: .importedAt,
            granularity: .year, calendar: calendar).map { $0.assets[0].id } == [first.id, second.id])
        #expect(RecordingMediaLibraryGrouping.groups(assets: [first, second], grouping: .capturedAt,
            granularity: .year, calendar: calendar).map { $0.assets[0].id } == [second.id, first.id])
        var local = calendar
        local.timeZone = TimeZone(identifier: "America/New_York")!
        let repeated = [asset(imported: "2026-11-01T05:30:00Z"), asset(imported: "2026-11-01T06:30:00Z")]
        let groups = RecordingMediaLibraryGrouping.groups(assets: repeated, grouping: .importedAt,
            granularity: .hour, calendar: local)
        #expect(groups.count == 2 && groups[0].id != groups[1].id)
        #expect(groups.map(\.date) == [date("2026-11-01T06:00:00Z"), date("2026-11-01T05:00:00Z")])
    }

    @Test(arguments: [RecordingMediaGrouping.importedAt, .capturedAt], RecordingMediaTimeGranularity.allCases)
    func unsupportedCalendarDatesRemainUnknownWithoutLosingOrChangingMedia(_ grouping: RecordingMediaGrouping,
                                                                         granularity: RecordingMediaTimeGranularity) {
        let valid = asset(imported: "2026-01-01T00:00:00Z", captured: "2026-01-01T00:00:00Z")
        let unknown = asset()
        let extreme = [Double.greatestFiniteMagnitude, -Double.greatestFiniteMagnitude].map { seconds in
            var media = asset()
            media.importedAt = Date(timeIntervalSinceReferenceDate: seconds)
            media.capturedAt = media.importedAt
            return media
        }
        for media in extreme {
            let timestamp = media.importedAt!
            #expect(calendar.dateInterval(of: granularity.component, for: timestamp)?.contains(timestamp) != true,
                "Foundation clamps unsupported finite dates to an unrelated calendar interval")
        }
        let assets = [unknown, extreme[0], valid, extreme[1]]
        let groups = RecordingMediaLibraryGrouping.groups(assets: assets, grouping: grouping,
            granularity: granularity, calendar: calendar)
        #expect(groups.count == 2 && groups.first?.assets == [valid])
        #expect(groups.last?.id == "unknown" && groups.last?.assets == [unknown, extreme[0], extreme[1]])
        #expect(groups.flatMap(\.assets).count == assets.count)
        #expect(Set(groups.flatMap(\.assets).map(\.id)) == Set(assets.map(\.id)))
        #expect(groups.last?.title == (grouping == .importedAt ? "未知导入时间" : "未知拍摄时间"))
    }
}
