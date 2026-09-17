import Combine
import Foundation
import ZislaCore

public struct VoiceRecordingResult: Equatable, Sendable {
    public var id: UUID
    public var audioFileURL: URL
    public var transcript: String
    public var duration: TimeInterval
    public var createdAt: Date

    public init(
        id: UUID,
        audioFileURL: URL,
        transcript: String,
        duration: TimeInterval,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.audioFileURL = audioFileURL
        self.transcript = transcript
        self.duration = duration
        self.createdAt = createdAt
    }
}

public struct VoiceHistoryEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var duration: TimeInterval
    public var rawTranscript: String
    public var processedTranscript: String?
    public var wordCount: Int
    public var audioFileName: String?

    public var displayTranscript: String {
        processedTranscript ?? rawTranscript
    }
}

public struct VoiceHistoryStatistics: Equatable, Sendable {
    public var totalWordCount: Int
    public var totalDuration: TimeInterval
    public var wordsPerMinute: Double
    public var savedTime: TimeInterval
}

struct VoiceHistoryPersistentState: Codable {
    var entries: [VoiceHistoryEntry]
    var cumulativeStatistics: CumulativeStatistics

    struct CumulativeStatistics: Codable, Equatable {
        var totalWordCount: Int
        var totalDuration: TimeInterval
    }
}

public enum VoiceTranscriptMetrics {
    public static let assumedTypingWordsPerMinute = 40.0

    public static func wordCount(in text: String) -> Int {
        var count = 0
        var isInsideWord = false

        for scalar in text.unicodeScalars {
            if isEastAsianUnit(scalar) {
                count += 1
                isInsideWord = false
            } else if scalar.properties.isAlphabetic || scalar.properties.numericType != nil {
                if !isInsideWord {
                    count += 1
                    isInsideWord = true
                }
            } else if scalar.properties.generalCategory != .nonspacingMark {
                isInsideWord = false
            }
        }
        return count
    }

    private static func isEastAsianUnit(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3040...0x30FF,
             0x3400...0x4DBF,
             0x4E00...0x9FFF,
             0xAC00...0xD7AF,
             0xF900...0xFAFF,
             0x20000...0x2FA1F:
            true
        default:
            false
        }
    }
}

@MainActor
public final class VoiceHistoryStore: ObservableObject {
    private struct StagedAudioFile {
        let originalURL: URL
        let stagingURL: URL
    }

    @Published public private(set) var entries: [VoiceHistoryEntry] = []
    @Published public private(set) var errorDescription: String?

    private let legacyStorageURL: URL
    private let recordingsDirectory: URL
    private let fileManager: FileManager
    private var database: VoiceHistoryDatabase?
    private var pendingAudioRevision: UUID?
    private var cumulativeWordCount: Int = 0
    private var cumulativeDuration: TimeInterval = 0

    public init(
        storageURL: URL = AppPaths.voiceHistory,
        recordingsDirectory: URL = AppPaths.voiceRecordings,
        fileManager: FileManager = .default
    ) {
        self.legacyStorageURL = storageURL
        self.recordingsDirectory = recordingsDirectory.standardizedFileURL
        self.fileManager = fileManager
        load()
    }

    public var statistics: VoiceHistoryStatistics {
        let wordsPerMinute = cumulativeDuration > 0
            ? min(Double(Int.max).nextDown, Double(cumulativeWordCount) * 60 / cumulativeDuration)
            : 0
        let estimatedTypingDuration = Double(cumulativeWordCount)
            / VoiceTranscriptMetrics.assumedTypingWordsPerMinute * 60
        return VoiceHistoryStatistics(
            totalWordCount: cumulativeWordCount,
            totalDuration: cumulativeDuration,
            wordsPerMinute: wordsPerMinute,
            savedTime: max(0, estimatedTypingDuration - cumulativeDuration)
        )
    }

    public func recordingURL(for id: UUID) -> URL {
        recordingsDirectory.appendingPathComponent("\(id.uuidString).caf", isDirectory: false)
    }

    public func audioURL(for entry: VoiceHistoryEntry) -> URL? {
        guard let audioFileName = entry.audioFileName,
              audioFileName == recordingURL(for: entry.id).lastPathComponent else { return nil }
        let url = recordingsDirectory.appendingPathComponent(audioFileName, isDirectory: false)
        guard isSafeRecordingURL(url, id: entry.id), isRegularFile(at: url) else { return nil }
        return url.standardizedFileURL
    }

    @discardableResult
    public func record(_ result: VoiceRecordingResult, retainAudio: Bool = true) -> Bool {
        guard beginAccess() else { return false }
        defer { finishAccess() }
        guard isSafeRecordingURL(result.audioFileURL, id: result.id) else {
            errorDescription = AppLocalization.text("录音文件不在语音记录目录中")
            return false
        }
        guard isRegularFile(at: result.audioFileURL) else {
            errorDescription = AppLocalization.text("录音文件不存在或不可读取")
            return false
        }
        let transcript = result.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let wordCount = VoiceTranscriptMetrics.wordCount(in: transcript)
        let duration = normalizedDuration(result.duration)

        let entry = VoiceHistoryEntry(
            id: result.id,
            createdAt: result.createdAt,
            duration: duration,
            rawTranscript: transcript,
            processedTranscript: nil,
            wordCount: wordCount,
            audioFileName: retainAudio ? recordingURL(for: result.id).lastPathComponent : nil
        )
        var candidate = entries
        let isReplacement = candidate.contains { $0.id == result.id }
        candidate.removeAll { $0.id == result.id }
        candidate.append(entry)
        candidate.sort {
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }

        let newCumulativeWordCount: Int
        let newCumulativeDuration: TimeInterval
        if isReplacement {
            newCumulativeWordCount = cumulativeWordCount
            newCumulativeDuration = cumulativeDuration
        } else {
            let (totalWordCount, overflow) = cumulativeWordCount.addingReportingOverflow(wordCount)
            newCumulativeWordCount = overflow ? .max : totalWordCount
            newCumulativeDuration = addingCumulativeDuration(cumulativeDuration, duration)
        }

        let stagedAudioFiles: [StagedAudioFile]
        if retainAudio {
            stagedAudioFiles = []
        } else {
            do {
                stagedAudioFiles = try stageAudioFiles([result.audioFileURL])
            } catch {
                errorDescription = error.localizedDescription
                return false
            }
        }
        guard persistCandidate(candidate, cumulativeWordCount: newCumulativeWordCount, cumulativeDuration: newCumulativeDuration) else {
            let persistenceError = errorDescription
            if let restorationError = restoreStagedAudioFiles(stagedAudioFiles) {
                errorDescription = restorationError.localizedDescription
            } else {
                errorDescription = persistenceError
            }
            return false
        }
        let removal = removeStagedAudioFiles(stagedAudioFiles)
        if let removalError = removal.error {
            // Commit compensation before restoring files so interrupted recovery has a durable decision.
            let rollbackSucceeded = persistCandidate(entries, cumulativeWordCount: cumulativeWordCount, cumulativeDuration: cumulativeDuration, commitRevision: UUID())
            let restorationError = rollbackSucceeded ? restoreStagedAudioFiles(removal.remaining) : nil
            if !rollbackSucceeded {
                entries = candidate
                cumulativeWordCount = newCumulativeWordCount
                cumulativeDuration = newCumulativeDuration
            }
            errorDescription = (restorationError ?? removalError).localizedDescription
            return false
        }
        entries = candidate
        cumulativeWordCount = newCumulativeWordCount
        cumulativeDuration = newCumulativeDuration
        return true
    }

    @discardableResult
    public func updateProcessedTranscript(id: UUID, transcript: String) -> Bool {
        guard beginAccess() else { return false }
        defer { finishAccess() }
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return false }
        let normalized = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        var candidate = entries
        candidate[index].processedTranscript = normalized.isEmpty ? nil : normalized
        guard persistCandidate(candidate, cumulativeWordCount: cumulativeWordCount, cumulativeDuration: cumulativeDuration) else { return false }
        entries = candidate
        return true
    }

    public func remove(id: UUID) {
        guard beginAccess() else { return }
        defer { finishAccess() }
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let entry = entries[index]
        let audioURL = audioURL(for: entry)
        var candidate = entries
        candidate.remove(at: index)
        let stagedAudioFiles: [StagedAudioFile]
        do {
            stagedAudioFiles = try stageAudioFiles(audioURL.map { [$0] } ?? [])
        } catch {
            errorDescription = error.localizedDescription
            return
        }
        guard persistCandidate(candidate, cumulativeWordCount: cumulativeWordCount, cumulativeDuration: cumulativeDuration) else {
            let persistenceError = errorDescription
            if let restorationError = restoreStagedAudioFiles(stagedAudioFiles) {
                errorDescription = restorationError.localizedDescription
            } else {
                errorDescription = persistenceError
            }
            return
        }
        let removal = removeStagedAudioFiles(stagedAudioFiles)
        if let removalError = removal.error {
            let rollbackSucceeded = persistCandidate(entries, cumulativeWordCount: cumulativeWordCount, cumulativeDuration: cumulativeDuration, commitRevision: UUID())
            let restorationError = rollbackSucceeded ? restoreStagedAudioFiles(removal.remaining) : nil
            if !rollbackSucceeded {
                entries = candidate
            }
            errorDescription = (restorationError ?? removalError).localizedDescription
            return
        }
        entries = candidate
    }

    public func removeBatch(ids: Set<UUID>) {
        guard beginAccess() else { return }
        defer { finishAccess() }
        let toRemove = entries.filter { ids.contains($0.id) }
        guard !toRemove.isEmpty else { return }

        let audioFiles = toRemove.compactMap { entry in
            audioURL(for: entry).map { (id: entry.id, url: $0) }
        }
        var candidate = entries
        candidate.removeAll { ids.contains($0.id) }
        let stagedAudioFiles: [StagedAudioFile]
        do {
            stagedAudioFiles = try stageAudioFiles(audioFiles.map(\.url))
        } catch {
            errorDescription = error.localizedDescription
            return
        }
        guard persistCandidate(candidate, cumulativeWordCount: cumulativeWordCount, cumulativeDuration: cumulativeDuration) else {
            let persistenceError = errorDescription
            if let restorationError = restoreStagedAudioFiles(stagedAudioFiles) {
                errorDescription = restorationError.localizedDescription
            } else {
                errorDescription = persistenceError
            }
            return
        }
        let removal = removeStagedAudioFiles(stagedAudioFiles)
        if let removalError = removal.error {
            let remainingURLs = Set(removal.remaining.map(\.originalURL))
            let restoredIDs = Set(audioFiles.compactMap { file in
                remainingURLs.contains(file.url) ? file.id : nil
            })
            let audioEntryIDs = Set(audioFiles.map(\.id))
            let fallback = entries.filter {
                !ids.contains($0.id)
                    || !audioEntryIDs.contains($0.id)
                    || restoredIDs.contains($0.id)
            }
            let rollbackSucceeded = persistCandidate(fallback, cumulativeWordCount: cumulativeWordCount, cumulativeDuration: cumulativeDuration, commitRevision: UUID())
            let restorationError = rollbackSucceeded ? restoreStagedAudioFiles(removal.remaining) : nil
            entries = rollbackSucceeded ? fallback : candidate
            errorDescription = (restorationError ?? removalError).localizedDescription
            return
        }
        entries = candidate
    }

    public func removeAll() {
        guard beginAccess() else { return }
        defer { finishAccess() }
        var audioURLsByEntryID: [UUID: URL] = [:]
        for entry in entries {
            if let audioURL = audioURL(for: entry) {
                audioURLsByEntryID[entry.id] = audioURL
            }
        }
        let audioURLs: [URL]
        do {
            audioURLs = try fileManager.contentsOfDirectory(
                at: recordingsDirectory,
                includingPropertiesForKeys: [.isDirectoryKey]
            ).filter { url in
                url.pathExtension.lowercased() == "caf"
                    && (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true
            }
        } catch {
            guard !fileManager.fileExists(atPath: recordingsDirectory.path) else {
                errorDescription = error.localizedDescription
                return
            }
            audioURLs = []
        }
        let stagedAudioFiles: [StagedAudioFile]
        do {
            stagedAudioFiles = try stageAudioFiles(audioURLs)
        } catch {
            errorDescription = error.localizedDescription
            return
        }
        guard persistCandidate([], cumulativeWordCount: cumulativeWordCount, cumulativeDuration: cumulativeDuration) else {
            let persistenceError = errorDescription
            if let restorationError = restoreStagedAudioFiles(stagedAudioFiles) {
                errorDescription = restorationError.localizedDescription
            } else {
                errorDescription = persistenceError
            }
            return
        }
        let removal = removeStagedAudioFiles(stagedAudioFiles)
        if let removalError = removal.error {
            let remainingURLs = Set(removal.remaining.filter { isRegularFile(at: $0.stagingURL) }.map(\.originalURL))
            let restoredEntryIDs = Set(audioURLsByEntryID.compactMap { id, url in
                remainingURLs.contains(url) ? id : nil
            })
            let fallback = entries.filter { entry in
                entry.audioFileName == nil || restoredEntryIDs.contains(entry.id)
            }
            let rollbackSucceeded = persistCandidate(fallback, cumulativeWordCount: cumulativeWordCount, cumulativeDuration: cumulativeDuration, commitRevision: UUID())
            let restorationError = rollbackSucceeded ? restoreStagedAudioFiles(removal.remaining) : nil
            entries = rollbackSucceeded ? fallback : []
            errorDescription = (restorationError ?? removalError).localizedDescription
            return
        }
        entries.removeAll()
    }

    private func load() {
        do {
            let database = try VoiceHistoryDatabase(
                storageURL: legacyStorageURL.deletingPathExtension().appendingPathExtension("sqlite"),
                fileManager: fileManager
            )
            try database.lock()
            defer { database.unlock() }
            let state: VoiceHistoryPersistentState
            if let stored = try database.load() {
                state = stored
            } else if fileManager.fileExists(atPath: legacyStorageURL.path) {
                let data = try Data(contentsOf: legacyStorageURL)
                if let stored = try? JSONDecoder().decode(VoiceHistoryPersistentState.self, from: data) {
                    state = stored
                } else {
                    state = VoiceHistoryPersistentState(
                        entries: try JSONDecoder().decode([VoiceHistoryEntry].self, from: data),
                        cumulativeStatistics: .init(totalWordCount: 0, totalDuration: 0)
                    )
                }
            } else {
                state = VoiceHistoryPersistentState(
                    entries: [],
                    cumulativeStatistics: .init(totalWordCount: 0, totalDuration: 0)
                )
            }
            try recoverStagedAudioFiles(committedRevision: database.revision)
            let loadedEntries = state.entries.map(normalizedEntry(_:))
            let visibleWordCount = loadedEntries.reduce(0) { $0 + $1.wordCount }
            let visibleDuration = loadedEntries.reduce(0) {
                addingCumulativeDuration($0, $1.duration)
            }
            let loadedWordCount = max(0, visibleWordCount, state.cumulativeStatistics.totalWordCount)
            let loadedDuration = max(visibleDuration, normalizedDuration(state.cumulativeStatistics.totalDuration))
            try database.save(VoiceHistoryPersistentState(
                entries: loadedEntries,
                cumulativeStatistics: .init(
                    totalWordCount: loadedWordCount,
                    totalDuration: loadedDuration
                )
            ))
            // Enable writes only after loading and migration have both succeeded.
            self.database = database
            entries = loadedEntries
            sortEntries()
            cumulativeWordCount = loadedWordCount
            cumulativeDuration = loadedDuration
            errorDescription = nil
        } catch {
            errorDescription = error.localizedDescription
        }
    }

    public func cleanupOldRecordings(
        policy: VoiceRecordingCleanupPolicy,
        now: Date = Date()
    ) {
        guard let daysThreshold = policy.daysThreshold else { return }
        guard beginAccess() else { return }
        defer { finishAccess() }
        let cutoffDate = now.addingTimeInterval(-Double(daysThreshold) * 24 * 60 * 60)
        var candidate = entries
        var audioDeletions: [(id: UUID, url: URL)] = []

        for index in candidate.indices
        where candidate[index].createdAt < cutoffDate && candidate[index].audioFileName != nil {
            guard let audioURL = audioURL(for: candidate[index]) else {
                candidate[index].audioFileName = nil
                continue
            }
            candidate[index].audioFileName = nil
            audioDeletions.append((candidate[index].id, audioURL))
        }
        guard candidate != entries else { return }
        let stagedAudioFiles: [StagedAudioFile]
        do {
            stagedAudioFiles = try stageAudioFiles(audioDeletions.map(\.url))
        } catch {
            errorDescription = error.localizedDescription
            return
        }
        guard persistCandidate(candidate, cumulativeWordCount: cumulativeWordCount, cumulativeDuration: cumulativeDuration) else {
            let persistenceError = errorDescription
            if let restorationError = restoreStagedAudioFiles(stagedAudioFiles) {
                errorDescription = restorationError.localizedDescription
            } else {
                errorDescription = persistenceError
            }
            return
        }
        let removal = removeStagedAudioFiles(stagedAudioFiles)
        if let removalError = removal.error {
            let remainingURLs = Set(removal.remaining.map(\.originalURL))
            let restoredIDs = Set(audioDeletions.compactMap { deletion in
                remainingURLs.contains(deletion.url) ? deletion.id : nil
            })
            var fallback = candidate
            for index in fallback.indices where restoredIDs.contains(fallback[index].id) {
                fallback[index].audioFileName = entries[index].audioFileName
            }
            let rollbackSucceeded = persistCandidate(fallback, cumulativeWordCount: cumulativeWordCount, cumulativeDuration: cumulativeDuration, commitRevision: UUID())
            let restorationError = rollbackSucceeded ? restoreStagedAudioFiles(removal.remaining) : nil
            entries = rollbackSucceeded ? fallback : candidate
            errorDescription = (restorationError ?? removalError).localizedDescription
            return
        }
        entries = candidate
    }

    @discardableResult
    private func persistCandidate(_ candidate: [VoiceHistoryEntry], cumulativeWordCount: Int, cumulativeDuration: TimeInterval, commitRevision: UUID? = nil) -> Bool {
        guard let database else { return false }
        do {
            try fileManager.createDirectory(
                at: recordingsDirectory,
                withIntermediateDirectories: true
            )
            let state = VoiceHistoryPersistentState(
                entries: candidate,
                cumulativeStatistics: VoiceHistoryPersistentState.CumulativeStatistics(
                    totalWordCount: cumulativeWordCount,
                    totalDuration: cumulativeDuration
                )
            )
            try database.save(state, commitRevision: commitRevision ?? pendingAudioRevision)
            pendingAudioRevision = nil
            errorDescription = nil
            return true
        } catch {
            errorDescription = error.localizedDescription
            return false
        }
    }

    private func beginAccess() -> Bool {
        guard let database else { return false }
        do {
            try database.lock()
        } catch {
            errorDescription = error.localizedDescription
            return false
        }
        do {
            try database.validateRevision()
            try recoverStagedAudioFiles(committedRevision: database.revision)
            return true
        } catch {
            database.unlock()
            errorDescription = error.localizedDescription
            return false
        }
    }

    private func finishAccess() {
        pendingAudioRevision = nil
        database?.unlock()
    }

    private func recoverStagedAudioFiles(committedRevision: String?) throws {
        let names: [String]
        do {
            names = try fileManager.contentsOfDirectory(atPath: recordingsDirectory.path)
        } catch {
            guard !fileManager.fileExists(atPath: recordingsDirectory.path) else { throw error }
            return
        }
        let prefix = ".zisla-deleting-"
        for name in names where name.hasPrefix(prefix) {
            let suffix = name.dropFirst(prefix.count)
            guard let separator = suffix.firstIndex(of: "."),
                  let revision = UUID(uuidString: String(suffix[..<separator])) else { continue }
            let originalName = String(suffix[suffix.index(after: separator)...])
            guard !originalName.isEmpty else { continue }
            let stagedURL = recordingsDirectory.appendingPathComponent(name, isDirectory: false)
            if revision.uuidString == committedRevision {
                try fileManager.removeItem(at: stagedURL)
            } else {
                let originalURL = recordingsDirectory.appendingPathComponent(originalName, isDirectory: false)
                try fileManager.moveItem(at: stagedURL, to: originalURL)
            }
        }
    }

    private func stageAudioFiles(_ audioURLs: [URL]) throws -> [StagedAudioFile] {
        var staged: [StagedAudioFile] = []
        var seen = Set<URL>()
        let commitRevision = UUID()
        for originalURL in audioURLs.map(\.standardizedFileURL)
        where seen.insert(originalURL).inserted {
            pendingAudioRevision = commitRevision
            let stagingURL = originalURL
                .deletingLastPathComponent()
                .appendingPathComponent(
                    ".zisla-deleting-\(commitRevision.uuidString).\(originalURL.lastPathComponent)",
                    isDirectory: false
                )
            do {
                try fileManager.moveItem(at: originalURL, to: stagingURL)
                staged.append(StagedAudioFile(originalURL: originalURL, stagingURL: stagingURL))
            } catch {
                if let restorationError = restoreStagedAudioFiles(staged) {
                    throw restorationError
                }
                throw error
            }
        }
        return staged
    }

    private func restoreStagedAudioFiles(_ staged: [StagedAudioFile]) -> Error? {
        for file in staged.reversed() where fileManager.fileExists(atPath: file.stagingURL.path) {
            do {
                try fileManager.moveItem(at: file.stagingURL, to: file.originalURL)
            } catch {
                return error
            }
        }
        return nil
    }

    private func removeStagedAudioFiles(
        _ staged: [StagedAudioFile]
    ) -> (remaining: [StagedAudioFile], error: Error?) {
        for index in staged.indices {
            do {
                try fileManager.removeItem(at: staged[index].stagingURL)
            } catch {
                if isMissingFile(at: staged[index].stagingURL) { continue }
                return (Array(staged[index...]), error)
            }
        }
        return ([], nil)
    }

    private func sortEntries() {
        entries.sort {
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    private func normalizedEntry(_ entry: VoiceHistoryEntry) -> VoiceHistoryEntry {
        var normalized = entry
        if entry.audioFileName != nil, audioURL(for: entry) == nil {
            normalized.audioFileName = nil
        }
        normalized.duration = normalizedDuration(entry.duration)
        normalized.rawTranscript = entry.rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.wordCount = VoiceTranscriptMetrics.wordCount(in: normalized.rawTranscript)
        if let processedTranscript = entry.processedTranscript {
            let trimmed = processedTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            normalized.processedTranscript = trimmed.isEmpty ? nil : trimmed
        }
        return normalized
    }

    private func normalizedDuration(_ duration: TimeInterval) -> TimeInterval {
        duration.isFinite ? max(0, duration) : 0
    }

    private func addingCumulativeDuration(_ lhs: TimeInterval, _ rhs: TimeInterval) -> TimeInterval {
        let sum = normalizedDuration(lhs) + normalizedDuration(rhs)
        return sum.isFinite ? sum : .greatestFiniteMagnitude
    }

    private func isSafeRecordingURL(_ url: URL, id: UUID) -> Bool {
        let standardized = url.standardizedFileURL
        guard standardized.lastPathComponent == recordingURL(for: id).lastPathComponent else { return false }
        let resolvedDirectory = recordingsDirectory.resolvingSymlinksInPath()
        return standardized.resolvingSymlinksInPath().deletingLastPathComponent() == resolvedDirectory
    }

    private func isRegularFile(at url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }

    private func isMissingFile(at url: URL) -> Bool {
        do {
            _ = try fileManager.attributesOfItem(atPath: url.path)
            return false
        } catch let error as CocoaError {
            return error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile
        } catch {
            return false
        }
    }
}
