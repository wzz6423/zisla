import Foundation
import Testing

@testable import ZislaKit

struct AudioPlaybackMonitorTests {
    @Test
    func activatedProcessWinsBeforeBundleFallback() {
        let sources = [
            source(id: "music", pids: [101], bundleIdentifier: "com.example.music"),
            source(id: "video", pids: [202], bundleIdentifier: "com.example.video"),
        ]

        #expect(
            AudioPlaybackMonitor.sourceID(
                processIdentifier: 202,
                bundleIdentifier: "com.example.music",
                sources: sources
            ) == "video"
        )
        #expect(
            AudioPlaybackMonitor.sourceID(
                processIdentifier: nil,
                bundleIdentifier: "com.example.video",
                sources: sources
            ) == "video"
        )
    }

    @Test
    func unknownActivatedProcessClearsThePreviousSourcePreference() {
        let sources = [
            source(id: "music", pids: [101], bundleIdentifier: "com.example.music"),
        ]

        #expect(
            AudioPlaybackMonitor.sourceID(
                processIdentifier: 404,
                bundleIdentifier: "com.example.unknown",
                sources: sources
            ) == nil
        )
    }

    private func source(
        id: String,
        pids: [pid_t],
        bundleIdentifier: String
    ) -> AudioPlaybackSource {
        AudioPlaybackSource(
            id: id,
            processIdentifiers: pids,
            bundleIdentifier: bundleIdentifier,
            applicationName: id,
            iconData: nil,
            isFrontmost: false
        )
    }
}
