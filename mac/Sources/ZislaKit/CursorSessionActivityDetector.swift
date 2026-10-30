import AppKit
import Foundation
import ZislaCore

/// Adapted from chat-stasher's Cursor reader (Apache-2.0); only indexed metadata is selected.
public final class CursorSessionActivityDetector: AIActivityDetecting {
    public let userDirectory: URL
    public let maxSessions: Int
    private let recencyThreshold: TimeInterval
    private let now: () -> Date
    private let isApplicationRunning: () -> Bool

    public init(
        userDirectory: URL = CursorSessionActivityDetector.defaultUserDirectory(),
        maxSessions: Int = 4,
        recencyThreshold: TimeInterval = 30 * 60,
        isApplicationRunning: @escaping () -> Bool = {
            !NSRunningApplication.runningApplications(withBundleIdentifier: "com.todesktop.230313mzl4w4u92").isEmpty
        },
        now: @escaping () -> Date = Date.init
    ) {
        self.userDirectory = userDirectory
        self.maxSessions = max(1, maxSessions)
        self.recencyThreshold = max(0, recencyThreshold)
        self.isApplicationRunning = isApplicationRunning
        self.now = now
    }

    public static func defaultUserDirectory(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent("Library/Application Support/Cursor/User", isDirectory: true)
    }

    private var databases: [URL] {
        let workspaceRoot = userDirectory.appendingPathComponent("workspaceStorage")
        let workspaces = (try? FileManager.default.contentsOfDirectory(
            at: workspaceRoot, includingPropertiesForKeys: nil
        )) ?? []
        return [userDirectory.appendingPathComponent("globalStorage/state.vscdb")] + workspaces
            .map { $0.appendingPathComponent("state.vscdb") }.sorted { $0.path < $1.path }
    }

    public var activityFileURLs: [URL] {
        databases.flatMap { [$0, URL(fileURLWithPath: $0.path + "-wal")] }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    public func activeTasks() throws -> [AIProgressTask] {
        guard isApplicationRunning() else { return [] }
        let currentTime = now()
        let cutoff = currentTime.addingTimeInterval(-recencyThreshold)
        var tasks: [String: AIProgressTask] = [:]
        for database in databases {
            let fields = """
                json_extract(c.value, '$.composerId') AS id,
                json_extract(c.value, '$.name') AS name,
                json_extract(c.value, '$.unfinishedRunAt') AS unfinished,
                json_extract(c.value, '$.hasBlockingPendingActions') AS blocked,
                COALESCE(NULLIF(json_extract(c.value, '$.lastUpdatedAt'), 0),
                         NULLIF(json_extract(c.value, '$.unfinishedRunAt'), 0)) AS updated,
                json_extract(c.value, '$.createdAt') AS created,
                json_extract(c.value, '$.modelConfig.modelName') AS model
                """
            let global = DesktopAIStorage.rows(at: database, sql: """
                SELECT \(fields) FROM cursorDiskKV c
                WHERE key LIKE 'composerData:%' AND json_valid(c.value)
                AND json_extract(c.value, '$.status') = 'generating'
                AND COALESCE(json_extract(c.value, '$.composerId'), '') != ''
                AND COALESCE(json_extract(c.value, '$.isArchived'), 0) = 0
                AND COALESCE(json_extract(c.value, '$.isDraft'), 0) = 0
                AND updated >= \(cutoff.timeIntervalSince1970 * 1_000)
                AND updated <= \(currentTime.timeIntervalSince1970 * 1_000)
                ORDER BY updated DESC LIMIT \(maxSessions)
                """, limit: maxSessions)
            let legacy = DesktopAIStorage.rows(at: database, sql: """
                SELECT \(fields) FROM ItemTable i,
                json_each(CASE WHEN NOT json_valid(i.value) THEN '[]'
                               WHEN json_type(i.value) = 'array' THEN i.value
                               ELSE json_extract(i.value, '$.allComposers') END) c
                WHERE i.key IN ('composer.composerData', 'allComposers') AND json_valid(i.value)
                AND json_valid(c.value)
                AND COALESCE(json_extract(c.value, '$.composerId'), '') != ''
                AND (json_extract(c.value, '$.status') = 'generating'
                     OR (json_extract(c.value, '$.status') IS NULL
                         AND json_extract(c.value, '$.unfinishedRunAt') > 0))
                AND COALESCE(json_extract(c.value, '$.isArchived'), 0) = 0
                AND COALESCE(json_extract(c.value, '$.isDraft'), 0) = 0
                AND updated >= \(cutoff.timeIntervalSince1970 * 1_000)
                AND updated <= \(currentTime.timeIntervalSince1970 * 1_000)
                ORDER BY updated DESC LIMIT \(maxSessions)
                """, limit: maxSessions)
            for row in global + legacy {
                guard let id = row["id"] as? String, !id.isEmpty,
                      let updated = DesktopAIStorage.milliseconds(row["updated"]) else { continue }
                let taskID = "cursor-session-" + DesktopAIStorage.identity([id])
                let task = AIProgressTask(
                    id: taskID, provider: .cursor,
                    title: (row["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Cursor",
                    detail: row["model"] as? String, progress: nil,
                    status: (row["blocked"] as? NSNumber)?.boolValue == true ? .blocked : .running,
                    updatedAt: updated, startedAt: DesktopAIStorage.milliseconds(row["unfinished"])
                        ?? DesktopAIStorage.milliseconds(row["created"])
                )
                if tasks[taskID].map({ $0.updatedAt >= updated }) != true { tasks[taskID] = task }
            }
        }
        return Array(tasks.values.sorted {
            $0.updatedAt != $1.updatedAt ? $0.updatedAt > $1.updatedAt : $0.id < $1.id
        }.prefix(maxSessions))
    }
}
