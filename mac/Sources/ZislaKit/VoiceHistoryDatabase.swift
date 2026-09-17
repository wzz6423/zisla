import Foundation
import Darwin
import SQLite3

private let voiceSQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class VoiceHistoryDatabase {
    private var connection: OpaquePointer?
    private var accessDescriptor: Int32 = -1
    private var persistedEntries: [UUID: VoiceHistoryEntry] = [:]
    private var persistedStatistics: VoiceHistoryPersistentState.CumulativeStatistics?
    private(set) var revision: String?

    init(storageURL: URL, fileManager: FileManager) throws {
        try fileManager.createDirectory(
            at: storageURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let result = sqlite3_open_v2(
            storageURL.path,
            &connection,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE,
            nil
        )
        try check(result)
        accessDescriptor = open(storageURL.appendingPathExtension("lock").path, O_RDWR | O_CREAT, 0o600)
        guard accessDescriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        try lock()
        defer { unlock() }
        let version = try schemaVersion()
        guard version == 0 || version == 1 else { throw CocoaError(.fileReadCorruptFile) }
        try execute("PRAGMA journal_mode = WAL")
        if version == 0 {
            try execute("""
                CREATE TABLE IF NOT EXISTS voice_history_entries (
                    id TEXT PRIMARY KEY NOT NULL,
                    payload BLOB NOT NULL
                );
                CREATE TABLE IF NOT EXISTS voice_history_state (
                    id INTEGER PRIMARY KEY CHECK(id = 1),
                    revision TEXT NOT NULL,
                    statistics BLOB NOT NULL
                );
                """)
        }
    }

    deinit {
        sqlite3_close_v2(connection)
        if accessDescriptor >= 0 { close(accessDescriptor) }
    }

    func lock() throws {
        guard flock(accessDescriptor, LOCK_EX | LOCK_NB) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }

    func unlock() {
        flock(accessDescriptor, LOCK_UN)
    }

    func validateRevision() throws {
        let statement = try prepare("SELECT revision FROM voice_history_state WHERE id = 1")
        defer { sqlite3_finalize(statement) }
        try check(sqlite3_step(statement), expected: SQLITE_ROW)
        guard let currentRevision = sqlite3_column_text(statement, 0),
              String(cString: currentRevision) == revision else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    func load() throws -> VoiceHistoryPersistentState? {
        var loadedRevision: String?
        var loadedEntries: [UUID: VoiceHistoryEntry] = [:]
        let state: VoiceHistoryPersistentState? = try transaction(begin: "BEGIN") {
            let stateStatement = try prepare("SELECT revision, statistics FROM voice_history_state WHERE id = 1")
            defer { sqlite3_finalize(stateStatement) }
            let result = sqlite3_step(stateStatement)
            if result == SQLITE_DONE {
                let entriesStatement = try prepare("SELECT 1 FROM voice_history_entries LIMIT 1")
                defer { sqlite3_finalize(entriesStatement) }
                try check(sqlite3_step(entriesStatement), expected: SQLITE_DONE)
                // A committed database must never fall back to the stale JSON archive.
                guard try schemaVersion() == 0 else { throw CocoaError(.fileReadCorruptFile) }
                return nil
            }
            try check(result, expected: SQLITE_ROW)
            guard try schemaVersion() == 1 else { throw CocoaError(.fileReadCorruptFile) }
            guard let revisionText = sqlite3_column_text(stateStatement, 0) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            loadedRevision = String(cString: revisionText)
            let statistics = try JSONDecoder().decode(
                VoiceHistoryPersistentState.CumulativeStatistics.self,
                from: blob(at: 1, in: stateStatement)
            )
            let entriesStatement = try prepare("SELECT id, payload FROM voice_history_entries")
            defer { sqlite3_finalize(entriesStatement) }
            while true {
                let result = sqlite3_step(entriesStatement)
                if result == SQLITE_DONE { break }
                try check(result, expected: SQLITE_ROW)
                let entry = try JSONDecoder().decode(VoiceHistoryEntry.self, from: blob(at: 1, in: entriesStatement))
                guard let idText = sqlite3_column_text(entriesStatement, 0),
                      String(cString: idText) == entry.id.uuidString,
                      loadedEntries.updateValue(entry, forKey: entry.id) == nil else {
                    throw CocoaError(.fileReadCorruptFile)
                }
            }
            return VoiceHistoryPersistentState(entries: Array(loadedEntries.values), cumulativeStatistics: statistics)
        }
        persistedEntries = loadedEntries
        persistedStatistics = state?.cumulativeStatistics
        revision = loadedRevision
        return state
    }

    func save(_ state: VoiceHistoryPersistentState, commitRevision: UUID? = nil) throws {
        var candidate: [UUID: VoiceHistoryEntry] = [:]
        for entry in state.entries {
            guard candidate.updateValue(entry, forKey: entry.id) == nil else {
                throw CocoaError(.fileReadCorruptFile)
            }
        }
        let removedIDs = persistedEntries.keys.filter { candidate[$0] == nil }
        let changedEntries = try state.entries.compactMap { entry -> (UUID, Data)? in
            guard persistedEntries[entry.id] != entry else { return nil }
            return (entry.id, try JSONEncoder().encode(entry))
        }
        guard !removedIDs.isEmpty || !changedEntries.isEmpty
            || persistedStatistics != state.cumulativeStatistics || commitRevision != nil else {
            try validateRevision()
            return
        }

        let nextRevision = (commitRevision ?? UUID()).uuidString
        let statisticsData = try JSONEncoder().encode(state.cumulativeStatistics)
        try transaction(begin: "BEGIN IMMEDIATE") {
            if !removedIDs.isEmpty {
                let statement = try prepare("DELETE FROM voice_history_entries WHERE id = ?")
                defer { sqlite3_finalize(statement) }
                for id in removedIDs {
                    sqlite3_reset(statement)
                    try bind(id.uuidString, to: 1, in: statement)
                    try check(sqlite3_step(statement), expected: SQLITE_DONE)
                }
            }
            if !changedEntries.isEmpty {
                let statement = try prepare("""
                    INSERT INTO voice_history_entries(id, payload) VALUES(?, ?)
                    ON CONFLICT(id) DO UPDATE SET payload = excluded.payload
                    """)
                defer { sqlite3_finalize(statement) }
                for (id, data) in changedEntries {
                    sqlite3_reset(statement)
                    try bind(id.uuidString, to: 1, in: statement)
                    try bind(data, to: 2, in: statement)
                    try check(sqlite3_step(statement), expected: SQLITE_DONE)
                }
            }
            let statement = try prepare(revision == nil
                ? "INSERT INTO voice_history_state(statistics, revision, id) VALUES(?, ?, 1)"
                : "UPDATE voice_history_state SET statistics = ?, revision = ? WHERE id = 1 AND revision = ?"
            )
            defer { sqlite3_finalize(statement) }
            try bind(statisticsData, to: 1, in: statement)
            try bind(nextRevision, to: 2, in: statement)
            if let revision { try bind(revision, to: 3, in: statement) }
            try check(sqlite3_step(statement), expected: SQLITE_DONE)
            // Reject a stale store rather than overwrite another writer's cumulative totals.
            guard sqlite3_changes(connection) == 1 else { throw CocoaError(.fileWriteUnknown) }
            if revision == nil { try execute("PRAGMA user_version = 1") }
        }
        persistedEntries = candidate
        persistedStatistics = state.cumulativeStatistics
        revision = nextRevision
    }

    private func transaction<T>(begin: String, _ body: () throws -> T) throws -> T {
        try execute(begin)
        do {
            let result = try body()
            try execute("COMMIT")
            return result
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func schemaVersion() throws -> Int32 {
        let statement = try prepare("PRAGMA user_version")
        defer { sqlite3_finalize(statement) }
        try check(sqlite3_step(statement), expected: SQLITE_ROW)
        return sqlite3_column_int(statement, 0)
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        try check(sqlite3_prepare_v2(connection, sql, -1, &statement, nil))
        return statement
    }

    private func execute(_ sql: String) throws {
        try check(sqlite3_exec(connection, sql, nil, nil, nil))
    }

    private func bind(_ value: String, to index: Int32, in statement: OpaquePointer?) throws {
        try check(value.withCString {
            sqlite3_bind_text(statement, index, $0, -1, voiceSQLiteTransient)
        })
    }

    private func bind(_ value: Data, to index: Int32, in statement: OpaquePointer?) throws {
        try check(value.withUnsafeBytes {
            sqlite3_bind_blob64(statement, index, $0.baseAddress, UInt64($0.count), voiceSQLiteTransient)
        })
    }

    private func blob(at index: Int32, in statement: OpaquePointer?) -> Data {
        let count = Int(sqlite3_column_bytes(statement, index))
        return sqlite3_column_blob(statement, index).map { Data(bytes: $0, count: count) } ?? Data()
    }

    private func check(_ result: Int32, expected: Int32 = SQLITE_OK) throws {
        guard result == expected else {
            throw NSError(
                domain: "SQLite",
                code: Int(result),
                userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(connection))]
            )
        }
    }
}
