import Foundation
import ZislaCore

// MARK: - Record

/// One persisted sample of the system monitor.
///
/// Optional fields stay `nil` when the machine cannot report them (GPU counters, fan speeds,
/// AppleSMC temperatures) so an exported sheet keeps the "unavailable" distinction instead of
/// fabricating zeros. `Double?` also survives a JSON round trip, which is what the on-disk
/// history relies on.
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

/// Storage seam for the history file, so tests never touch the real filesystem.
public protocol SystemMetricsHistoryPersisting: Sendable {
    func loadRecords() -> [SystemMetricsRecord]
    func appendRecord(_ record: SystemMetricsRecord)
    func replaceRecords(_ records: [SystemMetricsRecord])
}

/// Append-only JSON Lines file: each sample is one line, so recording stays a cheap append and the
/// file is only rewritten when the ring buffer drops old samples.
public final class SystemMetricsFileHistoryPersistence: SystemMetricsHistoryPersisting, @unchecked Sendable {
    private let fileURL: URL
    private let fileManager: FileManager

    public init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    public func loadRecords() -> [SystemMetricsRecord] {
        guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else { return [] }
        let decoder = JSONDecoder()
        return data
            .split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
            .compactMap { try? decoder.decode(SystemMetricsRecord.self, from: Data($0)) }
    }

    public func appendRecord(_ record: SystemMetricsRecord) {
        guard let encoded = try? JSONEncoder().encode(record) else { return }
        createParentDirectoryIfNeeded()
        var line = encoded
        line.append(UInt8(ascii: "\n"))
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: fileURL, options: .atomic)
        }
    }

    public func replaceRecords(_ records: [SystemMetricsRecord]) {
        let encoder = JSONEncoder()
        var payload = Data()
        for record in records {
            guard let encoded = try? encoder.encode(record) else { continue }
            payload.append(encoded)
            payload.append(UInt8(ascii: "\n"))
        }
        createParentDirectoryIfNeeded()
        try? payload.write(to: fileURL, options: .atomic)
    }

    private func createParentDirectoryIfNeeded() {
        let directory = fileURL.deletingLastPathComponent()
        guard !fileManager.fileExists(atPath: directory.path) else { return }
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}

/// Resolves `AppPaths.systemMetricsHistory` on first use: constructing a `SystemMonitorService`
/// must not read or write Application Support, which is also part of the package smoke contract.
public final class LazySystemMetricsFileHistoryPersistence: SystemMetricsHistoryPersisting, @unchecked Sendable {
    private let makePersistence: @Sendable () -> SystemMetricsFileHistoryPersistence
    private let lock = NSLock()
    private var resolved: SystemMetricsFileHistoryPersistence?

    public init(makePersistence: @escaping @Sendable () -> SystemMetricsFileHistoryPersistence = {
        SystemMetricsFileHistoryPersistence(fileURL: AppPaths.systemMetricsHistory)
    }) {
        self.makePersistence = makePersistence
    }

    public func loadRecords() -> [SystemMetricsRecord] {
        persistence().loadRecords()
    }

    public func appendRecord(_ record: SystemMetricsRecord) {
        persistence().appendRecord(record)
    }

    public func replaceRecords(_ records: [SystemMetricsRecord]) {
        persistence().replaceRecords(records)
    }

    private func persistence() -> SystemMetricsFileHistoryPersistence {
        lock.lock()
        defer { lock.unlock() }
        if let resolved { return resolved }
        let created = makePersistence()
        resolved = created
        return created
    }
}

// MARK: - Store

/// Ring buffer of samples with an append-only backing store: samples are appended one line at a
/// time and the file is rewritten only when the buffer overflows, which keeps a long recording
/// window affordable on SSD.
public final class SystemMetricsHistoryStore: @unchecked Sendable {
    public let capacity: Int
    private let persistence: any SystemMetricsHistoryPersisting
    private let lock = NSLock()
    private var stored: [SystemMetricsRecord] = []
    private var isLoaded = false

    public init(persistence: any SystemMetricsHistoryPersisting, capacity: Int = 10_080) {
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
        guard stored.count > capacity else {
            persistence.appendRecord(record)
            return
        }
        stored.removeFirst(stored.count - capacity)
        persistence.replaceRecords(stored)
    }

    public func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        isLoaded = true
        stored = []
        persistence.replaceRecords([])
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
                guard let start else { return true }
                return record.timestamp >= start && record.timestamp <= now
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
