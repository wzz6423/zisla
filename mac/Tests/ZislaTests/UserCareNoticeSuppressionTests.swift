import Combine
import Foundation
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

@MainActor
struct UserCareNoticeSuppressionTests {
    private static let screen = ScreenSnapshot(
        displayID: 7,
        frame: CGRect(x: 20_000, y: 0, width: 1_512, height: 982),
        visibleFrame: CGRect(x: 20_000, y: 0, width: 1_512, height: 950)
    )

    @Test(arguments: ["island", "voice", "clipboard", "lock", "transient", "screenshot", "placement"])
    func suppressionDropsAnAlreadyQueuedReminderAndDoesNotReplayIt(reason: String) async throws {
        let suiteName = "Zisla.UserCareSuppression.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = FeatureSettingsStore(defaults: defaults)
        let queue = SideNoticeQueue()
        var rightUpdateCount = 0
        let rightUpdates = queue.$right.sink { _ in rightUpdateCount += 1 }
        defer { rightUpdates.cancel() }
        let sweep = AIResultSweepController()
        let presenter = SideNoticePresenter(
            queue: queue,
            resultSweep: sweep,
            media: NowPlayingService(),
            browserDownloads: BrowserDownloadMonitor(),
            settingsStore: settings,
            languageStore: AppLanguageStore(defaults: defaults),
            screenSnapshotProvider: { [Self.screen] }
        )
        defer {
            presenter.stop()
            queue.removeAll()
            sweep.cancel()
            settings.flushPendingChanges()
        }
        #expect(presenter.canPresentUserCareNotice)
        queue.enqueue(IslandNotice(id: UserCareService.noticeID, title: "Synthetic reminder", style: .message))
        #expect(queue.right.count == 1)
        setSuppressed(true, reason: reason, presenter: presenter)
        #expect(!presenter.canPresentUserCareNotice)
        #expect(queue.right.isEmpty)
        let hiddenUpdateCount = rightUpdateCount
        for _ in 0..<3 {
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
        }
        #expect(rightUpdateCount == hiddenUpdateCount,
            "An empty reminder queue must not feed back into repeated panel refreshes")
        setSuppressed(false, reason: reason, presenter: presenter)
        #expect(presenter.canPresentUserCareNotice)
        #expect(queue.right.isEmpty, "Ending suppression must not replay the old reminder")
        presenter.stop()
        #expect(!presenter.canPresentUserCareNotice)
    }

    @Test
    func overlappingPresenterSuppressionDoesNotPrematurelyAllowNewReminders() throws {
        let suiteName = "Zisla.UserCareSuppression.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = FeatureSettingsStore(defaults: defaults)
        let queue = SideNoticeQueue()
        let sweep = AIResultSweepController()
        let presenter = SideNoticePresenter(
            queue: queue,
            resultSweep: sweep,
            media: NowPlayingService(),
            browserDownloads: BrowserDownloadMonitor(),
            settingsStore: settings,
            languageStore: AppLanguageStore(defaults: defaults),
            screenSnapshotProvider: { [Self.screen] }
        )
        defer {
            presenter.stop()
            queue.removeAll()
            sweep.cancel()
            settings.flushPendingChanges()
        }
        presenter.setIslandExpanded(true)
        presenter.setClipboardAssistantVisible(true)
        presenter.setScreenshotActive(true)
        presenter.setIslandExpanded(false)
        #expect(!presenter.canPresentUserCareNotice)
        presenter.setClipboardAssistantVisible(false)
        #expect(!presenter.canPresentUserCareNotice)
        presenter.setScreenshotActive(false)
        #expect(presenter.canPresentUserCareNotice)
    }

    private func setSuppressed(_ value: Bool, reason: String, presenter: SideNoticePresenter) {
        switch reason {
        case "island": presenter.setIslandExpanded(value)
        case "voice": presenter.setVoiceRecording(value)
        case "clipboard": presenter.setClipboardAssistantVisible(value)
        case "lock": presenter.setScreenLocked(value)
        case "transient": presenter.setTransientNoticePresented(value, message: value ? "Synthetic transient" : nil)
        case "screenshot": presenter.setScreenshotActive(value)
        default: presenter.setPlacementSelectionActive(value)
        }
    }
}
