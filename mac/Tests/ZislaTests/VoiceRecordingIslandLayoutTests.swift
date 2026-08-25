import CoreGraphics
import Foundation
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

    @Test
    func voiceRecordingSuppressesTheIndependentCompactStatusPresenter() throws {
        let presenterSource = try String(
            contentsOf: Self.sourcesDirectoryURL.appendingPathComponent("Zisla/SideNoticePresenter.swift"),
            encoding: .utf8
        )
        let appSource = try String(
            contentsOf: Self.sourcesDirectoryURL.appendingPathComponent("Zisla/ZislaApp.swift"),
            encoding: .utf8
        )

        #expect(presenterSource.contains("private var suppression = SideNoticeSuppression()"))
        #expect(presenterSource.contains("func setVoiceRecording(_ recording: Bool)"))
        #expect(presenterSource.contains("updateSuppression { $0.isVoiceRecording = recording }"))
        #expect(presenterSource.contains("guard !suppression.hidesNotices else"))
        #expect(appSource.contains("noticePresenter?.setVoiceRecording(true)"))
        #expect(appSource.contains("noticePresenter?.setVoiceRecording(false)"))
    }

    @Test
    func theRecordingSurfaceIsDrivenByTheCombinedCaptureFlag() throws {
        let controllerSource = try Self.source(of: "Zisla/VoiceInputController.swift")
        let rootViewSource = try Self.source(of: "Zisla/IslandRootView.swift")
        let appSource = try Self.source(of: "Zisla/ZislaApp.swift")

        // `isRecording` only rises once the dictation engine is live, up to a second after the
        // keypress; every presentation decision has to read the combined flag instead.
        #expect(controllerSource.contains("var isCapturingInput: Bool { isPreparing || isRecording }"))
        #expect(controllerSource.contains("private func finishPreparingIntoRecording()"))
        #expect(rootViewSource.contains("usesCompactGlassSurface: voiceInput.isCapturingInput"))
        #expect(rootViewSource.contains("if voiceInput.isCapturingInput {"))
        #expect(appSource.contains("model.voiceInput.isCapturingInputPublisher"))
        // The island content is mounted up front, so the first take's reveal animates from the
        // collapsed pill instead of being SwiftUI's initial render.
        #expect(appSource.contains("coordinator.prewarmPanel()"))
    }

    @Test
    func thePanelReturnsToItsModuleSizeOnlyAfterTheFoldHasRun() throws {
        let appSource = try Self.source(of: "Zisla/ZislaApp.swift")

        // The module panel reserves a pet slot that pulls the surface off the panel center. The mask
        // compensates for that offset on the fold's clock, not the layout's, so applying it while the
        // pill is still folding drags the pill sideways.
        #expect(appSource.contains("self.scheduleVoiceRecordingPanelRestore(saved)"))
        #expect(!appSource.contains("self.overlayCoordinator?.updateExpandedSize(saved)"))
        // Anything that expands the island needs the full frame immediately, fold or not.
        #expect(appSource.contains("self?.flushVoiceRecordingPanelRestore()"))
        #expect(ZislaMotion.islandRecycleSettleDelay > .milliseconds(220))
    }

    private static func source(of relativePath: String) throws -> String {
        try String(
            contentsOf: sourcesDirectoryURL.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private static var sourcesDirectoryURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources")
    }
}
