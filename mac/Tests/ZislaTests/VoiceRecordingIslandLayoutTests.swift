import CoreGraphics
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

struct VoiceRecordingIslandLayoutTests {
    @Test
    func voiceRecordingKeepsCollapsedWidthWithOneTranscriptRow() {
        let layout = IslandModuleLayout.voiceRecording

        #expect(layout.islandSize == CGSize(width: 240, height: 54))
        #expect(layout.panelSize == CGSize(width: 240, height: 58))
    }

    @Test
    func persistentPetDoesNotReserveHiddenStatusWingsDuringRecording() {
        let aiNotice = IslandNotice(id: "ai-active-codex", title: "Codex", side: .left)
        let voiceNotice = IslandNotice(
            id: "voice-processing-left",
            title: "正在整理语音",
            side: .left,
            style: .status
        )
        let notices = [aiNotice, voiceNotice]

        #expect(PersistentPetNoticePolicy.notices(
            notices,
            isVoiceRecording: true,
            voiceDisplayID: 2,
            displayID: 1
        ).isEmpty)
        #expect(PersistentPetNoticePolicy.notices(
            notices,
            isVoiceRecording: false,
            voiceDisplayID: 2,
            displayID: 1
        ) == [aiNotice])
        #expect(PersistentPetNoticePolicy.notices(
            notices,
            isVoiceRecording: false,
            voiceDisplayID: 2,
            displayID: 2
        ) == notices)
    }
}
