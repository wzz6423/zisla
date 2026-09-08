import AppKit
import Foundation
import ZislaCore

/// Infers activity state from the local data directory of the Doubao desktop app (PWA shell).
///
/// Data directory: `~/Library/Application Support/Doubao/`
/// Doubao is a PWA shell with no structured AI task log, so a running application and recent local-data
/// activity are both required before reporting an active session.
public final class DoubaoSessionActivityDetector: AIActivityDetecting {
    public static let defaultRecencyThreshold: TimeInterval = 90
    static let doubaoBundleIdentifier = "com.bot.pc.doubao"

    private enum ActivitySource {
        case chat
        case agentMode
    }

    private struct Candidate {
        var url: URL
        var modificationDate: Date
        var source: ActivitySource
    }

    public let dataRoots: [URL]
    public let maxFiles: Int
    public let recencyThreshold: TimeInterval

    private let fileManager: FileManager
    private let isDoubaoRunning: () -> Bool
    private let now: () -> Date
    private var cachedTask: AIProgressTask?
    private var cachedSignature: String?
    private var lastScanAt: Date = .distantPast
    private let scanInterval: TimeInterval

    public init(
        dataRoots: [URL]? = nil,
        maxFiles: Int = 32,
        recencyThreshold: TimeInterval = DoubaoSessionActivityDetector.defaultRecencyThreshold,
        scanInterval: TimeInterval = 5,
        fileManager: FileManager = .default,
        isDoubaoRunning: (() -> Bool)? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        if let dataRoots {
            self.dataRoots = dataRoots
        } else {
            self.dataRoots = Self.defaultDataRoots(
                home: fileManager.homeDirectoryForCurrentUser,
                fileManager: fileManager
            )
        }
        self.maxFiles = max(1, maxFiles)
        self.recencyThreshold = max(0, recencyThreshold)
        self.scanInterval = max(0, scanInterval)
        self.fileManager = fileManager
        self.isDoubaoRunning = isDoubaoRunning ?? Self.isDoubaoRunning
        self.now = now
    }

    public func activeTasks() throws -> [AIProgressTask] {
        guard isDoubaoRunning() else {
            cachedTask = nil
            cachedSignature = nil
            return []
        }

        let now = now()
        let cutoff = now.addingTimeInterval(-recencyThreshold)
        if now.timeIntervalSince(lastScanAt) < scanInterval,
           let cached = cachedTask,
           cached.updatedAt > cutoff {
            return [cached]
        }
        lastScanAt = now

        let candidates = recentFiles()
        let signature = signature(for: candidates)
        if signature == cachedSignature,
           let cached = cachedTask,
           cached.updatedAt > cutoff {
            return [cached]
        }
        cachedSignature = signature

        guard let latest = candidates.first,
              latest.modificationDate > cutoff else {
            cachedTask = nil
            return []
        }

        let isAgentMode = latest.source == .agentMode
        let task = AIProgressTask(
            id: Self.taskID,
            provider: .doubao,
            title: isAgentMode ? "豆包 Agent Mode" : "豆包",
            detail: isAgentMode ? "最近活动（90 秒内）" : nil,
            progress: nil,
            status: .running,
            updatedAt: latest.modificationDate,
            sessionURL: nil,
            effort: nil,
            startedAt: nil
        )
        cachedTask = task
        return [task]
    }

    public static let taskID = "doubao-active"

    private static func isDoubaoRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains { application in
            guard !application.isTerminated else { return false }
            return matchesDoubaoApplication(
                bundleIdentifier: application.bundleIdentifier,
                localizedName: application.localizedName,
                executableName: application.executableURL?.deletingPathExtension().lastPathComponent
            )
        }
    }

    static func matchesDoubaoApplication(
        bundleIdentifier: String?,
        localizedName: String?,
        executableName: String?
    ) -> Bool {
        if let bundleIdentifier {
            return bundleIdentifier.caseInsensitiveCompare(doubaoBundleIdentifier) == .orderedSame
        }

        return [localizedName, executableName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .contains { name in
                name == "豆包" || name.caseInsensitiveCompare("doubao") == .orderedSame
            }
    }

    public static func defaultDataRoots(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> [URL] {
        var roots: [URL] = []
        let appSupport = home.appendingPathComponent("Library/Application Support", isDirectory: true)

        let doubaoRoot = appSupport.appendingPathComponent("Doubao", isDirectory: true)
        if fileManager.fileExists(atPath: doubaoRoot.path) {
            roots.append(doubaoRoot)
        }

        // PWA variants may use different directory names.
        if let entries = try? fileManager.contentsOfDirectory(
            at: appSupport,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for entry in entries {
                let name = entry.lastPathComponent.lowercased()
                if name.contains("doubao") && !roots.contains(entry) {
                    roots.append(entry)
                }
            }
        }

        let cachesRoot = home.appendingPathComponent("Library/Caches", isDirectory: true)
        let doubaoCache = cachesRoot.appendingPathComponent("Doubao", isDirectory: true)
        if fileManager.fileExists(atPath: doubaoCache.path) {
            roots.append(doubaoCache)
        }

        return roots
    }

    // MARK: - File Discovery

    private func recentFiles() -> [Candidate] {
        var candidates: [Candidate] = []
        for root in dataRoots {
            candidates.append(contentsOf: chatCandidates(in: root))
            candidates.append(contentsOf: agentModeCandidates(in: root))
        }

        return Array(candidates.sorted {
            if $0.modificationDate != $1.modificationDate {
                return $0.modificationDate > $1.modificationDate
            }
            return $0.url.path < $1.url.path
        }.prefix(maxFiles))
    }

    private func chatCandidates(in root: URL) -> [Candidate] {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .contentModificationDateKey,
            ],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var candidates: [Candidate] = []
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [
                .isRegularFileKey,
                .contentModificationDateKey,
            ]), values.isRegularFile == true,
                  Self.isChatActivityFile(url) else { continue }
            candidates.append(Candidate(
                url: url,
                modificationDate: values.contentModificationDate ?? .distantPast,
                source: .chat
            ))
        }
        return candidates
    }

    private func agentModeCandidates(in root: URL) -> [Candidate] {
        let sessionsDirectory = root.appendingPathComponent(
            "Default/.doubao/agent_mode/workspace/.sessions",
            isDirectory: true
        )
        guard let sessionDirectories = try? fileManager.contentsOfDirectory(
            at: sessionsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var candidates: [Candidate] = []
        for sessionDirectory in sessionDirectories {
            guard let values = try? sessionDirectory.resourceValues(forKeys: [.isDirectoryKey]),
                  values.isDirectory == true,
                  let enumerator = fileManager.enumerator(
                      at: sessionDirectory,
                      includingPropertiesForKeys: [
                          .isRegularFileKey,
                          .contentModificationDateKey,
                      ],
                      options: [.skipsHiddenFiles]
                  ) else { continue }

            for case let url as URL in enumerator {
                guard Self.agentModeArtifactNames.contains(url.lastPathComponent),
                      let values = try? url.resourceValues(forKeys: [
                          .isRegularFileKey,
                          .contentModificationDateKey,
                      ]), values.isRegularFile == true else { continue }
                candidates.append(Candidate(
                    url: url,
                    modificationDate: values.contentModificationDate ?? .distantPast,
                    source: .agentMode
                ))
            }
        }
        return candidates
    }

    private static let agentModeArtifactNames = [
        "trajectory.jsonl",
        "findings.jsonl",
        "board.md",
        "assignment.md",
    ]

    private func signature(for candidates: [Candidate]) -> String {
        candidates.prefix(8).map { "\($0.url.path):\($0.modificationDate.timeIntervalSince1970)" }
            .joined(separator: "|")
    }

    private static func isChatActivityFile(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        return path.contains("/indexeddb/")
            && (path.contains("doubao-chat") || path.contains("doubao_chat"))
    }
}
