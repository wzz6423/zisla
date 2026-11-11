import Foundation
import Testing
import ZislaCore

@testable import Zisla
@testable import ZislaKit

@MainActor
struct BrowserDownloadNotificationScenarioTests {
    @Test(arguments: [false, true])
    func completionHoldCleanupPreservesDeferredOrPublishedReviewWithoutReplayingRows(endsSceneFirst: Bool) throws {
        let queue = SideNoticeQueue()
        defer { queue.removeAll() }
        var settings = FeatureSettings()
        settings.sideNoticesEnabled = true
        settings.browserDownloadIslandEnabled = true
        queue.configureNotificationScenarios(.init(enabled: true), displayIdentifiers: ["display"])
        queue.setNotificationScenarios([.focus])
        let progress = BrowserDownloadSnapshot(agent: .chrome, fileName: "report.pdf", fraction: 0.4, isFinished: false)
        AppModel.consumeBrowserDownloadSnapshot(progress, settings: settings, notices: queue)
        queue.setNotificationScenarios([])
        #expect(queue.scenarioReview(displayIdentifier: "display").isEmpty, "In-progress furniture must not create a completion review")
        queue.setNotificationScenarios([.focus])
        var completed = progress
        completed.fraction = 1
        completed.isFinished = true
        AppModel.consumeBrowserDownloadSnapshot(completed, settings: settings, notices: queue)
        if endsSceneFirst { queue.setNotificationScenarios([]) }
        let original = queue.scenarioReview(displayIdentifier: "display")
        if endsSceneFirst { #expect(original.count == 1) }
        let unrelated = IslandNotice(id: "other-failure", title: "Unrelated", kind: .error)
        queue.enqueue(unrelated, expiresAfter: nil)

        AppModel.consumeBrowserDownloadSnapshot(nil, settings: settings, notices: queue)

        #expect(queue.left.isEmpty && queue.right == [unrelated], "The routine hold cleanup removes only browser rows")
        queue.setNotificationScenarios([])
        let review = queue.scenarioReview(displayIdentifier: "display")
        #expect(review.count == 1)
        let item = try #require(review.first)
        #expect(item.title == "report.pdf" && item.detail == "100%" && item.kind == .success)
        if endsSceneFirst { #expect(review == original, "Hold cleanup must not re-record a published completion") }
        AppModel.consumeBrowserDownloadSnapshot(nil, settings: settings, notices: queue)
        #expect(queue.scenarioReview(displayIdentifier: "display") == review)
        #expect(queue.left.isEmpty && queue.right == [unrelated])
    }

    @Test(arguments: [false, true], [false, true])
    func disablingProgressClearsDeferredAndPublishedCompletions(endsSceneFirst: Bool, disablesSideNotices: Bool) {
        let queue = SideNoticeQueue()
        defer { queue.removeAll() }
        var settings = FeatureSettings()
        settings.sideNoticesEnabled = true
        settings.browserDownloadIslandEnabled = true
        queue.configureNotificationScenarios(.init(enabled: true), displayIdentifiers: ["display"])
        queue.setNotificationScenarios([.meeting])
        AppModel.consumeBrowserDownloadSnapshot(.init(agent: .safari, fileName: "file.pdf", fraction: 1, isFinished: true),
            settings: settings, notices: queue)
        if endsSceneFirst {
            queue.setNotificationScenarios([])
            #expect(queue.scenarioReview(displayIdentifier: "display").count == 1)
            AppModel.consumeBrowserDownloadSnapshot(nil, settings: settings, notices: queue)
        }
        if disablesSideNotices { settings.sideNoticesEnabled = false }
        else { settings.browserDownloadIslandEnabled = false }

        AppModel.consumeBrowserDownloadSnapshot(nil, settings: settings, notices: queue)

        queue.setNotificationScenarios([])
        #expect(queue.left.isEmpty && queue.right.isEmpty)
        #expect(queue.scenarioReview(displayIdentifier: "display").isEmpty)
    }

    @Test
    func cancellingAnUnfinishedTransferDoesNotCreateACompletionReview() {
        let queue = SideNoticeQueue()
        defer { queue.removeAll() }
        var settings = FeatureSettings()
        settings.sideNoticesEnabled = true
        settings.browserDownloadIslandEnabled = true
        queue.configureNotificationScenarios(.init(enabled: true), displayIdentifiers: ["display"])
        queue.setNotificationScenarios([.screenRecording])
        AppModel.consumeBrowserDownloadSnapshot(.init(agent: .chrome, fileName: "cancelled.pdf", fraction: 0.5, isFinished: false),
            settings: settings, notices: queue)
        AppModel.consumeBrowserDownloadSnapshot(nil, settings: settings, notices: queue)
        queue.setNotificationScenarios([])
        #expect(queue.left.isEmpty && queue.right.isEmpty)
        #expect(queue.scenarioReview(displayIdentifier: "display").isEmpty)
        AppModel.consumeBrowserDownloadSnapshot(.init(agent: .chrome, fileName: "completed.pdf", fraction: 1, isFinished: true),
            settings: settings, notices: queue)
        queue.removeAll(withIDPrefix: "browser-download-")
        #expect(queue.left.isEmpty && queue.right.isEmpty)
        #expect(queue.scenarioReview(displayIdentifier: "display").isEmpty)
    }
}
