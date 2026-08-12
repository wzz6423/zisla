import Foundation
import Testing

@testable import ZislaKit

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
    func failedAudioRemovalDuringRemoveAllKeepsOnlyUndeletableEntryPersisted() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let fileManager = FailingVoiceFileManager()
        let store = fixture.makeStore(fileManager: fileManager)
        let blockedID = UUID()
        let removableID = UUID()
        let blockedURL = store.recordingURL(for: blockedID)
        let removableURL = store.recordingURL(for: removableID)
        try fixture.writeAudio(at: blockedURL)
        try fixture.writeAudio(at: removableURL)
        #expect(store.record(VoiceRecordingResult(
            id: blockedID,
            audioFileURL: blockedURL,
            transcript: "保留录音",
            duration: 1
        )))
        #expect(store.record(VoiceRecordingResult(
            id: removableID,
            audioFileURL: removableURL,
            transcript: "删除录音",
            duration: 1
        )))

        fileManager.blockedURL = blockedURL
        let removed = store.removeAll()

        #expect(!removed)
        #expect(store.entries.map(\.id) == [blockedID])
        #expect(FileManager.default.fileExists(atPath: blockedURL.path))
        #expect(!FileManager.default.fileExists(atPath: removableURL.path))
        #expect(fixture.makeStore().entries.map(\.id) == [blockedID])
        #expect(store.errorDescription != nil)
    }

    @Test
    func failedFinalPersistenceStillRemovesDeletedAudioFromPublishedEntries() throws {
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
            transcript: "待删除录音",
            duration: 1
        )))
        fileManager.createDirectoryCallsBeforeFailure = 2

        let removed = store.removeAll()

        #expect(!removed)
        #expect(store.entries.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: audioURL.path))
        #expect(store.errorDescription != nil)
        #expect(fixture.makeStore().entries.isEmpty)
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
    var createDirectoryCallsBeforeFailure: Int?

    override func createDirectory(
        at url: URL,
        withIntermediateDirectories createIntermediates: Bool,
        attributes: [FileAttributeKey: Any]? = nil
    ) throws {
        if let remaining = createDirectoryCallsBeforeFailure {
            guard remaining > 0 else {
                createDirectoryCallsBeforeFailure = nil
                throw CocoaError(.fileWriteUnknown)
            }
            createDirectoryCallsBeforeFailure = remaining - 1
        }
        try super.createDirectory(
            at: url,
            withIntermediateDirectories: createIntermediates,
            attributes: attributes
        )
    }

    override func removeItem(at url: URL) throws {
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
