import Foundation
import SQLite3
import ZislaCore

/// Reads Antigravity's explicit non-idle conversation summaries without opening transcripts.
public final class AntigravitySessionActivityDetector: AIActivityDetecting {
    private static let surfaces = ["antigravity", "antigravity-ide", "antigravity-cli"]
    static let maximumTasksPerSurface = 128
    static let maximumTitleCharacters = 256
    static let maximumIdentifierBytes = 256
    static let maximumRowBytes: Int32 = 1_024 * 1_024

    public let dataDirectoryURL: URL

    private let now: () -> Date
    private let runningClients: () -> [String: Date]

    public init(
        dataDirectoryURL: URL? = nil,
        now: @escaping () -> Date = Date.init,
        fileManager: FileManager = .default,
        runningClients: @escaping () -> [String: Date] = AntigravitySessionActivityDetector.defaultRunningClients
    ) {
        self.dataDirectoryURL = dataDirectoryURL ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini", isDirectory: true)
        self.now = now
        self.runningClients = runningClients
    }

    public func activeTasks() throws -> [AIProgressTask] {
        let clients = runningClients()
        let currentTime = now()
        var tasks: [AIProgressTask] = []
        for surface in Self.surfaces {
            guard let launchedAt = clients[surface] else { continue }
            let databaseURL = dataDirectoryURL
                .appendingPathComponent(surface, isDirectory: true)
                .appendingPathComponent("conversation_summaries.db", isDirectory: false)
            tasks.append(contentsOf: queryTasks(
                in: databaseURL,
                surface: surface,
                from: launchedAt.timeIntervalSince1970,
                through: currentTime.timeIntervalSince1970
            ))
        }
        return tasks.sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id < $1.id
        }
    }

    private func queryTasks(
        in url: URL,
        surface: String,
        from cutoff: TimeInterval,
        through now: TimeInterval
    ) -> [AIProgressTask] {
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK,
              let database else {
            sqlite3_close(database)
            return []
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 500)
        sqlite3_limit(database, SQLITE_LIMIT_LENGTH, Self.maximumRowBytes)

        // A corrupt or unexpectedly large store must not stall every other provider's refresh.
        let remainingBatches = UnsafeMutablePointer<Int>.allocate(capacity: 1)
        remainingBatches.initialize(to: 1_000)
        sqlite3_progress_handler(database, 1_000, { context in
            let remaining = context!.assumingMemoryBound(to: Int.self)
            remaining.pointee -= 1
            return remaining.pointee <= 0 ? 1 : 0
        }, remainingBatches)
        defer {
            sqlite3_progress_handler(database, 0, nil, nil)
            remainingBatches.deinitialize(count: 1)
            remainingBatches.deallocate()
        }

        // The summary format has appeared as SQLite datetime text and numeric Unix timestamps.
        let sql = """
            WITH active AS (
                SELECT conversation_id, substr(title, 1, \(Self.maximumTitleCharacters)) AS title,
                       CASE
                           WHEN typeof(last_modified_time) IN ('integer', 'real')
                               THEN CASE WHEN last_modified_time >= 100000000000
                                   THEN last_modified_time / 1000.0 ELSE last_modified_time END
                           ELSE CAST(strftime('%s', last_modified_time) AS REAL)
                               + CAST(substr(strftime('%f', last_modified_time), 3) AS REAL)
                       END AS modified_at
                FROM conversation_summaries
                WHERE not_fully_idle = 1 AND killed = 0
                    AND typeof(conversation_id) = 'text'
                    AND length(CAST(conversation_id AS BLOB)) BETWEEN 1 AND \(Self.maximumIdentifierBytes)
            )
            SELECT conversation_id, title, modified_at
            FROM active
            WHERE modified_at >= ? AND modified_at <= ?
            ORDER BY modified_at DESC, conversation_id ASC
            LIMIT \(Self.maximumTasksPerSurface)
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            sqlite3_finalize(statement)
            return []
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, cutoff)
        sqlite3_bind_double(statement, 2, now)

        var tasks: [AIProgressTask] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return tasks }
            guard result == SQLITE_ROW else { return [] }
            guard let rawID = sqlite3_column_text(statement, 0),
                  let identifier = String(validatingCString: UnsafeRawPointer(rawID).assumingMemoryBound(to: CChar.self)),
                  identifier.utf8.count == Int(sqlite3_column_bytes(statement, 0)) else { continue }
            let conversationID = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !conversationID.isEmpty else { continue }
            let rawTitle = sqlite3_column_text(statement, 1)
            let title = rawTitle.flatMap {
                String(validatingCString: UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self))
            }?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            tasks.append(AIProgressTask(
                id: "\(surface)-\(conversationID)",
                provider: .antigravity,
                title: title.flatMap { $0.isEmpty ? nil : $0 } ?? "Antigravity",
                progress: nil,
                status: .running,
                updatedAt: Date(timeIntervalSince1970: now)
            ))
        }
    }

    public static func defaultRunningClients() -> [String: Date] {
        guard let data = CodexSessionActivityDetector.runProcessOutput(
            executableURL: URL(fileURLWithPath: "/bin/ps"),
            arguments: ["-axo", "pid=,lstart=,comm="],
            timeout: 2
        ) else { return [:] }
        return parseRunningClients(data)
    }

    static func parseRunningClients(_ data: Data) -> [String: Date] {
        var surfacesByPID: [Int32: [String]] = [:]
        for line in String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline) {
            let fields = line.split(maxSplits: 6, whereSeparator: \.isWhitespace)
            guard fields.count == 7, let pid = Int32(fields[0]), pid > 0 else { continue }
            let executable = String(fields[6]).lowercased()
            let executableURL = URL(fileURLWithPath: executable)
            let name = executableURL.lastPathComponent
            let directory = executableURL.deletingLastPathComponent().path
            let isEditor = directory.hasSuffix("/antigravity.app/contents/macos")
                || directory.hasSuffix("/antigravity ide.app/contents/macos")
            if isEditor, ["antigravity", "antigravity ide", "electron"].contains(name) {
                // Both folder names are used by editor releases; helper lifetimes do not prove a live editor.
                surfacesByPID[pid] = ["antigravity", "antigravity-ide"]
            } else if !executable.contains(".app/"), ["agy", "antigravity"].contains(name) {
                surfacesByPID[pid] = ["antigravity-cli"]
            }
        }

        let startsByPID = CodexSessionActivityDetector.parseProcessStartDates(
            fromProcessList: data,
            matching: Set(surfacesByPID.keys)
        )
        var startsBySurface: [String: Date] = [:]
        for (pid, surfaces) in surfacesByPID {
            guard let startedAt = startsByPID[pid] else { continue }
            for surface in surfaces {
                startsBySurface[surface] = min(startsBySurface[surface] ?? startedAt, startedAt)
            }
        }
        return startsBySurface
    }
}
