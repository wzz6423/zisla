import Foundation
import SQLite3
import ZislaCore

// MARK: - Record

/// One persisted sample of the system monitor.
///
/// Optional fields stay `nil` when the machine cannot report them (GPU counters, fan speeds,
/// AppleSMC temperatures) so an exported sheet keeps the "unavailable" distinction instead of
/// fabricating zeros. `Double?` maps to a nullable column in the history database, which is what
/// keeps that distinction across a restart.
public struct SystemMetricsRecord: Codable, Equatable, Sendable {
    public var timestamp: Date
    public var cpuUsage: Double
    public var cpuUser: Double
    public var cpuSystem: Double
    public var cpuIdle: Double
    public var cpuTemperatureCelsius: Double?
    public var gpuUsage: Double?
    public var gpuRenderer: Double?
    public var gpuTiler: Double?
    public var gpuTemperatureCelsius: Double?
    public var memoryUsedBytes: UInt64
    public var memoryTotalBytes: UInt64
    public var memoryPressureRatio: Double
    public var diskUsedBytes: UInt64
    public var diskTotalBytes: UInt64
    public var diskReadBytesPerSecond: Double?
    public var diskWriteBytesPerSecond: Double?
    public var diskTemperatureCelsius: Double?
    public var fanRPMs: [Double]
    public var networkReceiveBytesPerSecond: Double
    public var networkSendBytesPerSecond: Double
    public var networkReceivedBytes: UInt64
    public var networkSentBytes: UInt64

    public init(
        timestamp: Date,
        cpuUsage: Double = 0,
        cpuUser: Double = 0,
        cpuSystem: Double = 0,
        cpuIdle: Double = 0,
        cpuTemperatureCelsius: Double? = nil,
        gpuUsage: Double? = nil,
        gpuRenderer: Double? = nil,
        gpuTiler: Double? = nil,
        gpuTemperatureCelsius: Double? = nil,
        memoryUsedBytes: UInt64 = 0,
        memoryTotalBytes: UInt64 = 0,
        memoryPressureRatio: Double = 0,
        diskUsedBytes: UInt64 = 0,
        diskTotalBytes: UInt64 = 0,
        diskReadBytesPerSecond: Double? = nil,
        diskWriteBytesPerSecond: Double? = nil,
        diskTemperatureCelsius: Double? = nil,
        fanRPMs: [Double] = [],
        networkReceiveBytesPerSecond: Double = 0,
        networkSendBytesPerSecond: Double = 0,
        networkReceivedBytes: UInt64 = 0,
        networkSentBytes: UInt64 = 0
    ) {
        self.timestamp = timestamp
        self.cpuUsage = cpuUsage
        self.cpuUser = cpuUser
        self.cpuSystem = cpuSystem
        self.cpuIdle = cpuIdle
        self.cpuTemperatureCelsius = cpuTemperatureCelsius
        self.gpuUsage = gpuUsage
        self.gpuRenderer = gpuRenderer
        self.gpuTiler = gpuTiler
        self.gpuTemperatureCelsius = gpuTemperatureCelsius
        self.memoryUsedBytes = memoryUsedBytes
        self.memoryTotalBytes = memoryTotalBytes
        self.memoryPressureRatio = memoryPressureRatio
        self.diskUsedBytes = diskUsedBytes
        self.diskTotalBytes = diskTotalBytes
        self.diskReadBytesPerSecond = diskReadBytesPerSecond
        self.diskWriteBytesPerSecond = diskWriteBytesPerSecond
        self.diskTemperatureCelsius = diskTemperatureCelsius
        self.fanRPMs = fanRPMs
        self.networkReceiveBytesPerSecond = networkReceiveBytesPerSecond
        self.networkSendBytesPerSecond = networkSendBytesPerSecond
        self.networkReceivedBytes = networkReceivedBytes
        self.networkSentBytes = networkSentBytes
    }

    public init(snapshot: SystemMetricsSnapshot) {
        let temperature: (TemperatureMetric?) -> Double? = { metric in
            guard case let .celsius(value)? = metric else { return nil }
            return value
        }
        let gpu: GPUUsageMetrics?
        if case let .available(metrics) = snapshot.gpu {
            gpu = metrics
        } else {
            gpu = nil
        }
        let fans: [Double]
        if case let .available(rpm, _) = snapshot.fan {
            fans = rpm
        } else {
            fans = []
        }

        self.init(
            timestamp: snapshot.sampledAt,
            cpuUsage: snapshot.cpu.usage,
            cpuUser: snapshot.cpu.userFraction + snapshot.cpu.niceFraction,
            cpuSystem: snapshot.cpu.systemFraction,
            cpuIdle: snapshot.cpu.idleFraction,
            cpuTemperatureCelsius: temperature(snapshot.cpu.temperature),
            gpuUsage: gpu?.usage,
            gpuRenderer: gpu?.rendererUsage,
            gpuTiler: gpu?.tilerUsage,
            gpuTemperatureCelsius: temperature(gpu?.temperature),
            memoryUsedBytes: snapshot.memory.usedBytes,
            memoryTotalBytes: snapshot.memory.totalBytes,
            memoryPressureRatio: snapshot.memory.pressureRatio,
            diskUsedBytes: snapshot.disk.usedBytes,
            diskTotalBytes: snapshot.disk.totalBytes,
            diskReadBytesPerSecond: snapshot.disk.readBytesPerSecond,
            diskWriteBytesPerSecond: snapshot.disk.writeBytesPerSecond,
            diskTemperatureCelsius: temperature(snapshot.disk.temperature),
            fanRPMs: fans,
            networkReceiveBytesPerSecond: snapshot.network.receiveBytesPerSecond,
            networkSendBytesPerSecond: snapshot.network.sendBytesPerSecond,
            networkReceivedBytes: snapshot.network.bytesReceived,
            networkSentBytes: snapshot.network.bytesSent
        )
    }

    /// 0...1; 0 when the total is unknown.
    public var memoryUsageRatio: Double {
        guard memoryTotalBytes > 0 else { return 0 }
        return min(1, max(0, Double(memoryUsedBytes) / Double(memoryTotalBytes)))
    }

    /// 0...1; 0 when the total is unknown.
    public var diskUsageRatio: Double {
        guard diskTotalBytes > 0 else { return 0 }
        return min(1, max(0, Double(diskUsedBytes) / Double(diskTotalBytes)))
    }
}

// MARK: - Stats

public struct SystemMetricsHistoryStats: Equatable, Sendable {
    public var count: Int
    public var oldest: Date?
    public var newest: Date?

    public init(count: Int = 0, oldest: Date? = nil, newest: Date? = nil) {
        self.count = count
        self.oldest = oldest
        self.newest = newest
    }

    public static let empty = SystemMetricsHistoryStats()

    /// Covered interval in seconds; 0 for fewer than two samples.
    public var span: TimeInterval {
        guard let oldest, let newest else { return 0 }
        return max(0, newest.timeIntervalSince(oldest))
    }
}

// MARK: - Persistence

/// Storage seam for the history archive, so tests never touch Application Support.
public protocol SystemMetricsHistoryPersisting: Sendable {
    /// Every stored sample, oldest first.
    func loadRecords() -> [SystemMetricsRecord]
    /// Stores one sample and drops the oldest ones beyond `capacity`.
    func appendRecord(_ record: SystemMetricsRecord, capacity: Int)
    func removeAll()
}

private struct SystemMetricsHistoryDatabaseError: LocalizedError {
    let message: String
    var isNotADatabase = false

    var errorDescription: String? { message }
}

/// SQLite archive of the recorded samples.
///
/// One row per sample in `metrics`, keyed by its timestamp, with the per-fan readings in a child
/// table so the schema does not bake in a fan count. Recording is a single-row `INSERT` and the ring
/// buffer is enforced in SQL, so nothing rewrites the whole archive the way an append-only text log
/// has to once it overflows.
public final class SystemMetricsHistoryDatabase: SystemMetricsHistoryPersisting, @unchecked Sendable {
    private let databaseURL: URL
    private let fileManager: FileManager
    private let queue = DispatchQueue(
        label: "com.zisla.system-metrics-history.database",
        qos: .utility
    )
    private let queueKey = DispatchSpecificKey<UInt8>()
    private var connection: OpaquePointer?
    private var isUnavailable = false

    public init(databaseURL: URL, fileManager: FileManager = .default) {
        self.databaseURL = databaseURL
        self.fileManager = fileManager
        queue.setSpecific(key: queueKey, value: 1)
    }

    deinit {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            closeConnection()
        } else {
            queue.sync { closeConnection() }
        }
    }

    public func loadRecords() -> [SystemMetricsRecord] {
        queue.sync {
            guard let database = connectionOrNil() else { return [] }
            return (try? readRecords(from: database)) ?? []
        }
    }

    public func appendRecord(_ record: SystemMetricsRecord, capacity: Int) {
        queue.sync {
            guard let database = connectionOrNil() else { return }
            // Recording is best effort: a full disk must never disturb the sampler.
            try? write(record, capacity: max(1, capacity), to: database)
        }
    }

    public func removeAll() {
        queue.sync {
            guard let database = connectionOrNil() else { return }
            try? execute("DELETE FROM metrics", on: database)
            try? execute("DELETE FROM metric_fans", on: database)
        }
    }

    // MARK: Connection

    private func connectionOrNil() -> OpaquePointer? {
        if let connection { return connection }
        guard !isUnavailable else { return nil }
        do {
            connection = try openDatabase()
            return connection
        } catch let error as SystemMetricsHistoryDatabaseError where error.isNotADatabase {
            // `sqlite3_open_v2` succeeds for a file that is not a database and only the first
            // statement fails, so a truncated or foreign file would otherwise disable recording for
            // the rest of the process. Drop it and start an empty archive instead.
            discardDatabaseFiles()
            if let recovered = try? openDatabase() {
                connection = recovered
                return recovered
            }
            isUnavailable = true
            return nil
        } catch {
            isUnavailable = true
            return nil
        }
    }

    private func openDatabase() throws -> OpaquePointer {
        try fileManager.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var opened: OpaquePointer?
        let result = sqlite3_open_v2(
            databaseURL.path,
            &opened,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX,
            nil
        )
        guard result == SQLITE_OK, let opened else {
            let message = sqliteMessage(opened, fallback: "system metrics history database could not be opened")
            sqlite3_close(opened)
            throw SystemMetricsHistoryDatabaseError(message: message)
        }
        do {
            guard sqlite3_busy_timeout(opened, 1_000) == SQLITE_OK else {
                throw SystemMetricsHistoryDatabaseError(
                    message: sqliteMessage(opened, fallback: "system metrics history database could not be configured")
                )
            }
            try verifyDatabaseFile(of: opened)
            try execute("PRAGMA journal_mode = WAL", on: opened)
            try execute("PRAGMA synchronous = NORMAL", on: opened)
            try execute("PRAGMA foreign_keys = ON", on: opened)
            try createSchema(on: opened)
            try restrictFilePermissions()
            return opened
        } catch {
            sqlite3_close(opened)
            throw error
        }
    }

    /// The cheapest statement that proves the file really is a database. Preparing it is not enough:
    /// SQLite compiles a statement without touching the file, so the header is only validated on the
    /// first `sqlite3_step`.
    private func verifyDatabaseFile(of database: OpaquePointer) throws {
        var statement: OpaquePointer?
        let prepared = sqlite3_prepare_v2(database, "PRAGMA schema_version", -1, &statement, nil)
        guard prepared == SQLITE_OK, let statement else {
            sqlite3_finalize(statement)
            throw SystemMetricsHistoryDatabaseError(
                message: sqliteMessage(database, fallback: "system metrics history file is not a database")
            )
        }
        defer { sqlite3_finalize(statement) }

        let stepped = sqlite3_step(statement)
        guard stepped == SQLITE_ROW || stepped == SQLITE_DONE else {
            let code = sqlite3_errcode(database)
            throw SystemMetricsHistoryDatabaseError(
                message: sqliteMessage(database, fallback: "system metrics history file is not a database"),
                isNotADatabase: code == SQLITE_NOTADB || code == SQLITE_CORRUPT
            )
        }
    }

    private func createSchema(on database: OpaquePointer) throws {
        try execute(
            """
            CREATE TABLE IF NOT EXISTS metrics (
                timestamp REAL PRIMARY KEY,
                cpu_usage REAL NOT NULL,
                cpu_user REAL NOT NULL,
                cpu_system REAL NOT NULL,
                cpu_idle REAL NOT NULL,
                cpu_temperature REAL,
                gpu_usage REAL,
                gpu_renderer REAL,
                gpu_tiler REAL,
                gpu_temperature REAL,
                memory_used_bytes INTEGER NOT NULL,
                memory_total_bytes INTEGER NOT NULL,
                memory_pressure_ratio REAL NOT NULL,
                disk_used_bytes INTEGER NOT NULL,
                disk_total_bytes INTEGER NOT NULL,
                disk_read_bytes_per_second REAL,
                disk_write_bytes_per_second REAL,
                disk_temperature REAL,
                network_receive_bytes_per_second REAL NOT NULL,
                network_send_bytes_per_second REAL NOT NULL,
                network_received_bytes INTEGER NOT NULL,
                network_sent_bytes INTEGER NOT NULL
            )
            """,
            on: database
        )
        // The fan rows cascade with their sample, so pruning never leaves readings behind.
        try execute(
            """
            CREATE TABLE IF NOT EXISTS metric_fans (
                timestamp REAL NOT NULL REFERENCES metrics(timestamp) ON DELETE CASCADE,
                fan_index INTEGER NOT NULL,
                rpm REAL NOT NULL,
                PRIMARY KEY (timestamp, fan_index)
            )
            """,
            on: database
        )
    }

    private func discardDatabaseFiles() {
        for path in databaseFilePaths() {
            try? fileManager.removeItem(atPath: path)
        }
    }

    private func restrictFilePermissions() throws {
        for path in databaseFilePaths() where fileManager.fileExists(atPath: path) {
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
        }
    }

    private func databaseFilePaths() -> [String] {
        [
            databaseURL.path,
            "\(databaseURL.path)-wal",
            "\(databaseURL.path)-shm",
        ]
    }

    // MARK: Reading

    private func readRecords(from database: OpaquePointer) throws -> [SystemMetricsRecord] {
        let fans = try readFans(from: database)
        let statement = try prepare(
            """
            SELECT timestamp, cpu_usage, cpu_user, cpu_system, cpu_idle, cpu_temperature,
                   gpu_usage, gpu_renderer, gpu_tiler, gpu_temperature,
                   memory_used_bytes, memory_total_bytes, memory_pressure_ratio,
                   disk_used_bytes, disk_total_bytes, disk_read_bytes_per_second,
                   disk_write_bytes_per_second, disk_temperature,
                   network_receive_bytes_per_second, network_send_bytes_per_second,
                   network_received_bytes, network_sent_bytes
            FROM metrics
            ORDER BY timestamp ASC
            """,
            on: database
        )
        defer { sqlite3_finalize(statement) }

        var records: [SystemMetricsRecord] = []
        rows: while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                let timestamp = sqlite3_column_double(statement, 0)
                records.append(
                    SystemMetricsRecord(
                        timestamp: Date(timeIntervalSince1970: timestamp),
                        cpuUsage: sqlite3_column_double(statement, 1),
                        cpuUser: sqlite3_column_double(statement, 2),
                        cpuSystem: sqlite3_column_double(statement, 3),
                        cpuIdle: sqlite3_column_double(statement, 4),
                        cpuTemperatureCelsius: optionalDouble(statement, index: 5),
                        gpuUsage: optionalDouble(statement, index: 6),
                        gpuRenderer: optionalDouble(statement, index: 7),
                        gpuTiler: optionalDouble(statement, index: 8),
                        gpuTemperatureCelsius: optionalDouble(statement, index: 9),
                        memoryUsedBytes: unsignedValue(statement, index: 10),
                        memoryTotalBytes: unsignedValue(statement, index: 11),
                        memoryPressureRatio: sqlite3_column_double(statement, 12),
                        diskUsedBytes: unsignedValue(statement, index: 13),
                        diskTotalBytes: unsignedValue(statement, index: 14),
                        diskReadBytesPerSecond: optionalDouble(statement, index: 15),
                        diskWriteBytesPerSecond: optionalDouble(statement, index: 16),
                        diskTemperatureCelsius: optionalDouble(statement, index: 17),
                        fanRPMs: fans[timestamp] ?? [],
                        networkReceiveBytesPerSecond: sqlite3_column_double(statement, 18),
                        networkSendBytesPerSecond: sqlite3_column_double(statement, 19),
                        networkReceivedBytes: unsignedValue(statement, index: 20),
                        networkSentBytes: unsignedValue(statement, index: 21)
                    )
                )
            case SQLITE_DONE:
                break rows
            default:
                throw SystemMetricsHistoryDatabaseError(
                    message: sqliteMessage(database, fallback: "system metrics history could not be read")
                )
            }
        }
        return records
    }

    private func readFans(from database: OpaquePointer) throws -> [Double: [Double]] {
        let statement = try prepare(
            "SELECT timestamp, fan_index, rpm FROM metric_fans ORDER BY timestamp ASC, fan_index ASC",
            on: database
        )
        defer { sqlite3_finalize(statement) }

        var fans: [Double: [Double]] = [:]
        rows: while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                let timestamp = sqlite3_column_double(statement, 0)
                let index = Int(sqlite3_column_int64(statement, 1))
                guard index >= 0 else { continue }
                var readings = fans[timestamp] ?? []
                if index == readings.count {
                    readings.append(sqlite3_column_double(statement, 2))
                } else if index < readings.count {
                    readings[index] = sqlite3_column_double(statement, 2)
                }
                fans[timestamp] = readings
            case SQLITE_DONE:
                break rows
            default:
                throw SystemMetricsHistoryDatabaseError(
                    message: sqliteMessage(database, fallback: "system metrics fan readings could not be read")
                )
            }
        }
        return fans
    }

    // MARK: Writing

    private func write(_ record: SystemMetricsRecord, capacity: Int, to database: OpaquePointer) throws {
        try execute("BEGIN IMMEDIATE TRANSACTION", on: database)
        do {
            try insert(record, into: database)
            try prune(to: capacity, in: database)
            try execute("COMMIT", on: database)
        } catch {
            try? execute("ROLLBACK", on: database)
            throw error
        }
        try? restrictFilePermissions()
    }

    private func insert(_ record: SystemMetricsRecord, into database: OpaquePointer) throws {
        let statement = try prepare(
            """
            INSERT OR REPLACE INTO metrics (
                timestamp, cpu_usage, cpu_user, cpu_system, cpu_idle, cpu_temperature,
                gpu_usage, gpu_renderer, gpu_tiler, gpu_temperature,
                memory_used_bytes, memory_total_bytes, memory_pressure_ratio,
                disk_used_bytes, disk_total_bytes, disk_read_bytes_per_second,
                disk_write_bytes_per_second, disk_temperature,
                network_receive_bytes_per_second, network_send_bytes_per_second,
                network_received_bytes, network_sent_bytes
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            on: database
        )
        defer { sqlite3_finalize(statement) }

        try bind(record.timestamp.timeIntervalSince1970, to: statement, index: 1, database: database)
        try bind(record.cpuUsage, to: statement, index: 2, database: database)
        try bind(record.cpuUser, to: statement, index: 3, database: database)
        try bind(record.cpuSystem, to: statement, index: 4, database: database)
        try bind(record.cpuIdle, to: statement, index: 5, database: database)
        try bind(record.cpuTemperatureCelsius, to: statement, index: 6, database: database)
        try bind(record.gpuUsage, to: statement, index: 7, database: database)
        try bind(record.gpuRenderer, to: statement, index: 8, database: database)
        try bind(record.gpuTiler, to: statement, index: 9, database: database)
        try bind(record.gpuTemperatureCelsius, to: statement, index: 10, database: database)
        try bind(record.memoryUsedBytes, to: statement, index: 11, database: database)
        try bind(record.memoryTotalBytes, to: statement, index: 12, database: database)
        try bind(record.memoryPressureRatio, to: statement, index: 13, database: database)
        try bind(record.diskUsedBytes, to: statement, index: 14, database: database)
        try bind(record.diskTotalBytes, to: statement, index: 15, database: database)
        try bind(record.diskReadBytesPerSecond, to: statement, index: 16, database: database)
        try bind(record.diskWriteBytesPerSecond, to: statement, index: 17, database: database)
        try bind(record.diskTemperatureCelsius, to: statement, index: 18, database: database)
        try bind(record.networkReceiveBytesPerSecond, to: statement, index: 19, database: database)
        try bind(record.networkSendBytesPerSecond, to: statement, index: 20, database: database)
        try bind(record.networkReceivedBytes, to: statement, index: 21, database: database)
        try bind(record.networkSentBytes, to: statement, index: 22, database: database)
        try check(sqlite3_step(statement), expected: SQLITE_DONE, database: database)

        try replaceFans(record, in: database)
    }

    private func replaceFans(_ record: SystemMetricsRecord, in database: OpaquePointer) throws {
        let timestamp = record.timestamp.timeIntervalSince1970
        let deletion = try prepare("DELETE FROM metric_fans WHERE timestamp = ?", on: database)
        defer { sqlite3_finalize(deletion) }
        try bind(timestamp, to: deletion, index: 1, database: database)
        try check(sqlite3_step(deletion), expected: SQLITE_DONE, database: database)

        guard !record.fanRPMs.isEmpty else { return }
        let insertion = try prepare(
            "INSERT INTO metric_fans (timestamp, fan_index, rpm) VALUES (?, ?, ?)",
            on: database
        )
        defer { sqlite3_finalize(insertion) }
        for (index, rpm) in record.fanRPMs.enumerated() {
            sqlite3_reset(insertion)
            sqlite3_clear_bindings(insertion)
            try bind(timestamp, to: insertion, index: 1, database: database)
            try check(sqlite3_bind_int64(insertion, 2, sqlite3_int64(index)), database: database)
            try bind(rpm, to: insertion, index: 3, database: database)
            try check(sqlite3_step(insertion), expected: SQLITE_DONE, database: database)
        }
    }

    /// Keeps the newest `capacity` samples. A subquery that has no row (the archive is still smaller
    /// than the ring buffer) yields NULL, and `timestamp < NULL` matches nothing.
    private func prune(to capacity: Int, in database: OpaquePointer) throws {
        let statement = try prepare(
            """
            DELETE FROM metrics
            WHERE timestamp < (
                SELECT timestamp FROM metrics ORDER BY timestamp DESC LIMIT 1 OFFSET ?
            )
            """,
            on: database
        )
        defer { sqlite3_finalize(statement) }
        try check(
            sqlite3_bind_int64(statement, 1, sqlite3_int64(max(0, capacity - 1))),
            database: database
        )
        try check(sqlite3_step(statement), expected: SQLITE_DONE, database: database)
    }

    // MARK: SQLite plumbing

    private func prepare(_ sql: String, on database: OpaquePointer) throws -> OpaquePointer {
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard result == SQLITE_OK, let statement else {
            sqlite3_finalize(statement)
            throw SystemMetricsHistoryDatabaseError(
                message: sqliteMessage(database, fallback: "system metrics history statement could not be prepared")
            )
        }
        return statement
    }

    private func execute(_ sql: String, on database: OpaquePointer) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(database, sql, nil, nil, &errorMessage)
        defer { sqlite3_free(errorMessage) }
        guard result == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) }
                ?? sqliteMessage(database, fallback: "system metrics history database operation failed")
            throw SystemMetricsHistoryDatabaseError(message: message)
        }
    }

    private func bind(
        _ value: Double,
        to statement: OpaquePointer,
        index: Int32,
        database: OpaquePointer
    ) throws {
        try check(sqlite3_bind_double(statement, index, value), database: database)
    }

    private func bind(
        _ value: Double?,
        to statement: OpaquePointer,
        index: Int32,
        database: OpaquePointer
    ) throws {
        guard let value else {
            try check(sqlite3_bind_null(statement, index), database: database)
            return
        }
        try check(sqlite3_bind_double(statement, index, value), database: database)
    }

    private func bind(
        _ value: UInt64,
        to statement: OpaquePointer,
        index: Int32,
        database: OpaquePointer
    ) throws {
        try check(sqlite3_bind_int64(statement, index, sqlite3_int64(clamping: value)), database: database)
    }

    private func check(
        _ result: Int32,
        expected: Int32 = SQLITE_OK,
        database: OpaquePointer
    ) throws {
        guard result == expected else {
            throw SystemMetricsHistoryDatabaseError(
                message: sqliteMessage(database, fallback: "system metrics history database operation failed")
            )
        }
    }

    private func optionalDouble(_ statement: OpaquePointer, index: Int32) -> Double? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return sqlite3_column_double(statement, index)
    }

    private func unsignedValue(_ statement: OpaquePointer, index: Int32) -> UInt64 {
        UInt64(clamping: sqlite3_column_int64(statement, index))
    }

    private func sqliteMessage(_ database: OpaquePointer?, fallback: String) -> String {
        guard let database, let message = sqlite3_errmsg(database) else { return fallback }
        return String(cString: message)
    }

    private func closeConnection() {
        guard let connection else { return }
        sqlite3_close_v2(connection)
        self.connection = nil
    }
}

/// Resolves `AppPaths.systemMetricsHistory` on first use: constructing a `SystemMonitorService`
/// must not read or write Application Support, which is also part of the package smoke contract.
public final class LazySystemMetricsHistoryPersistence: SystemMetricsHistoryPersisting, @unchecked Sendable {
    private let makeDatabase: @Sendable () -> SystemMetricsHistoryDatabase
    private let lock = NSLock()
    private var resolved: SystemMetricsHistoryDatabase?

    public init(makeDatabase: @escaping @Sendable () -> SystemMetricsHistoryDatabase = {
        SystemMetricsHistoryDatabase(databaseURL: AppPaths.systemMetricsHistory)
    }) {
        self.makeDatabase = makeDatabase
    }

    public func loadRecords() -> [SystemMetricsRecord] {
        database().loadRecords()
    }

    public func appendRecord(_ record: SystemMetricsRecord, capacity: Int) {
        database().appendRecord(record, capacity: capacity)
    }

    public func removeAll() {
        database().removeAll()
    }

    private func database() -> SystemMetricsHistoryDatabase {
        lock.lock()
        defer { lock.unlock() }
        if let resolved { return resolved }
        let created = makeDatabase()
        resolved = created
        return created
    }
}

// MARK: - Store

/// Ring buffer of samples over the SQLite archive: recording writes a single row and the archive
/// trims itself in SQL, which keeps a long recording window affordable on SSD.
public final class SystemMetricsHistoryStore: @unchecked Sendable {
    public static let defaultCapacity = 30 * 24 * 60

    public let capacity: Int
    private let persistence: any SystemMetricsHistoryPersisting
    private let lock = NSLock()
    private var stored: [SystemMetricsRecord] = []
    private var isLoaded = false

    public init(
        persistence: any SystemMetricsHistoryPersisting,
        capacity: Int = SystemMetricsHistoryStore.defaultCapacity
    ) {
        self.persistence = persistence
        self.capacity = max(1, capacity)
    }

    public var records: [SystemMetricsRecord] {
        lock.lock()
        defer { lock.unlock() }
        loadIfNeededLocked()
        return stored
    }

    public var stats: SystemMetricsHistoryStats {
        lock.lock()
        defer { lock.unlock() }
        loadIfNeededLocked()
        return SystemMetricsHistoryStats(
            count: stored.count,
            oldest: stored.first?.timestamp,
            newest: stored.last?.timestamp
        )
    }

    public func append(_ record: SystemMetricsRecord) {
        lock.lock()
        defer { lock.unlock() }
        loadIfNeededLocked()
        stored.append(record)
        let overflow = stored.count - capacity
        if overflow > 0 {
            stored.removeFirst(overflow)
        }
        persistence.appendRecord(record, capacity: capacity)
    }

    public func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        isLoaded = true
        stored = []
        persistence.removeAll()
    }

    private func loadIfNeededLocked() {
        guard !isLoaded else { return }
        isLoaded = true
        let loaded = persistence.loadRecords().sorted { $0.timestamp < $1.timestamp }
        stored = loaded.count > capacity ? Array(loaded.suffix(capacity)) : loaded
    }
}

// MARK: - Recorder

/// Decides whether the freshly sampled snapshot should be persisted. Sampling runs every couple of
/// seconds for the live waveforms, which is far denser than a history worth keeping, so recording
/// is gated on its own interval.
public struct SystemMetricsHistoryRecorder: Equatable, Sendable {
    public var recordingInterval: TimeInterval
    private var lastRecordedAt: Date?

    public init(recordingInterval: TimeInterval = 60, lastRecordedAt: Date? = nil) {
        self.recordingInterval = max(1, recordingInterval)
        self.lastRecordedAt = lastRecordedAt
    }

    public var lastRecord: Date? { lastRecordedAt }

    public func shouldRecord(at date: Date) -> Bool {
        guard let lastRecordedAt else { return true }
        return date.timeIntervalSince(lastRecordedAt) >= recordingInterval
    }

    public mutating func markRecorded(at date: Date) {
        lastRecordedAt = date
    }

    public mutating func reset() {
        lastRecordedAt = nil
    }
}

// MARK: - Chart model

public enum SystemMetricsHistoryRange: String, CaseIterable, Sendable, Equatable {
    case day
    case week
    case month
    case all

    public static let `default` = SystemMetricsHistoryRange.week

    /// Window length; `nil` means "everything that was recorded".
    public var duration: TimeInterval? {
        switch self {
        case .day: 24 * 3600
        case .week: 7 * 24 * 3600
        case .month: 30 * 24 * 3600
        case .all: nil
        }
    }

    /// Simplified Chinese lookup key, resolved through `AppLocalization.text` by the UI.
    public var titleKey: String {
        switch self {
        case .day: "24 小时"
        case .week: "7 天"
        case .month: "30 天"
        case .all: "全部"
        }
    }

    public func startDate(relativeTo now: Date) -> Date? {
        guard let duration else { return nil }
        return now.addingTimeInterval(-duration)
    }
}

public enum SystemMetricsChartUnit: String, Sendable, Equatable {
    case ratio
    case bytesPerSecond
    case rpm
}

public struct SystemMetricsChartPoint: Equatable, Sendable {
    public var date: Date
    public var value: Double

    public init(date: Date, value: Double) {
        self.date = date
        self.value = value
    }
}

public struct SystemMetricsChartSeries: Equatable, Sendable, Identifiable {
    public var id: String
    /// Simplified Chinese lookup key resolved through `AppLocalization.text` by the UI.
    public var titleKey: String
    public var points: [SystemMetricsChartPoint]

    public init(id: String, titleKey: String, points: [SystemMetricsChartPoint]) {
        self.id = id
        self.titleKey = titleKey
        self.points = points
    }
}

public struct SystemMetricsChartSection: Equatable, Sendable, Identifiable {
    public var id: String
    public var titleKey: String
    public var unit: SystemMetricsChartUnit
    public var series: [SystemMetricsChartSeries]

    public init(
        id: String,
        titleKey: String,
        unit: SystemMetricsChartUnit,
        series: [SystemMetricsChartSeries]
    ) {
        self.id = id
        self.titleKey = titleKey
        self.unit = unit
        self.series = series
    }

    public var isEmpty: Bool {
        series.allSatisfy { $0.points.isEmpty }
    }
}

/// Buckets the recorded samples for charting. A long window can hold thousands of samples while a
/// chart only needs a few hundred points, so samples are averaged into contiguous buckets instead
/// of dropping every n-th sample, which would hide spikes.
public enum SystemMetricsHistorySeriesBuilder {
    public static let maximumPoints = 240

    public static func sections(
        records: [SystemMetricsRecord],
        range: SystemMetricsHistoryRange,
        now: Date,
        maximumPoints: Int = maximumPoints
    ) -> [SystemMetricsChartSection] {
        let start = range.startDate(relativeTo: now)
        let relevant = records
            .filter { record in
                guard record.timestamp <= now else { return false }
                guard let start else { return true }
                return record.timestamp >= start
            }
            .sorted { $0.timestamp < $1.timestamp }
        guard !relevant.isEmpty else { return [] }

        let buckets = makeBuckets(relevant, maximumPoints: max(2, maximumPoints))
        let fanCount = relevant.map(\.fanRPMs.count).max() ?? 0

        var sections: [SystemMetricsChartSection] = []
        sections.append(
            SystemMetricsChartSection(
                id: "cpu",
                titleKey: "CPU 利用率",
                unit: .ratio,
                series: [
                    series(id: "cpu.usage", titleKey: "利用率", buckets: buckets) { $0.cpuUsage },
                    series(id: "cpu.user", titleKey: "用户", buckets: buckets) { $0.cpuUser },
                    series(id: "cpu.system", titleKey: "系统", buckets: buckets) { $0.cpuSystem },
                ]
            )
        )
        sections.append(
            SystemMetricsChartSection(
                id: "gpu",
                titleKey: "GPU 利用率",
                unit: .ratio,
                series: [
                    series(id: "gpu.usage", titleKey: "利用率", buckets: buckets) { $0.gpuUsage },
                    series(id: "gpu.renderer", titleKey: "渲染", buckets: buckets) { $0.gpuRenderer },
                    series(id: "gpu.tiler", titleKey: "Tiler", buckets: buckets) { $0.gpuTiler },
                ]
            )
        )
        sections.append(
            SystemMetricsChartSection(
                id: "memory",
                titleKey: "内存使用率",
                unit: .ratio,
                series: [
                    series(id: "memory.usage", titleKey: "内存", buckets: buckets) { record in
                        record.memoryTotalBytes > 0 ? record.memoryUsageRatio : nil
                    },
                ]
            )
        )
        sections.append(
            SystemMetricsChartSection(
                id: "disk",
                titleKey: "磁盘读写",
                unit: .bytesPerSecond,
                series: [
                    series(id: "disk.read", titleKey: "读", buckets: buckets) { $0.diskReadBytesPerSecond },
                    series(id: "disk.write", titleKey: "写", buckets: buckets) { $0.diskWriteBytesPerSecond },
                ]
            )
        )
        if fanCount > 0 {
            sections.append(
                SystemMetricsChartSection(
                    id: "fans",
                    titleKey: "风扇转速",
                    unit: .rpm,
                    series: (0..<fanCount).map { index in
                        series(id: "fan.\(index)", titleKey: fanTitleKey(for: index), buckets: buckets) { record in
                            index < record.fanRPMs.count ? record.fanRPMs[index] : nil
                        }
                    }
                )
            )
        }
        sections.append(
            SystemMetricsChartSection(
                id: "network",
                titleKey: "网络速率",
                unit: .bytesPerSecond,
                series: [
                    series(id: "network.receive", titleKey: "下载", buckets: buckets) {
                        $0.networkReceiveBytesPerSecond
                    },
                    series(id: "network.send", titleKey: "上传", buckets: buckets) {
                        $0.networkSendBytesPerSecond
                    },
                ]
            )
        )
        return sections.filter { !$0.isEmpty }
    }

    public static func fanTitleKey(for index: Int) -> String {
        switch index {
        case 0: "左"
        case 1: "右"
        default: "风扇 %ld"
        }
    }

    private static func series(
        id: String,
        titleKey: String,
        buckets: [[SystemMetricsRecord]],
        value: (SystemMetricsRecord) -> Double?
    ) -> SystemMetricsChartSeries {
        var points: [SystemMetricsChartPoint] = []
        points.reserveCapacity(buckets.count)
        for bucket in buckets {
            var total = 0.0
            var count = 0
            var seconds = 0.0
            for record in bucket {
                guard let sample = value(record), sample.isFinite else { continue }
                total += sample
                seconds += record.timestamp.timeIntervalSince1970
                count += 1
            }
            guard count > 0 else { continue }
            points.append(
                SystemMetricsChartPoint(
                    date: Date(timeIntervalSince1970: seconds / Double(count)),
                    value: total / Double(count)
                )
            )
        }
        return SystemMetricsChartSeries(id: id, titleKey: titleKey, points: points)
    }

    private static func makeBuckets(
        _ records: [SystemMetricsRecord],
        maximumPoints: Int
    ) -> [[SystemMetricsRecord]] {
        guard records.count > maximumPoints else {
            return records.map { [$0] }
        }
        let bucketCount = maximumPoints
        let size = Double(records.count) / Double(bucketCount)
        return (0..<bucketCount).map { index in
            let lower = Int((Double(index) * size).rounded(.down))
            let upper = index == bucketCount - 1
                ? records.count
                : max(lower + 1, Int((Double(index + 1) * size).rounded(.down)))
            return Array(records[lower..<min(upper, records.count)])
        }
    }
}
