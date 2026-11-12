import Foundation

public enum AIStateRepositoryError: Error, Equatable, Sendable {
    case corruptedState
    case taskNotFound(String)
    case storageFailure(String)
}

public struct AIStateStorageChangeToken: Equatable, Sendable {
    private let databaseModificationDate: TimeInterval?
    private let databaseSize: Int?
    private let walModificationDate: TimeInterval?
    private let walSize: Int?

    init(
        databaseModificationDate: TimeInterval?,
        databaseSize: Int?,
        walModificationDate: TimeInterval?,
        walSize: Int?
    ) {
        self.databaseModificationDate = databaseModificationDate
        self.databaseSize = databaseSize
        self.walModificationDate = walModificationDate
        self.walSize = walSize
    }
}

/// SQLite repository for aggregated AI state.
public struct AIStateRepository: Sendable {
    public let directoryURL: URL
    private let maximumUsageSamples: Int

    public var databaseURL: URL {
        directoryURL.appendingPathComponent("ai-state.sqlite", isDirectory: false)
    }

    public var databaseWALURL: URL {
        URL(fileURLWithPath: databaseURL.path + "-wal", isDirectory: false)
    }

    public init(
        directoryURL: URL,
        fileManager _: FileManager = .default,
        maximumUsageSamples: Int = 30_000
    ) {
        self.directoryURL = directoryURL
        self.maximumUsageSamples = max(1, maximumUsageSamples)
    }

    public func load(includeUsageSamples: Bool = true) throws -> AIState {
        let database = try openDatabase()
        try database.trimUsageIfNeeded()
        return try database.load(includeUsageSamples: includeUsageSamples)
    }

    public func loadUsageSamples(startingAt startDate: Date? = nil) throws -> [AIUsageSample] {
        let database = try openDatabase()
        try database.trimUsageIfNeeded()
        return try database.loadUsageSamples(startingAt: startDate)
    }

    /// Applies retention before returning one consistent aggregate/model snapshot for panels and briefings.
    public func loadUsageHistory(startingAt startDate: Date? = nil, endingBefore endDate: Date? = nil) throws -> AIUsageHistory {
        let database = try openDatabase()
        try database.trimUsageIfNeeded()
        return try database.loadUsageHistory(startingAt: startDate, endingBefore: endDate)
    }

    public func upsert(_ task: AIProgressTask) throws {
        try openDatabase().upsertTask(task)
    }

    public func finish(id: String, failed: Bool, detail: String?, at date: Date) throws {
        let database = try openDatabase()
        guard var task = try database.task(id: id) else {
            throw AIStateRepositoryError.taskNotFound(id)
        }
        task.status = failed ? .failed : .succeeded
        if !failed { task.progress = 1 }
        if let detail { task.detail = detail }
        task.updatedAt = date
        try database.upsertTask(task)
    }

    @discardableResult
    public func remove(id: String) throws -> Bool {
        try openDatabase().removeTask(id: id)
    }

    public func clearTasks() throws {
        try openDatabase().clearTasks()
    }

    @discardableResult
    public func recordUsage(_ sample: AIUsageSample) throws -> Bool {
        try recordUsage([sample]) > 0
    }

    @discardableResult
    /// Uses the database transaction so manual totals and model attribution cannot commit independently.
    public func recordUsage(_ samples: [AIUsageSample]) throws -> Int {
        try openDatabase().recordUsage(samples)
    }

    /// Deduplicates detected events by source and keeps the visible history aggregated by day.
    @discardableResult
    public func recordDetectedUsage(_ samples: [AIUsageSample]) throws -> Int {
        try openDatabase().recordDetectedUsage(samples)
    }

    /// Clears only AI reporting history; tasks, notices, and cumulative replay protection remain intact.
    public func clearUsageHistory() throws {
        try openDatabase().clearUsageHistory()
    }

    /// Reads the committed state only after the usage transaction succeeds.
    public func stateRecordingUsage(_ samples: [AIUsageSample]) throws -> AIState {
        let database = try openDatabase()
        _ = try database.recordUsage(samples)
        return try database.load()
    }

    public func enqueueNotice(_ notice: IslandNotice) throws {
        try enqueueNotices([notice])
    }

    public func enqueueNotices(_ notices: [IslandNotice]) throws {
        try openDatabase().enqueueNotices(notices)
    }

    public func storageChangeToken() -> AIStateStorageChangeToken {
        let database = fileVersion(at: databaseURL)
        let wal = fileVersion(at: databaseWALURL)
        return AIStateStorageChangeToken(
            databaseModificationDate: database.modificationDate,
            databaseSize: database.size,
            walModificationDate: wal.modificationDate,
            walSize: wal.size
        )
    }

    private func openDatabase() throws -> AIStateDatabase {
        try AIStateDatabase(
            url: databaseURL,
            maximumUsageSamples: maximumUsageSamples
        )
    }

    private func fileVersion(at url: URL) -> (modificationDate: TimeInterval?, size: Int?) {
        guard let values = try? url.resourceValues(forKeys: [
            .contentModificationDateKey,
            .fileSizeKey,
        ]) else {
            return (nil, nil)
        }
        return (values.contentModificationDate?.timeIntervalSinceReferenceDate, values.fileSize)
    }
}
