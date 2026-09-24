import Foundation
import Testing
import ZislaCore

@testable import Zisla
@testable import ZislaKit

@MainActor
struct BrowserDownloadQuickActionTests {
    private let transfer = BrowserCompletedTransfer(
        id: UUID(), fileName: "report.pdf", directoryURL: URL(fileURLWithPath: "/tmp/download-fixture")
    )

    @Test(arguments: [false, true])
    func primaryTriggerOpensTheContainingFolderOnce(_ lightweight: Bool) {
        let controller = ClipboardAssistantController(windowPresenter: { _, _ in })
        defer { controller.dismiss(animated: false) }
        controller.isLightweightMode = lightweight
        var performed: [ClipboardAssistantAction] = []
        controller.onPerformAction = { performed.append($0) }

        #expect(present(transfer, on: controller))
        #expect(performed.isEmpty)
        #expect(controller.presentation.detection?.title == "report.pdf")
        #expect(controller.presentation.detection?.detail == .path(transfer.directoryURL.path))
        #expect(ClipboardAssistantToastView.actionLabel(.openFolder(transfer.directoryURL)) == "打开文件夹")

        controller.performCurrentAction()
        #expect(performed == [.openFolder(transfer.directoryURL)])
        #expect(controller.presentation.detection == nil)
        controller.performCurrentAction()
        #expect(performed.count == 1)
    }

    @Test
    func clipboardAndDownloadPromptsReplaceEachOtherAndRejectLateUpdates() throws {
        let controller = ClipboardAssistantController(windowPresenter: { _, _ in })
        defer { controller.dismiss(animated: false) }
        let old = ClipboardAssistantDetection(kind: .text, title: "old", actions: [.copyText("old")])
        let oldGeneration = try #require(controller.present(old, visualStyle: .transparent))
        #expect(present(transfer, on: controller))
        controller.updateDetection(old, for: oldGeneration)
        #expect(controller.presentation.detection?.action == .openFolder(transfer.directoryURL))

        let newer = BrowserCompletedTransfer(
            id: UUID(), fileName: "new.pdf", directoryURL: URL(fileURLWithPath: "/tmp/new-download-fixture")
        )
        #expect(present(newer, on: controller))
        #expect(controller.presentation.detection?.action == .openFolder(newer.directoryURL))
        let copied = ClipboardAssistantDetection(kind: .text, title: "new copy", actions: [.copyText("new copy")])
        controller.present(copied, visualStyle: .transparent)
        var performed: [ClipboardAssistantAction] = []
        controller.onPerformAction = { performed.append($0) }
        controller.performCurrentAction()
        #expect(performed == [.copyText("new copy")])
    }

    @Test
    func disabledAndBusyContextsDoNotOfferAFolderAction() {
        for (enabled, recording, preparing, expanded) in [
            (false, false, false, false),
            (true, true, false, false),
            (true, false, true, false),
            (true, false, false, true),
        ] {
            let controller = ClipboardAssistantController(windowPresenter: { _, _ in })
            defer { controller.dismiss(animated: false) }
            var settings = FeatureSettings.default
            settings.clipboardAssistantEnabled = enabled
            #expect(!BrowserDownloadQuickActionPresenter.present(
                transfer, on: controller, settings: settings,
                isVoiceRecording: recording, isVoicePreparing: preparing, isIslandVisible: expanded
            ))
            #expect(controller.presentation.detection == nil)
        }
    }

    @Test
    func screenshotAndScreenLockKeepCompletedTransfersHidden() throws {
        let controller = ClipboardAssistantController(windowPresenter: { _, _ in })
        defer { controller.dismiss(animated: false) }
        let copied = ClipboardAssistantDetection(kind: .text, title: "before screenshot")
        _ = try #require(controller.present(copied, visualStyle: .transparent))
        controller.setScreenshotActive(true)
        #expect(!present(transfer, on: controller))
        #expect(controller.presentation.detection == copied)
        controller.setScreenshotActive(false)
        controller.setSystemScreenshotActive(true)
        #expect(!present(transfer, on: controller))
        controller.setSystemScreenshotActive(false)
        controller.setScreenLocked(true)
        #expect(!present(transfer, on: controller))
        #expect(controller.presentation.detection == nil)
        controller.setScreenLocked(false)
        #expect(present(transfer, on: controller))
    }

    @Test(arguments: [ClipboardAssistantDisplayDuration.threeSeconds, .fiveSeconds, .sevenSeconds])
    func folderPromptUsesTheConfiguredDurationAndExpires(_ duration: ClipboardAssistantDisplayDuration) async throws {
        let gate = DismissalGate()
        let controller = ClipboardAssistantController(
            windowPresenter: { _, _ in }, dismissSleeper: { await gate.sleep(for: $0) }
        )
        defer { controller.dismiss(animated: false) }
        var settings = FeatureSettings.default
        settings.clipboardAssistantDisplayDuration = duration
        #expect(present(transfer, on: controller, settings: settings))
        await ClipboardAssistantCurrencyPresentationTests.expectAutomaticDismissal(
            controller, gate: gate, duration: try #require(duration.expiresAfter)
        )
        var performed: [ClipboardAssistantAction] = []
        controller.onPerformAction = { performed.append($0) }
        controller.performCurrentAction()
        #expect(performed.isEmpty)
    }

    @Test
    func neverDismissAndProgressAppearanceFollowQuickActionSettings() {
        let controller = ClipboardAssistantController(windowPresenter: { _, _ in })
        defer { controller.dismiss(animated: false) }
        var settings = FeatureSettings.default
        settings.clipboardAssistantDisplayDuration = .never
        settings.collapsedProgressGlowEnabled = false
        settings.islandVisualStyle = .frosted
        settings.sideNoticesEnabled = false
        settings.browserDownloadIslandEnabled = false
        #expect(present(transfer, on: controller, settings: settings))
        #expect(controller.dismissalProgress(at: .distantFuture) == nil)
        #expect(!controller.presentation.progressGlowEnabled)
        #expect(controller.presentation.visualStyle == .frosted)
    }

    private func present(
        _ transfer: BrowserCompletedTransfer,
        on controller: ClipboardAssistantController,
        settings: FeatureSettings = .default
    ) -> Bool {
        BrowserDownloadQuickActionPresenter.present(
            transfer, on: controller, settings: settings,
            isVoiceRecording: false, isVoicePreparing: false, isIslandVisible: false
        )
    }
}

struct BrowserDownloadObservationSettingsTests {
    @Test
    func observationAndProgressDisplayHaveIndependentSwitches() {
        var settings = FeatureSettings.default
        settings.sideNoticesEnabled = false
        settings.browserDownloadIslandEnabled = false
        settings.clipboardAssistantEnabled = true
        #expect(settings.observesBrowserDownloads)
        #expect(!settings.showsBrowserDownloadProgress)
        settings.clipboardAssistantEnabled = false
        #expect(!settings.observesBrowserDownloads)
        settings.sideNoticesEnabled = true
        #expect(!settings.observesBrowserDownloads)
        settings.browserDownloadIslandEnabled = true
        #expect(settings.observesBrowserDownloads)
        #expect(settings.showsBrowserDownloadProgress)
        settings.sideNoticesEnabled = false
        #expect(!settings.showsBrowserDownloadProgress)
        #expect(!settings.observesBrowserDownloads)
    }
}
