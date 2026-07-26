import Foundation
import Testing

@testable import ZislaCore
@testable import ZislaKit

struct BrowserDownloadAgentResolverTests {
    @Test
    func quarantineAgentNameMatchesDisplayNameShortNameAndBundleID() {
        #expect(BrowserDownloadAgentResolver.agent(forQuarantineAgentName: "Chrome") == .chrome)
        #expect(
            BrowserDownloadAgentResolver.agent(forQuarantineAgentName: "Google Chrome") == .chrome
        )
        #expect(
            BrowserDownloadAgentResolver.agent(forQuarantineAgentName: "com.google.Chrome")
                == .chrome
        )
        #expect(BrowserDownloadAgentResolver.agent(forQuarantineAgentName: "Safari") == .safari)
        #expect(
            BrowserDownloadAgentResolver.agent(forQuarantineAgentName: "Microsoft Edge") == .edge
        )
        #expect(BrowserDownloadAgentResolver.agent(forQuarantineAgentName: "Arc") == .arc)
    }

    /// Short names like `arc` would false-match `search` via substring; require whole-word matching.
    @Test
    func unrelatedAgentNameDoesNotMatchShortBrowserName() {
        #expect(BrowserDownloadAgentResolver.agent(forQuarantineAgentName: "Search Helper") == nil)
        #expect(BrowserDownloadAgentResolver.agent(forQuarantineAgentName: "") == nil)
        #expect(BrowserDownloadAgentResolver.agent(forQuarantineAgentName: "curl") == nil)
    }

    @Test
    func singleCandidateTempExtensionResolvesWithoutRunningApps() {
        #expect(
            BrowserDownloadAgentResolver.agent(
                forTempExtension: .download,
                runningBundleIdentifiers: []
            ) == .safari
        )
        #expect(
            BrowserDownloadAgentResolver.agent(
                forTempExtension: .part,
                runningBundleIdentifiers: []
            ) == .firefox
        )
    }

    /// `.crdownload` is shared across Chromium browsers; disambiguate via running browsers.
    @Test
    func chromiumTempExtensionPrefersRunningBrowser() {
        #expect(
            BrowserDownloadAgentResolver.agent(
                forTempExtension: .crdownload,
                runningBundleIdentifiers: ["com.microsoft.edgemac"]
            ) == .edge
        )
        #expect(
            BrowserDownloadAgentResolver.agent(
                forTempExtension: .crdownload,
                runningBundleIdentifiers: ["com.apple.Safari"]
            ) == .chrome
        )
    }

    @Test
    func missingTempExtensionResolvesOnlyWhenSingleBrowserRuns() {
        #expect(
            BrowserDownloadAgentResolver.agent(
                forTempExtension: nil,
                runningBundleIdentifiers: ["com.brave.Browser"]
            ) == .brave
        )
        #expect(
            BrowserDownloadAgentResolver.agent(
                forTempExtension: nil,
                runningBundleIdentifiers: ["com.brave.Browser", "com.apple.Safari"]
            ) == nil
        )
        #expect(
            BrowserDownloadAgentResolver.agent(
                forTempExtension: nil,
                runningBundleIdentifiers: []
            ) == nil
        )
    }

    @Test
    func displayFileNameStripsIntermediateExtension() {
        let base = URL(fileURLWithPath: "/Users/x/Downloads/report.pdf")
        #expect(
            BrowserDownloadAgentResolver.displayFileName(
                for: base.appendingPathExtension("crdownload")
            ) == "report.pdf"
        )
        #expect(BrowserDownloadAgentResolver.displayFileName(for: base) == "report.pdf")
    }
}

struct BrowserDownloadSnapshotTests {
    private func snapshot(
        fraction: Double?,
        isFinished: Bool = false
    ) -> BrowserDownloadSnapshot {
        BrowserDownloadSnapshot(
            agent: .chrome,
            fileName: "report.pdf",
            fraction: fraction,
            isFinished: isFinished
        )
    }

    /// Cap in-progress progress at 99%; reserve 100% for the completed checkmark.
    @Test
    func progressTextCapsAtNinetyNineWhileDownloading() {
        #expect(snapshot(fraction: 0.723).progressText == "72%")
        #expect(snapshot(fraction: 0.9999).progressText == "99%")
        #expect(snapshot(fraction: 1).progressText == "99%")
        #expect(snapshot(fraction: 1, isFinished: true).progressText == "100%")
    }

    @Test
    func progressTextFallsBackWhenTotalSizeUnknown() {
        #expect(snapshot(fraction: nil).progressText == "…")
        #expect(snapshot(fraction: nil, isFinished: true).progressText == "100%")
    }

    @Test
    func fractionIsClampedIntoUnitRange() {
        #expect(snapshot(fraction: -0.5).fraction == 0)
        #expect(snapshot(fraction: 1.5).fraction == 1)
    }

    /// Progress jitter within the same integer percent must not refresh the Dynamic Island.
    @Test
    func displayKeyIgnoresSubPercentChanges() {
        #expect(snapshot(fraction: 0.7201).displayKey == snapshot(fraction: 0.7299).displayKey)
        #expect(snapshot(fraction: 0.72).displayKey != snapshot(fraction: 0.73).displayKey)
        #expect(
            snapshot(fraction: 1).displayKey != snapshot(fraction: 1, isFinished: true).displayKey
        )
    }
}

struct BrowserDownloadTrackerTests {
    private func entry(
        agent: BrowserDownloadAgent? = .chrome,
        fileName: String = "report.pdf",
        fraction: Double? = 0,
        startedAt: Date = Date()
    ) -> BrowserDownloadTracker.Entry {
        BrowserDownloadTracker.Entry(
            fileURL: URL(fileURLWithPath: "/Users/x/Downloads/\(fileName)"),
            agent: agent,
            fileName: fileName,
            fraction: fraction,
            startedAt: startedAt
        )
    }

    @Test
    func snapshotIsNilWithoutEntries() {
        let tracker = BrowserDownloadTracker()
        #expect(tracker.snapshot == nil)
    }

    @Test
    func activeEntryReportsProgressAndUnfinishedState() {
        var tracker = BrowserDownloadTracker()
        let token = UUID()
        tracker.insert(token: token, entry: entry())
        tracker.update(token: token, fraction: 0.42)

        #expect(tracker.snapshot?.fraction == 0.42)
        #expect(tracker.snapshot?.isFinished == false)
        #expect(tracker.snapshot?.progressText == "42%")
        #expect(tracker.snapshot?.agent == .chrome)
    }

    /// Intermediate files may land after progress is published; the source agent must be backfillable.
    @Test
    func agentCanBeResolvedAfterInsertion() {
        var tracker = BrowserDownloadTracker()
        let token = UUID()
        tracker.insert(token: token, entry: entry(agent: nil))
        #expect(tracker.snapshot?.agent == nil)

        tracker.update(token: token, agent: .safari)
        #expect(tracker.snapshot?.agent == .safari)
    }

    @Test
    func agentUpdateWithNilKeepsPreviouslyResolvedAgent() {
        var tracker = BrowserDownloadTracker()
        let token = UUID()
        tracker.insert(token: token, entry: entry(agent: .edge))
        tracker.update(token: token, agent: nil)

        #expect(tracker.snapshot?.agent == .edge)
    }

    @Test
    func successfulFinishHoldsCompletedSnapshot() {
        var tracker = BrowserDownloadTracker()
        let token = UUID()
        tracker.insert(token: token, entry: entry())

        let held = tracker.finish(token: token, succeeded: true)
        #expect(held)
        #expect(tracker.entries.isEmpty)
        #expect(tracker.snapshot?.isFinished == true)
        #expect(tracker.snapshot?.progressText == "100%")

        tracker.clearFinishedHold()
        #expect(tracker.snapshot == nil)
    }

    /// Cancel or failure shows no checkmark and disappears immediately.
    @Test
    func failedFinishLeavesNothingToDisplay() {
        var tracker = BrowserDownloadTracker()
        let token = UUID()
        tracker.insert(token: token, entry: entry())

        let held = tracker.finish(token: token, succeeded: false)
        #expect(held == false)
        #expect(tracker.snapshot == nil)
    }

    @Test
    func finishingUnknownTokenReportsNoHold() {
        var tracker = BrowserDownloadTracker()
        let held = tracker.finish(token: UUID(), succeeded: true)
        #expect(held == false)
        #expect(tracker.snapshot == nil)
    }

    /// Concurrent downloads preserve every item for the expanded dashboard and average progress for the compact island.
    @Test
    func concurrentDownloadsExposeItemsAndAverageProgress() {
        var tracker = BrowserDownloadTracker()
        let chrome = UUID()
        let safari = UUID()
        tracker.insert(
            token: chrome,
            entry: entry(
                agent: .chrome,
                fileName: "report.zip",
                fraction: 0.2,
                startedAt: Date(timeIntervalSince1970: 100)
            )
        )
        tracker.insert(
            token: safari,
            entry: entry(
                agent: .safari,
                fileName: "archive.dmg",
                fraction: 0.8,
                startedAt: Date(timeIntervalSince1970: 200)
            )
        )

        #expect(tracker.snapshots.map(\.id) == [safari, chrome])
        #expect(tracker.snapshots.map(\.agent) == [.safari, .chrome])
        #expect(tracker.snapshots.map(\.fileName) == ["archive.dmg", "report.zip"])
        #expect(tracker.snapshot?.agent == nil)
        #expect(tracker.snapshot?.fileName == "2 项下载")
        #expect(tracker.snapshot?.fraction == 0.5)
        #expect(tracker.snapshot?.progressText == "50%")

        _ = tracker.finish(token: safari, succeeded: true)
        // Prefer an in-progress download over a just-finished checkmark when one is still active.
        #expect(tracker.snapshot?.fileName == "report.zip")
        #expect(tracker.snapshot?.isFinished == false)
    }

    @Test
    func concurrentDownloadsIgnoreUnknownFractionsWhenAveraging() {
        var tracker = BrowserDownloadTracker()
        tracker.insert(token: UUID(), entry: entry(fileName: "known.zip", fraction: 0.4))
        tracker.insert(token: UUID(), entry: entry(fileName: "unknown.zip", fraction: nil))

        #expect(tracker.snapshot?.fraction == 0.4)
        #expect(tracker.snapshot?.progressText == "40%")
    }

    /// A newly started download immediately replaces the previous success hold state.
    @Test
    func newDownloadReplacesFinishedHold() {
        var tracker = BrowserDownloadTracker()
        let first = UUID()
        tracker.insert(token: first, entry: entry(fileName: "first.zip"))
        _ = tracker.finish(token: first, succeeded: true)
        #expect(tracker.snapshot?.isFinished == true)

        tracker.insert(token: UUID(), entry: entry(fileName: "second.zip"))
        #expect(tracker.snapshot?.fileName == "second.zip")
        #expect(tracker.snapshot?.isFinished == false)

        tracker.clearFinishedHold()
        #expect(tracker.snapshot?.fileName == "second.zip")
    }

    @Test
    func removeAllClearsEntriesAndHold() {
        var tracker = BrowserDownloadTracker()
        let token = UUID()
        tracker.insert(token: token, entry: entry())
        _ = tracker.finish(token: token, succeeded: true)
        tracker.removeAll()

        #expect(tracker.snapshot == nil)
        #expect(tracker.entries.isEmpty)
    }
}
