import Foundation
import SQLite3
import ZislaCore

public struct ScreenshotSourceSnapshot: Codable, Equatable, Sendable {
    public var applicationName: String?
    public var bundleIdentifier: String?
    public var processIdentifier: Int32?
    public var capturedAt: Date

    public init(applicationName: String?, bundleIdentifier: String?, processIdentifier: Int32?, capturedAt: Date = Date()) {
        self.applicationName = applicationName
        self.bundleIdentifier = bundleIdentifier
        self.processIdentifier = processIdentifier
        self.capturedAt = capturedAt
    }
}

public struct ShelfScreenshotMetadata: Codable, Equatable, Sendable {
    public var source: ScreenshotSourceSnapshot
    public var isLongScreenshot: Bool
    public var initialCaptureRect: CGRect
    public var captureRect: CGRect
    public var screenFrame: CGRect?
    public var displayIdentifier: UInt32?
    public var pixelWidth: Int
    public var pixelHeight: Int

    public init(source: ScreenshotSourceSnapshot, isLongScreenshot: Bool, initialCaptureRect: CGRect,
                captureRect: CGRect, screenFrame: CGRect?, displayIdentifier: UInt32?,
                pixelWidth: Int, pixelHeight: Int) {
        self.source = source
        self.isLongScreenshot = isLongScreenshot
        self.initialCaptureRect = initialCaptureRect
        self.captureRect = captureRect
        self.screenFrame = screenFrame
        self.displayIdentifier = displayIdentifier
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}

struct ShelfScreenshotRecord {
    var id: UUID
    var addedAt: Date
    var shelfOrder: Int64
    var metadata: ShelfScreenshotMetadata
    var png: Data
}

struct ShelfScreenshotListing {
    var id: UUID
    var addedAt: Date
    var shelfOrder: Int64
    var metadata: ShelfScreenshotMetadata
}

private struct ShelfScreenshotDatabaseError: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}

/// Cache files are disposable; FileShelfStore serializes access on the main actor.
final class ShelfScreenshotDatabase {
    let directory: URL
    var storageURL: URL { directory.appendingPathComponent("screenshots.sqlite") }
    private var connection: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(directory: URL) { self.directory = directory }
    deinit { sqlite3_close(connection) }

    private func database() throws -> OpaquePointer {
        if let connection { return connection }
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        if !manager.fileExists(atPath: storageURL.path) {
            guard manager.createFile(atPath: storageURL.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                throw CocoaError(.fileWriteNoPermission)
            }
        }
        try restrictPermissions()
        var opened: OpaquePointer?
        guard sqlite3_open_v2(storageURL.path, &opened, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK,
              let opened else {
            let error = failure(opened)
            sqlite3_close(opened)
            throw error
        }
        do {
            guard sqlite3_busy_timeout(opened, 1_000) == SQLITE_OK else { throw failure(opened) }
            try execute("PRAGMA synchronous = FULL", on: opened)
            try execute("PRAGMA temp_store = MEMORY", on: opened)
            try execute("""
                CREATE TABLE IF NOT EXISTS screenshots (
                    id TEXT PRIMARY KEY NOT NULL,
                    added_at REAL NOT NULL,
                    shelf_order INTEGER NOT NULL,
                    metadata BLOB NOT NULL,
                    png BLOB NOT NULL
                )
                """, on: opened)
            try execute("CREATE INDEX IF NOT EXISTS screenshots_shelf_order ON screenshots(shelf_order, id)", on: opened)
            try restrictPermissions()
            connection = opened
            return opened
        } catch {
            sqlite3_close(opened)
            throw error
        }
    }

    private func restrictPermissions() throws {
        for suffix in ["", "-journal", "-wal", "-shm"] {
            let path = storageURL.path + suffix
            if FileManager.default.fileExists(atPath: path) {
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
            }
        }
    }

    private func failure(_ database: OpaquePointer?) -> Error {
        ShelfScreenshotDatabaseError(message: database.map { String(cString: sqlite3_errmsg($0)) }
            ?? AppLocalization.text("无法打开截图数据库"))
    }

    private func execute(_ sql: String, on database: OpaquePointer) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw failure(database) }
    }

    private func statement(_ sql: String, on database: OpaquePointer) throws -> OpaquePointer {
        var value: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &value, nil) == SQLITE_OK, let value else { throw failure(database) }
        return value
    }

    private func bind(_ data: Data, at index: Int32, to statement: OpaquePointer, database: OpaquePointer) throws {
        guard data.count <= Int(Int32.max) else { throw CocoaError(.fileReadTooLarge) }
        let result = data.withUnsafeBytes { sqlite3_bind_blob(statement, index, $0.baseAddress, Int32($0.count), transient) }
        guard result == SQLITE_OK else { throw failure(database) }
    }

    func insert(_ record: ShelfScreenshotRecord) throws {
        let database = try database()
        let query = try statement("INSERT INTO screenshots VALUES (?, ?, ?, ?, ?)", on: database)
        defer { sqlite3_finalize(query) }
        guard sqlite3_bind_text(query, 1, record.id.uuidString, -1, transient) == SQLITE_OK,
              sqlite3_bind_double(query, 2, record.addedAt.timeIntervalSince1970) == SQLITE_OK,
              sqlite3_bind_int64(query, 3, record.shelfOrder) == SQLITE_OK else { throw failure(database) }
        try bind(JSONEncoder().encode(record.metadata), at: 4, to: query, database: database)
        try bind(record.png, at: 5, to: query, database: database)
        guard sqlite3_step(query) == SQLITE_DONE else { throw failure(database) }
    }

    func records() throws -> [ShelfScreenshotListing] {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return [] }
        let database = try database()
        let query = try statement("SELECT id, added_at, shelf_order, metadata FROM screenshots ORDER BY shelf_order, id", on: database)
        defer { sqlite3_finalize(query) }
        var records: [ShelfScreenshotListing] = []
        while true {
            let result = sqlite3_step(query)
            if result == SQLITE_DONE { return records }
            guard result == SQLITE_ROW else { throw failure(database) }
            records.append(try listing(from: query))
        }
    }

    func record(id: UUID) throws -> ShelfScreenshotRecord {
        let database = try database()
        let query = try statement("SELECT id, added_at, shelf_order, metadata, png FROM screenshots WHERE id = ?", on: database)
        defer { sqlite3_finalize(query) }
        guard sqlite3_bind_text(query, 1, id.uuidString, -1, transient) == SQLITE_OK else { throw failure(database) }
        let result = sqlite3_step(query)
        if result == SQLITE_DONE { throw CocoaError(.fileReadNoSuchFile) }
        guard result == SQLITE_ROW else { throw failure(database) }
        let value = try listing(from: query)
        return ShelfScreenshotRecord(id: value.id, addedAt: value.addedAt, shelfOrder: value.shelfOrder,
            metadata: value.metadata, png: try blob(4, from: query))
    }

    private func listing(from query: OpaquePointer) throws -> ShelfScreenshotListing {
        guard let text = sqlite3_column_text(query, 0), let id = UUID(uuidString: String(cString: text)) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return ShelfScreenshotListing(id: id, addedAt: Date(timeIntervalSince1970: sqlite3_column_double(query, 1)),
            shelfOrder: sqlite3_column_int64(query, 2),
            metadata: try JSONDecoder().decode(ShelfScreenshotMetadata.self, from: blob(3, from: query)))
    }

    private func blob(_ column: Int32, from query: OpaquePointer) throws -> Data {
        guard let bytes = sqlite3_column_blob(query, column) else { throw CocoaError(.fileReadCorruptFile) }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(query, column)))
    }

    func remove(ids: [UUID]) throws {
        let database = try database()
        try execute("BEGIN IMMEDIATE", on: database)
        do {
            for id in ids {
                let query = try statement("DELETE FROM screenshots WHERE id = ?", on: database)
                defer { sqlite3_finalize(query) }
                guard sqlite3_bind_text(query, 1, id.uuidString, -1, transient) == SQLITE_OK,
                      sqlite3_step(query) == SQLITE_DONE else { throw failure(database) }
            }
            try execute("COMMIT", on: database)
        } catch {
            try execute("ROLLBACK", on: database)
            throw error
        }
    }
}
