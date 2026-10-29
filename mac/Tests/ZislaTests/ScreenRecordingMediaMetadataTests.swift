import AVFoundation
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import ZislaCore
@testable import Zisla

struct ScreenRecordingMediaMetadataTests {
    private var utc: TimeZone { TimeZone(secondsFromGMT: 0)! }

    @Test func exifDateHonorsOffsetFractionsAndRejectsInvalidInput() {
        let expected = ISO8601DateFormatter().date(from: "2026-10-29T01:30:45Z")!
        #expect(RecordingMediaMetadata.exifDate("2026:10:29 09:30:45", offset: "+08:00", subseconds: "125",
            timeZone: utc) == expected.addingTimeInterval(0.125))
        #expect(RecordingMediaMetadata.exifDate("2026:10:28 20:00:45", offset: "-05:30",
            timeZone: utc) == expected)
        #expect(RecordingMediaMetadata.exifDate("2026:10:29 01:30:45", timeZone: utc) == expected)
        for value in ["", "bad", "2026:02:30 01:30:45", "2026:10:29 24:30:45", "2026:10:29 01:30:45junk"] {
            #expect(RecordingMediaMetadata.exifDate(value, timeZone: utc) == nil)
        }
        #expect(RecordingMediaMetadata.exifDate("2026:10:29 01:30:45", offset: "+90:00", timeZone: utc) == nil)
        for value in ["", "1x", "-1", "１２"] {
            #expect(RecordingMediaMetadata.exifDate("2026:10:29 01:30:45", subseconds: value, timeZone: utc) == nil)
        }
    }

    @MainActor @Test func imagesReadTheirEmbeddedDateAndMissingMetadataStaysUnknown() throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        let imageURL = try fixture.createImage()
        #expect(RecordingMediaMetadata.capturedAt(image: imageURL) == nil)
        let source = try #require(CGImageSourceCreateWithURL(imageURL as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let target = fixture.directory.appendingPathComponent("dated.jpg")
        let destination = try #require(CGImageDestinationCreateWithURL(target as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        let properties: [String: Any] = [kCGImagePropertyExifDictionary as String: [
            kCGImagePropertyExifDateTimeOriginal as String: "2026:10:29 09:30:45",
            kCGImagePropertyExifOffsetTimeOriginal as String: "+08:00",
            kCGImagePropertyExifSubsecTimeOriginal as String: "125",
        ]]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        try #require(CGImageDestinationFinalize(destination))
        let expected = ISO8601DateFormatter().date(from: "2026-10-29T01:30:45Z")!.addingTimeInterval(0.125)
        #expect(RecordingMediaMetadata.capturedAt(image: target) == expected)
        try FileManager.default.setAttributes([.creationDate: Date(timeIntervalSince1970: 0)], ofItemAtPath: imageURL.path)
        #expect(RecordingMediaMetadata.capturedAt(image: imageURL) == nil,
            "A file creation date must not be mistaken for the camera capture date")
        #expect(RecordingMediaMetadata.capturedAt(image: fixture.directory.appendingPathComponent("missing.png")) == nil)
    }

    @MainActor @Test func missingOrInvalidEXIFFallsBackToTheEmbeddedTIFFDate() throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        let sourceURL = try fixture.createImage()
        let source = try #require(CGImageSourceCreateWithURL(sourceURL as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let tiffDate = "2020:01:02 03:04:05"
        let expected = try #require(RecordingMediaMetadata.exifDate(tiffDate))
        for (index, original) in [nil, "invalid", "2026:10:29 09:30:45"].enumerated() {
            let target = fixture.directory.appendingPathComponent("date-\(index).tiff")
            let destination = try #require(CGImageDestinationCreateWithURL(target as CFURL,
                UTType.tiff.identifier as CFString, 1, nil))
            var properties: [String: Any] = [kCGImagePropertyTIFFDictionary as String:
                [kCGImagePropertyTIFFDateTime as String: tiffDate]]
            if let original {
                properties[kCGImagePropertyExifDictionary as String] = [
                    kCGImagePropertyExifDateTimeOriginal as String: original,
                    kCGImagePropertyExifOffsetTimeOriginal as String: "+08:00",
                ]
            }
            CGImageDestinationAddImage(destination, image, properties as CFDictionary)
            try #require(CGImageDestinationFinalize(destination))
            #expect(RecordingMediaMetadata.capturedAt(image: target) == (index == 2
                ? ISO8601DateFormatter().date(from: "2026-10-29T01:30:45Z") : expected),
                "A valid original camera timestamp takes precedence; absent or invalid EXIF uses embedded TIFF metadata")
        }
    }

    @Test func audiovisualMetadataSupportsDateValuesAndISOStringsWithoutFabricatingDates() async throws {
        let date = Date(timeIntervalSince1970: 1_793_239_845.125)
        let direct = AVMutableMetadataItem()
        direct.identifier = .commonIdentifierCreationDate
        direct.value = date as NSDate
        #expect(try await RecordingMediaMetadata.metadataDate([direct]) == date)
        let string = AVMutableMetadataItem()
        string.identifier = .quickTimeMetadataCreationDate
        string.value = "2026-10-29T01:30:45.125Z" as NSString
        #expect(try await RecordingMediaMetadata.metadataDate([string]) == ISO8601DateFormatterWithFractions.date("2026-10-29T01:30:45.125Z"))
        string.value = "2026-10-29T01:30:45Z" as NSString
        #expect(try await RecordingMediaMetadata.metadataDate([string]) == ISO8601DateFormatter().date(from: "2026-10-29T01:30:45Z"))
        string.value = "unknown" as NSString
        #expect(try await RecordingMediaMetadata.metadataDate([string]) == nil)
        #expect(try await RecordingMediaMetadata.metadataDate([]) == nil)
    }
}

private enum ISO8601DateFormatterWithFractions {
    static func date(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text)
    }
}
