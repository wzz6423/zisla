import Testing

@testable import Zisla

struct MediaSpectrumMonitoringPolicyTests {
    @Test @MainActor
    func collapsedSideNoticesStartAudibilityMonitoringBeforePlaybackSnapshot() {
        #expect(AppModel.shouldMonitorSpectrum(
            mediaEnabled: true,
            sideNoticesEnabled: true,
            voiceInputIsCapturing: false,
            isIslandVisible: false,
            isPlaying: false,
            backgroundSoundsPlaying: false
        ))
    }

    @Test @MainActor
    func monitoringRespectsMediaAndVoiceInputGates() {
        #expect(!AppModel.shouldMonitorSpectrum(
            mediaEnabled: false,
            sideNoticesEnabled: true,
            voiceInputIsCapturing: false,
            isIslandVisible: false,
            isPlaying: false,
            backgroundSoundsPlaying: false
        ))
        #expect(!AppModel.shouldMonitorSpectrum(
            mediaEnabled: true,
            sideNoticesEnabled: true,
            voiceInputIsCapturing: true,
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
            voiceInputIsCapturing: false,
            isIslandVisible: true,
            isPlaying: false,
            backgroundSoundsPlaying: false
        ))
    }
}
