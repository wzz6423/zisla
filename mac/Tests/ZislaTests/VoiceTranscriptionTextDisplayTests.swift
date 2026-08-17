import Foundation
import Testing

@testable import Zisla

struct VoiceTranscriptionTextDisplayTests {
    @Test
    func recordingTranscriptUsesNonRepeatingTailFollowWithoutTruncation() throws {
        let source = try String(contentsOf: Self.islandRootSourceURL, encoding: .utf8)
        let start = try #require(source.range(of: "private struct VoiceTranscriptionView"))
        let suffix = source[start.lowerBound...]
        let end = try #require(suffix.range(of: "@MainActor\nprivate final class IslandDropState"))
        let transcriptView = suffix[..<end.lowerBound]

        #expect(transcriptView.contains("MarqueeText("))
        #expect(transcriptView.contains("repeats: false"))
        #expect(transcriptView.contains("scrollProgress: 1"))
        #expect(transcriptView.contains("clipsOverflowWhenStatic: true"))
        // Top row mirrors the collapsed recording pill: mic icon plus animated waveform.
        #expect(transcriptView.contains("mic.fill"))
        #expect(transcriptView.contains("waveform"))
        #expect(!transcriptView.contains("truncationMode"))
    }

    @Test
    func externallyPositionedTextStillFollowsTheTailWhenMotionIsReduced() throws {
        let source = try String(contentsOf: Self.marqueeSourceURL, encoding: .utf8)
        #expect(source.contains("scrollProgress != nil || !reduceMotion"))
    }

    private static var islandRootSourceURL: URL {
        sourceURL("IslandRootView.swift")
    }

    private static var marqueeSourceURL: URL {
        sourceURL("MarqueeText.swift")
    }

    private static func sourceURL(_ fileName: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Zisla")
            .appendingPathComponent(fileName)
    }
}
