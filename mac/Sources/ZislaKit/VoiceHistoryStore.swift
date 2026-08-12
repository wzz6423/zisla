import Combine
import Foundation

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
    public var audioFileName: String

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
    @Published public private(set) var entries: [VoiceHistoryEntry] = []
    @Published public private(set) var errorDescription: String?

    private let storageURL: URL
    private let recordingsDirectory: URL
    private let fileManager: FileManager

    public init(
        storageURL: URL = AppPaths.voiceHistory,
        recordingsDirectory: URL = AppPaths.voiceRecordings,
        fileManager: FileManager = .default
    ) {
        self.storageURL = storageURL
        self.recordingsDirectory = recordingsDirectory.standardizedFileURL
        self.fileManager = fileManager
        load()
    }

    public var statistics: VoiceHistoryStatistics {
        let totalWordCount = entries.reduce(0) { $0 + $1.wordCount }
        let totalDuration = entries.reduce(0) { $0 + $1.duration }
        let wordsPerMinute = totalDuration > 0
            ? Double(totalWordCount) / (totalDuration / 60)
            : 0
        let estimatedTypingDuration = Double(totalWordCount)
            / VoiceTranscriptMetrics.assumedTypingWordsPerMinute * 60
        return VoiceHistoryStatistics(
            totalWordCount: totalWordCount,
            totalDuration: totalDuration,
            wordsPerMinute: wordsPerMinute,
            savedTime: max(0, estimatedTypingDuration - totalDuration)
        )
    }

    public func recordingURL(for id: UUID) -> URL {
        recordingsDirectory.appendingPathComponent("\(id.uuidString).caf", isDirectory: false)
    }

    public func audioURL(for entry: VoiceHistoryEntry) -> URL? {
        guard entry.audioFileName == recordingURL(for: entry.id).lastPathComponent else { return nil }
        let url = recordingsDirectory.appendingPathComponent(entry.audioFileName, isDirectory: false)
        guard isSafeRecordingURL(url, id: entry.id), isRegularFile(at: url) else { return nil }
        return url.standardizedFileURL
    }

    @discardableResult
    public func record(_ result: VoiceRecordingResult) -> Bool {
        guard isSafeRecordingURL(result.audioFileURL, id: result.id) else {
            errorDescription = "录音文件不在语音记录目录中"
            return false
        }
        guard isRegularFile(at: result.audioFileURL) else {
            errorDescription = "录音文件不存在或不可读取"
            return false
        }

        let transcript = result.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = VoiceHistoryEntry(
            id: result.id,
            createdAt: result.createdAt,
            duration: normalizedDuration(result.duration),
            rawTranscript: transcript,
            processedTranscript: nil,
            wordCount: VoiceTranscriptMetrics.wordCount(in: transcript),
            audioFileName: recordingURL(for: result.id).lastPathComponent
        )
        var candidate = entries
        candidate.removeAll { $0.id == result.id }
        candidate.append(entry)
        candidate.sort {
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
        guard persistCandidate(candidate) else { return false }
        entries = candidate
        return true
    }

    @discardableResult
    public func updateProcessedTranscript(id: UUID, transcript: String) -> Bool {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return false }
        let normalized = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        var candidate = entries
        candidate[index].processedTranscript = normalized.isEmpty ? nil : normalized
        guard persistCandidate(candidate) else { return false }
        entries = candidate
        return true
    }

    public func remove(id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let entry = entries[index]
        let audioURL = audioURL(for: entry)
        var candidate = entries
        candidate.remove(at: index)
        guard persistCandidate(candidate) else { return }
        if let audioURL {
            do {
                try fileManager.removeItem(at: audioURL)
            } catch {
                // 文件系统拒绝删除时回滚索引，避免下次启动因音频仍存在而恢复记录。
                _ = persistCandidate(entries)
                errorDescription = error.localizedDescription
                return
            }
        }
        entries = candidate
    }

    @discardableResult
    public func removeAll() -> Bool {
        let audioURLs: [URL]
        if fileManager.fileExists(atPath: recordingsDirectory.path) {
            do {
                audioURLs = try fileManager.contentsOfDirectory(
                    at: recordingsDirectory,
                    includingPropertiesForKeys: [.isDirectoryKey]
                ).filter { url in
                    url.pathExtension.lowercased() == "caf"
                        && (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true
                }
            } catch {
                errorDescription = error.localizedDescription
                return false
            }
        } else {
            audioURLs = []
        }
        // 先确认索引可写，避免持久化失败时删掉仍被引用的音频。
        guard persistCandidate(entries) else { return false }

        var failedAudioPaths: Set<String> = []
        var removalErrorDescription: String?
        for audioURL in audioURLs {
            do {
                try fileManager.removeItem(at: audioURL)
            } catch {
                failedAudioPaths.insert(audioURL.standardizedFileURL.path)
                removalErrorDescription = removalErrorDescription ?? error.localizedDescription
            }
        }

        let candidate = entries.filter { entry in
            failedAudioPaths.contains(recordingURL(for: entry.id).standardizedFileURL.path)
        }
        guard persistCandidate(candidate) else {
            entries = candidate
            return false
        }
        entries = candidate
        errorDescription = removalErrorDescription
        return removalErrorDescription == nil
    }

    private func load() {
        guard fileManager.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            let decoded = try JSONDecoder().decode([VoiceHistoryEntry].self, from: data)
            entries = decoded.compactMap(normalizedEntry(_:))
            sortEntries()
            errorDescription = nil
            if entries != decoded {
                _ = persistCandidate(entries)
            }
        } catch {
            entries = []
            errorDescription = error.localizedDescription
        }
    }

    @discardableResult
    private func persistCandidate(_ candidate: [VoiceHistoryEntry]) -> Bool {
        do {
            try fileManager.createDirectory(
                at: storageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.createDirectory(
                at: recordingsDirectory,
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(candidate)
            try data.write(to: storageURL, options: .atomic)
            errorDescription = nil
            return true
        } catch {
            errorDescription = error.localizedDescription
            return false
        }
    }

    private func sortEntries() {
        entries.sort {
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    private func normalizedEntry(_ entry: VoiceHistoryEntry) -> VoiceHistoryEntry? {
        guard audioURL(for: entry) != nil else { return nil }
        var normalized = entry
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

    private func isSafeRecordingURL(_ url: URL, id: UUID) -> Bool {
        let standardized = url.standardizedFileURL
        guard standardized.lastPathComponent == recordingURL(for: id).lastPathComponent else { return false }
        let resolvedDirectory = recordingsDirectory.resolvingSymlinksInPath()
        return standardized.resolvingSymlinksInPath().deletingLastPathComponent() == resolvedDirectory
    }

    private func isRegularFile(at url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }
}
