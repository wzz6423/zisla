import Foundation
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
        var root = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: fixture.metadataURL)) as? [String: Any]
        )
        root["cumulativeStatistics"] = [
            "totalWordCount": -1,
            "totalDuration": -10,
        ]
        try JSONSerialization.data(withJSONObject: root).write(to: fixture.metadataURL)

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

        var root = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: fixture.metadataURL)) as? [String: Any]
        )
        root["cumulativeStatistics"] = [
            "totalWordCount": Int.max,
            "totalDuration": 1,
        ]
        try JSONSerialization.data(withJSONObject: root).write(to: fixture.metadataURL)

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

    func blockMetadataWrites() throws {
        if FileManager.default.fileExists(atPath: metadataURL.path) {
            try FileManager.default.removeItem(at: metadataURL)
        }
        try FileManager.default.createDirectory(at: metadataURL, withIntermediateDirectories: true)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}

private final class FailingVoiceFileManager: FileManager {
    var blockedURL: URL?
    var blockedStagedRemovalFileName: String?
    var stagedRemovalFailureIndex: Int? {
        didSet { stagedRemovalAttemptCount = 0 }
    }
    private var stagedRemovalAttemptCount = 0

    override func moveItem(at srcURL: URL, to dstURL: URL) throws {
        if let blockedURL, srcURL.standardizedFileURL == blockedURL.standardizedFileURL {
            throw CocoaError(.fileWriteUnknown)
        }
        try super.moveItem(at: srcURL, to: dstURL)
    }

    override func removeItem(at url: URL) throws {
        if url.lastPathComponent.hasPrefix(".zisla-deleting-") {
            stagedRemovalAttemptCount += 1
            if stagedRemovalFailureIndex == stagedRemovalAttemptCount {
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
