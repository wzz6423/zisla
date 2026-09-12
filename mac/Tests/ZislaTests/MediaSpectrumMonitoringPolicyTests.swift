import Testing

@testable import Zisla

struct MediaSpectrumMonitoringPolicyTests {
    @Test @MainActor
    func collapsedSideNoticesStartAudibilityMonitoringBeforePlaybackSnapshot() {
        #expect(AppModel.shouldMonitorSpectrum(
            mediaEnabled: true,
            sideNoticesEnabled: true,
            isIslandVisible: false,
            isPlaying: false,
            backgroundSoundsPlaying: false
        ))
    }

    @Test @MainActor
    func monitoringRespectsMediaGate() {
        #expect(!AppModel.shouldMonitorSpectrum(
            mediaEnabled: false,
            sideNoticesEnabled: true,
            isIslandVisible: false,
            isPlaying: false,
            backgroundSoundsPlaying: false
        ))
    }

    @Test @MainActor
    func expandedIslandRetainsMonitoringWithoutSideNotices() {
        #expect(AppModel.shouldMonitorSpectrum(
            mediaEnabled: true,
            sideNoticesEnabled: false,
            isIslandVisible: true,
            isPlaying: false,
            backgroundSoundsPlaying: false
        ))
    }
}
