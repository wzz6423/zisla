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
    public func recordUsage(_ samples: [AIUsageSample]) throws -> Int {
        try openDatabase().recordUsage(
            AIUsageAnalytics.dailyUsageSamples(samples: samples, calendar: .current)
        )
    }

    /// Deduplicates detected events by source and keeps the visible history aggregated by day.
    @discardableResult
    public func recordDetectedUsage(_ samples: [AIUsageSample]) throws -> Int {
        try openDatabase().recordDetectedUsage(samples)
    }

    public func stateRecordingUsage(_ samples: [AIUsageSample]) throws -> AIState {
        let database = try openDatabase()
        _ = try database.recordUsage(AIUsageAnalytics.dailyUsageSamples(samples: samples, calendar: .current))
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
