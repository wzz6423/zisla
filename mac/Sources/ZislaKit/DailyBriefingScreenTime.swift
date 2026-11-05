import Foundation
import SQLite3

public struct ScreenTimeUsageInterval: Equatable, Sendable {
    public var deviceID: String
    public var bundleID: String
    public var start: Date
    public var end: Date

    public init(deviceID: String, bundleID: String, start: Date, end: Date) {
        self.deviceID = deviceID
        self.bundleID = bundleID
        self.start = start
        self.end = end
    }

    public static func normalized(_ intervals: [Self], within range: DateInterval) -> [Self] {
        var result: [Self] = []
        for device in Dictionary(grouping: intervals, by: \.deviceID).values {
            var merged: [Self] = []
            for var item in device.sorted(by: { ($0.start, $0.end, $0.bundleID) < ($1.start, $1.end, $1.bundleID) }) {
                item.start = max(item.start, range.start)
                item.end = min(item.end, range.end)
                guard item.start < item.end else { continue }
                if var previous = merged.last, item.start < previous.end {
                    if previous.bundleID == item.bundleID {
                        merged[merged.count - 1].end = max(previous.end, item.end)
                        continue
                    }
                    previous.end = item.start
                    merged.removeLast()
                    if previous.end > previous.start { merged.append(previous) }
                }
                merged.append(item)
            }
            result += merged
        }
        return result.sorted { ($0.start, $0.deviceID) < ($1.start, $1.deviceID) }
    }
}

public struct DailyBriefingScreenTimeResult: Sendable {
    public var local: [ScreenTimeUsageInterval]?
    public var remote: [ScreenTimeUsageInterval]?
    public var notificationCount: Int?

    public init(
        local: [ScreenTimeUsageInterval]? = nil,
        remote: [ScreenTimeUsageInterval]? = nil,
        notificationCount: Int? = nil
    ) {
        self.local = local
        self.remote = remote
        self.notificationCount = notificationCount
    }

    public var allDeviceSeconds: TimeInterval? {
        guard let local, !local.isEmpty, let remote else { return nil }
        return (local + remote).reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
    }
}

public struct DailyBriefingScreenTimeReader: Sendable {
    private let library: URL

    public init(library: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library")) {
        self.library = library
    }

    public func read(within range: DateInterval) -> DailyBriefingScreenTimeResult {
        // Each source can be denied independently by TCC or change format after a system update.
        // A missing source stays nil, so the report cannot turn missing data into zero usage.
        let local = try? withLocalDatabase { database in
            DailyBriefingScreenTimeResult(
                local: try Self.readLocalUsage(database, within: range),
                notificationCount: try? Self.readNotificationCount(database, within: range)
            )
        }
        let remote = try? readRemote(within: range)
        return DailyBriefingScreenTimeResult(
            local: local?.local,
            remote: remote,
            notificationCount: local?.notificationCount
        )
    }

    func readLocal(within range: DateInterval) throws -> [ScreenTimeUsageInterval] {
        try withLocalDatabase { try Self.readLocalUsage($0, within: range) }
    }

    private func withLocalDatabase<Value>(_ read: (OpaquePointer?) throws -> Value) throws -> Value {
        let source = library.appendingPathComponent("Application Support/Knowledge/knowledgeC.db")
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-screentime-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let destination = temporary.appendingPathComponent("knowledgeC.db")
        let before = try source.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        try FileManager.default.copyItem(at: source, to: destination)
        let wal = URL(fileURLWithPath: source.path + "-wal")
        if FileManager.default.fileExists(atPath: wal.path) {
            try FileManager.default.copyItem(at: wal, to: URL(fileURLWithPath: destination.path + "-wal"))
        }
        let after = try source.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        guard before.contentModificationDate == after.contentModificationDate,
              before.fileSize == after.fileSize else { throw CocoaError(.fileReadCorruptFile) }
        var database: OpaquePointer?
        guard sqlite3_open_v2(destination.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(database)
            throw CocoaError(.fileReadCorruptFile)
        }
        defer { sqlite3_close(database) }
        return try read(database)
    }

    private static func readLocalUsage(_ database: OpaquePointer?, within range: DateInterval) throws -> [ScreenTimeUsageInterval] {
        let query = """
            SELECT o.ZVALUESTRING, o.ZSTARTDATE, o.ZENDDATE
            FROM ZOBJECT o LEFT JOIN ZSOURCE s ON s.Z_PK = o.ZSOURCE
            WHERE o.ZSTREAMNAME = '/app/usage' AND s.ZDEVICEID IS NULL
              AND o.ZENDDATE > ? AND o.ZSTARTDATE < ?
            ORDER BY o.ZSTARTDATE LIMIT 100000
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else {
            throw CocoaError(.fileReadCorruptFile)
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, range.start.timeIntervalSinceReferenceDate)
        sqlite3_bind_double(statement, 2, range.end.timeIntervalSinceReferenceDate)
        var intervals: [ScreenTimeUsageInterval] = []
        var status = sqlite3_step(statement)
        while status == SQLITE_ROW {
            if let bundle = sqlite3_column_text(statement, 0) {
                let start = sqlite3_column_double(statement, 1)
                let end = sqlite3_column_double(statement, 2)
                if start.isFinite, end.isFinite, end > start {
                    intervals.append(.init(deviceID: "local", bundleID: String(cString: bundle),
                        start: Date(timeIntervalSinceReferenceDate: start), end: Date(timeIntervalSinceReferenceDate: end)))
                }
            }
            status = sqlite3_step(statement)
        }
        guard status == SQLITE_DONE else { throw CocoaError(.fileReadCorruptFile) }
        return ScreenTimeUsageInterval.normalized(intervals, within: range)
    }

    private static func readNotificationCount(_ database: OpaquePointer?, within range: DateInterval) throws -> Int? {
        // SUM preserves NULL when there is no local receipt history to establish coverage.
        let query = """
            SELECT SUM(CASE WHEN o.ZSTARTDATE >= ? AND o.ZSTARTDATE < ? THEN 1 ELSE 0 END)
            FROM ZOBJECT o LEFT JOIN ZSOURCE s ON s.Z_PK = o.ZSOURCE
            WHERE o.ZSTREAMNAME = '/notification/usage' AND o.ZVALUESTRING = 'Receive'
              AND s.ZDEVICEID IS NULL AND typeof(o.ZSTARTDATE) IN ('integer', 'real')
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else {
            throw CocoaError(.fileReadCorruptFile)
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, range.start.timeIntervalSinceReferenceDate)
        sqlite3_bind_double(statement, 2, range.end.timeIntervalSinceReferenceDate)
        guard sqlite3_step(statement) == SQLITE_ROW else { throw CocoaError(.fileReadCorruptFile) }
        return sqlite3_column_type(statement, 0) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(statement, 0))
    }

    func readRemote(within range: DateInterval) throws -> [ScreenTimeUsageInterval] {
        let root = library.appendingPathComponent("Biome/streams/restricted/App.InFocus/remote")
        let devices = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey])
            .filter { UUID(uuidString: $0.lastPathComponent) != nil }
        guard devices.count <= 32 else { throw ScreenTimeBiomeParser.ParseError.tooLarge }
        var result: [ScreenTimeUsageInterval] = []
        var readBytes = 0
        for device in devices {
            guard try device.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
                throw CocoaError(.fileReadNoPermission)
            }
            let files = try FileManager.default.contentsOfDirectory(at: device,
                includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
                .filter { UInt64($0.lastPathComponent) != nil }
                .sorted { UInt64($0.lastPathComponent)! < UInt64($1.lastPathComponent)! }
            let start = range.start.timeIntervalSinceReferenceDate * 1_000_000
            let end = range.end.timeIntervalSinceReferenceDate * 1_000_000
            let previous = files.last { Double($0.lastPathComponent)! < start }
            let selected = files.filter { file in
                let timestamp = Double(file.lastPathComponent)!
                return file == previous || (timestamp >= start && timestamp <= end)
            }
            guard selected.count <= 256 else { throw ScreenTimeBiomeParser.ParseError.tooLarge }
            var transitions: [ScreenTimeBiomeParser.Transition] = []
            for file in selected {
                let values = try file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true else {
                    throw CocoaError(.fileReadNoPermission)
                }
                readBytes += values.fileSize ?? 0
                guard readBytes <= 64 * 1024 * 1024 else { throw ScreenTimeBiomeParser.ParseError.tooLarge }
                transitions += try ScreenTimeBiomeParser.transitions(in: Data(contentsOf: file))
            }
            result += Self.intervals(from: transitions, deviceID: device.lastPathComponent)
        }
        return ScreenTimeUsageInterval.normalized(result, within: range)
    }

    static func intervals(from transitions: [ScreenTimeBiomeParser.Transition], deviceID: String) -> [ScreenTimeUsageInterval] {
        var current: ScreenTimeBiomeParser.Transition?
        var intervals: [ScreenTimeUsageInterval] = []
        for transition in transitions.sorted(by: { $0.date < $1.date }) {
            if let previous = current {
                if previous.bundleID == transition.bundleID && transition.gainedFocus { continue }
                if transition.gainedFocus || transition.bundleID == previous.bundleID {
                    if transition.date > previous.date {
                        intervals.append(.init(deviceID: deviceID, bundleID: previous.bundleID,
                            start: previous.date, end: transition.date))
                    }
                    current = nil
                }
            }
            if transition.gainedFocus { current = transition }
        }
        // An unmatched gain is incomplete synchronized data, not evidence of continuous use.
        return intervals
    }
}
