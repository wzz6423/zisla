import Foundation
import SQLite3
import Testing

@testable import ZislaKit
@testable import ZislaCore

@MainActor
struct VoiceHistoryStoreTests {
    @Test
    func recordsAudioBackedEntryAndReloadsIt() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let store = fixture.makeStore()
        let id = UUID()
        let audioURL = store.recordingURL(for: id)
        try fixture.writeAudio(at: audioURL)
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)

        let recorded = store.record(VoiceRecordingResult(
            id: id,
            audioFileURL: audioURL,
            transcript: "  你好 Swift world  ",
            duration: 12.5,
            createdAt: createdAt
        ))

        #expect(recorded)
        let entry = try #require(store.entries.first)
        #expect(entry.id == id)
        #expect(entry.createdAt == createdAt)
        #expect(entry.duration == 12.5)
        #expect(entry.rawTranscript == "你好 Swift world")
        #expect(entry.processedTranscript == nil)
        #expect(entry.wordCount == 4)
        #expect(store.audioURL(for: entry) == audioURL.standardizedFileURL)

        let reloaded = fixture.makeStore()
        #expect(reloaded.entries == [entry])
        #expect(reloaded.errorDescription == nil)
    }

    @Test
    func computesWordCountSpeedAndSavedTypingTime() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let store = fixture.makeStore()
        let id = UUID()
        let audioURL = store.recordingURL(for: id)
        try fixture.writeAudio(at: audioURL)

        #expect(VoiceTranscriptMetrics.wordCount(in: "你好 Swift world 2026") == 5)
        #expect(store.record(VoiceRecordingResult(
            id: id,
            audioFileURL: audioURL,
            transcript: String(repeating: "你", count: 100),
            duration: 60
        )))

        #expect(store.statistics.totalWordCount == 100)
        #expect(store.statistics.totalDuration == 60)
        #expect(store.statistics.wordsPerMinute == 100)
        #expect(store.statistics.savedTime == 90)
    }

    @Test
    func nonFiniteRecordingDurationIsNormalizedBeforePersistence() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let store = fixture.makeStore()
        let id = UUID()
        let audioURL = store.recordingURL(for: id)
        try fixture.writeAudio(at: audioURL)

        #expect(store.record(VoiceRecordingResult(
            id: id,
            audioFileURL: audioURL,
            transcript: "有效文本",
            duration: .infinity
        )))

        #expect(store.entries.first?.duration == 0)
        #expect(fixture.makeStore().entries.first?.duration == 0)
    }

    @Test
    func shortDurationsKeepDisplayedSpeedWithinIntegerRange() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let store = fixture.makeStore()
        let id = UUID()
        let audioURL = store.recordingURL(for: id)
        try fixture.writeAudio(at: audioURL)
        #expect(store.record(VoiceRecordingResult(
            id: id,
            audioFileURL: audioURL,
            transcript: "word",
            duration: .leastNonzeroMagnitude
        )))

        #expect(store.statistics.wordsPerMinute.isFinite)
        #expect(store.statistics.wordsPerMinute.rounded() < Double(Int.max))
    }

    @Test
    func reloadNormalizesForgedStatisticsFields() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let id = UUID()
        let audioURL = fixture.recordingsDirectory.appendingPathComponent("\(id.uuidString).caf")
        try fixture.writeAudio(at: audioURL)
        let forged = VoiceHistoryEntry(
            id: id,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            duration: -10,
            rawTranscript: "你好 Swift",
            processedTranscript: "  整理文本  ",
            wordCount: .max,
            audioFileName: audioURL.lastPathComponent
        )
        try JSONEncoder().encode([forged]).write(to: fixture.metadataURL)

        let store = fixture.makeStore()

        #expect(store.entries.first?.duration == 0)
        #expect(store.entries.first?.wordCount == 3)
        #expect(store.entries.first?.processedTranscript == "整理文本")
        #expect(store.statistics.wordsPerMinute == 0)
    }

    @Test
    func updatesProcessedTranscriptAndPersistsIt() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let store = fixture.makeStore()
        let id = UUID()
        let audioURL = store.recordingURL(for: id)
        try fixture.writeAudio(at: audioURL)
        #expect(store.record(VoiceRecordingResult(
            id: id,
            audioFileURL: audioURL,
            transcript: "嗯明天开会",
            duration: 2
        )))

        #expect(store.updateProcessedTranscript(id: id, transcript: "明天开会。"))

        let reloaded = fixture.makeStore()
        #expect(reloaded.entries.first?.rawTranscript == "嗯明天开会")
        #expect(reloaded.entries.first?.processedTranscript == "明天开会。")
    }

    @Test
    func failedPersistenceDoesNotPublishNewEntry() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let store = fixture.makeStore()
        let id = UUID()
        let audioURL = store.recordingURL(for: id)
        try fixture.writeAudio(at: audioURL)
        try fixture.blockMetadataWrites()

        let recorded = store.record(VoiceRecordingResult(
            id: id,
            audioFileURL: audioURL,
            transcript: "明天十点开会",
            duration: 2
        ))

        #expect(!recorded)
        #expect(store.entries.isEmpty)
        #expect(FileManager.default.fileExists(atPath: audioURL.path))
        #expect(store.statistics.totalWordCount == 0)
        #expect(store.errorDescription != nil)
        #expect(fixture.makeStore().entries.isEmpty)

        try fixture.executeSQL("DROP TRIGGER fail_voice_state_update")
        #expect(store.record(VoiceRecordingResult(
            id: id,
            audioFileURL: audioURL,
            transcript: "明天十点开会",
            duration: 2
        )))
        #expect(store.errorDescription == nil)
        #expect(fixture.makeStore().entries == store.entries)
        #expect(fixture.makeStore().statistics == store.statistics)
    }

    @Test
    func failedPersistenceWithoutAudioRetentionKeepsAudioFile() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let store = fixture.makeStore()
        let id = UUID()
        let audioURL = store.recordingURL(for: id)
        try fixture.writeAudio(at: audioURL)
        try fixture.blockMetadataWrites()

        let recorded = store.record(VoiceRecordingResult(
            id: id,
            audioFileURL: audioURL,
            transcript: "仅保留文字",
            duration: 2
        ), retainAudio: false)

        #expect(!recorded)
        #expect(store.entries.isEmpty)
        #expect(FileManager.default.fileExists(atPath: audioURL.path))
    }

    @Test
    func failedProcessedTranscriptPersistenceKeepsPreviousEntry() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let store = fixture.makeStore()
        let id = UUID()
        let audioURL = store.recordingURL(for: id)
        try fixture.writeAudio(at: audioURL)
        #expect(store.record(VoiceRecordingResult(
            id: id,
            audioFileURL: audioURL,
            transcript: "嗯，明天十点开会",
            duration: 2
        )))
        try fixture.blockMetadataWrites()

        let updated = store.updateProcessedTranscript(id: id, transcript: "明天十点开会。")

        #expect(!updated)
        #expect(store.entries.first?.rawTranscript == "嗯，明天十点开会")
        #expect(store.entries.first?.processedTranscript == nil)
    }

    @Test
    func failedRemovalPersistenceKeepsEntriesAndAudioFiles() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let store = fixture.makeStore()
        let firstID = UUID()
        let secondID = UUID()
        let firstURL = store.recordingURL(for: firstID)
        let secondURL = store.recordingURL(for: secondID)
        try fixture.writeAudio(at: firstURL)
        try fixture.writeAudio(at: secondURL)
        #expect(store.record(VoiceRecordingResult(
            id: firstID,
            audioFileURL: firstURL,
            transcript: "第一条",
            duration: 1
        )))
        #expect(store.record(VoiceRecordingResult(
            id: secondID,
            audioFileURL: secondURL,
            transcript: "第二条",
            duration: 1
        )))
        try fixture.blockMetadataWrites()

        store.remove(id: firstID)

        #expect(store.entries.count == 2)
        #expect(FileManager.default.fileExists(atPath: firstURL.path))

        store.removeAll()

        #expect(store.entries.count == 2)
        #expect(FileManager.default.fileExists(atPath: firstURL.path))
        #expect(FileManager.default.fileExists(atPath: secondURL.path))
    }

    @Test
    func failedBatchRemovalPersistenceKeepsEntriesAndAudioFiles() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let store = fixture.makeStore()
        let ids = [UUID(), UUID()]
        for id in ids {
            let audioURL = store.recordingURL(for: id)
            try fixture.writeAudio(at: audioURL)
            #expect(store.record(VoiceRecordingResult(
                id: id,
                audioFileURL: audioURL,
                transcript: "保留记录",
                duration: 1
            )))
        }
        try fixture.blockMetadataWrites()

        store.removeBatch(ids: Set(ids))

        #expect(store.entries.count == 2)
        #expect(FileManager.default.fileExists(atPath: store.recordingURL(for: ids[0]).path))
        #expect(FileManager.default.fileExists(atPath: store.recordingURL(for: ids[1]).path))
    }

    @Test
    func failedAudioRemovalRestoresEntryAndMetadata() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let fileManager = FailingVoiceFileManager()
        let store = fixture.makeStore(fileManager: fileManager)
        let id = UUID()
        let audioURL = store.recordingURL(for: id)
        try fixture.writeAudio(at: audioURL)
        #expect(store.record(VoiceRecordingResult(
            id: id,
            audioFileURL: audioURL,
            transcript: "保留记录",
            duration: 1
        )))

        fileManager.blockedURL = audioURL
        store.remove(id: id)

        #expect(store.entries.count == 1)
        #expect(FileManager.default.fileExists(atPath: audioURL.path))
        #expect(fixture.makeStore().entries == store.entries)
        #expect(store.errorDescription != nil)
    }

    @Test
    func batchRemovalRetainsOnlyTheEntryWhoseStagedAudioCannotBeDeleted() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let fileManager = FailingVoiceFileManager()
        let store = fixture.makeStore(fileManager: fileManager)
        let firstID = UUID()
        let secondID = UUID()
        let firstURL = store.recordingURL(for: firstID)
        let secondURL = store.recordingURL(for: secondID)
        try fixture.writeAudio(at: firstURL)
        try fixture.writeAudio(at: secondURL)
        #expect(store.record(VoiceRecordingResult(
            id: firstID,
            audioFileURL: firstURL,
            transcript: "第一条",
            duration: 1,
            createdAt: Date(timeIntervalSince1970: 2)
        )))
        #expect(store.record(VoiceRecordingResult(
            id: secondID,
            audioFileURL: secondURL,
            transcript: "第二条",
            duration: 1,
            createdAt: Date(timeIntervalSince1970: 1)
        )))

        fileManager.blockedStagedRemovalFileName = secondURL.lastPathComponent
        store.removeBatch(ids: [firstID, secondID])

        #expect(store.entries.map(\.id) == [secondID])
        #expect(!FileManager.default.fileExists(atPath: firstURL.path))
        #expect(FileManager.default.fileExists(atPath: secondURL.path))
        #expect(fixture.makeStore().entries == store.entries)
        #expect(store.errorDescription != nil)
    }

    @Test
    func partialBatchRemovalKeepsSelectedTextOnlyEntries() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let fileManager = FailingVoiceFileManager()
        let store = fixture.makeStore(fileManager: fileManager)
        let textID = UUID()
        let firstID = UUID()
        let secondID = UUID()
        let textURL = store.recordingURL(for: textID)
        let firstURL = store.recordingURL(for: firstID)
        let secondURL = store.recordingURL(for: secondID)
        try fixture.writeAudio(at: textURL)
        try fixture.writeAudio(at: firstURL)
        try fixture.writeAudio(at: secondURL)
        #expect(store.record(VoiceRecordingResult(
            id: textID,
            audioFileURL: textURL,
            transcript: "仅文字",
            duration: 1,
            createdAt: Date(timeIntervalSince1970: 3)
        ), retainAudio: false))
        #expect(store.record(VoiceRecordingResult(
            id: firstID,
            audioFileURL: firstURL,
            transcript: "第一条",
            duration: 1,
            createdAt: Date(timeIntervalSince1970: 2)
        )))
        #expect(store.record(VoiceRecordingResult(
            id: secondID,
            audioFileURL: secondURL,
            transcript: "第二条",
            duration: 1,
            createdAt: Date(timeIntervalSince1970: 1)
        )))

        fileManager.blockedStagedRemovalFileName = secondURL.lastPathComponent
        store.removeBatch(ids: [textID, firstID, secondID])

        #expect(store.entries.map(\.id) == [textID, secondID])
        #expect(!FileManager.default.fileExists(atPath: firstURL.path))
        #expect(FileManager.default.fileExists(atPath: secondURL.path))
        #expect(fixture.makeStore().entries == store.entries)
    }

    @Test
    func removeAllRetainsOnlyTextAndRestoredAudioWhenSecondStagedRemovalFails() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let fileManager = FailingVoiceFileManager()
        let store = fixture.makeStore(fileManager: fileManager)
        let textID = UUID()
        let firstID = UUID()
        let secondID = UUID()
        let textURL = store.recordingURL(for: textID)
        let firstURL = store.recordingURL(for: firstID)
        let secondURL = store.recordingURL(for: secondID)
        try fixture.writeAudio(at: textURL)
        try fixture.writeAudio(at: firstURL)
        try fixture.writeAudio(at: secondURL)
        #expect(store.record(VoiceRecordingResult(
            id: textID,
            audioFileURL: textURL,
            transcript: "仅文字",
            duration: 1,
            createdAt: Date(timeIntervalSince1970: 3)
        ), retainAudio: false))
        #expect(store.record(VoiceRecordingResult(
            id: firstID,
            audioFileURL: firstURL,
            transcript: "第一条",
            duration: 1,
            createdAt: Date(timeIntervalSince1970: 2)
        )))
        #expect(store.record(VoiceRecordingResult(
            id: secondID,
            audioFileURL: secondURL,
            transcript: "第二条",
            duration: 1,
            createdAt: Date(timeIntervalSince1970: 1)
        )))

        fileManager.stagedRemovalFailureIndex = 2
        store.removeAll()

        let restoredAudioIDs = [firstID, secondID].filter {
            FileManager.default.fileExists(atPath: store.recordingURL(for: $0).path)
        }
        let restoredAudioID = try #require(restoredAudioIDs.first)
        #expect(restoredAudioIDs.count == 1)
        #expect(store.entries.map(\.id) == [textID, restoredAudioID])
        #expect(fixture.makeStore().entries == store.entries)
        #expect(store.errorDescription != nil)
    }

    @Test(arguments: ["remove", "batch", "clear", "cleanup", "discard", "orphan"])
    func missingStagedFileDoesNotRollBackCompletedDeletion(_ operation: String) throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let fileManager = FailingVoiceFileManager()
        let store = fixture.makeStore(fileManager: fileManager)
        let id = UUID()
        let audioURL = operation == "orphan"
            ? fixture.recordingsDirectory.appendingPathComponent("orphan.caf")
            : store.recordingURL(for: id)
        try fixture.writeAudio(at: audioURL)
        let recording = VoiceRecordingResult(
            id: id, audioFileURL: audioURL, transcript: "removed", duration: 2,
            createdAt: Date(timeIntervalSince1970: 1)
        )
        if operation != "discard" && operation != "orphan" { #expect(store.record(recording)) }
        fileManager.stagedRemovalFailureIndex = 1
        fileManager.removeBeforeReportingFailure = true

        switch operation {
        case "remove": store.remove(id: id)
        case "batch": store.removeBatch(ids: [id])
        case "clear", "orphan": store.removeAll()
        case "cleanup": store.cleanupOldRecordings(policy: .sevenDays, now: Date(timeIntervalSince1970: 2_000_000_000))
        case "discard": #expect(store.record(recording, retainAudio: false))
        default: Issue.record("unexpected operation")
        }

        #expect(store.errorDescription == nil)
        #expect(store.entries.count == (["cleanup", "discard"].contains(operation) ? 1 : 0))
        #expect(store.entries.allSatisfy { $0.audioFileName == nil })
        #expect(store.statistics.totalWordCount == (operation == "orphan" ? 0 : 1))
        #expect(!FileManager.default.fileExists(atPath: audioURL.path))
        #expect(fixture.makeStore().entries == store.entries)
        #expect(fixture.makeStore().statistics == store.statistics)
    }

    @Test(arguments: [false, true])
    func unreadableStagedFileIsNotTreatedAsAlreadyDeleted(nonCocoaError: Bool) throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let fileManager = FailingVoiceFileManager()
        let store = fixture.makeStore(fileManager: fileManager)
        let id = UUID()
        let audioURL = store.recordingURL(for: id)
        try fixture.writeAudio(at: audioURL)
        #expect(store.record(.init(id: id, audioFileURL: audioURL, transcript: "retained", duration: 2)))
        let original = store.entries
        fileManager.stagedRemovalFailureIndex = 1
        fileManager.stagedRestorationFailureIndex = 1
        fileManager.stagedAttributesError = nonCocoaError
            ? VoiceSQLiteTestError(message: "injected unknown attributes failure")
            : CocoaError(.fileReadNoPermission)

        store.remove(id: id)

        #expect(store.errorDescription != nil)
        #expect(store.entries == original)
        let stagedURL = try #require(fileManager.stagedRemovalURLs.last)
        #expect(FileManager.default.fileExists(atPath: stagedURL.path))
        #expect(fixture.makeStore().entries == original)
        #expect(FileManager.default.fileExists(atPath: audioURL.path))
    }

    @Test
    func removeAllCompensationExcludesAnotherStagedFileThatDisappeared() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let fileManager = FailingVoiceFileManager()
        let store = fixture.makeStore(fileManager: fileManager)
        for _ in 0..<3 {
            let id = UUID()
            let audioURL = store.recordingURL(for: id)
            try fixture.writeAudio(at: audioURL)
            #expect(store.record(.init(id: id, audioFileURL: audioURL, transcript: "retained", duration: 2)))
        }
        let original = store.entries
        var disappearedFileName: String?
        fileManager.stagedRemovalFailureIndex = 1
        fileManager.beforeStagedRemovalFailure = { failedURL in
            let other = try #require(FileManager.default.contentsOfDirectory(at: fixture.recordingsDirectory, includingPropertiesForKeys: nil)
                .first { $0.lastPathComponent.hasPrefix(".zisla-deleting-") && $0 != failedURL })
            disappearedFileName = String(other.lastPathComponent.dropFirst(".zisla-deleting-".count + 37))
            try FileManager.default.removeItem(at: other)
        }

        store.removeAll()

        let disappeared = try #require(disappearedFileName)
        #expect(store.errorDescription != nil)
        #expect(store.entries == original.filter { $0.audioFileName != disappeared })
        #expect(store.entries.allSatisfy { store.audioURL(for: $0) != nil })
        #expect(fixture.makeStore().entries == store.entries)
    }

    @Test
    func removingEntriesAlsoRemovesTheirAudioFiles() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let store = fixture.makeStore()
        let firstID = UUID()
        let secondID = UUID()
        let firstURL = store.recordingURL(for: firstID)
        let secondURL = store.recordingURL(for: secondID)
        try fixture.writeAudio(at: firstURL)
        try fixture.writeAudio(at: secondURL)
        #expect(store.record(VoiceRecordingResult(
            id: firstID,
            audioFileURL: firstURL,
            transcript: "第一条",
            duration: 1
        )))
        #expect(store.record(VoiceRecordingResult(
            id: secondID,
            audioFileURL: secondURL,
            transcript: "第二条",
            duration: 1
        )))

        store.remove(id: firstID)

        #expect(!FileManager.default.fileExists(atPath: firstURL.path))
        #expect(FileManager.default.fileExists(atPath: secondURL.path))
        #expect(store.entries.map(\.id) == [secondID])

        store.removeAll()

        #expect(store.entries.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: secondURL.path))
        #expect(fixture.makeStore().entries.isEmpty)
    }

    @Test
    func rejectsAudioOutsideTheRecordingDirectory() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let store = fixture.makeStore()
        let id = UUID()
        let outsideURL = fixture.root.appendingPathComponent("\(id.uuidString).caf")
        try Data("outside".utf8).write(to: outsideURL)

        let recorded = store.record(VoiceRecordingResult(
            id: id,
            audioFileURL: outsideURL,
            transcript: "不应记录",
            duration: 1
        ))

        #expect(!recorded)
        #expect(store.entries.isEmpty)
        #expect(store.errorDescription != nil)
        #expect(FileManager.default.fileExists(atPath: outsideURL.path))
    }

    @Test
    func repeatedRecordingIDIsIdempotent() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let store = fixture.makeStore()
        let id = UUID()
        let audioURL = store.recordingURL(for: id)
        try fixture.writeAudio(at: audioURL)
        let recording = VoiceRecordingResult(
            id: id,
            audioFileURL: audioURL,
            transcript: "同一条",
            duration: 1
        )

        #expect(store.record(recording))
        #expect(store.record(recording))

        #expect(store.entries.count == 1)
    }

    @Test
    func cumulativeDurationRemainsFiniteWhenLargeValidDurationsAreRecorded() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let store = fixture.makeStore()
        let firstID = UUID()
        let secondID = UUID()
        let firstURL = store.recordingURL(for: firstID)
        let secondURL = store.recordingURL(for: secondID)
        try fixture.writeAudio(at: firstURL)
        try fixture.writeAudio(at: secondURL)

        #expect(store.record(VoiceRecordingResult(
            id: firstID,
            audioFileURL: firstURL,
            transcript: "第一条",
            duration: .greatestFiniteMagnitude
        )))
        #expect(store.record(VoiceRecordingResult(
            id: secondID,
            audioFileURL: secondURL,
            transcript: "第二条",
            duration: .greatestFiniteMagnitude
        )))

        #expect(store.statistics.totalDuration == .greatestFiniteMagnitude)
        #expect(store.statistics.totalDuration.isFinite)
    }

    @Test
    func removeAllDeletesOrphanedAudioButKeepsUnrelatedFiles() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let store = fixture.makeStore()
        let orphanedAudio = fixture.recordingsDirectory.appendingPathComponent("orphaned.caf")
        let unrelatedFile = fixture.recordingsDirectory.appendingPathComponent("keep.txt")
        try fixture.writeAudio(at: orphanedAudio)
        try Data("keep".utf8).write(to: unrelatedFile)

        store.removeAll()

        #expect(!FileManager.default.fileExists(atPath: orphanedAudio.path))
        #expect(FileManager.default.fileExists(atPath: unrelatedFile.path))
    }

    @Test
    func corruptMetadataAndUnicodeChaosDoNotCrash() throws {
        let payloads = [
            Data(),
            Data("null".utf8),
            Data("{}".utf8),
            Data("[{\"id\":true}]".utf8),
            Data([0xFF, 0x00, 0x7B]),
        ]
        for payload in payloads {
            let fixture = try makeFixture()
            defer { fixture.cleanup() }
            try payload.write(to: fixture.metadataURL)

            let store = fixture.makeStore()

            #expect(store.entries.isEmpty)
            #expect(store.errorDescription != nil)
        }

        let samples = [
            "",
            "\u{0000}\u{0008}\n\t",
            "🎙️🙂👨‍👩‍👧‍👦",
            "e\u{301} café 中文 한글",
            String(repeating: "语音 mixed_123 ", count: 1_000),
        ]
        for sample in samples {
            let count = VoiceTranscriptMetrics.wordCount(in: sample)
            #expect(count >= 0)
            #expect(count <= sample.unicodeScalars.count)
        }
    }

    @Test
    func corruptMetadataCannotBeOverwrittenByNewRecordings() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let originalData = Data("{\"entries\":[{\"rawTranscript\":\"recoverable text\"}".utf8)
        try originalData.write(to: fixture.metadataURL)
        let store = fixture.makeStore()
        let id = UUID()
        let audioURL = store.recordingURL(for: id)
        try fixture.writeAudio(at: audioURL)

        #expect(!store.record(VoiceRecordingResult(
            id: id,
            audioFileURL: audioURL,
            transcript: "new recording",
            duration: 1
        ), retainAudio: false))

        #expect(store.entries.isEmpty)
        #expect(store.statistics.totalWordCount == 0)
        #expect(store.errorDescription != nil)
        #expect(try Data(contentsOf: fixture.metadataURL) == originalData)
        #expect(FileManager.default.fileExists(atPath: audioURL.path))
    }

    @Test
    func legacyMigrationPreservesSourceAndDoesNotResurrectClearedHistory() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let entry = VoiceHistoryEntry(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            duration: 12,
            rawTranscript: "legacy recording",
            processedTranscript: nil,
            wordCount: 2,
            audioFileName: nil
        )
        let originalData = try JSONEncoder().encode([entry])
        try originalData.write(to: fixture.metadataURL)

        let store = fixture.makeStore()

        #expect(store.entries == [entry])
        #expect(try Data(contentsOf: fixture.metadataURL) == originalData)
        #expect(FileManager.default.fileExists(atPath: fixture.databaseURL.path))

        store.removeAll()

        let reloaded = fixture.makeStore()
        #expect(reloaded.entries.isEmpty)
        #expect(reloaded.statistics.totalWordCount == 2)
        #expect(reloaded.statistics.totalDuration == 12)
        #expect(try Data(contentsOf: fixture.metadataURL) == originalData)
    }

    @Test
    func staleNoOpRemovalCannotDeleteAnotherStoresNewAudio() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let stale = fixture.makeStore()
        let writer = fixture.makeStore()
        let id = UUID()
        let audioURL = writer.recordingURL(for: id)
        try fixture.writeAudio(at: audioURL)
        #expect(writer.record(VoiceRecordingResult(
            id: id, audioFileURL: audioURL, transcript: "new recording", duration: 2
        )))

        stale.removeAll()

        #expect(stale.errorDescription != nil)
        #expect(FileManager.default.fileExists(atPath: audioURL.path))
        #expect(fixture.makeStore().entries == writer.entries)
        #expect(fixture.makeStore().statistics == writer.statistics)
    }

    @Test
    func duplicateLegacyIDsDoNotPublishOrCommitPartialHistory() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let entry = VoiceHistoryEntry(
            id: UUID(), createdAt: Date(timeIntervalSince1970: 1), duration: 2,
            rawTranscript: "duplicate", processedTranscript: nil, wordCount: 1, audioFileName: nil
        )
        let originalData = try JSONEncoder().encode([entry, entry])
        try originalData.write(to: fixture.metadataURL)

        let store = fixture.makeStore()

        #expect(store.errorDescription != nil)
        #expect(store.entries.isEmpty)
        #expect(store.statistics.totalWordCount == 0)
        #expect(try Data(contentsOf: fixture.metadataURL) == originalData)
        let database = try VoiceHistoryDatabase(storageURL: fixture.databaseURL, fileManager: .default)
        #expect(try database.load() == nil)
    }

    @Test(arguments: ["[]", "{\"entries\":[],\"cumulativeStatistics\":{\"totalWordCount\":0,\"totalDuration\":0}}"])
    func emptyLegacyFormatsMigrateWithoutChangingSource(_ json: String) throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let data = Data(json.utf8)
        try data.write(to: fixture.metadataURL)

        let store = fixture.makeStore()

        #expect(store.errorDescription == nil)
        #expect(store.entries.isEmpty)
        #expect(store.statistics.totalWordCount == 0)
        #expect(FileManager.default.fileExists(atPath: fixture.databaseURL.path))
        #expect(fixture.makeStore().errorDescription == nil)
        #expect(try Data(contentsOf: fixture.metadataURL) == data)
    }

    @Test
    func wrappedLegacyFormatPreservesLifetimeTotalsAndSource() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let entry = VoiceHistoryEntry(
            id: UUID(), createdAt: Date(timeIntervalSince1970: 1), duration: 2,
            rawTranscript: "remaining record", processedTranscript: "整理结果", wordCount: 2, audioFileName: nil
        )
        let state = VoiceHistoryPersistentState(
            entries: [entry], cumulativeStatistics: .init(totalWordCount: 100, totalDuration: 90)
        )
        let data = try JSONEncoder().encode(state)
        try data.write(to: fixture.metadataURL)

        let store = fixture.makeStore()

        #expect(store.entries == [entry])
        #expect(store.statistics.totalWordCount == 100)
        #expect(store.statistics.totalDuration == 90)
        store.removeAll()
        let reloaded = fixture.makeStore()
        #expect(reloaded.entries.isEmpty)
        #expect(reloaded.statistics == store.statistics)
        #expect(try Data(contentsOf: fixture.metadataURL) == data)
    }

    @Test
    func failedMigrationRollsBackEntriesAndCanRetryAfterReopening() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let entry = VoiceHistoryEntry(
            id: UUID(), createdAt: Date(timeIntervalSince1970: 1), duration: 2,
            rawTranscript: "legacy", processedTranscript: nil, wordCount: 1, audioFileName: nil
        )
        let data = try JSONEncoder().encode([entry])
        try data.write(to: fixture.metadataURL)
        let database = try VoiceHistoryDatabase(storageURL: fixture.databaseURL, fileManager: .default)
        #expect(try database.load() == nil)
        try fixture.executeSQL("""
            CREATE TRIGGER fail_voice_migration BEFORE INSERT ON voice_history_state
            BEGIN SELECT RAISE(ABORT, 'injected migration failure'); END;
            """)

        let failed = fixture.makeStore()

        #expect(failed.entries.isEmpty)
        #expect(failed.errorDescription != nil)
        #expect(try database.load() == nil)
        #expect(try Data(contentsOf: fixture.metadataURL) == data)
        try fixture.executeSQL("DROP TRIGGER fail_voice_migration")

        let id = UUID()
        let audioURL = failed.recordingURL(for: id)
        try fixture.writeAudio(at: audioURL)
        #expect(!failed.record(VoiceRecordingResult(
            id: id, audioFileURL: audioURL, transcript: "must reopen", duration: 1
        ), retainAudio: false))
        #expect(FileManager.default.fileExists(atPath: audioURL.path))
        let recovered = fixture.makeStore()
        #expect(recovered.errorDescription == nil)
        #expect(recovered.entries == [entry])
        #expect(recovered.statistics.totalWordCount == 1)
        #expect(try Data(contentsOf: fixture.metadataURL) == data)
    }

    @Test
    func staleWritesRollBackEntriesStatisticsAndAudioDeletion() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let first = fixture.makeStore()
        let stale = fixture.makeStore()
        let firstID = UUID()
        let secondID = UUID()
        let firstURL = first.recordingURL(for: firstID)
        let secondURL = first.recordingURL(for: secondID)
        try fixture.writeAudio(at: firstURL)
        try fixture.writeAudio(at: secondURL)
        #expect(first.record(VoiceRecordingResult(
            id: firstID, audioFileURL: firstURL, transcript: "first", duration: 2
        )))
        let secondRecording = VoiceRecordingResult(
            id: secondID, audioFileURL: secondURL, transcript: "second", duration: 3
        )

        #expect(!stale.record(secondRecording, retainAudio: false))

        #expect(stale.errorDescription != nil)
        #expect(stale.entries.isEmpty)
        #expect(stale.statistics.totalWordCount == 0)
        #expect(FileManager.default.fileExists(atPath: secondURL.path))
        let recovered = fixture.makeStore()
        #expect(recovered.entries == first.entries)
        #expect(recovered.statistics == first.statistics)
        #expect(recovered.record(secondRecording))
        #expect(!first.updateProcessedTranscript(id: firstID, transcript: "stale edit"))
        #expect(fixture.makeStore().entries == recovered.entries)
        #expect(recovered.statistics.totalWordCount == 2)
        #expect(recovered.statistics.totalDuration == 5)
    }

    @Test
    func competingInitialMigrationsCannotOverwriteTheCommittedState() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let first = try VoiceHistoryDatabase(storageURL: fixture.databaseURL, fileManager: .default)
        let second = try VoiceHistoryDatabase(storageURL: fixture.databaseURL, fileManager: .default)
        #expect(try first.load() == nil)
        #expect(try second.load() == nil)
        let entry = VoiceHistoryEntry(
            id: UUID(), createdAt: Date(timeIntervalSince1970: 1), duration: 2,
            rawTranscript: "first", processedTranscript: nil, wordCount: 1, audioFileName: nil
        )
        let state = VoiceHistoryPersistentState(
            entries: [entry], cumulativeStatistics: .init(totalWordCount: 1, totalDuration: 2)
        )
        try first.save(state)

        #expect(throws: (any Error).self) {
            try second.save(.init(entries: [], cumulativeStatistics: .init(totalWordCount: 0, totalDuration: 0)))
        }

        #expect(try second.load()?.entries == [entry])
        #expect(try second.load()?.cumulativeStatistics == state.cumulativeStatistics)
    }

    @Test
    func incrementalWritesLeaveUnchangedHistoryUntouched() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let entries = (0..<1_024).map { index in
            VoiceHistoryEntry(
                id: UUID(), createdAt: Date(timeIntervalSince1970: Double(index)), duration: 2,
                rawTranscript: String(repeating: "history ", count: 128),
                processedTranscript: nil, wordCount: 128, audioFileName: nil
            )
        }
        let source = try JSONEncoder().encode(entries)
        try source.write(to: fixture.metadataURL)
        let store = fixture.makeStore()
        let changedID = entries[0].id
        try fixture.executeSQL("""
            CREATE TRIGGER protect_unchanged_update BEFORE UPDATE ON voice_history_entries
            WHEN OLD.id != '\(changedID.uuidString)'
            BEGIN SELECT RAISE(ABORT, 'unchanged entry was rewritten'); END;
            CREATE TRIGGER protect_unchanged_delete BEFORE DELETE ON voice_history_entries
            WHEN OLD.id != '\(changedID.uuidString)'
            BEGIN SELECT RAISE(ABORT, 'unchanged entry was removed'); END;
            """)

        for index in 0..<16 {
            #expect(store.updateProcessedTranscript(id: changedID, transcript: "edit \(index)"))
        }
        let addedID = UUID()
        let audioURL = store.recordingURL(for: addedID)
        try fixture.writeAudio(at: audioURL)
        #expect(store.record(VoiceRecordingResult(
            id: addedID, audioFileURL: audioURL, transcript: "new", duration: 1
        )))
        store.remove(id: changedID)
        #expect(store.errorDescription == nil)
        #expect(store.entries.count == 1_024)
        #expect(store.statistics.totalWordCount == 1_024 * 128 + 1)
        #expect(fixture.makeStore().entries == store.entries)
        #expect(try Data(contentsOf: fixture.metadataURL) == source)
    }

    @Test
    func unchangedWritesAndReloadsDoNotRewriteCommittedState() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let store = fixture.makeStore()
        let id = UUID()
        let audioURL = store.recordingURL(for: id)
        try fixture.writeAudio(at: audioURL)
        let recording = VoiceRecordingResult(
            id: id, audioFileURL: audioURL, transcript: "same", duration: 2,
            createdAt: Date(timeIntervalSince1970: 1)
        )
        #expect(store.record(recording))
        try fixture.blockMetadataWrites()

        #expect(store.record(recording))
        #expect(store.updateProcessedTranscript(id: id, transcript: " \n"))
        #expect(store.errorDescription == nil)
        #expect(fixture.makeStore().errorDescription == nil)
        #expect(fixture.makeStore().entries == store.entries)
        #expect(store.statistics.totalWordCount == 1)
        #expect(store.statistics.totalDuration == 2)
    }

    @Test(arguments: [
        "PRAGMA user_version = 2; PRAGMA journal_mode = DELETE;",
        "DELETE FROM voice_history_state;",
        "DELETE FROM voice_history_state; DELETE FROM voice_history_entries;",
        "PRAGMA user_version = 0;",
        "PRAGMA user_version = 0; DELETE FROM voice_history_state;",
        "UPDATE voice_history_entries SET id = 'mismatched-id';",
        "UPDATE voice_history_entries SET payload = X'7B';",
        "UPDATE voice_history_entries SET payload = X'';",
        "UPDATE voice_history_state SET statistics = X'7B';",
        "DROP TABLE voice_history_state;",
        """
        ALTER TABLE voice_history_state RENAME TO saved_state;
        CREATE TABLE voice_history_state AS SELECT id, NULL AS revision, statistics FROM saved_state;
        DROP TABLE saved_state;
        """,
        """
        ALTER TABLE voice_history_entries RENAME TO saved_entries;
        CREATE TABLE voice_history_entries AS SELECT NULL AS id, payload FROM saved_entries;
        DROP TABLE saved_entries;
        """,
        """
        ALTER TABLE voice_history_entries RENAME TO saved_entries;
        CREATE TABLE voice_history_entries AS SELECT * FROM saved_entries;
        INSERT INTO voice_history_entries SELECT * FROM saved_entries;
        DROP TABLE saved_entries;
        """,
    ])
    func invalidDatabaseStateNeverFallsBackToLegacyJSON(_ damageSQL: String) throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let entry = VoiceHistoryEntry(
            id: UUID(), createdAt: Date(timeIntervalSince1970: 1), duration: 2,
            rawTranscript: "archived", processedTranscript: nil, wordCount: 1, audioFileName: nil
        )
        let data = try JSONEncoder().encode([entry])
        try data.write(to: fixture.metadataURL)
        #expect(fixture.makeStore().entries == [entry])
        try fixture.executeSQL(damageSQL)
        let databaseBytes = try Data(contentsOf: fixture.databaseURL)

        let store = fixture.makeStore()

        #expect(store.errorDescription != nil)
        #expect(store.entries.isEmpty)
        let id = UUID()
        let audioURL = store.recordingURL(for: id)
        try fixture.writeAudio(at: audioURL)
        #expect(!store.record(VoiceRecordingResult(
            id: id, audioFileURL: audioURL, transcript: "new", duration: 1
        ), retainAudio: false))
        #expect(FileManager.default.fileExists(atPath: audioURL.path))
        #expect(try Data(contentsOf: fixture.metadataURL) == data)
        #expect(fixture.makeStore().errorDescription != nil)
        #expect(try Data(contentsOf: fixture.databaseURL) == databaseBytes)
    }

    @Test(arguments: [Data("not a database".utf8), Data("SQLite format 3\0truncated".utf8)])
    func corruptDatabaseBytesRemainUntouched(_ data: Data) throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        try data.write(to: fixture.databaseURL)
        try Data("[]".utf8).write(to: fixture.metadataURL)

        let store = fixture.makeStore()

        #expect(store.entries.isEmpty)
        #expect(store.errorDescription != nil)
        store.removeAll()
        #expect(try Data(contentsOf: fixture.databaseURL) == data)
        #expect(try Data(contentsOf: fixture.metadataURL) == Data("[]".utf8))
    }

    @Test
    func writeLockFailureCanRecoverInTheSameStore() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let store = fixture.makeStore()
        let id = UUID()
        let audioURL = store.recordingURL(for: id)
        try fixture.writeAudio(at: audioURL)
        let recording = VoiceRecordingResult(
            id: id, audioFileURL: audioURL, transcript: "retry", duration: 2
        )
        var lock: OpaquePointer?
        #expect(sqlite3_open(fixture.databaseURL.path, &lock) == SQLITE_OK)
        defer { sqlite3_close(lock) }
        #expect(sqlite3_exec(lock, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK)

        #expect(!store.record(recording, retainAudio: false))
        #expect(store.entries.isEmpty)
        #expect(store.errorDescription != nil)
        #expect(FileManager.default.fileExists(atPath: audioURL.path))
        #expect(sqlite3_exec(lock, "ROLLBACK", nil, nil, nil) == SQLITE_OK)

        #expect(store.record(recording, retainAudio: false))
        #expect(store.errorDescription == nil)
        #expect(!FileManager.default.fileExists(atPath: audioURL.path))
        #expect(fixture.makeStore().entries == store.entries)
        #expect(fixture.makeStore().statistics == store.statistics)
    }

    @Test
    func readSnapshotDoesNotBlockAnotherStoresCommit() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let store = fixture.makeStore()
        var reader: OpaquePointer?
        #expect(sqlite3_open(fixture.databaseURL.path, &reader) == SQLITE_OK)
        defer { sqlite3_close(reader) }
        #expect(sqlite3_exec(reader, "BEGIN; SELECT * FROM voice_history_state", nil, nil, nil) == SQLITE_OK)
        let id = UUID()
        let audioURL = store.recordingURL(for: id)
        try fixture.writeAudio(at: audioURL)

        #expect(store.record(VoiceRecordingResult(
            id: id, audioFileURL: audioURL, transcript: "concurrent write", duration: 2
        )))

        var statement: OpaquePointer?
        #expect(sqlite3_prepare_v2(reader, "SELECT COUNT(*) FROM voice_history_entries", -1, &statement, nil) == SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        #expect(sqlite3_step(statement) == SQLITE_ROW)
        #expect(sqlite3_column_int(statement, 0) == 0)
        #expect(sqlite3_reset(statement) == SQLITE_OK)
        #expect(sqlite3_exec(reader, "COMMIT", nil, nil, nil) == SQLITE_OK)
        #expect(sqlite3_step(statement) == SQLITE_ROW)
        #expect(sqlite3_column_int(statement, 0) == 1)
        #expect(fixture.makeStore().entries == store.entries)
    }

    @Test
    func invalidRecordingDateDoesNotPublishAndCanBeRetried() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let store = fixture.makeStore()
        let id = UUID()
        let audioURL = store.recordingURL(for: id)
        try fixture.writeAudio(at: audioURL)
        var recording = VoiceRecordingResult(
            id: id, audioFileURL: audioURL, transcript: "valid transcript", duration: 2,
            createdAt: Date(timeIntervalSince1970: .infinity)
        )

        #expect(!store.record(recording, retainAudio: false))

        #expect(store.entries.isEmpty)
        #expect(store.statistics.totalWordCount == 0)
        #expect(store.errorDescription != nil)
        #expect(FileManager.default.fileExists(atPath: audioURL.path))
        recording.createdAt = Date(timeIntervalSince1970: 1)
        #expect(store.record(recording))
        #expect(fixture.makeStore().entries == store.entries)
    }

    @Test
    func databaseOpenFailureDoesNotOverwriteLegacyData() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        try Data("[]".utf8).write(to: fixture.metadataURL)
        try FileManager.default.createDirectory(at: fixture.databaseURL, withIntermediateDirectories: true)

        let failed = fixture.makeStore()

        #expect(failed.errorDescription != nil)
        #expect(failed.entries.isEmpty)
        #expect(try Data(contentsOf: fixture.metadataURL) == Data("[]".utf8))
        try FileManager.default.removeItem(at: fixture.databaseURL)
        #expect(fixture.makeStore().errorDescription == nil)
    }

    @Test
    func boundedUnicodeAndDurationCorpusRoundTrips() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let store = fixture.makeStore()
        let pieces = ["word ", "中文", "e\u{301}", "👨‍👩‍👧‍👦", "\u{0000}", " \n\t", "한글"]
        let durations: [TimeInterval] = [0, -1, .infinity, .nan, .leastNonzeroMagnitude, 1, 12.5]
        var seed: UInt64 = 0xA117_C0DE
        for index in 0..<32 {
            let id = UUID()
            let audioURL = store.recordingURL(for: id)
            try fixture.writeAudio(at: audioURL)
            var transcript = ""
            for _ in 0..<(index % 8) {
                seed = seed &* 6_364_136_223_846_793_005 &+ 1
                transcript += pieces[Int(seed % UInt64(pieces.count))]
            }
            #expect(store.record(VoiceRecordingResult(
                id: id, audioFileURL: audioURL, transcript: transcript,
                duration: durations[index % durations.count],
                createdAt: Date(timeIntervalSince1970: Double(index))
            ), retainAudio: false))
            #expect(store.statistics.wordsPerMinute.isFinite)
            #expect(!FileManager.default.fileExists(atPath: audioURL.path))
            let reloaded = fixture.makeStore()
            #expect(reloaded.errorDescription == nil)
            #expect(reloaded.entries == store.entries)
            #expect(reloaded.statistics == store.statistics)
        }
        #expect(!FileManager.default.fileExists(atPath: fixture.metadataURL.path))
    }

    @Test(arguments: [false, true])
    func interruptedStagingIsRecoveredBeforeNormalizingAudioReferences(legacy: Bool) throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let id = UUID()
        let audioURL = fixture.recordingsDirectory.appendingPathComponent("\(id.uuidString).caf")
        try fixture.writeAudio(at: audioURL)
        let entry = VoiceHistoryEntry(
            id: id, createdAt: Date(timeIntervalSince1970: 1), duration: 2,
            rawTranscript: "recoverable", processedTranscript: nil, wordCount: 1,
            audioFileName: audioURL.lastPathComponent
        )
        try JSONEncoder().encode([entry]).write(to: fixture.metadataURL)
        if !legacy { #expect(fixture.makeStore().entries == [entry]) }
        let stagedURL = try fixture.stageAudio(at: audioURL)

        let recovered = fixture.makeStore()

        #expect(recovered.errorDescription == nil)
        #expect(recovered.entries == [entry])
        #expect(recovered.audioURL(for: entry) == audioURL)
        #expect(!FileManager.default.fileExists(atPath: stagedURL.path))
        #expect(fixture.makeStore().entries == [entry])
    }

    @Test(arguments: ["remove", "batch", "clear", "cleanup", "discard", "orphan"])
    func committedAudioDeletionResumesAfterReopening(_ operation: String) throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let fileManager = FailingVoiceFileManager()
        let store = fixture.makeStore(fileManager: fileManager)
        let ids = [UUID(), UUID()]
        var originalURLs: [URL] = []
        if operation == "orphan" {
            let audioURL = fixture.recordingsDirectory.appendingPathComponent("orphan.caf")
            originalURLs.append(audioURL)
            try fixture.writeAudio(at: audioURL)
        } else {
            for id in ids {
                let audioURL = store.recordingURL(for: id)
                originalURLs.append(audioURL)
                try fixture.writeAudio(at: audioURL)
                #expect(store.record(.init(
                    id: id, audioFileURL: audioURL, transcript: "retained text", duration: 2,
                    createdAt: Date(timeIntervalSince1970: 1)
                ), retainAudio: operation != "discard"))
            }
        }
        switch operation {
        case "remove": for id in ids { store.remove(id: id) }
        case "batch": store.removeBatch(ids: Set(ids))
        case "clear", "orphan": store.removeAll()
        case "cleanup": store.cleanupOldRecordings(policy: .sevenDays, now: Date(timeIntervalSince1970: 2_000_000_000))
        default: break
        }
        #expect(store.errorDescription == nil)
        // Recreate only the last committed operation's residue; earlier operations had already finished.
        let lastStaged = try #require(fileManager.stagedRemovalURLs.last)
        let revisionPrefix = lastStaged.lastPathComponent.prefix(".zisla-deleting-".count + 36)
        let residue = fileManager.stagedRemovalURLs.filter { $0.lastPathComponent.hasPrefix(revisionPrefix) }
        for url in residue { try fixture.writeAudio(at: url) }

        let recovered = fixture.makeStore()

        #expect(recovered.errorDescription == nil)
        #expect(recovered.entries == store.entries)
        #expect(recovered.statistics == store.statistics)
        #expect(originalURLs.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
        #expect(residue.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    }

    @Test
    func loadingDuringRemovalCannotClearTemporarilyMissingAudio() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let fileManager = FailingVoiceFileManager()
        let store = fixture.makeStore(fileManager: fileManager)
        let id = UUID()
        let audioURL = store.recordingURL(for: id)
        try fixture.writeAudio(at: audioURL)
        #expect(store.record(.init(id: id, audioFileURL: audioURL, transcript: "retained", duration: 2)))
        var reader: VoiceHistoryStore?
        fileManager.afterStaging = { reader = fixture.makeStore() }

        store.remove(id: id)

        #expect(reader?.errorDescription != nil)
        #expect(store.errorDescription == nil)
        #expect(store.entries.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: audioURL.path))
        #expect(fixture.makeStore().entries.isEmpty)
    }

    @Test
    func existingInstanceRecoversUncommittedAudioBeforeWriting() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let store = fixture.makeStore()
        let id = UUID()
        let audioURL = store.recordingURL(for: id)
        try fixture.writeAudio(at: audioURL)
        let stagedURL = try fixture.stageAudio(at: audioURL)

        #expect(store.record(.init(id: id, audioFileURL: audioURL, transcript: "recovered", duration: 2)))

        #expect(store.errorDescription == nil)
        #expect(FileManager.default.fileExists(atPath: audioURL.path))
        #expect(!FileManager.default.fileExists(atPath: stagedURL.path))
        #expect(fixture.makeStore().entries == store.entries)
    }

    @Test
    func failedOrphanCompensationCanResumeRestoringAudio() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let fileManager = FailingVoiceFileManager()
        let store = fixture.makeStore(fileManager: fileManager)
        let audioURL = fixture.recordingsDirectory.appendingPathComponent("orphan.caf")
        try fixture.writeAudio(at: audioURL)
        fileManager.stagedRemovalFailureIndex = 1
        fileManager.stagedRestorationFailureIndex = 1

        store.removeAll()

        #expect(store.errorDescription != nil)
        #expect(!FileManager.default.fileExists(atPath: audioURL.path))
        let recovered = fixture.makeStore()
        #expect(recovered.errorDescription == nil)
        #expect(recovered.entries.isEmpty)
        #expect(FileManager.default.fileExists(atPath: audioURL.path))
    }

    @Test(arguments: ["remove", "batch", "clear", "cleanup", "discard", "orphan"])
    func failedCompensationKeepsCommittedDeletionForRecovery(_ operation: String) throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let fileManager = FailingVoiceFileManager()
        let store = fixture.makeStore(fileManager: fileManager)
        let id = UUID()
        let audioURL = operation == "orphan"
            ? fixture.recordingsDirectory.appendingPathComponent("orphan.caf")
            : store.recordingURL(for: id)
        try fixture.writeAudio(at: audioURL)
        let recording = VoiceRecordingResult(
            id: id, audioFileURL: audioURL, transcript: "retained", duration: 2,
            createdAt: Date(timeIntervalSince1970: 1)
        )
        if operation != "discard" && operation != "orphan" { #expect(store.record(recording)) }
        try fixture.executeSQL("""
            CREATE TABLE commit_attempts (count INTEGER NOT NULL);
            INSERT INTO commit_attempts VALUES(0);
            CREATE TRIGGER fail_compensation BEFORE UPDATE ON voice_history_state
            BEGIN
                UPDATE commit_attempts SET count = count + 1;
                SELECT RAISE(ABORT, 'injected compensation failure') WHERE (SELECT count FROM commit_attempts) > 1;
            END;
            """)
        fileManager.stagedRemovalFailureIndex = 1

        switch operation {
        case "remove": store.remove(id: id)
        case "batch": store.removeBatch(ids: [id])
        case "clear", "orphan": store.removeAll()
        case "cleanup": store.cleanupOldRecordings(policy: .sevenDays, now: Date(timeIntervalSince1970: 2_000_000_000))
        case "discard": #expect(!store.record(recording, retainAudio: false))
        default: Issue.record("unexpected operation")
        }

        #expect(store.errorDescription != nil)
        #expect(store.entries.count == (["cleanup", "discard"].contains(operation) ? 1 : 0))
        #expect(store.entries.allSatisfy { $0.audioFileName == nil })
        #expect(!FileManager.default.fileExists(atPath: audioURL.path))
        let stagedURL = try #require(fileManager.stagedRemovalURLs.last)
        #expect(FileManager.default.fileExists(atPath: stagedURL.path))
        let recovered = fixture.makeStore()
        #expect(recovered.errorDescription == nil)
        #expect(recovered.entries == store.entries)
        #expect(recovered.statistics == store.statistics)
        #expect(!FileManager.default.fileExists(atPath: stagedURL.path))
    }

    @Test
    func staleInstanceCannotRestoreAnotherWritersCommittedAudioDeletion() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let fileManager = FailingVoiceFileManager()
        let writer = fixture.makeStore(fileManager: fileManager)
        let id = UUID()
        let audioURL = writer.recordingURL(for: id)
        try fixture.writeAudio(at: audioURL)
        #expect(writer.record(.init(id: id, audioFileURL: audioURL, transcript: "retained", duration: 2)))
        let stale = fixture.makeStore()
        try fixture.executeSQL("""
            CREATE TRIGGER fail_compensation BEFORE UPDATE ON voice_history_state
            WHEN (SELECT COUNT(*) FROM voice_history_entries) > 0
            BEGIN SELECT RAISE(ABORT, 'injected compensation failure'); END;
            """)
        fileManager.stagedRemovalFailureIndex = 1
        writer.remove(id: id)
        let stagedURL = try #require(fileManager.stagedRemovalURLs.last)

        #expect(!stale.updateProcessedTranscript(id: id, transcript: "stale"))

        #expect(stale.errorDescription != nil)
        #expect(!FileManager.default.fileExists(atPath: audioURL.path))
        #expect(FileManager.default.fileExists(atPath: stagedURL.path))
        #expect(fixture.makeStore().entries.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: stagedURL.path))
    }

    @Test(arguments: [false, true])
    func interruptedRecoveryCanResumeWithoutDroppingReferences(committed: Bool) throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let fileManager = FailingVoiceFileManager()
        let store = fixture.makeStore(fileManager: fileManager)
        var audioURLs: [URL] = []
        for _ in 0..<2 {
            let id = UUID()
            let audioURL = store.recordingURL(for: id)
            audioURLs.append(audioURL)
            try fixture.writeAudio(at: audioURL)
            #expect(store.record(.init(id: id, audioFileURL: audioURL, transcript: "retained", duration: 2)))
        }
        if committed {
            store.removeAll()
            for url in fileManager.stagedRemovalURLs { try fixture.writeAudio(at: url) }
        } else {
            for url in audioURLs { _ = try fixture.stageAudio(at: url) }
        }
        let interruptedManager = FailingVoiceFileManager()
        interruptedManager.stagedRemovalFailureIndex = committed ? 2 : nil
        interruptedManager.stagedRestorationFailureIndex = committed ? nil : 2

        let interrupted = fixture.makeStore(fileManager: interruptedManager)

        #expect(interrupted.errorDescription != nil)
        let recovered = fixture.makeStore()
        #expect(recovered.errorDescription == nil)
        #expect(recovered.entries == store.entries)
        #expect(audioURLs.allSatisfy { FileManager.default.fileExists(atPath: $0.path) != committed })
    }

    @Test
    func recoveryDestinationConflictPreservesBothFilesAndReleasesLock() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let store = fixture.makeStore()
        let id = UUID()
        let audioURL = store.recordingURL(for: id)
        try fixture.writeAudio(at: audioURL)
        #expect(store.record(.init(id: id, audioFileURL: audioURL, transcript: "retained", duration: 2)))
        let stagedURL = try fixture.stageAudio(at: audioURL)
        try Data("newer audio".utf8).write(to: audioURL)

        let conflicted = fixture.makeStore()

        #expect(conflicted.errorDescription != nil)
        #expect(try Data(contentsOf: audioURL) == Data("newer audio".utf8))
        #expect(try Data(contentsOf: stagedURL) == Data("audio".utf8))
        try FileManager.default.removeItem(at: audioURL)
        #expect(fixture.makeStore().entries == store.entries)
    }

    @Test
    func malformedStagingNamesRemainUntouchedDuringRecovery() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let names = [
            "unrelated.txt",
            ".zisla-deleting-not-a-uuid.audio.caf",
            ".zisla-deleting-00000000-0000-0000-0000-000000000002",
            ".zisla-deleting-00000000-0000-0000-0000-000000000002.",
        ]
        for name in names { try fixture.writeAudio(at: fixture.recordingsDirectory.appendingPathComponent(name)) }

        let recovered = fixture.makeStore()

        #expect(recovered.errorDescription == nil)
        for name in names {
            #expect(try Data(contentsOf: fixture.recordingsDirectory.appendingPathComponent(name)) == Data("audio".utf8))
        }
    }

    @Test
    func recoveryDirectoryReadFailurePreservesHistoryAndReleasesLock() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let fileManager = FailingVoiceFileManager()
        let store = fixture.makeStore(fileManager: fileManager)
        let id = UUID()
        let audioURL = store.recordingURL(for: id)
        try fixture.writeAudio(at: audioURL)
        #expect(store.record(.init(id: id, audioFileURL: audioURL, transcript: "retained", duration: 2)))
        let original = store.entries
        let stagedURL = try fixture.stageAudio(at: audioURL)
        fileManager.failRecoveryDirectoryRead = true

        #expect(!store.updateProcessedTranscript(id: id, transcript: "blocked"))
        #expect(fixture.makeStore(fileManager: fileManager).errorDescription != nil)
        #expect(store.entries == original)
        #expect(FileManager.default.fileExists(atPath: stagedURL.path))

        fileManager.failRecoveryDirectoryRead = false
        #expect(fixture.makeStore().entries == original)
        #expect(store.updateProcessedTranscript(id: id, transcript: "retry"))
        #expect(!FileManager.default.fileExists(atPath: stagedURL.path))
    }

    @Test
    func allMutationPathsReleaseTheLockAfterContentionAndFailure() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let store = fixture.makeStore()
        let id = UUID()
        let audioURL = store.recordingURL(for: id)
        try fixture.writeAudio(at: audioURL)
        let recording = VoiceRecordingResult(id: id, audioFileURL: audioURL, transcript: "retained", duration: 2, createdAt: Date(timeIntervalSince1970: 1))
        #expect(store.record(recording))
        let original = store.entries
        do {
            let locker = try VoiceHistoryDatabase(storageURL: fixture.databaseURL, fileManager: .default)
            try locker.lock()
            defer { locker.unlock() }
            #expect(!store.record(recording))
            #expect(!store.updateProcessedTranscript(id: id, transcript: "blocked"))
            store.remove(id: id)
            store.removeBatch(ids: [id])
            store.removeAll()
            store.cleanupOldRecordings(policy: .sevenDays, now: Date(timeIntervalSince1970: 2_000_000_000))
            #expect(store.errorDescription != nil)
            #expect(store.entries == original)
            #expect(FileManager.default.fileExists(atPath: audioURL.path))
        }
        #expect(store.updateProcessedTranscript(id: id, transcript: "after lock"))
        try fixture.blockMetadataWrites()
        #expect(!store.updateProcessedTranscript(id: id, transcript: "failed write"))
        try fixture.executeSQL("DROP TRIGGER fail_voice_state_update")
        #expect(fixture.makeStore().errorDescription == nil)
        #expect(store.updateProcessedTranscript(id: id, transcript: "retry"))
    }

    @Test
    func recordWithoutAudioRetentionKeepsTranscriptAfterReload() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let store = fixture.makeStore()
        let id = UUID()
        let audioURL = store.recordingURL(for: id)
        try fixture.writeAudio(at: audioURL)

        #expect(store.record(VoiceRecordingResult(
            id: id,
            audioFileURL: audioURL,
            transcript: "仅保留文字",
            duration: 2
        ), retainAudio: false))

        let entry = try #require(store.entries.first)
        #expect(entry.audioFileName == nil)
        #expect(!FileManager.default.fileExists(atPath: audioURL.path))
        #expect(fixture.makeStore().entries == [entry])
    }

    @Test
    func finiteCleanupPoliciesRemoveOnlyExpiredAudioAndPersistTextHistory() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let day: TimeInterval = 24 * 60 * 60
        let policies: [(VoiceRecordingCleanupPolicy, Int)] = [
            (.sevenDays, 7),
            (.fifteenDays, 15),
            (.thirtyDays, 30),
        ]

        for (policy, days) in policies {
            let fixture = try makeFixture()
            defer { fixture.cleanup() }
            let store = fixture.makeStore()
            let expiredID = UUID()
            let currentID = UUID()
            let expiredURL = store.recordingURL(for: expiredID)
            let currentURL = store.recordingURL(for: currentID)
            try fixture.writeAudio(at: expiredURL)
            try fixture.writeAudio(at: currentURL)

            #expect(store.record(VoiceRecordingResult(
                id: expiredID,
                audioFileURL: expiredURL,
                transcript: "过期录音文字",
                duration: 1,
                createdAt: now.addingTimeInterval(-Double(days + 1) * day)
            )))
            #expect(store.record(VoiceRecordingResult(
                id: currentID,
                audioFileURL: currentURL,
                transcript: "保留录音文字",
                duration: 1,
                createdAt: now.addingTimeInterval(-Double(days - 1) * day)
            )))

            store.cleanupOldRecordings(policy: policy, now: now)

            #expect(!FileManager.default.fileExists(atPath: expiredURL.path))
            #expect(FileManager.default.fileExists(atPath: currentURL.path))
            #expect(store.entries.first(where: { $0.id == expiredID })?.audioFileName == nil)
            #expect(fixture.makeStore().entries.count == 2)
        }
    }

    @Test
    func failedCleanupPersistenceKeepsAudioReferenceAndFile() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let store = fixture.makeStore()
        let id = UUID()
        let audioURL = store.recordingURL(for: id)
        try fixture.writeAudio(at: audioURL)
        #expect(store.record(VoiceRecordingResult(
            id: id,
            audioFileURL: audioURL,
            transcript: "保留过期录音",
            duration: 1,
            createdAt: Date(timeIntervalSince1970: 1)
        )))
        try fixture.blockMetadataWrites()

        store.cleanupOldRecordings(
            policy: .sevenDays,
            now: Date(timeIntervalSince1970: 2_000_000_000)
        )

        #expect(store.entries.first?.audioFileName == audioURL.lastPathComponent)
        #expect(FileManager.default.fileExists(atPath: audioURL.path))
    }

    @Test
    func neverCleanupPolicyKeepsOldAudio() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let store = fixture.makeStore()
        let id = UUID()
        let audioURL = store.recordingURL(for: id)
        try fixture.writeAudio(at: audioURL)
        #expect(store.record(VoiceRecordingResult(
            id: id,
            audioFileURL: audioURL,
            transcript: "长期保留",
            duration: 1,
            createdAt: Date(timeIntervalSince1970: 1)
        )))

        store.cleanupOldRecordings(policy: .never, now: Date(timeIntervalSince1970: 2_000_000_000))

        #expect(FileManager.default.fileExists(atPath: audioURL.path))
    }

    @Test
    func removingEntriesRetainsCumulativeStatistics() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let store = fixture.makeStore()
        let firstID = UUID()
        let secondID = UUID()
        let firstURL = store.recordingURL(for: firstID)
        let secondURL = store.recordingURL(for: secondID)
        try fixture.writeAudio(at: firstURL)
        try fixture.writeAudio(at: secondURL)
        #expect(store.record(VoiceRecordingResult(
            id: firstID,
            audioFileURL: firstURL,
            transcript: String(repeating: "你", count: 100),
            duration: 60
        )))
        #expect(store.record(VoiceRecordingResult(
            id: secondID,
            audioFileURL: secondURL,
            transcript: String(repeating: "好", count: 50),
            duration: 30
        )))

        #expect(store.statistics.totalWordCount == 150)
        #expect(store.statistics.totalDuration == 90)

        store.remove(id: firstID)

        #expect(store.entries.count == 1)
        #expect(store.statistics.totalWordCount == 150)
        #expect(store.statistics.totalDuration == 90)

        let reloaded = fixture.makeStore()
        #expect(reloaded.statistics.totalWordCount == 150)
        #expect(reloaded.statistics.totalDuration == 90)
        #expect(reloaded.entries.count == 1)
    }

    @Test
    func removeAllRetainsCumulativeStatistics() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let store = fixture.makeStore()
        let id = UUID()
        let audioURL = store.recordingURL(for: id)
        try fixture.writeAudio(at: audioURL)
        #expect(store.record(VoiceRecordingResult(
            id: id,
            audioFileURL: audioURL,
            transcript: String(repeating: "测", count: 200),
            duration: 120
        )))

        #expect(store.statistics.totalWordCount == 200)

        store.removeAll()

        #expect(store.entries.isEmpty)
        #expect(store.statistics.totalWordCount == 200)
        #expect(store.statistics.totalDuration == 120)
        #expect(!FileManager.default.fileExists(atPath: audioURL.path))

        let reloaded = fixture.makeStore()
        #expect(reloaded.entries.isEmpty)
        #expect(reloaded.statistics.totalWordCount == 200)
        #expect(reloaded.statistics.totalDuration == 120)
    }

    @Test
    func batchRemovalRetainsCumulativeStatistics() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let store = fixture.makeStore()
        let ids = (0..<3).map { _ in UUID() }
        for id in ids {
            let audioURL = store.recordingURL(for: id)
            try fixture.writeAudio(at: audioURL)
            #expect(store.record(VoiceRecordingResult(
                id: id,
                audioFileURL: audioURL,
                transcript: String(repeating: "词", count: 10),
                duration: 10
            )))
        }

        #expect(store.statistics.totalWordCount == 30)
        #expect(store.statistics.totalDuration == 30)

        store.removeBatch(ids: Set([ids[0], ids[1]]))

        #expect(store.entries.count == 1)
        #expect(store.statistics.totalWordCount == 30)
        #expect(store.statistics.totalDuration == 30)
        #expect(!FileManager.default.fileExists(atPath: store.recordingURL(for: ids[0]).path))
        #expect(!FileManager.default.fileExists(atPath: store.recordingURL(for: ids[1]).path))
        #expect(FileManager.default.fileExists(atPath: store.recordingURL(for: ids[2]).path))
    }

    @Test
    func migrationFromLegacyArrayFormatPreservesCumulativeData() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let id = UUID()
        let audioURL = fixture.recordingsDirectory.appendingPathComponent("\(id.uuidString).caf")
        try fixture.writeAudio(at: audioURL)
        let legacyEntry = VoiceHistoryEntry(
            id: id,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            duration: 15,
            rawTranscript: String(repeating: "旧", count: 80),
            processedTranscript: nil,
            wordCount: 80,
            audioFileName: audioURL.lastPathComponent
        )
        try JSONEncoder().encode([legacyEntry]).write(to: fixture.metadataURL)

        let store = fixture.makeStore()

        #expect(store.entries.count == 1)
        #expect(store.statistics.totalWordCount == 80)
        #expect(store.statistics.totalDuration == 15)

        store.remove(id: id)

        #expect(store.entries.isEmpty)
        #expect(store.statistics.totalWordCount == 80)
        #expect(store.statistics.totalDuration == 15)
    }

    @Test
    func reloadRepairsCumulativeStatisticsBelowVisibleHistory() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let store = fixture.makeStore()
        let id = UUID()
        let audioURL = store.recordingURL(for: id)
        try fixture.writeAudio(at: audioURL)
        #expect(store.record(VoiceRecordingResult(
            id: id,
            audioFileURL: audioURL,
            transcript: String(repeating: "累", count: 12),
            duration: 6
        )))
        try fixture.executeSQL("""
            UPDATE voice_history_state
            SET statistics = CAST('{"totalWordCount":-1,"totalDuration":-10}' AS BLOB);
            """)

        let reloaded = fixture.makeStore()

        #expect(reloaded.statistics.totalWordCount == 12)
        #expect(reloaded.statistics.totalDuration == 6)
    }

    @Test
    func recordingSaturatesCumulativeWordCountInsteadOfOverflowing() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let firstID = UUID()
        let firstAudioURL = fixture.recordingsDirectory.appendingPathComponent("\(firstID.uuidString).caf")
        try fixture.writeAudio(at: firstAudioURL)
        let initial = fixture.makeStore()
        #expect(initial.record(VoiceRecordingResult(
            id: firstID,
            audioFileURL: firstAudioURL,
            transcript: "初",
            duration: 1
        )))

        try fixture.executeSQL("""
            UPDATE voice_history_state
            SET statistics = CAST('{"totalWordCount":\(Int.max),"totalDuration":1}' AS BLOB);
            """)

        let store = fixture.makeStore()
        let secondID = UUID()
        let secondAudioURL = store.recordingURL(for: secondID)
        try fixture.writeAudio(at: secondAudioURL)

        #expect(store.record(VoiceRecordingResult(
            id: secondID,
            audioFileURL: secondAudioURL,
            transcript: "增",
            duration: 1
        )))
        #expect(store.statistics.totalWordCount == .max)
    }
}

private struct VoiceHistoryFixture {
    let root: URL
    let metadataURL: URL
    let recordingsDirectory: URL

    var databaseURL: URL {
        metadataURL.deletingPathExtension().appendingPathExtension("sqlite")
    }

    @MainActor
    func makeStore(fileManager: FileManager = .default) -> VoiceHistoryStore {
        VoiceHistoryStore(
            storageURL: metadataURL,
            recordingsDirectory: recordingsDirectory,
            fileManager: fileManager
        )
    }

    func writeAudio(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("audio".utf8).write(to: url)
    }

    func stageAudio(at originalURL: URL) throws -> URL {
        let stagedURL = originalURL.deletingLastPathComponent().appendingPathComponent(
            ".zisla-deleting-00000000-0000-0000-0000-000000000002.\(originalURL.lastPathComponent)"
        )
        try FileManager.default.moveItem(at: originalURL, to: stagedURL)
        return stagedURL
    }

    func blockMetadataWrites() throws {
        try executeSQL("""
            CREATE TRIGGER fail_voice_state_update BEFORE UPDATE ON voice_history_state
            BEGIN SELECT RAISE(ABORT, 'injected metadata write failure'); END;
            """)
    }

    func executeSQL(_ sql: String) throws {
        var connection: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &connection) == SQLITE_OK, let connection else {
            sqlite3_close(connection)
            throw VoiceSQLiteTestError(message: "unable to open test database")
        }
        defer { sqlite3_close(connection) }
        var message: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(connection, sql, nil, nil, &message)
        defer { sqlite3_free(message) }
        guard result == SQLITE_OK else {
            throw VoiceSQLiteTestError(message: message.map { String(cString: $0) } ?? "unable to execute test SQL")
        }
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}

private struct VoiceSQLiteTestError: Error {
    let message: String
}

private final class FailingVoiceFileManager: FileManager {
    var blockedURL: URL?
    var blockedStagedRemovalFileName: String?
    var stagedRemovalFailureIndex: Int? {
        didSet { stagedRemovalAttemptCount = 0 }
    }
    private var stagedRemovalAttemptCount = 0
    var removeBeforeReportingFailure = false
    var failRecoveryDirectoryRead = false
    var stagedAttributesError: Error?
    var stagedRemovalURLs: [URL] = []
    var beforeStagedRemovalFailure: (@MainActor (URL) throws -> Void)?
    var afterStaging: (@MainActor () -> Void)?
    var stagedRestorationFailureIndex: Int?
    private var stagedRestorationAttemptCount = 0

    override func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any] {
        if URL(fileURLWithPath: path).lastPathComponent.hasPrefix(".zisla-deleting-"), let stagedAttributesError {
            throw stagedAttributesError
        }
        return try super.attributesOfItem(atPath: path)
    }

    override func contentsOfDirectory(atPath path: String) throws -> [String] {
        if failRecoveryDirectoryRead { throw CocoaError(.fileReadNoPermission) }
        return try super.contentsOfDirectory(atPath: path)
    }

    override func moveItem(at srcURL: URL, to dstURL: URL) throws {
        if srcURL.lastPathComponent.hasPrefix(".zisla-deleting-") {
            stagedRestorationAttemptCount += 1
            if stagedRestorationAttemptCount == stagedRestorationFailureIndex {
                throw CocoaError(.fileWriteUnknown)
            }
        }
        if let blockedURL, srcURL.standardizedFileURL == blockedURL.standardizedFileURL {
            throw CocoaError(.fileWriteUnknown)
        }
        try super.moveItem(at: srcURL, to: dstURL)
        if dstURL.lastPathComponent.hasPrefix(".zisla-deleting-"), let afterStaging {
            self.afterStaging = nil
            MainActor.assumeIsolated { afterStaging() }
        }
    }

    override func removeItem(at url: URL) throws {
        if url.lastPathComponent.hasPrefix(".zisla-deleting-") {
            stagedRemovalURLs.append(url)
            stagedRemovalAttemptCount += 1
            if stagedRemovalFailureIndex == stagedRemovalAttemptCount {
                if let beforeStagedRemovalFailure {
                    try MainActor.assumeIsolated { try beforeStagedRemovalFailure(url) }
                }
                if removeBeforeReportingFailure { try super.removeItem(at: url) }
                throw CocoaError(.fileWriteUnknown)
            }
        }
        if let blockedStagedRemovalFileName,
           url.lastPathComponent.hasSuffix(blockedStagedRemovalFileName) {
            throw CocoaError(.fileWriteUnknown)
        }
        if let blockedURL, url.standardizedFileURL == blockedURL.standardizedFileURL {
            throw CocoaError(.fileWriteUnknown)
        }
        try super.removeItem(at: url)
    }
}

private func makeFixture() throws -> VoiceHistoryFixture {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("Zisla.VoiceHistoryStoreTests.\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return VoiceHistoryFixture(
        root: root,
        metadataURL: root.appendingPathComponent("voice-history.json", isDirectory: false),
        recordingsDirectory: root.appendingPathComponent("voice-recordings", isDirectory: true)
    )
}
