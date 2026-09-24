import Foundation
import Testing

@testable import ZislaCore
@testable import ZislaKit

struct BrowserDownloadAgentResolverTests {
    @Test
    func quarantineAgentNameMatchesDisplayNameShortNameAndBundleID() {
        #expect(BrowserDownloadAgentResolver.agent(forQuarantineAgentName: "AirDrop") == .airDrop)
        #expect(
            BrowserDownloadAgentResolver.agent(forQuarantineAgentName: "com.apple.sharingd")
                == .airDrop
        )
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
        #expect(
            BrowserDownloadAgentResolver.agent(
                forTempExtension: nil,
                runningBundleIdentifiers: ["com.apple.sharingd"]
            ) == nil
        )
    }

    @Test
    func airDropUsesDedicatedSymbol() {
        #expect(BrowserDownloadAgent.airDrop.displayName == "AirDrop")
        #expect(BrowserDownloadAgent.airDrop.symbolName == "dot.radiowaves.left.and.right")
        #expect(BrowserDownloadAgent.chrome.symbolName == "arrow.down.circle.fill")
    }

    @Test
    func receivingFileProgressResolvesToAirDrop() {
        #expect(
            BrowserDownloadAgentResolver.agent(forFileOperationKind: .receiving) == .airDrop
        )
        #expect(BrowserDownloadAgentResolver.agent(forFileOperationKind: .downloading) == nil)
        #expect(BrowserDownloadAgentResolver.agent(forFileOperationKind: nil) == nil)
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

struct AirDropBatchParserTests {
    @Test
    func parsesObservedModernReceiveTransferWithoutPerFileSizes() throws {
        let identifier = UUID()
        // The shape comes from a real macOS receive-transfer event; sender details are omitted.
        let payload: [String: Any] = [
            "receiveTransfers": [
                ["id": "request-key"],
                [
                    "receiveID": identifier.uuidString,
                    "startDate": 100.0,
                    "askRequest": ["items": [
                        ["fileName": "first.HEIC", "fileBomPath": "./NSIRD_sharingd_a/first.HEIC"],
                        ["fileName": "second.MOV", "fileBomPath": "./NSIRD_sharingd_b/second.MOV"],
                    ]],
                    "state": ["transferring": ["progress": ["transferring": [
                        "bytesCopied": 6_700, "totalBytes": 10_000, "filesCopied": 1,
                    ]]]],
                ],
            ],
            "sendTransfers": [],
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let batches = try #require(AirDropBatchParser.batches(from: data))

        #expect(batches.count == 1)
        #expect(batches[0].id == identifier)
        #expect(batches[0].fileNames == ["first.HEIC", "second.MOV"])
        #expect(batches[0].snapshot.fileName == "2 项下载")
        #expect(batches[0].snapshot.progressText == "67%")
    }

    @Test
    func emptyAndUnsupportedEventsAreDifferent() {
        #expect(AirDropBatchParser.batches(from: Data(#"{"receiveTransfers":[],"sendTransfers":[]}"#.utf8))?.isEmpty == true)
        #expect(AirDropBatchParser.batches(from: Data(#"{"sendTransfers":[]}"#.utf8)) == nil)
        #expect(AirDropBatchParser.batches(from: Data("invalid".utf8)) == nil)
    }

    @Test
    func ignoresRequestsThatHaveNotStartedReceiving() throws {
        let payload: [String: Any] = [
            "receiveTransfers": [[
                "receiveID": UUID().uuidString,
                "askRequest": ["items": [["fileName": "item.bin"]]],
                "state": ["awaitingAcceptance": [:]],
            ]]
        ]
        #expect(
            AirDropBatchParser.batches(from: try JSONSerialization.data(withJSONObject: payload))?.isEmpty == true
        )
    }
}

struct BrowserDownloadMonitorLifecycleTests {
    @Test(arguments: [Int64(9_990), 10_000])
    func cancelledProgressCannotCompleteATransfer(_ completed: Int64) {
        let progress = Progress(totalUnitCount: 10_000)
        progress.completedUnitCount = completed
        progress.cancel()
        #expect(!BrowserDownloadMonitor.completedSuccessfully(progress))
    }

    @Test
    func onlyFinishedProgressCompletesATransfer() {
        let progress = Progress(totalUnitCount: 10_000)
        progress.completedUnitCount = 9_990
        #expect(!BrowserDownloadMonitor.completedSuccessfully(progress))
        progress.completedUnitCount = 10_000
        #expect(BrowserDownloadMonitor.completedSuccessfully(progress))
    }

    @Test
    func staleCallbacksAreRejectedAfterStopAndRestart() {
        var lifecycle = BrowserDownloadMonitorLifecycle()
        let firstGeneration = lifecycle.start()
        #expect(lifecycle.accepts(firstGeneration))

        lifecycle.stop()
        #expect(!lifecycle.accepts(firstGeneration))

        let secondGeneration = lifecycle.start()
        #expect(!lifecycle.accepts(firstGeneration))
        #expect(lifecycle.accepts(secondGeneration))
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

    @Test
    func nonFiniteFractionFallsBackToUnknownProgress() {
        for fraction in [Double.nan, Double.infinity, -Double.infinity] {
            let value = snapshot(fraction: fraction)
            #expect(value.fraction == nil)
            #expect(value.progressText == "…")
        }

        var mutated = snapshot(fraction: 0.5)
        mutated.fraction = .nan
        #expect(mutated.progressText == "…")
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

struct BrowserDownloadFileURLPolicyTests {
    @Test
    func airDropKeepsTheURLCapturedForEachPublishedItem() {
        let first = URL(fileURLWithPath: "/Users/test/Downloads/first.bin")
        let second = URL(fileURLWithPath: "/Users/test/Downloads/second.bin")

        #expect(
            !BrowserDownloadMonitor.shouldReplacePublishedFileURL(
                first,
                with: second,
                agent: .airDrop
            )
        )
        #expect(
            BrowserDownloadMonitor.shouldReplacePublishedFileURL(
                nil,
                with: first,
                agent: .airDrop
            )
        )
    }

    @Test
    func browserCanAdoptALaterPublishedURL() {
        let first = URL(fileURLWithPath: "/Users/test/Downloads/report.pdf")
        let temporary = first.appendingPathExtension("crdownload")

        #expect(
            BrowserDownloadMonitor.shouldReplacePublishedFileURL(
                first,
                with: temporary,
                agent: .chrome
            )
        )
        #expect(
            !BrowserDownloadMonitor.shouldReplacePublishedFileURL(
                first,
                with: first,
                agent: .chrome
            )
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

    @Test(arguments: [0.66, 0.67])
    func repeatedAirDropItemPublicationsProduceOneBatchCard(fraction: Double) {
        var tracker = BrowserDownloadTracker()
        for index in 0..<210 {
            tracker.insert(
                token: UUID(),
                entry: entry(agent: .airDrop, fileName: "IMG_\(index).HEIC", fraction: fraction)
            )
        }

        #expect(tracker.snapshots.count == 1)
        #expect(tracker.snapshots[0].agent == .airDrop)
        #expect(tracker.snapshots[0].fileName == "210 项下载")
        #expect(tracker.snapshots[0].progressText == "\(Int(fraction * 100))%")
        #expect(tracker.snapshot?.fraction == fraction)
    }

    @Test
    func fallbackBatchKeepsItsIdentityAndCountDuringUnpublication() {
        var tracker = BrowserDownloadTracker()
        let first = UUID()
        let second = UUID()
        tracker.insert(token: first, entry: entry(agent: .airDrop, fileName: "first.bin", fraction: 0.4))
        tracker.insert(token: second, entry: entry(agent: .airDrop, fileName: "second.bin", fraction: 0.4))
        let batchID = tracker.snapshots.first?.id
        _ = tracker.finish(token: first, succeeded: true)

        #expect(tracker.snapshots.count == 1)
        #expect(tracker.snapshots.first?.id == batchID)
        #expect(tracker.snapshots.first?.fileName == "2 项下载")
        #expect(tracker.snapshots.first?.isFinished == false)

        _ = tracker.finish(token: second, succeeded: true)
        #expect(tracker.snapshots.first?.id == batchID)
        #expect(tracker.snapshots.first?.fileName == "2 项下载")
        #expect(tracker.snapshots.first?.progressText == "100%")
        #expect(tracker.snapshots.first?.isFinished == true)
    }

    @Test
    func realBatchIdentifiersKeepSimultaneousAirDropsSeparateWithoutDuplicatingFiles() {
        var tracker = BrowserDownloadTracker()
        let first = UUID()
        let second = UUID()
        tracker.insert(token: UUID(), entry: entry(agent: .airDrop, fileName: "a.bin", fraction: 0.2))
        tracker.insert(token: UUID(), entry: entry(agent: .airDrop, fileName: "b.bin", fraction: 0.2))
        tracker.insert(token: UUID(), entry: entry(agent: .airDrop, fileName: "c.bin", fraction: 0.8))
        tracker.updateAirDropBatches([
            AirDropBatch(id: first, fileNames: ["a.bin", "b.bin"], fraction: 0.2, startedAt: Date(timeIntervalSince1970: 100)),
            AirDropBatch(id: second, fileNames: ["c.bin"], fraction: 0.8, startedAt: Date(timeIntervalSince1970: 200)),
        ])

        #expect(tracker.snapshots.map(\.id) == [second, first])
        #expect(tracker.snapshots.map(\.progressText) == ["80%", "20%"])
        #expect(tracker.snapshots.map(\.fileName) == ["c.bin", "2 项下载"])

        tracker.updateAirDropBatches([])
        #expect(tracker.snapshots.count == 1)
        #expect(tracker.snapshots.first?.fileName == "3 项下载")
    }

    @Test
    func browserCardsRemainIndependentAlongsideAirDropBatch() {
        var tracker = BrowserDownloadTracker()
        tracker.insert(token: UUID(), entry: entry(agent: .airDrop, fileName: "a.bin", fraction: 0.6))
        tracker.insert(token: UUID(), entry: entry(agent: .airDrop, fileName: "b.bin", fraction: 0.6))
        tracker.insert(token: UUID(), entry: entry(agent: .chrome, fileName: "report.pdf", fraction: 0.2))
        tracker.insert(token: UUID(), entry: entry(agent: .chrome, fileName: "archive.zip", fraction: 0.8))

        #expect(tracker.snapshots.count == 3)
        #expect(tracker.snapshots.filter { $0.agent == .airDrop }.count == 1)
        #expect(Set(tracker.snapshots.filter { $0.agent == .chrome }.map(\.fileName)) == ["report.pdf", "archive.zip"])
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

    @Test
    func uniqueAgentsDeduplicatesAndSortsNewestFirst() {
        var tracker = BrowserDownloadTracker()
        tracker.insert(
            token: UUID(),
            entry: entry(
                agent: .chrome,
                fileName: "file1.zip",
                startedAt: Date(timeIntervalSince1970: 100)
            )
        )
        tracker.insert(
            token: UUID(),
            entry: entry(
                agent: .safari,
                fileName: "file2.zip",
                startedAt: Date(timeIntervalSince1970: 200)
            )
        )
        tracker.insert(
            token: UUID(),
            entry: entry(
                agent: .chrome,
                fileName: "file3.zip",
                startedAt: Date(timeIntervalSince1970: 300)
            )
        )

        #expect(tracker.uniqueAgents == [.chrome, .safari])
    }

    @Test
    func uniqueAgentsIgnoresNilAgents() {
        var tracker = BrowserDownloadTracker()
        tracker.insert(token: UUID(), entry: entry(agent: nil, fileName: "file1.zip"))
        tracker.insert(token: UUID(), entry: entry(agent: .firefox, fileName: "file2.zip"))
        tracker.insert(token: UUID(), entry: entry(agent: nil, fileName: "file3.zip"))

        #expect(tracker.uniqueAgents == [.firefox])
    }

    @Test
    func uniqueAgentsEmptyWhenNoEntries() {
        let tracker = BrowserDownloadTracker()
        #expect(tracker.uniqueAgents.isEmpty)
    }

    @Test
    func uniqueAgentsKeepsFinishedAgentDuringHold() {
        var tracker = BrowserDownloadTracker()
        let token = UUID()
        tracker.insert(token: token, entry: entry(agent: .safari))

        _ = tracker.finish(token: token, succeeded: true)

        #expect(tracker.uniqueAgents == [.safari])
    }
}

struct BrowserDownloadCompletionTrackerTests {
    private func entry(url: URL?, agent: BrowserDownloadAgent?) -> BrowserDownloadTracker.Entry {
        BrowserDownloadTracker.Entry(
            fileURL: url,
            agent: agent,
            fileName: url.map(BrowserDownloadAgentResolver.displayFileName) ?? "下载",
            fraction: 1,
            startedAt: Date(timeIntervalSince1970: 100)
        )
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-completed-transfer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test
    func chromeTemporaryNameResolvesToRenamedFinalFile() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let temporary = directory.appendingPathComponent("Unconfirmed 123.crdownload")
        let completed = directory.appendingPathComponent("report.pdf")
        let unrelated = directory.appendingPathComponent("Unconfirmed 123")
        try Data("older".utf8).write(to: unrelated)
        try Data("download".utf8).write(to: temporary)
        var tracker = BrowserDownloadCompletionTracker()
        let finishedAt = Date(timeIntervalSince1970: 200)

        tracker.record(token: UUID(), entry: entry(url: temporary, agent: .chrome), succeeded: true, at: finishedAt)
        #expect(tracker.resolve(at: finishedAt, directories: [directory], hasActiveAirDrop: false) == nil)
        try FileManager.default.moveItem(at: temporary, to: completed)

        let transfer = tracker.resolve(at: finishedAt, directories: [directory], hasActiveAirDrop: false)
        #expect(transfer?.fileName == "report.pdf")
        #expect(transfer?.directoryURL.resolvingSymlinksInPath() == directory.resolvingSymlinksInPath())
    }

    @Test
    func capturedTemporaryIdentitySurvivesRenameBeforeUnpublish() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let temporary = directory.appendingPathComponent("Unconfirmed 456.crdownload")
        let completed = directory.appendingPathComponent("invoice.pdf")
        try Data("download".utf8).write(to: temporary)
        let identity = try #require(BrowserDownloadFileIdentity(url: temporary))
        try FileManager.default.moveItem(at: temporary, to: completed)
        var finishedEntry = entry(url: temporary, agent: .chrome)
        finishedEntry.fileIdentity = identity
        var tracker = BrowserDownloadCompletionTracker()

        tracker.record(
            token: UUID(), entry: finishedEntry, succeeded: true,
            at: Date(timeIntervalSince1970: 200)
        )

        #expect(tracker.resolve(
            at: Date(timeIntervalSince1970: 200), directories: [directory], hasActiveAirDrop: false
        )?.fileName == "invoice.pdf")
    }

    @Test(arguments: ["crdownload", "download", "part", "opdownload"])
    func browserWaitsForTheFinalFileInsteadOfOpeningATemporaryDownload(_ suffix: String) throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let completed = directory.appendingPathComponent("report.pdf")
        let temporary = completed.appendingPathExtension(suffix)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
        var tracker = BrowserDownloadCompletionTracker()
        let finishedAt = Date(timeIntervalSince1970: 200)

        tracker.record(token: UUID(), entry: entry(url: temporary, agent: .chrome), succeeded: true, at: finishedAt)
        #expect(tracker.resolve(at: finishedAt, directories: [directory], hasActiveAirDrop: false) == nil)
        try Data("done".utf8).write(to: completed)
        let resolved = tracker.resolve(
            at: finishedAt.addingTimeInterval(0.5), directories: [directory], hasActiveAirDrop: false
        )
        let transfer = try #require(resolved)
        #expect(transfer.fileName == "report.pdf")
        #expect(transfer.directoryURL == directory)
        #expect(tracker.resolve(at: finishedAt.addingTimeInterval(1), directories: [directory], hasActiveAirDrop: false) == nil)
    }

    @Test
    func airDropWaitsForTheBatchAndTheFinalDestination() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let stagingDirectory = directory.appendingPathComponent("NSIRD_sharingd_123", isDirectory: true)
        try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: false)
        let staged = stagingDirectory.appendingPathComponent("photo.HEIC")
        try Data("photo".utf8).write(to: staged)
        var tracker = BrowserDownloadCompletionTracker()
        let finishedAt = Date(timeIntervalSince1970: 200)

        tracker.record(token: UUID(), entry: entry(url: staged, agent: .airDrop), succeeded: true, at: finishedAt)
        #expect(tracker.resolve(at: finishedAt, directories: [directory], hasActiveAirDrop: true) == nil)
        #expect(tracker.resolve(at: finishedAt, directories: [directory], hasActiveAirDrop: false) == nil)

        let finalURL = directory.appendingPathComponent("photo.HEIC")
        try FileManager.default.moveItem(at: staged, to: finalURL)
        let resolved = tracker.resolve(
            at: finishedAt.addingTimeInterval(1), directories: [directory], hasActiveAirDrop: false
        )
        let transfer = try #require(resolved)
        #expect(transfer.directoryURL == directory)
        #expect(transfer.fileName == "photo.HEIC")
    }

    @Test
    func failedMissingAndExpiredTransfersNeverPublishAFolder() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let missing = directory.appendingPathComponent("missing.pdf")
        var tracker = BrowserDownloadCompletionTracker()
        let finishedAt = Date(timeIntervalSince1970: 200)

        tracker.record(token: UUID(), entry: entry(url: missing, agent: .chrome), succeeded: false, at: finishedAt)
        tracker.record(token: UUID(), entry: entry(url: nil, agent: .chrome), succeeded: true, at: finishedAt)
        tracker.record(token: UUID(), entry: entry(url: missing, agent: nil), succeeded: true, at: finishedAt)
        #expect(!tracker.hasPending)

        tracker.record(token: UUID(), entry: entry(url: missing, agent: .chrome), succeeded: true, at: finishedAt)
        #expect(tracker.resolve(at: finishedAt, directories: [directory], hasActiveAirDrop: false) == nil)
        #expect(tracker.resolve(at: finishedAt.addingTimeInterval(11), directories: [directory], hasActiveAirDrop: false) == nil)
        try Data("late".utf8).write(to: missing)
        #expect(tracker.resolve(at: finishedAt.addingTimeInterval(11), directories: [directory], hasActiveAirDrop: false) == nil)
        #expect(!tracker.hasPending)
    }

    @Test
    func newestCompletedDownloadWinsEvenWhenAnotherDownloadIsStillActive() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("first.pdf")
        let second = directory.appendingPathComponent("second.pdf")
        try Data().write(to: first)
        try Data().write(to: second)
        var tracker = BrowserDownloadCompletionTracker()
        let finishedAt = Date(timeIntervalSince1970: 200)

        tracker.record(token: UUID(), entry: entry(url: first, agent: .chrome), succeeded: true, at: finishedAt)
        #expect(tracker.resolve(at: finishedAt, directories: [directory], hasActiveAirDrop: false)?.fileName == "first.pdf")
        tracker.record(token: UUID(), entry: entry(url: second, agent: .safari), succeeded: true, at: finishedAt)
        #expect(tracker.resolve(at: finishedAt, directories: [directory], hasActiveAirDrop: false)?.fileName == "second.pdf")
    }

    @Test
    func completedAirDropBatchDoesNotWaitForAnotherBatch() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("received.HEIC")
        try Data().write(to: file)
        let completedBatch = UUID()
        let activeBatch = UUID()
        let finishedAt = Date(timeIntervalSince1970: 200)
        var tracker = BrowserDownloadCompletionTracker()
        tracker.record(
            token: UUID(), entry: entry(url: file, agent: .airDrop), succeeded: true,
            airDropBatchID: completedBatch, at: finishedAt
        )
        #expect(tracker.resolve(
            at: finishedAt, directories: [directory], hasActiveAirDrop: true,
            activeAirDropBatchIDs: [completedBatch, activeBatch]
        ) == nil)
        #expect(tracker.resolve(
            at: finishedAt, directories: [directory], hasActiveAirDrop: true,
            activeAirDropBatchIDs: [activeBatch]
        )?.fileName == "received.HEIC")
    }

    @Test
    func oldPendingDownloadCannotReplaceANewerCompletedDownload() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let oldFile = directory.appendingPathComponent("old.pdf")
        let newFile = directory.appendingPathComponent("new.pdf")
        try Data().write(to: newFile)
        let finishedAt = Date(timeIntervalSince1970: 200)
        var tracker = BrowserDownloadCompletionTracker()
        tracker.record(token: UUID(), entry: entry(url: oldFile, agent: .chrome), succeeded: true, at: finishedAt)
        tracker.record(token: UUID(), entry: entry(url: newFile, agent: .safari), succeeded: true, at: finishedAt)
        #expect(tracker.resolve(at: finishedAt, directories: [directory], hasActiveAirDrop: false)?.fileName == "new.pdf")
        try Data().write(to: oldFile)
        #expect(tracker.resolve(at: finishedAt, directories: [directory], hasActiveAirDrop: false) == nil)
    }

    @Test
    func receivingBatchDoesNotConsumeTheFinalFileResolutionWindow() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("received.HEIC")
        try Data().write(to: file)
        let batch = UUID()
        let finishedAt = Date(timeIntervalSince1970: 200)
        var tracker = BrowserDownloadCompletionTracker()
        tracker.record(
            token: UUID(), entry: entry(url: file, agent: .airDrop), succeeded: true,
            airDropBatchID: batch, at: finishedAt
        )
        #expect(tracker.resolve(
            at: finishedAt, directories: [directory], hasActiveAirDrop: true,
            activeAirDropBatchIDs: [batch]
        ) == nil)
        #expect(tracker.resolve(
            at: finishedAt.addingTimeInterval(60), directories: [directory], hasActiveAirDrop: false
        )?.fileName == "received.HEIC")
    }

    @Test
    func airDropDoesNotResolveAnOldNamesakeWhileTheNewFileIsStillStaged() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let staging = directory.appendingPathComponent("NSIRD_sharingd_fixture", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
        let staged = staging.appendingPathComponent("photo.HEIC")
        try Data("new".utf8).write(to: staged)
        try Data("old".utf8).write(to: directory.appendingPathComponent("photo.HEIC"))
        let finishedAt = Date(timeIntervalSince1970: 200)
        var tracker = BrowserDownloadCompletionTracker()
        tracker.record(token: UUID(), entry: entry(url: staged, agent: .airDrop), succeeded: true, at: finishedAt)
        #expect(tracker.resolve(at: finishedAt, directories: [directory], hasActiveAirDrop: false) == nil)
    }

    @Test
    func nonFileURLsAndAirDropTraversalNeverResolveAFolder() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let finishedAt = Date(timeIntervalSince1970: 200)
        var tracker = BrowserDownloadCompletionTracker()
        tracker.record(
            token: UUID(), entry: entry(url: URL(string: "https://example.invalid/report.pdf"), agent: .chrome),
            succeeded: true, at: finishedAt
        )
        #expect(!tracker.hasPending)
        let downloads = directory.appendingPathComponent("downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: false)
        try Data("outside".utf8).write(to: directory.appendingPathComponent("outside.txt"))
        for name in ["../outside.txt", "/", ".", "..", ""] {
            tracker.removeAll()
            var malicious = entry(url: downloads.appendingPathComponent("NSIRD_fixture/missing"), agent: .airDrop)
            malicious.fileName = name
            tracker.record(token: UUID(), entry: malicious, succeeded: true, at: finishedAt)
            #expect(tracker.resolve(at: finishedAt, directories: [downloads], hasActiveAirDrop: false) == nil)
        }
    }

    @Test
    func stoppingClearsPendingCompletionWithoutReplayingIt() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("later.zip")
        var tracker = BrowserDownloadCompletionTracker()
        let finishedAt = Date(timeIntervalSince1970: 200)

        tracker.record(token: UUID(), entry: entry(url: file, agent: .chrome), succeeded: true, at: finishedAt)
        #expect(tracker.hasPending)
        tracker.removeAll()
        try Data().write(to: file)
        #expect(tracker.resolve(at: finishedAt, directories: [directory], hasActiveAirDrop: false) == nil)
    }
}
