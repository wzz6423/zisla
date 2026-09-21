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

struct AirDropTransferMetadataParserTests {
    @Test
    func parsesCurrentAndLegacyFileMetadataKeys() {
        let destination = URL(fileURLWithPath: "/Users/test/Downloads", isDirectory: true)
        let completed = URL(fileURLWithPath: "/Users/test/Downloads/legacy.bin")

        let items = AirDropTransferMetadataParser.items(
            from: [
                ["fileName": "current.bin", "fileSize": NSNumber(value: 200)],
                ["FileName": "legacy.bin", "FileSize": NSNumber(value: 100)],
                ["FileName": NSNumber(value: 42), "FileSize": NSNumber(value: 50)],
                NSNull(),
            ],
            destinationURL: destination,
            completedURLs: [completed]
        )

        #expect(items.map(\.fileName) == ["current.bin", "legacy.bin"])
        #expect(items.map(\.expectedByteCount) == [200, 100])
        #expect(items.allSatisfy { $0.destinationURL == destination })
        #expect(items.allSatisfy { $0.completedURLs == [completed] })
    }

    @Test
    func missingOrInvalidSizeRemainsUnknown() throws {
        let items = AirDropTransferMetadataParser.items(
            from: [
                ["FileName": "missing.bin"],
                ["FileName": "invalid.bin", "FileSize": "100"],
            ],
            destinationURL: nil,
            completedURLs: []
        )

        #expect(items.count == 2)
        #expect(try #require(items.first { $0.fileName == "missing.bin" }).expectedByteCount == nil)
        #expect(try #require(items.first { $0.fileName == "invalid.bin" }).expectedByteCount == nil)
    }
}

struct AirDropItemProgressResolverTests {
    @Test
    func twoItemsUseTheirOwnWrittenByteCounts() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-airdrop-progress-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let firstURL = directory.appendingPathComponent("first.bin")
        let secondURL = directory.appendingPathComponent("second.bin")
        try Data(repeating: 1, count: 20).write(to: firstURL)
        try Data(repeating: 2, count: 80).write(to: secondURL)
        let first = AirDropTransferItem(
            fileName: "first.bin",
            expectedByteCount: 100,
            destinationURL: directory,
            completedURLs: []
        )
        let second = AirDropTransferItem(
            fileName: "second.bin",
            expectedByteCount: 100,
            destinationURL: directory,
            completedURLs: []
        )
        let byteCount: (URL) -> Int64? = {
            AirDropItemProgressResolver.fileByteCount(at: $0, fileManager: .default)
        }

        #expect(AirDropItemProgressResolver.fraction(for: first, progressFileURL: nil, fileByteCount: byteCount) == 0.2)
        #expect(AirDropItemProgressResolver.fraction(for: second, progressFileURL: nil, fileByteCount: byteCount) == 0.8)
    }

    @Test
    func explicitProgressFileURLIsUsedWhenPrivateDestinationIsUnavailable() {
        let fileURL = URL(fileURLWithPath: "/Users/test/Downloads/item.bin")
        let item = AirDropTransferItem(
            fileName: "item.bin",
            expectedByteCount: 200,
            destinationURL: nil,
            completedURLs: []
        )

        let fraction = AirDropItemProgressResolver.fraction(
            for: item,
            progressFileURL: fileURL,
            fileByteCount: { $0 == fileURL ? 50 : nil }
        )

        #expect(fraction == 0.25)
    }

    @Test
    func temporaryProgressFileTakesPriorityOverPrivateDestination() {
        let destination = URL(fileURLWithPath: "/Users/test/Downloads", isDirectory: true)
        let temporaryURL = destination.appendingPathComponent("item.bin.download")
        let item = AirDropTransferItem(
            fileName: "item.bin",
            expectedByteCount: 200,
            destinationURL: destination,
            completedURLs: []
        )
        var requestedURLs: [URL] = []

        let fraction = AirDropItemProgressResolver.fraction(
            for: item,
            progressFileURL: temporaryURL,
            fileByteCount: {
                requestedURLs.append($0)
                return $0 == temporaryURL ? 50 : 200
            }
        )

        #expect(fraction == 0.25)
        #expect(requestedURLs == [temporaryURL])
    }

    @Test
    func invalidSizeAndUnsafePathDoNotReadAnyFile() {
        var readCount = 0
        let read: (URL) -> Int64? = { _ in
            readCount += 1
            return 50
        }
        let destination = URL(fileURLWithPath: "/Users/test/Downloads", isDirectory: true)
        let invalidSizes: [Int64?] = [nil, 0, -1]
        for expectedByteCount in invalidSizes {
            let item = AirDropTransferItem(
                fileName: "item.bin",
                expectedByteCount: expectedByteCount,
                destinationURL: destination,
                completedURLs: []
            )
            #expect(AirDropItemProgressResolver.fraction(for: item, progressFileURL: nil, fileByteCount: read) == nil)
        }
        let traversal = AirDropTransferItem(
            fileName: "../outside.bin",
            expectedByteCount: 100,
            destinationURL: destination,
            completedURLs: []
        )
        #expect(AirDropItemProgressResolver.fraction(for: traversal, progressFileURL: nil, fileByteCount: read) == nil)
        #expect(readCount == 0)
    }

    @Test
    func nonFileDestinationAndUnrelatedCompletedURLAreRejected() {
        let item = AirDropTransferItem(
            fileName: "item.bin",
            expectedByteCount: 100,
            destinationURL: URL(string: "https://example.com/Downloads"),
            completedURLs: [URL(fileURLWithPath: "/Users/test/Downloads/other.bin")]
        )

        #expect(AirDropItemProgressResolver.privateFileURLs(for: item).isEmpty)
    }

    @Test
    func byteCountRejectsDirectoriesAndSymbolicLinks() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-airdrop-file-kind-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("target.bin")
        let link = directory.appendingPathComponent("link.bin")
        try Data([1, 2, 3]).write(to: target)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        #expect(AirDropItemProgressResolver.fileByteCount(at: target, fileManager: .default) == 3)
        #expect(AirDropItemProgressResolver.fileByteCount(at: directory, fileManager: .default) == nil)
        #expect(AirDropItemProgressResolver.fileByteCount(at: link, fileManager: .default) == nil)
    }

    @Test
    func writtenBytesAreCappedAtComplete() {
        let item = AirDropTransferItem(
            fileName: "item.bin",
            expectedByteCount: 100,
            destinationURL: URL(fileURLWithPath: "/Users/test/Downloads", isDirectory: true),
            completedURLs: []
        )

        #expect(AirDropItemProgressResolver.fraction(for: item, progressFileURL: nil, fileByteCount: { _ in 120 }) == 1)
    }
}

struct BrowserDownloadMonitorLifecycleTests {
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
        batchFraction: Double? = nil,
        startedAt: Date = Date()
    ) -> BrowserDownloadTracker.Entry {
        BrowserDownloadTracker.Entry(
            fileURL: URL(fileURLWithPath: "/Users/x/Downloads/\(fileName)"),
            agent: agent,
            fileName: fileName,
            fraction: fraction,
            batchFraction: batchFraction,
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
    func airDropBatchKeepsIndependentItemsAndUsesBatchOnlyForCompactSummary() {
        var tracker = BrowserDownloadTracker()
        let first = UUID()
        let second = UUID()
        tracker.insert(
            token: first,
            entry: entry(
                agent: .airDrop,
                fileName: "IMG_8239.HEIC",
                fraction: 0.2,
                batchFraction: 0.67,
                startedAt: Date(timeIntervalSince1970: 100)
            )
        )
        tracker.insert(
            token: second,
            entry: entry(
                agent: .airDrop,
                fileName: "IMG_8240.HEIC",
                fraction: 0.8,
                batchFraction: 0.67,
                startedAt: Date(timeIntervalSince1970: 200)
            )
        )

        #expect(tracker.snapshots.map(\.id) == [second, first])
        #expect(tracker.snapshots.map(\.fileName) == ["IMG_8240.HEIC", "IMG_8239.HEIC"])
        #expect(tracker.snapshots.map(\.fraction) == [0.8, 0.2])
        #expect(tracker.snapshot?.fileName == "2 项下载")
        #expect(tracker.snapshot?.fraction == 0.67)
    }

    @Test
    func unresolvedAirDropItemsDoNotReuseBatchProgress() {
        var tracker = BrowserDownloadTracker()
        let first = UUID()
        let second = UUID()
        tracker.insert(
            token: first,
            entry: entry(
                agent: .airDrop,
                fileName: "IMG_8239.HEIC",
                fraction: nil,
                batchFraction: 0.67,
                startedAt: Date(timeIntervalSince1970: 100)
            )
        )
        tracker.insert(
            token: second,
            entry: entry(
                agent: .airDrop,
                fileName: "IMG_8240.HEIC",
                fraction: nil,
                batchFraction: 0.67,
                startedAt: Date(timeIntervalSince1970: 200)
            )
        )

        #expect(tracker.snapshots.map(\.id) == [second, first])
        #expect(tracker.snapshots.allSatisfy { $0.fraction == nil })
        #expect(tracker.snapshots.allSatisfy { $0.progressText == "…" })
        #expect(tracker.snapshot?.fraction == 0.67)
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
