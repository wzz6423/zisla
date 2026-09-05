import CoreGraphics
import Foundation
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

struct VoiceRecordingIslandLayoutTests {
    @Test
    func modulePagesUseTheFormerAIMonitorWidth() {
        for module in IslandModule.allCases {
            let layout = IslandModuleLayout.resolved(
                for: module,
                dashboardCardCount: 0
            )

            #expect(layout.islandSize.width == 820)
            #expect(layout.panelSize.width == 820)
        }
    }

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
    func independentStatusPanelsRejoinFullscreenSpacesWhenPresented() throws {
        let presenterSource = try String(
            contentsOf: Self.sourcesDirectoryURL.appendingPathComponent("Zisla/SideNoticePresenter.swift"),
            encoding: .utf8
        )

        #expect(presenterSource.contains("panel.orderFrontRegardless()"))
        #expect(!presenterSource.contains("panel.orderFront(nil)"))
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
        #expect(rootViewSource.contains("let usesCompactSurface = voiceInput.isCapturingInput"))
        #expect(rootViewSource.contains("usesCompactGlassSurface: usesCompactSurface"))
        #expect(rootViewSource.contains("if voiceInput.isCapturingInput {"))
        #expect(appSource.contains("model.voiceInput.isCapturingInputPublisher"))
        // The island content is mounted up front, so the first take's reveal animates from the
        // collapsed pill instead of being SwiftUI's initial render.
        #expect(appSource.contains("coordinator.prewarmPanel()"))
    }

    @Test
    func recordingStartWiresSynchronousOverlayProtectionAndEndDoesNotRefocusTheTarget() throws {
        let appModelSource = try Self.source(of: "Zisla/AppModel.swift")
        #expect(appModelSource.contains("var onVoiceInputWillStart: (() -> Void)?"))
        let appModelHandler = try #require(appModelSource.range(of: "voiceInput.onRecordingWillStart = {"))
        let handlerEnd = try #require(
            appModelSource[appModelHandler.upperBound...].range(of: "voiceInput.onTranscriptCompleted = {")
        )
        let handler = appModelSource[appModelHandler.lowerBound..<handlerEnd.lowerBound]
        #expect(handler.contains("onVoiceInputWillStart?()"))

        let appSource = try Self.source(of: "Zisla/ZislaApp.swift")
        #expect(appSource.contains("model.onVoiceInputWillStart = {"))
        #expect(appSource.contains("coordinator.setVoiceRecording(true, at: NSEvent.mouseLocation)"))
        #expect(!appSource.contains("AppModel.shared.restoreVoiceInputTargetFocus()"))
    }

    @Test
    func voiceCaptureSuppressesSystemSpectrumMonitoring() throws {
        let appModelSource = try Self.source(of: "Zisla/AppModel.swift")
        let updateStart = try #require(appModelSource.range(of: "private func updateSpectrumMonitoring()"))
        let updateBody = appModelSource[updateStart.lowerBound...]

        #expect(appModelSource.contains("voiceInput.isCapturingInputPublisher"))
        #expect(updateBody.contains("let voiceInputIsCapturing = voiceInput.isCapturingInput"))
        #expect(updateBody.contains("!voiceInputIsCapturing"))

        let startHandler = try #require(appModelSource.range(of: "voiceInput.onRecordingWillStart = {"))
        let handler = appModelSource[startHandler.lowerBound..<updateStart.lowerBound]
        let stopSpectrum = try #require(handler.range(of: "self.updateSpectrumMonitoring()"))
        let overlayHook = try #require(handler.range(of: "self.onVoiceInputWillStart?()"))
        #expect(stopSpectrum.lowerBound < overlayHook.lowerBound)
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

    /// The collapsed notice reuses the recording surface, so it has to reuse its exclusivity too:
    /// centered on the notch, with the status wings and the pet panel folded away.
    @Test
    func theCollapsedNoticeMatchesTheRecordingSurfaceExclusivity() throws {
        let rootViewSource = try Self.source(of: "Zisla/IslandRootView.swift")
        let appSource = try Self.source(of: "Zisla/ZislaApp.swift")
        let presenterSource = try Self.source(of: "Zisla/SideNoticePresenter.swift")
        let coordinatorSource = try Self.source(of: "ZislaKit/OverlayCoordinator.swift")

        // The module panel is wider than the compact surface and reserves a pet slot on one side, so
        // keeping the slot would push the notice row half a slot off the notch. Recording only
        // escapes that because its panel is resized down to the compact width.
        let petSlot = try #require(rootViewSource.range(of: "let reservesPetSlot = "))
        let petSlotEnd = try #require(
            rootViewSource[petSlot.upperBound...].range(of: "let petSlotWidth")
        )
        #expect(
            rootViewSource[petSlot.lowerBound..<petSlotEnd.lowerBound]
                .contains("&& !usesCompactSurface")
        )

        #expect(presenterSource.contains("updateSuppression { $0.isTransientNoticePresented = presented }"))
        #expect(coordinatorSource.contains("guard !isVoiceRecording,\n            !isTransientNoticePresented,"))
        #expect(appSource.contains("noticePresenter?.setTransientNoticePresented(presented)"))
        #expect(appSource.contains("coordinator?.setTransientNoticePresented(presented)"))
        #expect(
            appSource.contains("hasMessage && !islandVisible && !mirror && !teleprompter")
        )
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
