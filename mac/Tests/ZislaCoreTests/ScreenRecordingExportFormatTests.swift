import Foundation
import Testing
@testable import ZislaCore

struct ScreenRecordingExportFormatTests {
    @Test func commonFormatsAreDistinctAndPreserveTheirStableIdentifiers() throws {
        let required = ["mp4", "mov", "m4v", "mkv", "webm", "avi", "wmv", "flv", "mpeg", "ts", "3gp",
                        "gif", "livephoto", "m4a", "mp3", "wav", "flac", "aac", "ogg", "aiff", "opus"]
        let identifiers = RecordingExportFormat.allCases.map(\.rawValue)
        #expect(Set(identifiers).count == identifiers.count)
        for identifier in required {
            let format = try #require(RecordingExportFormat(rawValue: identifier), "Missing export format \(identifier)")
            let encoded = try JSONEncoder().encode(format)
            #expect(try JSONDecoder().decode(RecordingExportFormat.self, from: encoded) == format)
        }
        #expect(RecordingExportConfiguration().format == .mp4)
        #expect(RecordingExportFormat.allCases.filter(\.isVideo).count == 11)
        #expect(RecordingExportFormat.allCases.filter(\.isAudioOnly).count == 8)
        for format in RecordingExportFormat.allCases {
            #expect(format.fileExtension == format.rawValue)
            #expect(!format.title.isEmpty)
            #expect(format.isVideo == ["mp4", "mov", "m4v", "mkv", "webm", "avi", "wmv", "flv", "mpeg", "ts", "3gp"].contains(format.rawValue))
            #expect(format.isAudioOnly == ["m4a", "mp3", "wav", "flac", "aac", "ogg", "aiff", "opus"].contains(format.rawValue))
            #expect(format.requiresFFmpeg == ["mkv", "webm", "avi", "wmv", "flv", "mpeg", "ts", "3gp", "mp3", "ogg", "opus"].contains(format.rawValue))
        }
        #expect(RecordingExportFormat.livePhoto.title == "Live Photo")
        #expect(try JSONDecoder().decode(RecordingExportFormat.self, from: Data("\"mp4\"".utf8)) == .mp4)
        #expect(try JSONDecoder().decode(RecordingExportFormat.self, from: Data("\"gif\"".utf8)) == .gif)
    }
}
