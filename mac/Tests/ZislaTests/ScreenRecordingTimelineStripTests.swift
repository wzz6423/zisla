import Foundation
import Testing
import ZislaCore

@testable import Zisla

struct ScreenRecordingTimelineStripTests {
    private var segments: [RecordingSegment] {
        [.init(start: 8, end: 12, speed: 2), .init(start: 0, end: 2, speed: 0.5), .init(start: 8, end: 10)]
    }

    @Test
    func widthsAndOrderFollowOutputDurationIncludingSlowAndRepeatedSourceRanges() throws {
        let segments = segments
        let geometry = try #require(ScreenRecordingTimelineStripGeometry(segments: segments, viewportWidth: 800, zoom: 1))
        #expect(geometry.duration == 8)
        #expect(geometry.items.map(\.id) == segments.map(\.id))
        #expect(geometry.items.map(\.width) == [200, 400, 200])
        #expect(geometry.items.map(\.x) == [0, 200, 600])
        #expect(geometry.items.map { $0.slice.outputStart } == [0, 2, 6])
        let enlarged = try #require(ScreenRecordingTimelineStripGeometry(segments: segments, viewportWidth: 800, zoom: 4))
        #expect(enlarged.width == 3_200)
        #expect(enlarged.items.map(\.width) == [800, 1_600, 800])
        #expect(enlarged.duration == geometry.duration)
    }

    @Test
    func clickingTheOutputTimelineSeeksTheCorrectSourceAndChoosesTheNextClipAtACut() throws {
        let segments = segments
        let geometry = try #require(ScreenRecordingTimelineStripGeometry(segments: segments, viewportWidth: 800, zoom: 1))
        #expect(geometry.target(at: -20) == .init(segmentID: segments[0].id, sourceTime: 8, outputTime: 0))
        #expect(geometry.target(at: 100) == .init(segmentID: segments[0].id, sourceTime: 10, outputTime: 1))
        #expect(geometry.target(at: 200) == .init(segmentID: segments[1].id, sourceTime: 0, outputTime: 2))
        #expect(geometry.target(at: 400) == .init(segmentID: segments[1].id, sourceTime: 1, outputTime: 4))
        #expect(geometry.target(at: 600) == .init(segmentID: segments[2].id, sourceTime: 8, outputTime: 6))
        #expect(geometry.target(at: 1_000) == .init(segmentID: segments[2].id, sourceTime: 10, outputTime: 8))
        #expect(geometry.target(at: .nan) == nil)
        #expect(geometry.target(at: .infinity) == nil)
    }

    @Test
    func playheadUsesTheSelectedRepeatedClipAndTheActualPlaybackOutputClock() throws {
        let segments = segments
        let geometry = try #require(ScreenRecordingTimelineStripGeometry(segments: segments, viewportWidth: 800, zoom: 1))
        #expect(geometry.playheadX(sourceTime: 9, selectedID: segments[0].id, outputTime: nil) == 50)
        #expect(geometry.playheadX(sourceTime: 9, selectedID: segments[2].id, outputTime: nil) == 700)
        #expect(geometry.playheadX(sourceTime: 9, selectedID: segments[2].id, outputTime: 3) == 300)
        #expect(geometry.playheadX(sourceTime: 20, selectedID: segments[2].id, outputTime: nil) == nil)
        #expect(geometry.playheadX(sourceTime: .nan, selectedID: nil, outputTime: nil) == nil)
        #expect(geometry.playheadX(sourceTime: 9, selectedID: nil, outputTime: 100) == 800)
    }

    @Test
    func emptyTimelineAndTransientInvalidViewGeometryDoNotProduceHitTargets() throws {
        let empty = try #require(ScreenRecordingTimelineStripGeometry(segments: [], viewportWidth: 800, zoom: 1))
        #expect(empty.items.isEmpty)
        #expect(empty.target(at: 0) == nil)
        #expect(empty.playheadX(sourceTime: 0, selectedID: nil, outputTime: 0) == nil)
        #expect(empty.ticks.isEmpty)
        for width in [0.0, -1, .infinity, .nan] {
            #expect(ScreenRecordingTimelineStripGeometry(segments: segments, viewportWidth: width, zoom: 1) == nil)
        }
        for zoom in [0.0, 0.5, 17, .infinity, .nan] {
            #expect(ScreenRecordingTimelineStripGeometry(segments: segments, viewportWidth: 800, zoom: zoom) == nil)
        }
        #expect(ScreenRecordingTimelineStripGeometry(segments: segments, viewportWidth: .greatestFiniteMagnitude, zoom: 16) == nil)
    }

    @Test
    func rulerWorkStaysBoundedForLongHighlyZoomedProjects() throws {
        let geometry = try #require(ScreenRecordingTimelineStripGeometry(
            segments: [.init(start: 0, end: 604_800, speed: 0.1)], viewportWidth: 1_920, zoom: 16))
        #expect(geometry.ticks.first == 0)
        #expect(geometry.ticks.count <= 241)
        #expect(geometry.ticks.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= geometry.duration })
        #expect(zip(geometry.ticks, geometry.ticks.dropFirst()).allSatisfy { $0 < $1 })
    }

    @Test
    func startTrimConvertsOutputDragDistanceUsingSpeedAndClampsAtTheOtherEdge() throws {
        let segment = RecordingSegment(start: 2, end: 10, speed: 2)
        var trim = ScreenRecordingTimelineTrim(original: segment, edge: .start, pointsPerSecond: 100, translation: 100)
        let replacement = try #require(trim.replacement(sourceDuration: 20))
        #expect(replacement.start == 4)
        #expect(replacement.end == segment.end)
        #expect(replacement.id == segment.id)
        #expect(replacement.speed == segment.speed)
        #expect(segment.start == 2, "A drag draft must not mutate the original clip")
        trim.translation = -1_000
        #expect(trim.replacement(sourceDuration: 20)?.start == 0)
        trim.translation = 1_000
        #expect(trim.replacement(sourceDuration: 20)?.start == 9.999)
    }

    @Test
    func endTrimClampsToMediaDurationAndNeverDeletesTheWholeClip() throws {
        let segment = RecordingSegment(start: 2, end: 10, speed: 2)
        var trim = ScreenRecordingTimelineTrim(original: segment, edge: .end, pointsPerSecond: 100, translation: -100)
        #expect(trim.replacement(sourceDuration: 20)?.end == 8)
        trim.translation = 1_000
        #expect(trim.replacement(sourceDuration: 20)?.end == 20)
        trim.translation = -1_000
        #expect(trim.replacement(sourceDuration: 20)?.end == 2.001)
        #expect(trim.replacement(sourceDuration: 20)?.start == segment.start)
        let short = RecordingSegment(start: 0, end: 0.0005)
        let shortTrim = ScreenRecordingTimelineTrim(original: short, edge: .start, pointsPerSecond: 100, translation: 100)
        #expect(shortTrim.replacement(sourceDuration: 20) == short)
    }

    @Test(arguments: [0.25, 1.0, 4.0], [-10_000.0, -100, 0, 100, 10_000])
    func trimsRemainValidAcrossSpeedAndDragBoundaries(speed: Double, translation: Double) throws {
        let original = RecordingSegment(start: 2, end: 10, speed: speed)
        for edge in [ScreenRecordingTimelineTrim.Edge.start, .end] {
            let trim = ScreenRecordingTimelineTrim(original: original, edge: edge, pointsPerSecond: 80, translation: translation)
            let replacement = try #require(trim.replacement(sourceDuration: 20))
            #expect(replacement.start >= 0)
            #expect(replacement.end <= 20)
            #expect(replacement.end > replacement.start)
            #expect(replacement.id == original.id)
            #expect(replacement.speed == original.speed)
        }
    }

    @Test
    func invalidDragCoordinatesCannotBeCommitted() {
        let original = RecordingSegment(start: 2, end: 10)
        for scale in [0.0, -1, .infinity, .nan] {
            #expect(ScreenRecordingTimelineTrim(original: original, edge: .start, pointsPerSecond: scale)
                .replacement(sourceDuration: 20) == nil)
        }
        for translation in [Double.infinity, .nan] {
            #expect(ScreenRecordingTimelineTrim(original: original, edge: .end, pointsPerSecond: 100, translation: translation)
                .replacement(sourceDuration: 20) == nil)
        }
    }

    @Test
    func splittingTheSelectedCopyPreservesItsIdentityAndLeavesTheOriginalUntouched() throws {
        let original = RecordingSegment(start: 2, end: 10, speed: 2)
        let copy = RecordingSegment(start: original.start, end: original.end, speed: original.speed)
        var segments = [original, copy]
        let pieces = try #require(ScreenRecordingTimelineTrim.split(copy, at: 6))
        segments.replaceSubrange(1...1, with: pieces)
        #expect(segments[0] == original)
        #expect(segments.map(\.start) == [2, 2, 6])
        #expect(segments.map(\.end) == [10, 6, 10])
        #expect(pieces.first?.id == copy.id)
        #expect(pieces.last?.id != copy.id)
        #expect(pieces.allSatisfy { $0.speed == copy.speed })
        for time in [2.0, 2.0005, 9.9995, 10, .nan, .infinity] {
            #expect(ScreenRecordingTimelineTrim.split(copy, at: time) == nil)
        }
    }
}
