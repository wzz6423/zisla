import Combine
import CryptoKit
import Darwin
import Foundation
import IOKit
import SystemConfiguration
import ZislaNVMe

// MARK: - Snapshots

public struct CPUMetrics: Equatable, Sendable {
    /// Overall usage in 0...1 (user + system) / total
    public var usage: Double
    public var userFraction: Double
    public var systemFraction: Double
    public var idleFraction: Double
    public var niceFraction: Double
    public var temperature: TemperatureMetric

    public init(
        usage: Double,
        userFraction: Double,
        systemFraction: Double,
        idleFraction: Double,
        niceFraction: Double,
        temperature: TemperatureMetric = .unavailableByPublicAPI
    ) {
        self.usage = usage
        self.userFraction = userFraction
        self.systemFraction = systemFraction
        self.idleFraction = idleFraction
        self.niceFraction = niceFraction
        self.temperature = temperature
    }

    public static let zero = CPUMetrics(
        usage: 0,
        userFraction: 0,
        systemFraction: 0,
        idleFraction: 1,
        niceFraction: 0
    )
}

/// Temperature is displayed only when the system provides a clear, verifiable sensor reading; thermal state is not mapped to Celsius.
public enum TemperatureMetric: Equatable, Sendable {
    case unavailable(reason: String)
    case celsius(Double)

    public static let unavailableByPublicAPI = TemperatureMetric.unavailable(
        reason: "此 Mac 未提供公开温度传感器接口"
    )
}

public struct MemoryMetrics: Equatable, Sendable {
    public var totalBytes: UInt64
    public var usedBytes: UInt64
    public var freeBytes: UInt64
    public var activeBytes: UInt64
    public var inactiveBytes: UInt64
    public var wiredBytes: UInt64
    public var compressedBytes: UInt64
    /// 0...1
    public var pressureRatio: Double

    public init(
        totalBytes: UInt64,
        usedBytes: UInt64,
        freeBytes: UInt64,
        activeBytes: UInt64,
        inactiveBytes: UInt64,
        wiredBytes: UInt64,
        compressedBytes: UInt64,
        pressureRatio: Double
    ) {
        self.totalBytes = totalBytes
        self.usedBytes = usedBytes
        self.freeBytes = freeBytes
        self.activeBytes = activeBytes
        self.inactiveBytes = inactiveBytes
        self.wiredBytes = wiredBytes
        self.compressedBytes = compressedBytes
        self.pressureRatio = pressureRatio
    }
}

public struct DiskMetrics: Equatable, Sendable {
    public var totalBytes: UInt64
    public var freeBytes: UInt64
    public var usedBytes: UInt64
    public var volumeURL: URL
    public var volumeName: String?
    public var readBytesPerSecond: Double?
    public var writeBytesPerSecond: Double?
    public var temperature: TemperatureMetric

    public init(
        totalBytes: UInt64,
        freeBytes: UInt64,
        usedBytes: UInt64,
        volumeURL: URL,
        volumeName: String? = nil,
        readBytesPerSecond: Double? = nil,
        writeBytesPerSecond: Double? = nil,
        temperature: TemperatureMetric = .unavailableByPublicAPI
    ) {
        self.totalBytes = totalBytes
        self.freeBytes = freeBytes
        self.usedBytes = usedBytes
        self.volumeURL = volumeURL
        self.volumeName = volumeName
        self.readBytesPerSecond = readBytesPerSecond
        self.writeBytesPerSecond = writeBytesPerSecond
        self.temperature = temperature
    }
}

public struct NetworkMetrics: Equatable, Sendable {
    /// Cumulative bytes since boot
    public var bytesReceived: UInt64
    public var bytesSent: UInt64
    /// Rate relative to the previous sample (B/s); 0 on the first sample
    public var receiveBytesPerSecond: Double
    public var sendBytesPerSecond: Double

    public init(
        bytesReceived: UInt64,
        bytesSent: UInt64,
        receiveBytesPerSecond: Double,
        sendBytesPerSecond: Double
    ) {
        self.bytesReceived = bytesReceived
        self.bytesSent = bytesSent
        self.receiveBytesPerSecond = receiveBytesPerSecond
        self.sendBytesPerSecond = sendBytesPerSecond
    }

    public static let zero = NetworkMetrics(
        bytesReceived: 0,
        bytesSent: 0,
        receiveBytesPerSecond: 0,
        sendBytesPerSecond: 0
    )
}

public struct NetworkIdentity: Equatable, Sendable {
    public var privateIPv4Address: String?
    public var publicIPAddress: String?

    public init(privateIPv4Address: String? = nil, publicIPAddress: String? = nil) {
        self.privateIPv4Address = privateIPv4Address
        self.publicIPAddress = publicIPAddress
    }
}

/// Hardware names are read once at startup to avoid placing fixed info in the per-second sampling path.
public struct SystemHardwareInfo: Equatable, Sendable {
    public var cpuName: String?
    public var gpuName: String?
    public var gpuCoreCount: Int?
    /// Total physical core count from system_profiler JSON; nil if unavailable
    public var cpuCoreCount: Int?
    /// Apple Silicon performance cores (hw.perflevel0.physicalcpu); nil if unavailable
    public var cpuPerformanceCoreCount: Int?
    /// Apple Silicon efficiency cores (hw.perflevel1.physicalcpu); nil if unavailable
    public var cpuEfficiencyCoreCount: Int?

    public init(
        cpuName: String? = nil,
        gpuName: String? = nil,
        gpuCoreCount: Int? = nil,
        cpuCoreCount: Int? = nil,
        cpuPerformanceCoreCount: Int? = nil,
        cpuEfficiencyCoreCount: Int? = nil
    ) {
        self.cpuName = cpuName
        self.gpuName = gpuName
        self.gpuCoreCount = gpuCoreCount
        self.cpuCoreCount = cpuCoreCount
        self.cpuPerformanceCoreCount = cpuPerformanceCoreCount
        self.cpuEfficiencyCoreCount = cpuEfficiencyCoreCount
    }

    public static let unavailable = SystemHardwareInfo()
}

public struct SystemMetricHistory: Equatable, Sendable {
    public private(set) var cpuUsage: [Double] = []
    public private(set) var cpuUser: [Double] = []
    public private(set) var cpuSystem: [Double] = []
    public private(set) var cpuIdle: [Double] = []
    public private(set) var gpuUsage: [Double] = []
    public private(set) var gpuRenderer: [Double] = []
    public private(set) var gpuTiler: [Double] = []
    public private(set) var networkDownload: [Double] = []
    public private(set) var networkUpload: [Double] = []

    public init() {}

    public mutating func append(
        cpu: CPUMetrics,
        gpu: GPUMetrics,
        network: NetworkMetrics,
        limit: Int = 60
    ) {
        appendCPU(cpu, limit: limit)
        appendGPU(gpu, limit: limit)
        networkDownload = appending(
            networkDownload,
            value: nonnegativeFinite(network.receiveBytesPerSecond),
            limit: limit
        )
        networkUpload = appending(
            networkUpload,
            value: nonnegativeFinite(network.sendBytesPerSecond),
            limit: limit
        )
    }

    private mutating func appendCPU(_ cpu: CPUMetrics, limit: Int) {
        let user = clamped(cpu.userFraction + cpu.niceFraction)
        let system = clamped(cpu.systemFraction)
        let idle = clamped(cpu.idleFraction)
        cpuUsage = appending(cpuUsage, value: clamped(cpu.usage), limit: limit)
        cpuUser = appending(cpuUser, value: user, limit: limit)
        cpuSystem = appending(cpuSystem, value: system, limit: limit)
        cpuIdle = appending(cpuIdle, value: idle, limit: limit)
    }

    private mutating func appendGPU(_ gpu: GPUMetrics, limit: Int) {
        guard case let .available(metrics) = gpu else { return }
        gpuUsage = appending(gpuUsage, value: clamped(metrics.usage), limit: limit)
        gpuRenderer = appending(gpuRenderer, value: clamped(metrics.rendererUsage ?? 0), limit: limit)
        gpuTiler = appending(gpuTiler, value: clamped(metrics.tilerUsage ?? 0), limit: limit)
    }

    private func appending(_ values: [Double], value: Double, limit: Int) -> [Double] {
        var result = values
        result.append(value)
        let resolvedLimit = max(1, limit)
        if result.count > resolvedLimit {
            result.removeFirst(result.count - resolvedLimit)
        }
        return result
    }

    private func clamped(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(1, max(0, value))
    }

    private func nonnegativeFinite(_ value: Double) -> Double {
        value.isFinite ? max(0, value) : 0
    }
}

public protocol PublicIPProviding: Sendable {
    func publicIPAddress() async -> String?
}

private struct DefaultPublicIPProvider: PublicIPProviding {
    private struct Response: Decodable {
        let ip: String
    }

    func publicIPAddress() async -> String? {
        guard let url = URL(string: "https://api64.ipify.org?format=json") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(Response.self, from: data).ip
        } catch {
            return nil
        }
    }
}

/// GPU historical readings. `IORegistry` keys have no stable public contract; callers must mark usage as experimental.
public struct GPUUsageMetrics: Equatable, Sendable {
    public var usage: Double
    public var rendererUsage: Double?
    public var tilerUsage: Double?
    public var detail: String?
    public var temperature: TemperatureMetric

    public init(
        usage: Double,
        rendererUsage: Double? = nil,
        tilerUsage: Double? = nil,
        detail: String? = nil,
        temperature: TemperatureMetric = .unavailableByPublicAPI
    ) {
        self.usage = usage
        self.rendererUsage = rendererUsage
        self.tilerUsage = tilerUsage
        self.detail = detail
        self.temperature = temperature
    }
}

/// Explicitly unavailable when there is no stable public GPU API; fabricating values is prohibited.
public enum GPUMetrics: Equatable, Sendable {
    case unavailable(reason: String)
    case available(GPUUsageMetrics)
}

/// Explicitly unavailable when there is no stable public fan API; fabricating values is prohibited.
public enum FanMetrics: Equatable, Sendable {
    case unavailable(reason: String)
    case available(rpm: [Double], detail: String?)
}

public struct SystemMetricsSnapshot: Equatable, Sendable {
    public var sampledAt: Date
    public var hardware: SystemHardwareInfo
    public var cpu: CPUMetrics
    public var memory: MemoryMetrics
    public var disk: DiskMetrics
    public var network: NetworkMetrics
    public var networkIdentity: NetworkIdentity
    public var gpu: GPUMetrics
    public var fan: FanMetrics

    public init(
        sampledAt: Date,
        hardware: SystemHardwareInfo = .unavailable,
        cpu: CPUMetrics,
        memory: MemoryMetrics,
        disk: DiskMetrics,
        network: NetworkMetrics,
        networkIdentity: NetworkIdentity = NetworkIdentity(),
        gpu: GPUMetrics,
        fan: FanMetrics
    ) {
        self.sampledAt = sampledAt
        self.hardware = hardware
        self.cpu = cpu
        self.memory = memory
        self.disk = disk
        self.network = network
        self.networkIdentity = networkIdentity
        self.gpu = gpu
        self.fan = fan
    }
}

// MARK: - Cleanup models

public struct DiskCleanupCandidate: Equatable, Identifiable, Sendable {
    public var id: URL { url }
    public var url: URL
    public var kind: DiskCleanupKind
    public var safetyLevel: DiskCleanupSafetyLevel
    public var byteSize: UInt64
    public var displayName: String
    public var detail: String?
    public var source: String?

    public var isActionable: Bool {
        safetyLevel != .analysisOnly && kind.safetyLevel != .analysisOnly
    }

    public init(
        url: URL,
        kind: DiskCleanupKind,
        byteSize: UInt64,
        displayName: String,
        detail: String? = nil,
        safetyLevel: DiskCleanupSafetyLevel? = nil,
        source: String? = nil
    ) {
        self.url = url
        self.kind = kind
        self.safetyLevel = safetyLevel ?? kind.safetyLevel
        self.byteSize = byteSize
        self.displayName = displayName
        self.detail = detail
        self.source = source
    }
}

public enum DiskCleanupSafetyLevel: String, Equatable, Sendable {
    case safeToClean
    case requiresManualReview
    case analysisOnly

    public var title: String {
        switch self {
        case .safeToClean: "可安全清理"
        case .requiresManualReview: "需人工复核"
        case .analysisOnly: "仅分析"
        }
    }

    public var reason: String {
        switch self {
        case .safeToClean: "可再生数据；下次使用时可能重新生成或下载"
        case .requiresManualReview: "可能是用户文件、诊断资料或仍有保留价值的数据"
        case .analysisOnly: "可能包含持久数据或系统状态；只展示，不会移入废纸篓"
        }
    }
}

/// Controls breadth and thresholds for a read-only cleanup scan.
public struct DiskCleanupScanOptions: Equatable, Sendable {
    public var largeFileThreshold: UInt64
    public var oldFileAge: TimeInterval
    public var unfinishedDownloadAge: TimeInterval
    public var userFileMaxDepth: Int
    /// Kept for source compatibility; analysis-only categories are no longer scanned.
    public var includeAnalysisOnly: Bool
    public var referenceDate: Date?
    public var additionalUserDirectories: [URL]

    public init(
        largeFileThreshold: UInt64 = 50 * 1024 * 1024,
        oldFileAge: TimeInterval = 30 * 24 * 3600,
        unfinishedDownloadAge: TimeInterval = 3 * 24 * 3600,
        userFileMaxDepth: Int = 8,
        includeAnalysisOnly: Bool = true,
        referenceDate: Date? = nil,
        additionalUserDirectories: [URL] = []
    ) {
        self.largeFileThreshold = max(1, largeFileThreshold)
        self.oldFileAge = max(0, oldFileAge)
        self.unfinishedDownloadAge = max(0, unfinishedDownloadAge)
        self.userFileMaxDepth = min(16, max(1, userFileMaxDepth))
        self.includeAnalysisOnly = includeAnalysisOnly
        self.referenceDate = referenceDate
        self.additionalUserDirectories = additionalUserDirectories
    }

    public static let `default` = DiskCleanupScanOptions()
}

public enum DiskCleanupKind: String, Equatable, Sendable, CaseIterable {
    /// Rebuilable app, sandbox, and group container caches under the current user's Library.
    case appCache
    case cache
    case log
    case trash
    case developerArtifacts
    case temporaryFiles
    /// Rebuilable caches for package managers and language toolchains (not user project directories).
    case packageManagerCache
    case crashReport
    case diskImage
    case largeFile
    case duplicateFile
    case browserCache
    case mailDownloads
    case unfinishedDownload
    case iosBackup
    case projectBuildArtifact
    case xcodeArchive
    case simulatorData
    case applicationResidual
    case timeMachineSnapshot
    case dockerData
    case virtualMachineData
    case aiToolCache
    case languagePack
    case cloudStorageCache

    public var safetyLevel: DiskCleanupSafetyLevel {
        switch self {
        case .appCache, .cache, .developerArtifacts, .packageManagerCache,
             .browserCache, .projectBuildArtifact, .aiToolCache:
            .safeToClean
        case .log, .trash, .temporaryFiles, .crashReport, .diskImage, .largeFile, .duplicateFile,
             .mailDownloads, .unfinishedDownload, .iosBackup, .xcodeArchive, .applicationResidual,
             .languagePack:
            .requiresManualReview
        case .simulatorData, .timeMachineSnapshot, .dockerData, .virtualMachineData, .cloudStorageCache:
            .analysisOnly
        }
    }

    /// When the same path appears in multiple scan categories, the higher value (more specific kind) takes precedence.
    public var classificationPriority: Int {
        switch self {
        case .crashReport: 90
        case .temporaryFiles: 85
        case .packageManagerCache: 80
        case .developerArtifacts: 70
        case .diskImage: 60
        case .duplicateFile: 50
        case .largeFile: 40
        case .appCache: 35
        case .cache: 30
        case .log: 20
        case .trash: 10
        case .iosBackup: 95
        case .timeMachineSnapshot: 94
        case .applicationResidual: 93
        case .mailDownloads: 92
        case .browserCache: 88
        case .projectBuildArtifact: 86
        case .xcodeArchive: 84
        case .simulatorData: 83
        case .dockerData: 82
        case .virtualMachineData: 81
        case .aiToolCache: 79
        case .languagePack: 78
        case .cloudStorageCache: 77
        case .unfinishedDownload: 76
        }
    }
}

public struct DiskCleanupFailure: Equatable, Sendable {
    public var url: URL
    public var message: String

    public init(url: URL, message: String) {
        self.url = url
        self.message = message
    }
}

public struct DiskCleanupResult: Equatable, Sendable {
    public var successCount: Int
    public var freedBytes: UInt64
    public var failures: [DiskCleanupFailure]

    public init(successCount: Int, freedBytes: UInt64, failures: [DiskCleanupFailure]) {
        self.successCount = successCount
        self.freedBytes = freedBytes
        self.failures = failures
    }
}

public enum DiskCleanupError: Error, LocalizedError, Equatable, Sendable {
    case pathOutsideAllowedRoots
    case notAFileURL
    case analysisOnlyCandidate

    public var errorDescription: String? {
        switch self {
        case .pathOutsideAllowedRoots: "目标不在允许清理的用户目录内"
        case .notAFileURL: "仅支持本地文件路径"
        case .analysisOnlyCandidate: "该项目仅用于分析，不能移入废纸篓"
        }
    }
}

// MARK: - Injectable file operations

public protocol SystemMonitorFileManaging: Sendable {
    func fileExists(atPath path: String) -> Bool
    func urls(for directory: FileManager.SearchPathDirectory, in domainMask: FileManager.SearchPathDomainMask) -> [URL]
    func homeDirectoryForCurrentUser() -> URL
    func temporaryDirectoryForCurrentUser() -> URL
    func contentsOfDirectory(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]?,
        options: FileManager.DirectoryEnumerationOptions
    ) throws -> [URL]
    func attributesOfFileSystem(forPath path: String) throws -> [FileAttributeKey: Any]
    func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any]
    func enumerator(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]?,
        options: FileManager.DirectoryEnumerationOptions
    ) -> FileManager.DirectoryEnumerator?
    func trashItem(at url: URL) throws -> URL
    func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws
    func removeItem(at url: URL) throws
    func createFile(atPath path: String, contents data: Data?) -> Bool
    func contents(atPath path: String) -> Data?
    func sha256Digest(at url: URL) -> Data?
    /// Returns the volume's total capacity and available space (including purgeable space, matching macOS System Settings).
    /// The default implementation uses URLResourceValues; a test mock may return nil to fall back to attributesOfFileSystem.
    func volumeCapacity(for url: URL) -> (total: UInt64, available: UInt64)?
}

public extension SystemMonitorFileManaging {
    /// Test doubles may retain in-memory data; the production file manager streams reads to avoid loading large files into memory.
    func sha256Digest(at url: URL) -> Data? {
        guard let data = contents(atPath: url.path) else { return nil }
        return Data(SHA256.hash(data: data))
    }

    /// Uses `volumeAvailableCapacityForImportantUsageKey` to obtain available space,
    /// which includes APFS purgeable space (local snapshots, caches, etc.), consistent with macOS System Settings.
    func volumeCapacity(for url: URL) -> (total: UInt64, available: UInt64)? {
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
        ]
        // Foundation caches URL resource values; invalidate them so cleanup and external changes are visible.
        var refreshedURL = url
        refreshedURL.removeAllCachedResourceValues()
        guard let values = try? refreshedURL.resourceValues(forKeys: keys) else { return nil }
        let total = UInt64(max(0, values.volumeTotalCapacity ?? 0))
        guard let availableInt = values.volumeAvailableCapacityForImportantUsage else { return nil }
        let available = UInt64(max(0, availableInt))
        guard total > 0 else { return nil }
        return (total, available)
    }
}

private final class DefaultSystemMonitorFileManager: SystemMonitorFileManaging, @unchecked Sendable {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func fileExists(atPath path: String) -> Bool {
        fileManager.fileExists(atPath: path)
    }

    func urls(
        for directory: FileManager.SearchPathDirectory,
        in domainMask: FileManager.SearchPathDomainMask
    ) -> [URL] {
        fileManager.urls(for: directory, in: domainMask)
    }

    func homeDirectoryForCurrentUser() -> URL {
        fileManager.homeDirectoryForCurrentUser
    }

    func temporaryDirectoryForCurrentUser() -> URL {
        fileManager.temporaryDirectory
    }

    func contentsOfDirectory(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]?,
        options: FileManager.DirectoryEnumerationOptions
    ) throws -> [URL] {
        try fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: keys,
            options: options
        )
    }

    func attributesOfFileSystem(forPath path: String) throws -> [FileAttributeKey: Any] {
        try fileManager.attributesOfFileSystem(forPath: path)
    }

    func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any] {
        try fileManager.attributesOfItem(atPath: path)
    }

    func enumerator(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]?,
        options: FileManager.DirectoryEnumerationOptions
    ) -> FileManager.DirectoryEnumerator? {
        fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: options
        )
    }

    func trashItem(at url: URL) throws -> URL {
        var resulting: NSURL?
        try fileManager.trashItem(at: url, resultingItemURL: &resulting)
        return (resulting as URL?) ?? url
    }

    func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws {
        try fileManager.createDirectory(
            at: url,
            withIntermediateDirectories: withIntermediateDirectories,
            attributes: nil
        )
    }

    func removeItem(at url: URL) throws {
        try fileManager.removeItem(at: url)
    }

    func createFile(atPath path: String, contents data: Data?) -> Bool {
        fileManager.createFile(atPath: path, contents: data)
    }

    func contents(atPath path: String) -> Data? {
        fileManager.contents(atPath: path)
    }

    func sha256Digest(at url: URL) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        var hasher = SHA256()
        do {
            while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
                hasher.update(data: chunk)
            }
            return Data(hasher.finalize())
        } catch {
            return nil
        }
    }
}

// MARK: - Pure helpers (testable without live host)

public enum SystemMonitorMath {
    /// Computes usage from the delta between two host_cpu_load_info samples.
    public static func cpuMetrics(
        previous: host_cpu_load_info,
        current: host_cpu_load_info
    ) -> CPUMetrics {
        let user = Double(current.cpu_ticks.0 &- previous.cpu_ticks.0)
        let system = Double(current.cpu_ticks.1 &- previous.cpu_ticks.1)
        let idle = Double(current.cpu_ticks.2 &- previous.cpu_ticks.2)
        let nice = Double(current.cpu_ticks.3 &- previous.cpu_ticks.3)
        let total = user + system + idle + nice
        guard total > 0 else { return .zero }
        return CPUMetrics(
            usage: (user + system + nice) / total,
            userFraction: user / total,
            systemFraction: system / total,
            idleFraction: idle / total,
            niceFraction: nice / total
        )
    }

    public static func networkRates(
        previousReceived: UInt64,
        previousSent: UInt64,
        currentReceived: UInt64,
        currentSent: UInt64,
        elapsedSeconds: TimeInterval
    ) -> (receive: Double, send: Double) {
        guard elapsedSeconds > 0 else { return (0, 0) }
        let dr = currentReceived >= previousReceived
            ? Double(currentReceived - previousReceived)
            : Double(currentReceived)
        let ds = currentSent >= previousSent
            ? Double(currentSent - previousSent)
            : Double(currentSent)
        return (dr / elapsedSeconds, ds / elapsedSeconds)
    }

    public static func diskRates(
        previousRead: UInt64,
        previousWrite: UInt64,
        currentRead: UInt64,
        currentWrite: UInt64,
        elapsedSeconds: TimeInterval
    ) -> (read: Double, write: Double) {
        let rates = networkRates(
            previousReceived: previousRead,
            previousSent: previousWrite,
            currentReceived: currentRead,
            currentSent: currentWrite,
            elapsedSeconds: elapsedSeconds
        )
        return (rates.receive, rates.send)
    }

    public static func memoryPressureRatio(usedBytes: UInt64, totalBytes: UInt64) -> Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, max(0, Double(usedBytes) / Double(totalBytes)))
    }
}

public enum SystemMonitorPathSafety {
    /// Returns whether `url` lies within any of the allowed roots (normalized prefix match).
    public static func isURL(_ url: URL, withinAllowedRoots roots: [URL]) -> Bool {
        guard url.isFileURL else { return false }
        let candidate = standardizedPath(url)
        for root in roots {
            let rootPath = standardizedPath(root)
            if candidate == rootPath { return true }
            let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
            if candidate.hasPrefix(prefix) { return true }
        }
        return false
    }

    public static func standardizedPath(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    public static func defaultAllowedRoots(fileManager: SystemMonitorFileManaging) -> [URL] {
        SystemDiskCleanup.allowedScanRoots(fileManager: fileManager).map(\.url)
    }
}

// MARK: - Sampling core

enum SystemSampler {
    static func sampleCPULoad() -> host_cpu_load_info? {
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        var info = host_cpu_load_info()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return info
    }

    static func sampleMemory() -> MemoryMetrics? {
        var size = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        var stats = vm_statistics64()
        let kr = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(size)) { rebound in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &size)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }

        var pageSize: vm_size_t = 0
        guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS else { return nil }
        let pageSizeBytes = UInt64(pageSize)
        let free = UInt64(stats.free_count) * pageSizeBytes
        let active = UInt64(stats.active_count) * pageSizeBytes
        let inactive = UInt64(stats.inactive_count) * pageSizeBytes
        let wired = UInt64(stats.wire_count) * pageSizeBytes
        let compressed = UInt64(stats.compressor_page_count) * pageSizeBytes
        let speculative = UInt64(stats.speculative_count) * pageSizeBytes

        var total: UInt64 = 0
        var totalSize = size_t(MemoryLayout<UInt64>.size)
        sysctlbyname("hw.memsize", &total, &totalSize, nil, 0)

        // used ≈ active + wired + compressed (consistent with Activity Monitor's approach, no private API)
        let used = active + wired + compressed
        // available = free + inactive (reclaimable) + speculative, consistent with most third-party monitors (= total - used)
        let available = free + inactive + speculative
        return MemoryMetrics(
            totalBytes: total,
            usedBytes: min(used, total == 0 ? used : total),
            freeBytes: available,
            activeBytes: active,
            inactiveBytes: inactive,
            wiredBytes: wired,
            compressedBytes: compressed,
            pressureRatio: SystemMonitorMath.memoryPressureRatio(usedBytes: used, totalBytes: total)
        )
    }

    static func sampleDisk(fileManager: SystemMonitorFileManaging, volumeURL: URL) -> DiskMetrics? {
        let volumeName = try? volumeURL.resourceValues(forKeys: [.volumeNameKey]).volumeName
        let temperature = sampleDiskTemperature()

        // Prefer URLResourceValues (includes APFS purgeable space, matching macOS System Settings "Available")
        if let capacity = fileManager.volumeCapacity(for: volumeURL) {
            let used = capacity.total >= capacity.available
                ? capacity.total - capacity.available
                : 0
            return DiskMetrics(
                totalBytes: capacity.total,
                freeBytes: capacity.available,
                usedBytes: used,
                volumeURL: volumeURL,
                volumeName: volumeName ?? nil,
                temperature: temperature
            )
        }

        // Fall back to statfs (attributesOfFileSystem), which excludes purgeable space
        do {
            let attrs = try fileManager.attributesOfFileSystem(forPath: volumeURL.path)
            let total = (attrs[.systemSize] as? NSNumber)?.uint64Value ?? 0
            let free = (attrs[.systemFreeSize] as? NSNumber)?.uint64Value ?? 0
            let used = total >= free ? total - free : 0
            return DiskMetrics(
                totalBytes: total,
                freeBytes: free,
                usedBytes: used,
                volumeURL: volumeURL,
                volumeName: volumeName ?? nil,
                temperature: temperature
            )
        } catch {
            return nil
        }
    }

    /// Reads internal NVMe/SSD temperature; returns unavailable when the reading cannot be verified.
    static func sampleDiskTemperature() -> TemperatureMetric {
        let smartCelsius = ZislaReadNVMeTemperatureCelsius()
        if smartCelsius.isFinite, (0...120).contains(smartCelsius) {
            return .celsius(smartCelsius)
        }

        let classNames = ["AppleANS3NVMeController", "IONVMeController", "AppleNVMeController"]
        for className in classNames {
            var iterator: io_iterator_t = 0
            guard IOServiceGetMatchingServices(
                kIOMainPortDefault,
                IOServiceMatching(className),
                &iterator
            ) == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(iterator) }

            while true {
                let service = IOIteratorNext(iterator)
                guard service != 0 else { break }
                defer { IOObjectRelease(service) }
                var properties: Unmanaged<CFMutableDictionary>?
                guard IORegistryEntryCreateCFProperties(
                    service,
                    &properties,
                    kCFAllocatorDefault,
                    0
                ) == KERN_SUCCESS,
                let dictionary = properties?.takeRetainedValue() as? [String: Any],
                let statistics = dictionary["PerformanceStatistics"] as? [String: Any]
                else { continue }

                for key in ["Temperature", "Controller Temperature", "Composite Temperature"] {
                    let celsius: Double?
                    if let number = statistics[key] as? NSNumber {
                        celsius = number.doubleValue
                    } else if let text = statistics[key] as? String {
                        celsius = Double(text)
                    } else {
                        celsius = nil
                    }
                    if let value = celsius, (0...120).contains(value) {
                        return .celsius(value)
                    }
                }
            }
        }
        return .unavailable(reason: "内置存储未提供可读取的温度传感器")
    }

    /// Reads cumulative disk I/O counters from IORegistry; returns nil when the reading cannot be verified.
    static func sampleDiskCounters() -> (read: UInt64, write: UInt64)? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOBlockStorageDriver"),
            &iterator
        ) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var read: UInt64 = 0
        var write: UInt64 = 0
        var foundStatistic = false
        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            defer { IOObjectRelease(service) }
            var properties: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(
                service,
                &properties,
                kCFAllocatorDefault,
                0
            ) == KERN_SUCCESS,
            let dictionary = properties?.takeRetainedValue() as? [String: Any],
            let statistics = dictionary["Statistics"] as? [String: Any]
            else { continue }

            if let readValue = counterValue(statistics["Bytes (Read)"]) {
                read += readValue
                foundStatistic = true
            }
            if let writeValue = counterValue(statistics["Bytes (Write)"]) {
                write += writeValue
                foundStatistic = true
            }
        }
        return foundStatistic ? (read, write) : nil
    }

    static func sampleNetworkCounters() -> (received: UInt64, sent: UInt64) {
        var ifaddrPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPointer) == 0, let first = ifaddrPointer else {
            return (0, 0)
        }
        defer { freeifaddrs(ifaddrPointer) }

        var received: UInt64 = 0
        var sent: UInt64 = 0
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let current = cursor {
            let name = String(cString: current.pointee.ifa_name)
            // Skip loopback
            if name.hasPrefix("lo") {
                cursor = current.pointee.ifa_next
                continue
            }
            if current.pointee.ifa_addr?.pointee.sa_family == UInt8(AF_LINK) {
                current.pointee.ifa_data.withMemoryRebound(to: if_data.self, capacity: 1) { data in
                    // ifa_data points to if_data for AF_LINK
                }
                if let data = current.pointee.ifa_data {
                    let ifdata = data.assumingMemoryBound(to: if_data.self)
                    received += UInt64(ifdata.pointee.ifi_ibytes)
                    sent += UInt64(ifdata.pointee.ifi_obytes)
                }
            }
            cursor = current.pointee.ifa_next
        }
        return (received, sent)
    }

    static func samplePrivateIPv4Address() -> String? {
        var ifaddrPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPointer) == 0, let first = ifaddrPointer else { return nil }
        defer { freeifaddrs(ifaddrPointer) }

        let primaryInterface = primaryInterfaceName()
        var fallback: String?
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let current = cursor {
            defer { cursor = current.pointee.ifa_next }
            let name = String(cString: current.pointee.ifa_name)
            guard !name.hasPrefix("lo"), !name.hasPrefix("utun"),
                  !name.hasPrefix("awdl"), !name.hasPrefix("llw"),
                  let address = current.pointee.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET)
            else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                address,
                socklen_t(address.pointee.sa_len),
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            guard result == 0 else { continue }
            let value = String(
                decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) },
                as: UTF8.self
            )
            guard isPrivateIPv4Address(value) else { continue }
            if name == primaryInterface { return value }
            fallback = fallback ?? value
        }
        return fallback
    }

    private static func primaryInterfaceName() -> String? {
        guard let store = SCDynamicStoreCreate(nil, "Zisla" as CFString, nil, nil),
              let state = SCDynamicStoreCopyValue(
                store,
                "State:/Network/Global/IPv4" as CFString
              ) as? [String: Any]
        else { return nil }
        return state["PrimaryInterface"] as? String
    }

    static func isPrivateIPv4Address(_ address: String) -> Bool {
        let octets = address.split(separator: ".").compactMap { Int($0) }
        guard octets.count == 4 else { return false }
        let first = octets[0]
        let second = octets[1]
        return first == 10
            || (first == 192 && second == 168)
            || (first == 172 && (16...31).contains(second))
    }

    static func sampleGPU() -> GPUMetrics {
        let classNames = ["IOAccelerator", "IOGPU", "AGXAccelerator"]
        var maximumUsage: Double?
        var maximumRendererUsage: Double?
        var maximumTilerUsage: Double?

        for className in classNames {
            var iterator: io_iterator_t = 0
            guard IOServiceGetMatchingServices(
                kIOMainPortDefault,
                IOServiceMatching(className),
                &iterator
            ) == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(iterator) }

            while true {
                let service = IOIteratorNext(iterator)
                guard service != 0 else { break }
                defer { IOObjectRelease(service) }
                var properties: Unmanaged<CFMutableDictionary>?
                guard IORegistryEntryCreateCFProperties(
                    service,
                    &properties,
                    kCFAllocatorDefault,
                    0
                ) == KERN_SUCCESS,
                let dictionary = properties?.takeRetainedValue() as? [String: Any],
                let statistics = dictionary["PerformanceStatistics"] as? [String: Any]
                else { continue }

                maximumUsage = maximum(
                    maximumUsage,
                    percentageValue(statistics["Device Utilization %"])
                        ?? percentageValue(statistics["GPU Activity(%)"])
                )
                maximumRendererUsage = maximum(
                    maximumRendererUsage,
                    percentageValue(statistics["Renderer Utilization %"])
                )
                maximumTilerUsage = maximum(
                    maximumTilerUsage,
                    percentageValue(statistics["Tiler Utilization %"])
                )
            }
        }

        if let maximumUsage {
            return .available(
                GPUUsageMetrics(
                    usage: maximumUsage,
                    rendererUsage: maximumRendererUsage,
                    tilerUsage: maximumTilerUsage,
                    detail: "IORegistry 实验读数"
                )
            )
        }
        return .unavailable(reason: "当前 GPU 未提供可读取的性能统计")
    }

    private static func counterValue(_ value: Any?) -> UInt64? {
        (value as? NSNumber)?.uint64Value
    }

    private static func percentageValue(_ value: Any?) -> Double? {
        let raw: Double?
        if let number = value as? NSNumber {
            raw = number.doubleValue
        } else if let text = value as? String {
            raw = Double(text)
        } else {
            raw = nil
        }
        guard let raw else { return nil }
        return min(1, max(0, raw / 100))
    }

    private static func maximum(_ lhs: Double?, _ rhs: Double?) -> Double? {
        switch (lhs, rhs) {
        case let (.some(lhs), .some(rhs)): max(lhs, rhs)
        case let (.some(lhs), .none): lhs
        case let (.none, .some(rhs)): rhs
        case (.none, .none): nil
        }
    }
}

private struct AppleSMCSensorSample: Sendable {
    var cpuTemperature: TemperatureMetric
    var gpuTemperature: TemperatureMetric
    var fan: FanMetrics
}

/// State — read-only AppleSMC request layout used on Apple Silicon; contains no write or speed-control commands.
enum AppleSMCSensorReader {
    private static let structureSize = 0x50
    private static let keyInfoOffset = 0x1C
    private static let typeOffset = 0x20
    private static let resultOffset = 0x28
    private static let commandOffset = 0x2A
    private static let bytesOffset = 0x30
    private static let selector: UInt32 = 2
    private static let readBytesCommand: UInt8 = 5
    private static let readKeyInfoCommand: UInt8 = 9

    /// CPU/GPU temperature SMC keys for each Apple Silicon generation.
    /// Sources: exelban/stats + MacThrottle empirical testing (https://stanislas.blog/2025/12/macos-thermal-throttling-app/).
    private enum AppleSiliconGeneration {
        case m1, m2, m3, m4, m5, unknown

        static func from(chipName: String?) -> AppleSiliconGeneration {
            guard let chipName else { return .unknown }
            if chipName.contains("Apple M5") { return .m5 }
            if chipName.contains("Apple M4") { return .m4 }
            if chipName.contains("Apple M3") { return .m3 }
            if chipName.contains("Apple M2") { return .m2 }
            if chipName.contains("Apple M1") { return .m1 }
            return .unknown
        }

        var cpuTemperatureKeys: [String] {
            switch self {
            case .m1:
                // Efficiency cores + performance cores
                ["Tp09", "Tp0T", "Tp01", "Tp05", "Tp0D", "Tp0H", "Tp0L", "Tp0P", "Tp0X", "Tp0b"]
            case .m2:
                // Efficiency cores + performance cores
                ["Tp1h", "Tp1t", "Tp1p", "Tp1l",
                 "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0X", "Tp0b", "Tp0f", "Tp0j"]
            case .m3:
                // Te (efficiency) + Tf (performance)
                ["Te05", "Te0L", "Te0P", "Te0S",
                 "Tf04", "Tf09", "Tf0A", "Tf0B", "Tf0D", "Tf0E",
                 "Tf44", "Tf49", "Tf4A", "Tf4B", "Tf4D", "Tf4E"]
            case .m4:
                // Te (efficiency) + Tp (performance)
                ["Te05", "Te0S", "Te09", "Te0H",
                 "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0V", "Tp0Y", "Tp0b", "Tp0e"]
            case .m5:
                ["Tp00", "Tp04", "Tp0C", "Tp0G", "Tp0O", "Tp0R", "Tp0X", "Tp0a", "Tp0p", "Tp0u", "Tp0y"]
            case .unknown:
                []
            }
        }

        var gpuTemperatureKeys: [String] {
            switch self {
            case .m1:
                ["Tg05", "Tg0D", "Tg0L", "Tg0T"]
            case .m2:
                ["Tg0f", "Tg0j"]
            case .m3:
                ["Tf14", "Tf18", "Tf19", "Tf1A", "Tf24", "Tf28", "Tf29", "Tf2A"]
            case .m4:
                ["Tg0G", "Tg0H", "Tg1U", "Tg1k", "Tg0K", "Tg0L", "Tg0d", "Tg0e", "Tg0j", "Tg0k"]
            case .m5:
                // M5 GPU keys have no publicly verified data yet; using M4 keys as candidate placeholders
                ["Tg0G", "Tg0H", "Tg1U", "Tg1k", "Tg0K", "Tg0L", "Tg0d", "Tg0e", "Tg0j", "Tg0k"]
            case .unknown:
                []
            }
        }
    }

    fileprivate static func sample(chipName: String?) -> AppleSMCSensorSample {
        guard let connection = openConnection() else {
            return AppleSMCSensorSample(
                cpuTemperature: .unavailable(reason: "AppleSMC 只读传感器不可用"),
                gpuTemperature: .unavailable(reason: "AppleSMC 只读传感器不可用"),
                fan: .unavailable(reason: "AppleSMC 只读传感器不可用")
            )
        }
        defer { IOServiceClose(connection) }
        return AppleSMCSensorSample(
            cpuTemperature: cpuTemperature(chipName: chipName, connection: connection),
            gpuTemperature: gpuTemperature(chipName: chipName, connection: connection),
            fan: fanMetrics(connection: connection)
        )
    }

    static func float32(from bytes: [UInt8]) -> Double? {
        guard bytes.count == 4 else { return nil }
        let bits = UInt32(bytes[0])
            | UInt32(bytes[1]) << 8
            | UInt32(bytes[2]) << 16
            | UInt32(bytes[3]) << 24
        let value = Double(Float(bitPattern: bits))
        return value.isFinite ? value : nil
    }

    static func averageCelsius(_ values: [Double]) -> Double? {
        let valid = values.filter { (20...110).contains($0) }
        guard !valid.isEmpty else { return nil }
        return valid.reduce(0, +) / Double(valid.count)
    }

    static func signedFixedPointCelsius(from bytes: [UInt8]) -> Double? {
        guard bytes.count == 2 else { return nil }
        let raw = Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        return Double(raw) / 256
    }

    static func batteryTemperatureCelsius() -> Double? {
        guard let connection = openConnection() else { return nil }
        defer { IOServiceClose(connection) }
        let values = ["TB0T", "TB1T", "TB2T"].compactMap { key in
            read(key, connection: connection).flatMap(floatingPointValue)
        }
        let valid = values.filter { (-20...80).contains($0) }
        guard !valid.isEmpty else { return nil }
        return valid.reduce(0, +) / Double(valid.count)
    }

    static func isValidFanRPM(_ value: Double) -> Bool {
        value.isFinite && (0...20_000).contains(value)
    }

    private static func openConnection() -> io_connect_t? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("AppleSMC"),
            &iterator
        ) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }
        let service = IOIteratorNext(iterator)
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var connection: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == KERN_SUCCESS else {
            return nil
        }
        return connection
    }

    private static func cpuTemperature(chipName: String?, connection: io_connect_t) -> TemperatureMetric {
        let generation = AppleSiliconGeneration.from(chipName: chipName)
        guard generation != .unknown else {
            return .unavailable(reason: "当前芯片没有经过验证的温度键映射")
        }
        let values = generation.cpuTemperatureKeys.compactMap { key in
            read(key, connection: connection).flatMap(floatingPointValue)
        }
        guard let average = averageCelsius(values) else {
            return .unavailable(reason: "未返回有效 CPU 温度读数")
        }
        return .celsius(average)
    }

    private static func gpuTemperature(chipName: String?, connection: io_connect_t) -> TemperatureMetric {
        let generation = AppleSiliconGeneration.from(chipName: chipName)
        guard generation != .unknown else {
            return .unavailable(reason: "当前芯片没有经过验证的温度键映射")
        }
        let values = generation.gpuTemperatureKeys.compactMap { key in
            read(key, connection: connection).flatMap(floatingPointValue)
        }
        guard let average = averageCelsius(values) else {
            return .unavailable(reason: "未返回有效 GPU 温度读数")
        }
        return .celsius(average)
    }

    private static func fanMetrics(connection: io_connect_t) -> FanMetrics {
        guard let countValue = read("FNum", connection: connection),
              let firstByte = countValue.bytes.first
        else {
            return .unavailable(reason: "此 Mac 未返回风扇数量")
        }
        let count = min(Int(firstByte), 8)
        guard count > 0 else { return .unavailable(reason: "此 Mac 没有可读风扇") }

        let rpm = (0..<count).compactMap { index -> Double? in
            guard let value = read("F\(index)Ac", connection: connection),
                  let rpm = floatingPointValue(value),
                  isValidFanRPM(rpm)
            else { return nil }
            return rpm
        }
        guard !rpm.isEmpty else { return .unavailable(reason: "未返回有效风扇转速") }
        return .available(rpm: rpm, detail: "AppleSMC 只读")
    }

    private static func read(_ key: String, connection: io_connect_t) -> (type: UInt32, bytes: [UInt8])? {
        guard let keyBytes = encodedKey(key) else { return nil }
        var input = [UInt8](repeating: 0, count: structureSize)
        var output = [UInt8](repeating: 0, count: structureSize)
        input.replaceSubrange(0..<4, with: keyBytes)
        input[commandOffset] = readKeyInfoCommand
        guard call(connection: connection, input: input, output: &output), output[resultOffset] == 0 else {
            return nil
        }
        let size = Int(readUInt32LE(output, at: keyInfoOffset))
        guard (1...32).contains(size) else { return nil }
        let type = readUInt32LE(output, at: typeOffset)

        input = [UInt8](repeating: 0, count: structureSize)
        output = [UInt8](repeating: 0, count: structureSize)
        input.replaceSubrange(0..<4, with: keyBytes)
        writeUInt32LE(UInt32(size), into: &input, at: keyInfoOffset)
        input[commandOffset] = readBytesCommand
        guard call(connection: connection, input: input, output: &output), output[resultOffset] == 0 else {
            return nil
        }
        return (type, Array(output[bytesOffset..<(bytesOffset + size)]))
    }

    private static func call(connection: io_connect_t, input: [UInt8], output: inout [UInt8]) -> Bool {
        var outputSize = output.count
        let result = input.withUnsafeBytes { inputBuffer in
            output.withUnsafeMutableBytes { outputBuffer in
                IOConnectCallStructMethod(
                    connection,
                    selector,
                    inputBuffer.baseAddress,
                    inputBuffer.count,
                    outputBuffer.baseAddress,
                    &outputSize
                )
            }
        }
        return result == KERN_SUCCESS && outputSize == structureSize
    }

    private static func floatingPointValue(_ value: (type: UInt32, bytes: [UInt8])) -> Double? {
        if value.type == fourCharacterCode("flt ") {
            return float32(from: value.bytes)
        }
        if value.type == fourCharacterCode("sp78") {
            return signedFixedPointCelsius(from: value.bytes)
        }
        guard value.type == fourCharacterCode("fpe2"), value.bytes.count == 2 else { return nil }
        return Double(UInt16(value.bytes[0]) << 8 | UInt16(value.bytes[1])) / 4
    }

    private static func encodedKey(_ key: String) -> [UInt8]? {
        let bytes = Array(key.utf8)
        guard bytes.count == 4 else { return nil }
        return [bytes[3], bytes[2], bytes[1], bytes[0]]
    }

    private static func fourCharacterCode(_ value: String) -> UInt32 {
        Array(value.utf8).reduce(0) { $0 << 8 | UInt32($1) }
    }

    private static func readUInt32LE(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset])
            | UInt32(bytes[offset + 1]) << 8
            | UInt32(bytes[offset + 2]) << 16
            | UInt32(bytes[offset + 3]) << 24
    }

    private static func writeUInt32LE(_ value: UInt32, into bytes: inout [UInt8], at offset: Int) {
        bytes[offset] = UInt8(truncatingIfNeeded: value)
        bytes[offset + 1] = UInt8(truncatingIfNeeded: value >> 8)
        bytes[offset + 2] = UInt8(truncatingIfNeeded: value >> 16)
        bytes[offset + 3] = UInt8(truncatingIfNeeded: value >> 24)
    }
}

enum SystemHardwareInfoReader {
    typealias SysctlIntReader = @Sendable (String) -> Int?

    static func read(sysctlInt: SysctlIntReader = SystemSysctl.intValue(named:)) -> SystemHardwareInfo {
        guard let output = try? AIAgentProcessRunner.runSynchronously(
            executableURL: URL(fileURLWithPath: "/usr/sbin/system_profiler"),
            arguments: ["-json", "SPHardwareDataType", "SPDisplaysDataType"],
            workingDirectoryURL: URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
            timeout: 30,
            maximumOutputBytes: 4 * 1_024 * 1_024,
            maximumErrorBytes: 64 * 1_024
        ),
        !output.didTimeout,
        output.status == 0
        else {
            return .unavailable
        }
        return parse(output.standardOutput, sysctlInt: sysctlInt)
    }

    static func parse(
        _ data: Data,
        sysctlInt: SysctlIntReader = SystemSysctl.intValue(named:)
    ) -> SystemHardwareInfo {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .unavailable
        }
        let hardware = (root["SPHardwareDataType"] as? [[String: Any]])?.first
        let displays = root["SPDisplaysDataType"] as? [[String: Any]] ?? []
        let gpu = displays.first { $0["sppci_device_type"] as? String == "spdisplays_gpu" } ?? displays.first
        let coreText = gpu?["sppci_cores"] as? String
        let topology = CPUCoreTopology.read(sysctlInt: sysctlInt)

        return SystemHardwareInfo(
            cpuName: hardware?["chip_type"] as? String,
            gpuName: (gpu?["sppci_model"] as? String) ?? (gpu?["_name"] as? String),
            gpuCoreCount: coreText.flatMap { Int($0.filter(\.isNumber)) },
            cpuCoreCount: physicalCoreCount(fromHardwareDictionary: hardware),
            cpuPerformanceCoreCount: topology.performanceCoreCount,
            cpuEfficiencyCoreCount: topology.efficiencyCoreCount
        )
    }

    /// system_profiler commonly returns `"proc 15:5:10:0"` (total:performance:efficiency:...); do not guess when the field is absent.
    static func physicalCoreCount(fromHardwareDictionary hardware: [String: Any]?) -> Int? {
        guard let raw = hardware?["number_processors"] else { return nil }
        if let number = raw as? Int {
            return number > 0 ? number : nil
        }
        if let number = raw as? NSNumber {
            let value = number.intValue
            return value > 0 ? value : nil
        }
        guard let text = raw as? String else { return nil }
        return physicalCoreCount(fromNumberProcessorsText: text)
    }

    static func physicalCoreCount(fromNumberProcessorsText text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let value = Int(trimmed), value > 0 {
            return value
        }
        // "proc 15:5:10:0"
        guard trimmed.hasPrefix("proc") else { return nil }
        let remainder = trimmed.dropFirst(4).trimmingCharacters(in: .whitespaces)
        guard let first = remainder.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true).first,
              let value = Int(first),
              value > 0
        else {
            return nil
        }
        return value
    }
}

/// Reads Apple Silicon performance/efficiency physical core counts via sysctl; keeps nil when a key is absent.
enum CPUCoreTopology {
    struct Counts: Equatable, Sendable {
        var performanceCoreCount: Int?
        var efficiencyCoreCount: Int?
    }

    static func read(sysctlInt: SystemHardwareInfoReader.SysctlIntReader) -> Counts {
        Counts(
            performanceCoreCount: positiveCoreCount(sysctlInt("hw.perflevel0.physicalcpu")),
            efficiencyCoreCount: positiveCoreCount(sysctlInt("hw.perflevel1.physicalcpu"))
        )
    }

    private static func positiveCoreCount(_ value: Int?) -> Int? {
        guard let value, value > 0 else { return nil }
        return value
    }
}

enum SystemSysctl {
    static func intValue(named name: String) -> Int? {
        var value: Int32 = 0
        var size = size_t(MemoryLayout<Int32>.size)
        let status = sysctlbyname(name, &value, &size, nil, 0)
        guard status == 0 else { return nil }
        return Int(value)
    }
}

// MARK: - Cleanup helpers

public enum SystemDiskCleanup {
    public static func allowedScanRoots(fileManager: SystemMonitorFileManaging) -> [(kind: DiskCleanupKind, url: URL)] {
        var items: [(DiskCleanupKind, URL)] = []
        func append(_ kind: DiskCleanupKind, _ url: URL) {
            items.append((kind, url.standardizedFileURL))
        }

        let home = fileManager.homeDirectoryForCurrentUser()

        // User-specific temporary directory (/private/var/folders/...)
        let temporaryDirectory = fileManager.temporaryDirectoryForCurrentUser().standardizedFileURL
        if isCurrentUserTemporaryDirectory(temporaryDirectory) {
            append(.temporaryFiles, temporaryDirectory)
        }
        // /tmp is a symlink to /private/tmp (known macOS alias); both are added and /tmp is used after deduplication.
        append(.temporaryFiles, URL(fileURLWithPath: "/tmp", isDirectory: true))
        append(.temporaryFiles, URL(fileURLWithPath: "/private/tmp", isDirectory: true))

        // Xcode / Simulator: rebuilable build and device-support caches
        let developerPaths = [
            "Library/Developer/Xcode/DerivedData",
            "Library/Developer/Xcode/iOS DeviceSupport",
            "Library/Developer/Xcode/watchOS DeviceSupport",
            "Library/Developer/Xcode/ModuleCache.noindex",
            "Library/Developer/CoreSimulator/Caches",
            ".cache",
        ]
        for path in developerPaths {
            append(.developerArtifacts, home.appendingPathComponent(path, isDirectory: true))
        }

        // Package manager / language toolchain caches (caches and rebuilable storage only, no user projects)
        let packageManagerPaths = [
            ".npm",
            ".pnpm-store",
            ".yarn/cache",
            ".bun/install/cache",
            ".gradle/caches",
            ".m2/repository",
            ".cargo/registry/cache",
            ".cocoapods/repos",
            ".cocoapods/cache",
            "Library/Caches/CocoaPods",
            "Library/Caches/org.carthage.CarthageKit",
            "Library/Caches/org.swift.swiftpm",
            "Library/Caches/SwiftPM",
            ".swiftpm/cache",
            "Library/Caches/pip",
            ".cache/pip",
            ".cache/uv",
            "go/pkg/mod",
            ".pub-cache",
            "Library/Caches/pub",
            ".nuget/packages",
            "Library/Caches/Yarn",
            "Library/Caches/typescript",
            "Library/Caches/Homebrew",
        ]
        for path in packageManagerPaths {
            append(.packageManagerCache, home.appendingPathComponent(path, isDirectory: true))
        }

        // Browser and Mail caches are registered separately so the UI can explain their owner.
        for root in browserCacheRoots(fileManager: fileManager) {
            append(.browserCache, root)
        }
        append(.mailDownloads, home.appendingPathComponent("Library/Mail Downloads", isDirectory: true))
        append(
            .mailDownloads,
            home.appendingPathComponent("Library/Containers/com.apple.mail/Data/Library/Mail Downloads", isDirectory: true)
        )
        append(
            .iosBackup,
            home.appendingPathComponent("Library/Application Support/MobileSync/Backup", isDirectory: true)
        )
        append(.xcodeArchive, home.appendingPathComponent("Library/Developer/Xcode/Archives", isDirectory: true))
        for path in aiToolCachePaths(home: home) {
            append(.aiToolCache, path)
        }

        // Register only rebuildable app caches; sandbox and group containers allow only their respective Library/Caches subdirectory.
        for root in applicationCacheRoots(fileManager: fileManager) {
            append(.appCache, root.url)
        }

        // User logs: application run logs; safe to clear without affecting functionality
        append(.log, home.appendingPathComponent("Library/Logs", isDirectory: true))

        // Crash reports: crash and diagnostic reports; safe to clear without affecting functionality
        append(.crashReport, home.appendingPathComponent("Library/Logs/DiagnosticReports", isDirectory: true))

        // Trash: files deleted but not yet emptied
        if let trashURL = fileManager.urls(for: .trashDirectory, in: .userDomainMask).first {
            append(.trash, trashURL)
        }

        // User file directories: used for disk image, large file, and duplicate file scans (the directories themselves are not cleanup candidates)
        for searchPath in [FileManager.SearchPathDirectory.downloadsDirectory, .desktopDirectory, .documentDirectory] {
            if let url = fileManager.urls(for: searchPath, in: .userDomainMask).first {
                append(.diskImage, url)
            }
        }

        // Keep only the most specific classification root for each path; /tmp and /private/tmp are known macOS aliases, normalized to /tmp.
        var bestByPath: [String: (DiskCleanupKind, URL)] = [:]
        for item in items {
            let rawPath = item.1.path
            let canonicalPath = rawPath == "/private/tmp" ? "/tmp" : rawPath
            let canonicalURL = rawPath == "/private/tmp" ? URL(fileURLWithPath: "/tmp") : item.1
            if let existing = bestByPath[canonicalPath] {
                if item.0.classificationPriority > existing.0.classificationPriority {
                    bestByPath[canonicalPath] = (item.0, canonicalURL)
                }
            } else {
                bestByPath[canonicalPath] = (item.0, canonicalURL)
            }
        }
        return bestByPath.values.sorted { $0.1.path < $1.1.path }
    }

    private static func browserCacheRoots(fileManager: SystemMonitorFileManaging) -> [URL] {
        let home = fileManager.homeDirectoryForCurrentUser().standardizedFileURL
        var roots = [
            home.appendingPathComponent("Library/Caches/com.apple.Safari", isDirectory: true),
            home.appendingPathComponent("Library/Caches/com.google.Chrome", isDirectory: true),
            home.appendingPathComponent("Library/Caches/com.microsoft.edgemac", isDirectory: true),
            home.appendingPathComponent("Library/Caches/com.brave.Browser", isDirectory: true),
            home.appendingPathComponent("Library/Caches/Firefox", isDirectory: true),
            home.appendingPathComponent("Library/Caches/company.thebrowser.Browser", isDirectory: true),
        ]

        let browserRoots = [
            home.appendingPathComponent("Library/Application Support/Google/Chrome", isDirectory: true),
            home.appendingPathComponent("Library/Application Support/Microsoft Edge", isDirectory: true),
            home.appendingPathComponent("Library/Application Support/BraveSoftware/Brave-Browser", isDirectory: true),
            home.appendingPathComponent("Library/Application Support/Firefox/Profiles", isDirectory: true),
            home.appendingPathComponent("Library/Application Support/Arc/User Data", isDirectory: true),
        ]
        for browserRoot in browserRoots {
            guard fileManager.fileExists(atPath: browserRoot.path),
                  let profiles = try? fileManager.contentsOfDirectory(
                      at: browserRoot,
                      includingPropertiesForKeys: [.isDirectoryKey],
                      options: [.skipsHiddenFiles]
                  )
            else {
                continue
            }
            for profile in profiles {
                roots.append(contentsOf: browserProfileCacheRoots(profile: profile))
            }
        }
        return uniqueURLs(roots)
    }

    private static func browserProfileCacheRoots(profile: URL) -> [URL] {
        [
            profile.appendingPathComponent("Cache", isDirectory: true),
            profile.appendingPathComponent("Code Cache", isDirectory: true),
            profile.appendingPathComponent("GPUCache", isDirectory: true),
            profile.appendingPathComponent("Service Worker/CacheStorage", isDirectory: true),
            profile.appendingPathComponent("cache2", isDirectory: true),
        ]
    }

    private static func aiToolCachePaths(home: URL) -> [URL] {
        [
            home.appendingPathComponent(".cache/huggingface", isDirectory: true),
            home.appendingPathComponent(".cache/torch", isDirectory: true),
            home.appendingPathComponent(".cache/ollama", isDirectory: true),
            home.appendingPathComponent("Library/Caches/com.anthropic.claude", isDirectory: true),
            home.appendingPathComponent("Library/Caches/com.openai.chat", isDirectory: true),
        ]
    }

    private static func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { seen.insert(SystemMonitorPathSafety.standardizedPath($0)).inserted }
    }

    private enum ApplicationCacheSource {
        case library
        case sandboxContainer
        case groupContainer

        var detailPrefix: String {
            switch self {
            case .library: "应用缓存"
            case .sandboxContainer: "沙盒应用缓存"
            case .groupContainer: "群组容器缓存"
            }
        }
    }

    private struct ApplicationCacheRoot {
        var url: URL
        var identifier: String
        var source: ApplicationCacheSource
    }

    /// Only whitelists the explicit `Library/Caches` directory of sandbox containers to avoid expanding app data directories into cleanable scope.
    private static func applicationCacheRoots(
        fileManager: SystemMonitorFileManaging
    ) -> [ApplicationCacheRoot] {
        let home = fileManager.homeDirectoryForCurrentUser().standardizedFileURL
        let allowedHome = [home]
        let libraryCaches = home.appendingPathComponent("Library/Caches", isDirectory: true)
        var roots = [
            ApplicationCacheRoot(
                url: libraryCaches,
                identifier: "Library/Caches",
                source: .library
            ),
        ]

        let containerSources: [(directory: String, cacheSuffix: String, source: ApplicationCacheSource)] = [
            ("Library/Containers", "Data/Library/Caches", .sandboxContainer),
            ("Library/Group Containers", "Library/Caches", .groupContainer),
        ]
        for entry in containerSources {
            let directory = home.appendingPathComponent(entry.directory, isDirectory: true)
            guard SystemMonitorPathSafety.isURL(directory, withinAllowedRoots: allowedHome),
                  let containers = try? fileManager.contentsOfDirectory(
                      at: directory,
                      includingPropertiesForKeys: nil,
                      options: [.skipsHiddenFiles]
                  )
            else {
                continue
            }
            for container in containers {
                let identifier = container.lastPathComponent
                let cacheURL = container
                    .appendingPathComponent(entry.cacheSuffix, isDirectory: true)
                    .standardizedFileURL
                guard fileManager.fileExists(atPath: cacheURL.path),
                      SystemMonitorPathSafety.isURL(cacheURL, withinAllowedRoots: allowedHome)
                else {
                    continue
                }
                roots.append(ApplicationCacheRoot(url: cacheURL, identifier: identifier, source: entry.source))
            }
        }

        var uniqueRoots: [String: ApplicationCacheRoot] = [:]
        for root in roots {
            uniqueRoots[SystemMonitorPathSafety.standardizedPath(root.url)] = root
        }
        return uniqueRoots.values.sorted { $0.url.path < $1.url.path }
    }

    public static func allocatedByteSize(of url: URL, fileManager: SystemMonitorFileManaging) -> UInt64 {
        guard fileManager.fileExists(atPath: url.path) else { return 0 }
        // Use resource values first
        if let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isDirectoryKey]) {
            if values.isDirectory == true {
                return directoryAllocatedSize(at: url, fileManager: fileManager)
            }
            if let total = values.totalFileAllocatedSize {
                return UInt64(total)
            }
            if let allocated = values.fileAllocatedSize {
                return UInt64(allocated)
            }
        }
        if let attrs = try? fileManager.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? NSNumber {
            // Rough directory check: recurse if contents are enumerable
            if let children = try? fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ), !children.isEmpty || (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                return directoryAllocatedSize(at: url, fileManager: fileManager)
            }
            return size.uint64Value
        }
        return directoryAllocatedSize(at: url, fileManager: fileManager)
    }

    private static func directoryAllocatedSize(at url: URL, fileManager: SystemMonitorFileManaging) -> UInt64 {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey],
            options: [.skipsPackageDescendants]
        ) else {
            guard let children = try? fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .totalFileAllocatedSizeKey],
                options: [.skipsHiddenFiles]
            ) else {
                return 0
            }
            return children.reduce(0) { total, child in
                total + allocatedByteSize(of: child, fileManager: fileManager)
            }
        }
        var total: UInt64 = 0
        for case let fileURL as URL in enumerator {
            total += autoreleasepool {
                if let values = try? fileURL.resourceValues(forKeys: [
                    .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey,
                ]) {
                    guard values.isRegularFile == true else { return 0 }
                    if let size = values.totalFileAllocatedSize {
                        return UInt64(size)
                    }
                    if let size = values.fileAllocatedSize {
                        return UInt64(size)
                    }
                } else if let attrs = try? fileManager.attributesOfItem(atPath: fileURL.path),
                          let size = attrs[.size] as? NSNumber {
                    return size.uint64Value
                }
                return 0
            }
        }
        return total
    }

    private static let maximumConcurrentScanWorkers = 3

    private static let excludedScanKinds: Set<DiskCleanupKind> = [
        .simulatorData, .timeMachineSnapshot, .dockerData, .virtualMachineData, .cloudStorageCache,
    ]

    private struct CleanupScanTask: @unchecked Sendable {
        let run: () -> [DiskCleanupCandidate]
    }

    private final class CleanupScanResults: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [[DiskCleanupCandidate]?]

        init(count: Int) {
            values = Array(repeating: nil, count: count)
        }

        func store(_ candidates: [DiskCleanupCandidate], at index: Int) {
            lock.lock()
            values[index] = candidates
            lock.unlock()
        }

        func flattened() -> [DiskCleanupCandidate] {
            lock.lock()
            let snapshot = values
            lock.unlock()
            return snapshot.compactMap { $0 }.flatMap { $0 }
        }
    }

    /// Keeps background scan work bounded so cache discovery cannot saturate CPU or storage I/O.
    static func scanWorkerLimit(
        requested: Int?,
        processorCount: Int = ProcessInfo.processInfo.activeProcessorCount
    ) -> Int {
        let availableProcessors = max(1, processorCount)
        let defaultLimit = min(maximumConcurrentScanWorkers, max(1, availableProcessors - 1))
        return min(maximumConcurrentScanWorkers, max(1, requested ?? defaultLimit))
    }

    private static func executeScanTasks(
        _ tasks: [CleanupScanTask],
        workerLimit: Int
    ) -> [DiskCleanupCandidate] {
        guard tasks.count > 1, workerLimit > 1 else {
            return tasks.flatMap { $0.run() }
        }

        let results = CleanupScanResults(count: tasks.count)
        let queue = OperationQueue()
        queue.name = "dev.wzz.zisla.disk-cleanup-scan"
        queue.qualityOfService = .utility
        queue.maxConcurrentOperationCount = workerLimit

        for (index, task) in tasks.enumerated() {
            queue.addOperation {
                let candidates = autoreleasepool { task.run() }
                results.store(candidates, at: index)
            }
        }
        queue.waitUntilAllOperationsAreFinished()
        return results.flattened()
    }

    private static func executeScanTasksWithProgress(
        _ tasks: [CleanupScanTask],
        workerLimit: Int,
        onProgress: @escaping @Sendable ([DiskCleanupCandidate]) -> Void
    ) -> [DiskCleanupCandidate] {
        guard tasks.count > 1, workerLimit > 1 else {
            var accumulated: [DiskCleanupCandidate] = []
            for task in tasks {
                accumulated.append(contentsOf: task.run())
                onProgress(deduplicateCandidates(accumulated).sorted { $0.byteSize > $1.byteSize })
            }
            return accumulated
        }

        let results = CleanupScanResults(count: tasks.count)
        let queue = OperationQueue()
        queue.name = "dev.wzz.zisla.disk-cleanup-scan"
        queue.qualityOfService = .utility
        queue.maxConcurrentOperationCount = workerLimit
        let progressLock = NSLock()

        for (index, task) in tasks.enumerated() {
            queue.addOperation {
                let candidates = autoreleasepool { task.run() }
                results.store(candidates, at: index)

                // Serialize updates so a later completion never publishes an older snapshot.
                progressLock.lock()
                onProgress(deduplicateCandidates(results.flattened()).sorted { $0.byteSize > $1.byteSize })
                progressLock.unlock()
            }
        }
        queue.waitUntilAllOperationsAreFinished()
        return results.flattened()
    }

    /// Scans all cleanup candidate categories; deduplicates by path and returns sorted by size descending.
    public static func scanCandidates(
        fileManager: SystemMonitorFileManaging,
        kinds: Set<DiskCleanupKind> = Set(DiskCleanupKind.allCases),
        maxDepthChildrenOnly: Bool = true,
        maxConcurrentScans: Int? = nil,
        options: DiskCleanupScanOptions = .default
    ) -> [DiskCleanupCandidate] {
        let requestedKinds = kinds.subtracting(excludedScanKinds)
        var tasks: [CleanupScanTask] = []

        if requestedKinds.contains(.appCache) {
            tasks.append(CleanupScanTask {
                scanApplicationCaches(fileManager: fileManager)
            })
        }

        // Directory scan: list direct children of known root directories.
        let directoryKinds: Set<DiskCleanupKind> = [
            .cache, .log, .trash, .developerArtifacts, .temporaryFiles, .packageManagerCache, .crashReport,
            .mailDownloads, .iosBackup, .xcodeArchive, .aiToolCache,
        ]
        let activeDirKinds = requestedKinds.intersection(directoryKinds)
        if !activeDirKinds.isEmpty {
            tasks.append(CleanupScanTask {
                scanDirectoryChildren(
                    fileManager: fileManager,
                    kinds: activeDirKinds,
                    maxDepthChildrenOnly: maxDepthChildrenOnly,
                    referenceDate: options.referenceDate
                )
            })
        }

        if requestedKinds.contains(.browserCache) {
            tasks.append(CleanupScanTask {
                scanBrowserCaches(fileManager: fileManager)
            })
        }

        let userFileKinds: Set<DiskCleanupKind> = [.diskImage, .largeFile, .duplicateFile]
        let activeUserFileKinds = requestedKinds.intersection(userFileKinds)
        if !activeUserFileKinds.isEmpty {
            tasks.append(CleanupScanTask {
                scanUserFileCandidates(
                    fileManager: fileManager,
                    kinds: activeUserFileKinds,
                    options: options
                )
            })
        }

        if requestedKinds.contains(.unfinishedDownload) {
            tasks.append(CleanupScanTask {
                scanUnfinishedDownloads(fileManager: fileManager, options: options)
            })
        }
        if requestedKinds.contains(.projectBuildArtifact) {
            tasks.append(CleanupScanTask {
                scanProjectBuildArtifacts(fileManager: fileManager)
            })
        }
        if requestedKinds.contains(.applicationResidual) {
            tasks.append(CleanupScanTask {
                scanApplicationResiduals(fileManager: fileManager)
            })
        }
        if requestedKinds.contains(.languagePack) {
            tasks.append(CleanupScanTask {
                scanLanguagePacks(fileManager: fileManager)
            })
        }
        let result = executeScanTasks(
            tasks,
            workerLimit: scanWorkerLimit(requested: maxConcurrentScans)
        )
        return deduplicateCandidates(result).sorted { $0.byteSize > $1.byteSize }
    }

    /// Publishes an accumulated candidate snapshot as each scan category completes.
    public static func scanCandidatesWithProgress(
        fileManager: SystemMonitorFileManaging,
        kinds: Set<DiskCleanupKind> = Set(DiskCleanupKind.allCases),
        maxConcurrentScans: Int? = nil,
        options: DiskCleanupScanOptions = .default,
        onProgress: @escaping @Sendable ([DiskCleanupCandidate]) -> Void
    ) -> [DiskCleanupCandidate] {
        let requestedKinds = kinds.subtracting(excludedScanKinds)
        var tasks: [CleanupScanTask] = []

        if requestedKinds.contains(.appCache) {
            tasks.append(CleanupScanTask {
                scanApplicationCaches(fileManager: fileManager)
            })
        }

        let directoryKinds: Set<DiskCleanupKind> = [
            .cache, .log, .trash, .developerArtifacts, .temporaryFiles, .packageManagerCache, .crashReport,
            .mailDownloads, .iosBackup, .xcodeArchive, .aiToolCache,
        ]
        let activeDirKinds = requestedKinds.intersection(directoryKinds)
        if !activeDirKinds.isEmpty {
            tasks.append(CleanupScanTask {
                scanDirectoryChildren(
                    fileManager: fileManager,
                    kinds: activeDirKinds,
                    maxDepthChildrenOnly: true,
                    referenceDate: options.referenceDate
                )
            })
        }

        if requestedKinds.contains(.browserCache) {
            tasks.append(CleanupScanTask {
                scanBrowserCaches(fileManager: fileManager)
            })
        }

        let userFileKinds: Set<DiskCleanupKind> = [.diskImage, .largeFile, .duplicateFile]
        let activeUserFileKinds = requestedKinds.intersection(userFileKinds)
        if !activeUserFileKinds.isEmpty {
            tasks.append(CleanupScanTask {
                scanUserFileCandidates(
                    fileManager: fileManager,
                    kinds: activeUserFileKinds,
                    options: options
                )
            })
        }

        if requestedKinds.contains(.unfinishedDownload) {
            tasks.append(CleanupScanTask {
                scanUnfinishedDownloads(fileManager: fileManager, options: options)
            })
        }
        if requestedKinds.contains(.projectBuildArtifact) {
            tasks.append(CleanupScanTask {
                scanProjectBuildArtifacts(fileManager: fileManager)
            })
        }
        if requestedKinds.contains(.applicationResidual) {
            tasks.append(CleanupScanTask {
                scanApplicationResiduals(fileManager: fileManager)
            })
        }
        if requestedKinds.contains(.languagePack) {
            tasks.append(CleanupScanTask {
                scanLanguagePacks(fileManager: fileManager)
            })
        }
        let result = executeScanTasksWithProgress(
            tasks,
            workerLimit: scanWorkerLimit(requested: maxConcurrentScans),
            onProgress: onProgress
        )
        return deduplicateCandidates(result).sorted { $0.byteSize > $1.byteSize }
    }

    private static func scanApplicationCaches(
        fileManager: SystemMonitorFileManaging
    ) -> [DiskCleanupCandidate] {
        let roots = applicationCacheRoots(fileManager: fileManager)
        let allowed = SystemMonitorPathSafety.defaultAllowedRoots(fileManager: fileManager)
        let dedicatedRootPaths = Set(
            allowedScanRoots(fileManager: fileManager)
                .filter { $0.kind != .appCache }
                .map { SystemMonitorPathSafety.standardizedPath($0.url) }
        )
        var result: [DiskCleanupCandidate] = []

        for root in roots {
            guard SystemMonitorPathSafety.isURL(root.url, withinAllowedRoots: allowed) else { continue }
            switch root.source {
            case .library:
                guard fileManager.fileExists(atPath: root.url.path),
                      let children = try? fileManager.contentsOfDirectory(
                          at: root.url,
                          includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .totalFileAllocatedSizeKey],
                          options: [.skipsHiddenFiles]
                      )
                else {
                    continue
                }
                for child in children {
                    let cacheURL = child.standardizedFileURL
                    guard SystemMonitorPathSafety.isURL(cacheURL, withinAllowedRoots: allowed),
                          !dedicatedRootPaths.contains(SystemMonitorPathSafety.standardizedPath(cacheURL))
                    else {
                        continue
                    }
                    result.append(applicationCacheCandidate(
                        at: cacheURL,
                        identifier: cacheURL.lastPathComponent,
                        source: .library,
                        fileManager: fileManager
                    ))
                }
            case .sandboxContainer, .groupContainer:
                result.append(applicationCacheCandidate(
                    at: root.url,
                    identifier: root.identifier,
                    source: root.source,
                    fileManager: fileManager
                ))
            }
        }
        return result
    }

    private static func applicationCacheCandidate(
        at url: URL,
        identifier: String,
        source: ApplicationCacheSource,
        fileManager: SystemMonitorFileManaging
    ) -> DiskCleanupCandidate {
        DiskCleanupCandidate(
            url: url,
            kind: .appCache,
            byteSize: allocatedByteSize(of: url, fileManager: fileManager),
            displayName: "\(identifier) 缓存",
            detail: "\(source.detailPrefix) · \(url.path)"
        )
    }

    /// Keeps only the more specific candidate for each path.
    public static func deduplicateCandidates(_ candidates: [DiskCleanupCandidate]) -> [DiskCleanupCandidate] {
        var bestByPath: [String: DiskCleanupCandidate] = [:]
        for candidate in candidates {
            let path = candidate.url.standardizedFileURL.path
            if let existing = bestByPath[path] {
                if candidate.kind.classificationPriority > existing.kind.classificationPriority {
                    bestByPath[path] = candidate
                }
            } else {
                bestByPath[path] = candidate
            }
        }
        return Array(bestByPath.values)
    }

    /// Directory scan: list direct children of known root directories (safe candidates).
    private static func scanDirectoryChildren(
        fileManager: SystemMonitorFileManaging,
        kinds: Set<DiskCleanupKind>,
        maxDepthChildrenOnly: Bool,
        referenceDate: Date?
    ) -> [DiskCleanupCandidate] {
        let allRoots = allowedScanRoots(fileManager: fileManager)
        let roots = allRoots.filter { kinds.contains($0.kind) }
        let allowed = SystemMonitorPathSafety.defaultAllowedRoots(fileManager: fileManager)
        let allowedRootPaths = Array(Set(allowed.map(SystemMonitorPathSafety.standardizedPath)))
        // Paths that are already dedicated scan roots: do not list them as direct children of a coarser parent root to avoid double-counting
        let dedicatedRootPaths = Set(allRoots.map { $0.url.path })
        let runningProcesses = runningProcessNames(fileManager: fileManager)
        var result: [DiskCleanupCandidate] = []

        for (kind, root) in roots {
            guard fileManager.fileExists(atPath: root.path) else { continue }
            guard SystemMonitorPathSafety.isURL(root, withinAllowedRoots: allowed) else { continue }
            guard !ownedApplicationIsRunning(
                for: kind,
                processNames: runningProcesses
            ) else { continue }
            result.append(contentsOf: scanDirectoryEntries(
                at: root,
                kind: kind,
                fileManager: fileManager,
                allowedRootPaths: allowedRootPaths,
                dedicatedRootPaths: dedicatedRootPaths,
                remainingDepth: maxDepthChildrenOnly ? 1 : 4,
                referenceDate: referenceDate
            ))
        }
        return result
    }

    private static func scanDirectoryEntries(
        at root: URL,
        kind: DiskCleanupKind,
        fileManager: SystemMonitorFileManaging,
        allowedRootPaths: [String],
        dedicatedRootPaths: Set<String>,
        remainingDepth: Int,
        referenceDate: Date?
    ) -> [DiskCleanupCandidate] {
        guard remainingDepth > 0,
              let children = try? fileManager.contentsOfDirectory(
                  at: root,
                  includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .totalFileAllocatedSizeKey],
                  options: [.skipsHiddenFiles]
              )
        else {
            return []
        }

        var result: [DiskCleanupCandidate] = []
        for child in children {
            let childCandidates: [DiskCleanupCandidate] = autoreleasepool {
                guard !isSymbolicLink(child),
                      isURL(child, withinStandardizedRootPaths: allowedRootPaths)
                else {
                    return []
                }
                let standardized = child.standardizedFileURL
                guard !(dedicatedRootPaths.contains(standardized.path) && standardized.path != root.path) else {
                    return []
                }
                let temporaryDetail = temporaryCandidateDetail(
                    for: standardized,
                    kind: kind,
                    fileManager: fileManager,
                    referenceDate: referenceDate
                )
                guard kind != .temporaryFiles || temporaryDetail != nil else { return [] }
                let candidate = DiskCleanupCandidate(
                    url: standardized,
                    kind: kind,
                    byteSize: allocatedByteSize(of: standardized, fileManager: fileManager),
                    displayName: standardized.lastPathComponent,
                    detail: directoryCandidateDetail(
                        for: standardized,
                        kind: kind,
                        fallback: temporaryDetail
                    )
                )
                guard remainingDepth > 1, isDirectory(standardized, fileManager: fileManager) else {
                    return [candidate]
                }
                return [candidate] + scanDirectoryEntries(
                    at: standardized,
                    kind: kind,
                    fileManager: fileManager,
                    allowedRootPaths: allowedRootPaths,
                    dedicatedRootPaths: dedicatedRootPaths,
                    remainingDepth: remainingDepth - 1,
                    referenceDate: referenceDate
                )
            }
            result.append(contentsOf: childCandidates)
        }
        return result
    }

    private static func isURL(_ url: URL, withinStandardizedRootPaths roots: [String]) -> Bool {
        guard url.isFileURL else { return false }
        let candidate = SystemMonitorPathSafety.standardizedPath(url)
        return roots.contains { root in
            candidate == root || candidate.hasPrefix(root.hasSuffix("/") ? root : root + "/")
        }
    }

    private static func ownedApplicationIsRunning(
        for kind: DiskCleanupKind,
        processNames: Set<String>
    ) -> Bool {
        switch kind {
        case .mailDownloads:
            return processNames.contains { $0.localizedCaseInsensitiveContains("mail") }
        case .xcodeArchive:
            return processNames.contains { $0.localizedCaseInsensitiveContains("xcode") }
        default:
            return false
        }
    }

    private static let temporaryFileMinAge: TimeInterval = 7 * 24 * 3600

    private static func isCurrentUserTemporaryDirectory(_ url: URL) -> Bool {
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        return path.hasPrefix("/private/var/folders/") || path.hasPrefix("/var/folders/")
    }

    private static func temporaryCandidateDetail(
        for url: URL,
        kind: DiskCleanupKind,
        fileManager: SystemMonitorFileManaging,
        referenceDate: Date?
    ) -> String? {
        guard kind == .temporaryFiles else { return nil }
        guard let modificationDate = try? fileManager.attributesOfItem(atPath: url.path)[.modificationDate] as? Date else {
            return nil
        }
        let age = (referenceDate ?? Date()).timeIntervalSince(modificationDate)
        guard age >= temporaryFileMinAge else { return nil }
        return "\(Int(age / 86400)) 天未修改"
    }

    private static func directoryCandidateDetail(
        for url: URL,
        kind: DiskCleanupKind,
        fallback: String?
    ) -> String? {
        switch kind {
        case .mailDownloads:
            return "Mail 附件下载 · \(url.path)"
        case .iosBackup:
            return "iPhone/iPad 备份 · \(url.path)"
        case .xcodeArchive:
            return "Xcode Archive · \(url.path)"
        case .aiToolCache:
            return "AI 工具缓存 · \(url.path)"
        default:
            return fallback
        }
    }

    private static func scanBrowserCaches(
        fileManager: SystemMonitorFileManaging
    ) -> [DiskCleanupCandidate] {
        let allowed = SystemMonitorPathSafety.defaultAllowedRoots(fileManager: fileManager)
        let roots = browserCacheRoots(fileManager: fileManager)
        let runningProcesses = runningProcessNames(fileManager: fileManager)
        var result: [DiskCleanupCandidate] = []
        for root in roots {
            guard fileManager.fileExists(atPath: root.path),
                  SystemMonitorPathSafety.isURL(root, withinAllowedRoots: allowed),
                  !browserOwnerIsRunning(for: root, processNames: runningProcesses)
            else {
                continue
            }
            let size = allocatedByteSize(of: root, fileManager: fileManager)
            guard size > 0 else { continue }
            result.append(
                DiskCleanupCandidate(
                    url: root.standardizedFileURL,
                    kind: .browserCache,
                    byteSize: size,
                    displayName: root.lastPathComponent,
                    detail: "浏览器可再生缓存 · \(root.path)",
                    source: browserName(for: root)
                )
            )
        }
        return result
    }

    private static func browserName(for url: URL) -> String {
        let path = url.path.lowercased()
        if path.contains("safari") { return "Safari" }
        if path.contains("microsoft edge") || path.contains("edgemac") { return "Microsoft Edge" }
        if path.contains("brave") { return "Brave" }
        if path.contains("firefox") { return "Firefox" }
        if path.contains("arc") || path.contains("thebrowser") { return "Arc" }
        return "Chrome"
    }

    private static func browserOwnerIsRunning(for url: URL, processNames: Set<String>) -> Bool {
        let names = switch browserName(for: url) {
        case "Safari": ["safari"]
        case "Microsoft Edge": ["microsoft edge", "msedge"]
        case "Brave": ["brave browser", "brave"]
        case "Firefox": ["firefox"]
        case "Arc": ["arc"]
        default: ["chrome", "google chrome"]
        }
        return processNames.contains { process in
            names.contains { process.localizedCaseInsensitiveContains($0) }
        }
    }

    private static func runningProcessNames(fileManager: SystemMonitorFileManaging) -> Set<String> {
        guard fileManager is DefaultSystemMonitorFileManager,
              let output = readOnlyCommand(executable: "/bin/ps", arguments: ["-axo", "comm="]) else {
            return []
        }
        return Set(output.split(whereSeparator: \.isNewline).map {
            String($0).trimmingCharacters(in: .whitespaces)
        })
    }

    private static let diskImageExtensions: Set<String> = ["dmg", "iso", "pkg", "ipsw", "xip"]
    private static let unfinishedDownloadExtensions: Set<String> = ["download", "crdownload", "part"]

    /// Scans user-selected folders for installer packages and disk images.
    private static func scanDiskImages(
        fileManager: SystemMonitorFileManaging,
        directories: [URL],
        maxDepth: Int
    ) -> [DiskCleanupCandidate] {
        let allowed = allowedUserFileRoots(fileManager: fileManager, directories: directories)
        var result: [DiskCleanupCandidate] = []
        enumerateUserFiles(
            in: directories,
            fileManager: fileManager,
            maxDepth: maxDepth,
            allowed: allowed
        ) { file in
            autoreleasepool {
                let standardized = file.standardizedFileURL
                guard diskImageExtensions.contains(standardized.pathExtension.lowercased()) else { return }
                let size = allocatedByteSize(of: standardized, fileManager: fileManager)
                result.append(
                    DiskCleanupCandidate(
                        url: standardized,
                        kind: .diskImage,
                        byteSize: size,
                        displayName: standardized.lastPathComponent,
                        detail: "安装包/磁盘镜像 · \(standardized.deletingLastPathComponent().path)"
                    )
                )
            }
        }
        return result
    }

    private struct DuplicateFileKey: Hashable, Sendable {
        let byteSize: UInt64
        let digest: Data
    }

    private struct DuplicateFileOriginal: Sendable {
        let url: URL
    }

    private static func scanUserFileCandidates(
        fileManager: SystemMonitorFileManaging,
        kinds: Set<DiskCleanupKind>,
        options: DiskCleanupScanOptions
    ) -> [DiskCleanupCandidate] {
        var result: [DiskCleanupCandidate] = []
        let directories = userFileScanDirectories(
            fileManager: fileManager,
            additional: options.additionalUserDirectories
        )
        if kinds.contains(.diskImage) {
            result.append(
                contentsOf: scanDiskImages(
                    fileManager: fileManager,
                    directories: directories,
                    maxDepth: options.userFileMaxDepth
                )
            )
        }

        let needsLargeFiles = kinds.contains(.largeFile)
        let needsDuplicates = kinds.contains(.duplicateFile)
        guard needsLargeFiles || needsDuplicates else { return result }

        let allowed = allowedUserFileRoots(fileManager: fileManager, directories: directories)
        let referenceDate = options.referenceDate ?? Date()
        let largeFileCutoff = referenceDate.addingTimeInterval(-options.oldFileAge)
        var firstFileSizes = Set<UInt64>()
        var repeatedFileSizes = Set<UInt64>()

        enumerateUserFiles(
            in: directories,
            fileManager: fileManager,
            maxDepth: options.userFileMaxDepth,
            allowed: allowed
        ) { fileURL in
            autoreleasepool {
                let standardized = fileURL.standardizedFileURL
                let size = allocatedByteSize(of: standardized, fileManager: fileManager)
                guard size > 0 else { return }

                if needsLargeFiles,
                   size >= options.largeFileThreshold,
                   let modificationDate = (try? fileManager.attributesOfItem(atPath: standardized.path)[.modificationDate]) as? Date,
                   modificationDate < largeFileCutoff {
                    let days = Int(referenceDate.timeIntervalSince(modificationDate) / 86400)
                    result.append(
                        DiskCleanupCandidate(
                            url: standardized,
                            kind: .largeFile,
                            byteSize: size,
                            displayName: standardized.lastPathComponent,
                            detail: "\(days) 天前修改"
                        )
                    )
                }

                guard needsDuplicates, !repeatedFileSizes.contains(size) else { return }
                if !firstFileSizes.insert(size).inserted {
                    firstFileSizes.remove(size)
                    repeatedFileSizes.insert(size)
                }
            }
        }
        if needsDuplicates {
            result.append(
                contentsOf: duplicateFileCandidates(
                    fileManager: fileManager,
                    directories: directories,
                    maxDepth: options.userFileMaxDepth,
                    allowed: allowed,
                    repeatedFileSizes: repeatedFileSizes
                )
            )
        }
        return result
    }

    /// Finds repeated allocated sizes first, then retains only the first SHA256 match for each duplicate group.
    private static func duplicateFileCandidates(
        fileManager: SystemMonitorFileManaging,
        directories: [URL],
        maxDepth: Int,
        allowed: [URL],
        repeatedFileSizes: Set<UInt64>
    ) -> [DiskCleanupCandidate] {
        guard !repeatedFileSizes.isEmpty else { return [] }
        var originals: [DuplicateFileKey: DuplicateFileOriginal] = [:]
        var result: [DiskCleanupCandidate] = []
        enumerateUserFiles(
            in: directories,
            fileManager: fileManager,
            maxDepth: maxDepth,
            allowed: allowed
        ) { fileURL in
            autoreleasepool {
                let standardized = fileURL.standardizedFileURL
                let size = allocatedByteSize(of: standardized, fileManager: fileManager)
                guard repeatedFileSizes.contains(size),
                      let digest = fileManager.sha256Digest(at: standardized)
                else {
                    return
                }
                let key = DuplicateFileKey(byteSize: size, digest: digest)
                if let original = originals[key] {
                    result.append(
                        DiskCleanupCandidate(
                            url: standardized,
                            kind: .duplicateFile,
                            byteSize: size,
                            displayName: standardized.lastPathComponent,
                            detail: "与 \(original.url.lastPathComponent) 重复 · 保留副本：\(original.url.path)"
                        )
                    )
                } else {
                    originals[key] = DuplicateFileOriginal(url: standardized)
                }
            }
        }
        return result
    }

    private static func scanUnfinishedDownloads(
        fileManager: SystemMonitorFileManaging,
        options: DiskCleanupScanOptions
    ) -> [DiskCleanupCandidate] {
        let referenceDate = options.referenceDate ?? Date()
        let directories = userFileScanDirectories(
            fileManager: fileManager,
            additional: options.additionalUserDirectories
        )
        let allowed = allowedUserFileRoots(fileManager: fileManager, directories: directories)
        var result: [DiskCleanupCandidate] = []
        enumerateUserFiles(
            in: directories,
            fileManager: fileManager,
            maxDepth: options.userFileMaxDepth,
            allowed: allowed
        ) { fileURL in
            autoreleasepool {
                let standardized = fileURL.standardizedFileURL
                let ext = standardized.pathExtension.lowercased()
                let name = standardized.lastPathComponent.lowercased()
                guard unfinishedDownloadExtensions.contains(ext)
                    || name.hasSuffix(".download")
                    || name.hasSuffix(".crdownload")
                    || name.hasSuffix(".part")
                else {
                    return
                }
                guard let modificationDate = (try? fileManager.attributesOfItem(atPath: standardized.path)[.modificationDate]) as? Date,
                      referenceDate.timeIntervalSince(modificationDate) >= options.unfinishedDownloadAge
                else {
                    return
                }
                let size = allocatedByteSize(of: standardized, fileManager: fileManager)
                guard size > 0 else { return }
                let days = Int(referenceDate.timeIntervalSince(modificationDate) / 86400)
                result.append(
                    DiskCleanupCandidate(
                        url: standardized,
                        kind: .unfinishedDownload,
                        byteSize: size,
                        displayName: standardized.lastPathComponent,
                        detail: "未完成下载 · \(days) 天未修改",
                        source: standardized.deletingLastPathComponent().lastPathComponent
                    )
                )
            }
        }
        return result
    }

    private static let projectMarkers: Set<String> = [
        ".git", "Package.swift", "package.json", "Cargo.toml", "pyproject.toml", "go.mod",
        "pom.xml", "build.gradle", "Podfile", "project.pbxproj",
    ]
    private static let projectArtifactNames: Set<String> = [
        ".build", "DerivedData", "node_modules", "target", "dist", ".next", "build",
        "__pycache__", ".pytest_cache", ".gradle",
    ]
    private static let projectTraversalExclusions: Set<String> = [
        "Library", "Applications", "System", ".Trash", "Movies", "Music", "Pictures",
        "Public", "Downloads", "Desktop", "Documents", "Caches", "Containers",
    ]

    private static func scanProjectBuildArtifacts(
        fileManager: SystemMonitorFileManaging
    ) -> [DiskCleanupCandidate] {
        let home = fileManager.homeDirectoryForCurrentUser().standardizedFileURL
        let roots = projectSearchRoots(fileManager: fileManager)
        let runningProcesses = runningProcessNames(fileManager: fileManager)
        var visited = Set<String>()
        var result: [DiskCleanupCandidate] = []
        for root in roots {
            guard !isSymbolicLink(root) else { continue }
            findProjectArtifacts(
                at: root,
                fileManager: fileManager,
                depth: 0,
                maxDepth: 5,
                home: home,
                runningProcesses: runningProcesses,
                visited: &visited,
                result: &result
            )
        }
        return result
    }

    private static func projectSearchRoots(fileManager: SystemMonitorFileManaging) -> [URL] {
        let home = fileManager.homeDirectoryForCurrentUser().standardizedFileURL
        var roots = [
            home.appendingPathComponent("Developer", isDirectory: true),
            home.appendingPathComponent("Projects", isDirectory: true),
        ]
        roots.append(contentsOf: userFileDirectories(fileManager: fileManager))

        if let children = try? fileManager.contentsOfDirectory(
            at: home,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            roots.append(contentsOf: children.filter {
                isDirectory($0, fileManager: fileManager)
                    && !projectTraversalExclusions.contains($0.lastPathComponent)
            })
        }
        return uniqueURLs(roots)
    }

    private static func findProjectArtifacts(
        at url: URL,
        fileManager: SystemMonitorFileManaging,
        depth: Int,
        maxDepth: Int,
        home: URL,
        runningProcesses: Set<String>,
        visited: inout Set<String>,
        result: inout [DiskCleanupCandidate]
    ) {
        guard depth <= maxDepth,
              result.count < 500,
              SystemMonitorPathSafety.isURL(url, withinAllowedRoots: [home]),
              fileManager.fileExists(atPath: url.path)
        else {
            return
        }
        let path = SystemMonitorPathSafety.standardizedPath(url)
        guard visited.insert(path).inserted else { return }

        guard let children = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) else {
            return
        }
        let childNames = Set(children.map(\.lastPathComponent))
        let isProjectRoot = !childNames.intersection(projectMarkers).isEmpty
        for child in children {
            guard !isSymbolicLink(child) else { continue }
            let name = child.lastPathComponent
            let childIsDirectory = isDirectory(child, fileManager: fileManager)
            guard childIsDirectory else { continue }
            if isProjectRoot, projectArtifactNames.contains(name) {
                guard !directoryContainsRunningProcess(child, processNames: runningProcesses) else { continue }
                let size = allocatedByteSize(of: child, fileManager: fileManager)
                guard size > 0 else { continue }
                result.append(
                    DiskCleanupCandidate(
                        url: child.standardizedFileURL,
                        kind: .projectBuildArtifact,
                        byteSize: size,
                        displayName: name,
                        detail: "项目构建产物 · 项目根：\(url.path)",
                        source: url.path
                    )
                )
                continue
            }
            guard depth < maxDepth,
                  !projectTraversalExclusions.contains(name),
                  !name.hasPrefix(".") || name == ".git"
            else {
                continue
            }
            findProjectArtifacts(
                at: child,
                fileManager: fileManager,
                depth: depth + 1,
                    maxDepth: maxDepth,
                    home: home,
                    runningProcesses: runningProcesses,
                    visited: &visited,
                    result: &result
            )
        }
    }

    private static func directoryContainsRunningProcess(_ directory: URL, processNames: Set<String>) -> Bool {
        let path = SystemMonitorPathSafety.standardizedPath(directory)
        return processNames.contains { processPath in
            processPath == path || processPath.hasPrefix(path + "/")
        }
    }

    private static let applicationResidualRoots = [
        "Library/Preferences",
        "Library/Application Support",
        "Library/Containers",
        "Library/Group Containers",
        "Library/Saved Application State",
        "Library/WebKit",
        "Library/LaunchAgents",
    ]
    private static let applicationResidualMinimumSize: UInt64 = 1 * 1024 * 1024

    private static func scanApplicationResiduals(
        fileManager: SystemMonitorFileManaging
    ) -> [DiskCleanupCandidate] {
        let home = fileManager.homeDirectoryForCurrentUser().standardizedFileURL
        let installed = installedBundleIdentifiers(fileManager: fileManager, home: home)
        var result: [DiskCleanupCandidate] = []
        for relativeRoot in applicationResidualRoots {
            let root = home.appendingPathComponent(relativeRoot, isDirectory: true)
            guard fileManager.fileExists(atPath: root.path),
                  let children = try? fileManager.contentsOfDirectory(
                      at: root,
                      includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .totalFileAllocatedSizeKey],
                      options: [.skipsHiddenFiles]
                  )
            else {
                continue
            }
            for child in children {
                autoreleasepool {
                    guard !isSymbolicLink(child) else { return }
                    let identifier = residualIdentifier(for: child, root: root)
                    guard let identifier,
                          !isAppleSystemIdentifier(identifier),
                          !isOwnedByInstalledApplication(identifier, installed: installed),
                          looksLikeBundleIdentifier(identifier),
                          let size = significantApplicationResidualSize(of: child, fileManager: fileManager)
                    else {
                        return
                    }
                    result.append(
                        DiskCleanupCandidate(
                            url: child.standardizedFileURL,
                            kind: .applicationResidual,
                            byteSize: size,
                            displayName: child.lastPathComponent,
                            detail: "可能是已卸载应用残留 · bundle id：\(identifier) · 需确认归属",
                            source: identifier
                        )
                    )
                }
            }
        }
        return result
    }

    private static func residualIdentifier(for url: URL, root: URL) -> String? {
        let name = url.deletingPathExtension().lastPathComponent
        if root.lastPathComponent == "Preferences" || root.lastPathComponent == "LaunchAgents" {
            return name
        }
        return url.lastPathComponent
    }

    private static func looksLikeBundleIdentifier(_ value: String) -> Bool {
        let parts = value.split(separator: ".")
        guard parts.count >= 2 else { return false }
        return parts.allSatisfy { part in
            !part.isEmpty && part.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        }
    }

    private static func isAppleSystemIdentifier(_ identifier: String) -> Bool {
        identifier == "com.apple"
            || identifier.hasPrefix("com.apple.")
            || identifier == "group.com.apple"
            || identifier.hasPrefix("group.com.apple.")
    }

    private static func significantApplicationResidualSize(
        of url: URL,
        fileManager: SystemMonitorFileManaging
    ) -> UInt64? {
        if isDirectory(url, fileManager: fileManager) {
            let size = allocatedByteSize(of: url, fileManager: fileManager)
            return size >= applicationResidualMinimumSize ? size : nil
        }
        guard let size = (try? fileManager.attributesOfItem(atPath: url.path)[.size]) as? NSNumber,
              size.uint64Value >= applicationResidualMinimumSize
        else {
            return nil
        }
        let allocated = allocatedByteSize(of: url, fileManager: fileManager)
        return allocated >= applicationResidualMinimumSize ? allocated : nil
    }

    private static func residualOwnerIdentifiers(for identifier: String) -> [String] {
        var values: Set<String> = [identifier]
        if identifier.hasPrefix("group.") {
            values.insert(String(identifier.dropFirst("group.".count)))
        }
        let parts = identifier.split(separator: ".")
        if let first = parts.first,
           first.unicodeScalars.count == 10,
           first.unicodeScalars.allSatisfy({ scalar in
               (48...57).contains(scalar.value) || (65...90).contains(scalar.value)
           }) {
            values.insert(parts.dropFirst().joined(separator: "."))
        }
        let currentValues = values
        for value in currentValues where value.hasSuffix(".savedState") {
            values.insert(String(value.dropLast(".savedState".count)))
        }
        return Array(values)
    }

    private static func isOwnedByInstalledApplication(_ identifier: String, installed: Set<String>) -> Bool {
        let ownerIdentifiers = residualOwnerIdentifiers(for: identifier)
        if ownerIdentifiers.contains(where: installed.contains) {
            return true
        }
        let ownerNamespaces = Set(ownerIdentifiers.compactMap { vendorNamespace(for: $0) })
        return installed.contains { installedIdentifier in
            guard let namespace = vendorNamespace(for: installedIdentifier) else { return false }
            return ownerNamespaces.contains(namespace)
        }
    }

    private static func vendorNamespace(for identifier: String) -> String? {
        let parts = identifier.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        return parts.prefix(2).joined(separator: ".")
    }

    private static func installedBundleIdentifiers(
        fileManager: SystemMonitorFileManaging,
        home: URL
    ) -> Set<String> {
        let roots = [
            home.appendingPathComponent("Applications", isDirectory: true),
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Library/CoreServices", isDirectory: true),
        ]
        var identifiers = Set<String>()
        var visited = Set<String>()
        for root in roots {
            collectInstalledBundleIdentifiers(
                at: root,
                fileManager: fileManager,
                depth: 0,
                maxDepth: 3,
                visited: &visited,
                identifiers: &identifiers
            )
        }
        return identifiers
    }

    private static let embeddedBundleTraversalDirectories: Set<String> = [
        "Contents", "MacOS", "PlugIns", "Frameworks", "Resources", "Library", "LoginItems", "app",
    ]

    private static func collectBundleIdentifiers(
        from bundle: URL,
        fileManager: SystemMonitorFileManaging,
        identifiers: inout Set<String>
    ) {
        let infoURL = bundle.appendingPathComponent("Contents/Info.plist")
        if let data = fileManager.contents(atPath: infoURL.path),
           let plist = try? PropertyListSerialization.propertyList(
               from: data,
               options: [],
               format: nil
           ) as? [String: Any],
           let identifier = plist["CFBundleIdentifier"] as? String {
            identifiers.insert(identifier)
        }
        collectEmbeddedBundleIdentifiers(
            at: bundle.appendingPathComponent("Contents", isDirectory: true),
            fileManager: fileManager,
            depth: 0,
            maxDepth: 6,
            identifiers: &identifiers
        )
    }

    private static func collectEmbeddedBundleIdentifiers(
        at url: URL,
        fileManager: SystemMonitorFileManaging,
        depth: Int,
        maxDepth: Int,
        identifiers: inout Set<String>
    ) {
        guard depth < maxDepth,
              let children = try? fileManager.contentsOfDirectory(
                  at: url,
                  includingPropertiesForKeys: [.isDirectoryKey],
                  options: [.skipsHiddenFiles]
              )
        else {
            return
        }
        for child in children {
            guard !isSymbolicLink(child) else { continue }
            let extensionName = child.pathExtension.lowercased()
            if extensionName == "app" || extensionName == "appex" {
                collectBundleIdentifiers(from: child, fileManager: fileManager, identifiers: &identifiers)
            } else if embeddedBundleTraversalDirectories.contains(child.lastPathComponent),
                      isDirectory(child, fileManager: fileManager) {
                collectEmbeddedBundleIdentifiers(
                    at: child,
                    fileManager: fileManager,
                    depth: depth + 1,
                    maxDepth: maxDepth,
                    identifiers: &identifiers
                )
            }
        }
    }

    private static func collectInstalledBundleIdentifiers(
        at url: URL,
        fileManager: SystemMonitorFileManaging,
        depth: Int,
        maxDepth: Int,
        visited: inout Set<String>,
        identifiers: inout Set<String>
    ) {
        guard depth <= maxDepth,
              fileManager.fileExists(atPath: url.path),
              visited.insert(url.standardizedFileURL.path).inserted,
                  let children = try? fileManager.contentsOfDirectory(
                      at: url,
                      includingPropertiesForKeys: [.isDirectoryKey],
                      options: []
                  )
        else {
            return
        }
        for child in children {
            if child.pathExtension.lowercased() == "app" {
                collectBundleIdentifiers(from: child, fileManager: fileManager, identifiers: &identifiers)
                continue
            }
            if isDirectory(child, fileManager: fileManager) {
                collectInstalledBundleIdentifiers(
                    at: child,
                    fileManager: fileManager,
                    depth: depth + 1,
                    maxDepth: maxDepth,
                    visited: &visited,
                    identifiers: &identifiers
                )
            }
        }
    }

    private static func scanLanguagePacks(
        fileManager: SystemMonitorFileManaging
    ) -> [DiskCleanupCandidate] {
        let home = fileManager.homeDirectoryForCurrentUser().standardizedFileURL
        let applications = home.appendingPathComponent("Applications", isDirectory: true)
        guard fileManager.fileExists(atPath: applications.path) else { return [] }
        let bundles = findApplicationBundles(at: applications, fileManager: fileManager, depth: 0, maxDepth: 3)
        var result: [DiskCleanupCandidate] = []
        for app in bundles {
            let resources = app.appendingPathComponent("Contents/Resources", isDirectory: true)
            guard let children = try? fileManager.contentsOfDirectory(
                at: resources,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }
            for locale in children where locale.pathExtension.lowercased() == "lproj" {
                let localeName = locale.deletingPathExtension().lastPathComponent
                guard localeName != "Base" else { continue }
                let size = allocatedByteSize(of: locale, fileManager: fileManager)
                guard size > 0 else { continue }
                result.append(
                    DiskCleanupCandidate(
                        url: locale.standardizedFileURL,
                        kind: .languagePack,
                        byteSize: size,
                        displayName: "\(app.deletingPathExtension().lastPathComponent) · \(localeName)",
                        detail: "应用语言包 · 仅建议在确认不需要该语言后处理",
                        source: app.path
                    )
                )
            }
        }
        return result
    }

    private static func findApplicationBundles(
        at url: URL,
        fileManager: SystemMonitorFileManaging,
        depth: Int,
        maxDepth: Int
    ) -> [URL] {
        guard depth <= maxDepth,
              let children = try? fileManager.contentsOfDirectory(
                  at: url,
                  includingPropertiesForKeys: [.isDirectoryKey],
                  options: [.skipsHiddenFiles]
              )
        else {
            return []
        }
        var result: [URL] = []
        for child in children {
            if child.pathExtension.lowercased() == "app" {
                result.append(child)
            } else if isDirectory(child, fileManager: fileManager) {
                result.append(contentsOf: findApplicationBundles(
                    at: child,
                    fileManager: fileManager,
                    depth: depth + 1,
                    maxDepth: maxDepth
                ))
            }
        }
        return result
    }

    private static func readOnlyCommand(executable: String, arguments: [String]) -> String? {
        guard FileManager.default.isExecutableFile(atPath: executable) else { return nil }
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            // Drain while the command is running; `ps` can exceed a pipe buffer on developer machines.
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    // MARK: - File helpers

    /// Returns user file directories: Downloads / Desktop / Documents
    private static func userFileDirectories(fileManager: SystemMonitorFileManaging) -> [URL] {
        userFileDirectories(fileManager: fileManager, additional: [])
    }

    private static func userFileDirectories(
        fileManager: SystemMonitorFileManaging,
        additional: [URL]
    ) -> [URL] {
        let dirs: [FileManager.SearchPathDirectory] = [.downloadsDirectory, .desktopDirectory, .documentDirectory]
        var result = dirs.compactMap { fileManager.urls(for: $0, in: .userDomainMask).first }
        result.append(contentsOf: additional)
        var seen = Set<String>()
        return result.filter { seen.insert(SystemMonitorPathSafety.standardizedPath($0)).inserted }
    }

    /// Removes nested roots so each user file is visited once without retaining every path in a de-duplication set.
    private static func userFileScanDirectories(
        fileManager: SystemMonitorFileManaging,
        additional: [URL]
    ) -> [URL] {
        let home = fileManager.homeDirectoryForCurrentUser().standardizedFileURL
        var roots: [URL] = []
        for directory in userFileDirectories(fileManager: fileManager, additional: additional) {
            let standardized = directory.standardizedFileURL
            guard SystemMonitorPathSafety.isURL(standardized, withinAllowedRoots: [home]) else { continue }
            if roots.contains(where: { SystemMonitorPathSafety.isURL(standardized, withinAllowedRoots: [$0]) }) {
                continue
            }
            roots.removeAll { SystemMonitorPathSafety.isURL($0, withinAllowedRoots: [standardized]) }
            roots.append(standardized)
        }
        return roots
    }

    private static func allowedUserFileRoots(
        fileManager: SystemMonitorFileManaging,
        directories: [URL]
    ) -> [URL] {
        let home = fileManager.homeDirectoryForCurrentUser().standardizedFileURL
        let defaultRoots = SystemMonitorPathSafety.defaultAllowedRoots(fileManager: fileManager)
        let userRoots = directories.filter {
            SystemMonitorPathSafety.isURL($0, withinAllowedRoots: [home])
        }
        return uniqueURLs(defaultRoots + userRoots)
    }

    private static func enumerateUserFiles(
        in directories: [URL],
        fileManager: SystemMonitorFileManaging,
        maxDepth: Int,
        allowed: [URL],
        handler: (URL) -> Void
    ) {
        for directory in directories {
            guard fileManager.fileExists(atPath: directory.path),
                  SystemMonitorPathSafety.isURL(directory, withinAllowedRoots: allowed)
            else {
                continue
            }
            enumerateFilesRecursively(
                at: directory,
                fileManager: fileManager,
                maxDepth: maxDepth,
                allowed: allowed,
                handler: handler
            )
        }
    }

    /// Streams files via callback without accumulating all URLs in memory.
    private static func enumerateFilesRecursively(
        at url: URL,
        fileManager: SystemMonitorFileManaging,
        maxDepth: Int,
        allowed: [URL],
        handler: (URL) -> Void
    ) {
        guard maxDepth > 0 else { return }
        guard SystemMonitorPathSafety.isURL(url, withinAllowedRoots: allowed) else { return }

        let children: [URL]
        do {
            children = try fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            return
        }

        for child in children {
            autoreleasepool {
                guard !isSymbolicLink(child) else { return }
                let standardized = child.standardizedFileURL
                guard SystemMonitorPathSafety.isURL(standardized, withinAllowedRoots: allowed) else { return }

                if isDirectory(standardized, fileManager: fileManager) {
                    enumerateFilesRecursively(
                        at: standardized,
                        fileManager: fileManager,
                        maxDepth: maxDepth - 1,
                        allowed: allowed,
                        handler: handler
                    )
                } else {
                    handler(standardized)
                }
            }
        }
    }

    private static func isSymbolicLink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }

    /// Returns whether a URL is a directory: prefers resourceValues, falls back to contentsOfDirectory.
    private static func isDirectory(_ url: URL, fileManager: SystemMonitorFileManaging) -> Bool {
        if let isDir = try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory,
           isDir == true {
            return isDir
        }
        // Fallback: try listing children; if non-empty, treat as directory
        let children = (try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return !children.isEmpty
    }

    /// Moves selected URLs to the Trash; never permanently deletes. Out-of-bounds URLs are recorded as failures.
    public static func trashSelected(
        urls: [URL],
        fileManager: SystemMonitorFileManaging,
        allowedRoots: [URL]? = nil,
        sizeProvider: ((URL) -> UInt64)? = nil
    ) -> DiskCleanupResult {
        let roots = allowedRoots ?? SystemMonitorPathSafety.defaultAllowedRoots(fileManager: fileManager)
        var success = 0
        var freed: UInt64 = 0
        var failures: [DiskCleanupFailure] = []

        for url in urls {
            guard url.isFileURL else {
                failures.append(DiskCleanupFailure(url: url, message: DiskCleanupError.notAFileURL.localizedDescription))
                continue
            }
            let standardized = url.standardizedFileURL
            guard SystemMonitorPathSafety.isURL(standardized, withinAllowedRoots: roots) else {
                failures.append(
                    DiskCleanupFailure(
                        url: standardized,
                        message: DiskCleanupError.pathOutsideAllowedRoots.localizedDescription
                    )
                )
                continue
            }
            guard fileManager.fileExists(atPath: standardized.path) else {
                failures.append(DiskCleanupFailure(url: standardized, message: "文件不存在"))
                continue
            }
            let size = sizeProvider?(standardized) ?? allocatedByteSize(of: standardized, fileManager: fileManager)
            do {
                _ = try fileManager.trashItem(at: standardized)
                success += 1
                freed += size
            } catch {
                failures.append(DiskCleanupFailure(url: standardized, message: error.localizedDescription))
            }
        }
        return DiskCleanupResult(successCount: success, freedBytes: freed, failures: failures)
    }

    /// Moves verified scan candidates to the Trash. Analysis-only candidates are rejected explicitly.
    public static func trashSelected(
        candidates: [DiskCleanupCandidate],
        fileManager: SystemMonitorFileManaging,
        sizeProvider: ((URL) -> UInt64)? = nil
    ) -> DiskCleanupResult {
        var success = 0
        var freed: UInt64 = 0
        var failures: [DiskCleanupFailure] = []

        for candidate in candidates {
            guard candidate.isActionable else {
                failures.append(
                    DiskCleanupFailure(
                        url: candidate.url,
                        message: DiskCleanupError.analysisOnlyCandidate.localizedDescription
                    )
                )
                continue
            }
            guard candidatePathIsEligibleForTrash(candidate, fileManager: fileManager) else {
                failures.append(
                    DiskCleanupFailure(
                        url: candidate.url,
                        message: DiskCleanupError.pathOutsideAllowedRoots.localizedDescription
                    )
                )
                continue
            }
            let result = trashSelected(
                urls: [candidate.url],
                fileManager: fileManager,
                allowedRoots: [candidate.url],
                sizeProvider: sizeProvider
            )
            success += result.successCount
            freed += result.freedBytes
            failures.append(contentsOf: result.failures)
        }
        return DiskCleanupResult(successCount: success, freedBytes: freed, failures: failures)
    }

    private static func candidatePathIsEligibleForTrash(
        _ candidate: DiskCleanupCandidate,
        fileManager: SystemMonitorFileManaging
    ) -> Bool {
        guard candidate.url.isFileURL, candidate.kind.safetyLevel != .analysisOnly else { return false }
        let path = SystemMonitorPathSafety.standardizedPath(candidate.url)
        let home = SystemMonitorPathSafety.standardizedPath(fileManager.homeDirectoryForCurrentUser())

        switch candidate.kind {
        case .applicationResidual:
            return applicationResidualRoots.contains { root in
                let rootURL = URL(fileURLWithPath: home).appendingPathComponent(root, isDirectory: true)
                return URL(fileURLWithPath: path).deletingLastPathComponent().path == rootURL.path
            }
        case .projectBuildArtifact:
            return path.hasPrefix(home + "/")
                && projectArtifactNames.contains(URL(fileURLWithPath: path).lastPathComponent)
        case .languagePack:
            return path.hasPrefix(home + "/Applications/") && path.hasSuffix(".lproj")
        default:
            return SystemMonitorPathSafety.isURL(
                candidate.url,
                withinAllowedRoots: SystemMonitorPathSafety.defaultAllowedRoots(fileManager: fileManager)
            )
        }
    }
}

// MARK: - Service

/// SwiftUI-facing system sampling and safe cleanup service; experimental readings are read-only and can be explicitly degraded.
@MainActor
public final class SystemMonitorService: ObservableObject {
    @Published public private(set) var snapshot: SystemMetricsSnapshot?
    @Published public private(set) var history = SystemMetricHistory()
    @Published public private(set) var lastErrorDescription: String?
    @Published public private(set) var isSampling: Bool = false
    @Published public private(set) var publicIPAddress: String?
    @Published public private(set) var isRefreshingPublicIPAddress = false

    public let samplingInterval: TimeInterval

    private static let publicIPRefreshInterval: TimeInterval = 10 * 60
    private let fileManager: any SystemMonitorFileManaging
    private let dateProvider: @Sendable () -> Date
    private let publicIPProvider: any PublicIPProviding
    private let hardwareInfoProvider: @Sendable () -> SystemHardwareInfo
    private let volumeURL: URL
    private var timer: AnyCancellable?
    private var diskCapacityTimer: AnyCancellable?
    private var previousCPU: host_cpu_load_info?
    private var previousNetwork: (received: UInt64, sent: UInt64, at: Date)?
    private var previousDisk: (read: UInt64, write: UInt64, at: Date)?
    private var networkIdentity = NetworkIdentity()
    private var lastPublicIPRefresh: Date?
    private var lastDiskCapacitySample: Date?
    private var needsDiskCapacityRefresh = false
    private var hardware = SystemHardwareInfo.unavailable
    private var didLoadHardware = false
    private var isSampleInProgress = false
    private var sampleWaiters: [CheckedContinuation<SystemMetricsSnapshot, Never>] = []
    private let postCleanupDiskRefreshDelay: Duration
    private let diskCapacityRefreshInterval: TimeInterval
    private var postCleanupDiskRefreshTask: Task<Void, Never>?
    static let slowMetricsRefreshInterval: TimeInterval = 5
    private var lastSlowMetricsSample: Date?
    private var cachedGPUMetrics: GPUMetrics?
    private var cachedSensorSample: AppleSMCSensorSample?

    public init(
        samplingInterval: TimeInterval = 1.5,
        fileManager: (any SystemMonitorFileManaging)? = nil,
        volumeURL: URL? = nil,
        dateProvider: @escaping @Sendable () -> Date = { Date() },
        publicIPProvider: (any PublicIPProviding)? = nil,
        hardwareInfoProvider: (@Sendable () -> SystemHardwareInfo)? = nil,
        postCleanupDiskRefreshDelay: Duration = .seconds(30),
        diskCapacityRefreshInterval: TimeInterval = 20
    ) {
        let fileManager = fileManager ?? DefaultSystemMonitorFileManager()
        self.samplingInterval = max(0.2, samplingInterval)
        self.fileManager = fileManager
        self.dateProvider = dateProvider
        self.publicIPProvider = publicIPProvider ?? DefaultPublicIPProvider()
        self.hardwareInfoProvider = hardwareInfoProvider ?? { SystemHardwareInfoReader.read() }
        self.postCleanupDiskRefreshDelay = max(.zero, postCleanupDiskRefreshDelay)
        self.diskCapacityRefreshInterval = max(0.01, diskCapacityRefreshInterval)
        self.volumeURL = volumeURL
            ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser()
    }

    public func start() {
        guard timer == nil else { return }
        isSampling = true
        // Sample immediately, then continue at the configured interval.
        Task { await self.sampleOnce() }
        timer = Timer.publish(every: samplingInterval, tolerance: samplingInterval * 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.sampleOnce() }
            }
        diskCapacityTimer = Timer.publish(every: diskCapacityRefreshInterval, tolerance: diskCapacityRefreshInterval * 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.refresh() }
            }
    }

    public func stop() {
        timer?.cancel()
        timer = nil
        diskCapacityTimer?.cancel()
        diskCapacityTimer = nil
        postCleanupDiskRefreshTask?.cancel()
        postCleanupDiskRefreshTask = nil
        isSampling = false
    }

    /// Releases only reclaimable cache pages owned by Zisla without affecting other apps or system memory.
    @discardableResult
    public func releaseAppMemoryCaches() -> UInt64 {
        URLCache.shared.removeAllCachedResponses()
        return UInt64(malloc_zone_pressure_relief(malloc_default_zone(), 0))
    }

    /// Creates short-lived memory pressure to make the kernel reclaim system inactive and compressed pages.
    /// Like State and similar tools, it allocates and touches large memory blocks, then releases them and returns
    /// the resulting increase in available memory.
    @discardableResult
    public func releaseSystemMemoryPressure() async -> UInt64 {
        URLCache.shared.removeAllCachedResponses()
        _ = malloc_zone_pressure_relief(malloc_default_zone(), 0)
        await sampleOnce()
        let beforeFree = snapshot?.memory.freeBytes ?? 0

        await Task.detached(priority: .userInitiated) {
            var pageSize: vm_size_t = 0
            guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS, pageSize > 0 else { return }
            let pageBytes = Int(pageSize)
            let chunkBytes = 128 * 1024 * 1024
            let chunkPages = chunkBytes / pageBytes
            for _ in 0..<8 {
                var address: mach_vm_address_t = 0
                let kr = mach_vm_allocate(
                    mach_task_self_,
                    &address,
                    mach_vm_size_t(chunkBytes),
                    VM_FLAGS_ANYWHERE
                )
                guard kr == KERN_SUCCESS else { break }
                // Touch each page to commit physical memory and trigger reclamation of inactive pages.
                if let ptr = UnsafeMutableRawPointer(bitPattern: UInt(address)) {
                    for page in 0..<chunkPages {
                        ptr.advanced(by: page * pageBytes)
                            .storeBytes(of: UInt8(0), as: UInt8.self)
                    }
                }
                mach_vm_deallocate(mach_task_self_, address, mach_vm_size_t(chunkBytes))
            }
        }.value

        await sampleOnce()
        let afterFree = snapshot?.memory.freeBytes ?? 0
        return afterFree > beforeFree ? afterFree - beforeFree : 0
    }

    /// Manual refreshes always query again so background polling throttling cannot ignore user actions.
    public func refreshPublicIPAddress() async {
        await refreshPublicIPAddress(force: true)
    }

    private func refreshPublicIPAddressIfNeeded() async {
        await refreshPublicIPAddress(force: false)
    }

    private func refreshPublicIPAddress(force: Bool) async {
        let now = dateProvider()
        guard force
            || lastPublicIPRefresh == nil
            || now.timeIntervalSince(lastPublicIPRefresh!) >= Self.publicIPRefreshInterval
        else { return }

        lastPublicIPRefresh = now
        isRefreshingPublicIPAddress = true
        defer { isRefreshingPublicIPAddress = false }

        guard let address = await publicIPProvider.publicIPAddress() else { return }
        publicIPAddress = address
        networkIdentity.publicIPAddress = address
        if var current = snapshot {
            current.networkIdentity = networkIdentity
            snapshot = current
        }
    }

    /// Performs one sample; overlapping requests share it so late stale results cannot overwrite newer data.
    @discardableResult
    public func sampleOnce() async -> SystemMetricsSnapshot {
        if isSampleInProgress {
            return await withCheckedContinuation { continuation in
                sampleWaiters.append(continuation)
            }
        }

        isSampleInProgress = true
        let snapshot = await performSampleOnce()
        isSampleInProgress = false
        let waiters = sampleWaiters
        sampleWaiters.removeAll()
        for waiter in waiters {
            waiter.resume(returning: snapshot)
        }
        return snapshot
    }

    /// Resamples after an in-progress sample finishes for operations, such as cleanup, that change disk state.
    @discardableResult
    public func refresh() async -> SystemMetricsSnapshot {
        needsDiskCapacityRefresh = true
        if isSampleInProgress {
            _ = await sampleOnce()
        }
        return await sampleOnce()
    }

    static func shouldRefreshSlowMetrics(
        lastSampledAt: Date?,
        now: Date,
        interval: TimeInterval
    ) -> Bool {
        guard let lastSampledAt else { return true }
        return now.timeIntervalSince(lastSampledAt) >= interval
    }

    /// CPU and network calculations run on a cooperative worker thread to avoid blocking the main thread.
    private func performSampleOnce() async -> SystemMetricsSnapshot {
        let now = dateProvider()
        let fm = fileManager
        let volume = volumeURL
        let prevCPU = previousCPU
        let prevNet = previousNetwork
        let prevDisk = previousDisk
        let readHardwareInfo = hardwareInfoProvider
        let currentHardware = hardware
        let shouldSampleDiskCapacity = needsDiskCapacityRefresh
            || lastDiskCapacitySample == nil
            || now.timeIntervalSince(lastDiskCapacitySample!) >= diskCapacityRefreshInterval
        needsDiskCapacityRefresh = false

        let shouldSampleSlowMetrics = Self.shouldRefreshSlowMetrics(
            lastSampledAt: lastSlowMetricsSample,
            now: now,
            interval: Self.slowMetricsRefreshInterval
        )

        let payload = await Task.detached(priority: .utility) { () -> (
            cpuLoad: host_cpu_load_info?,
            cpu: CPUMetrics,
            memory: MemoryMetrics?,
            disk: DiskMetrics?,
            diskCounters: (UInt64, UInt64)?,
            netCounters: (UInt64, UInt64),
            network: NetworkMetrics,
            privateIP: String?,
            gpu: GPUMetrics?,
            sensors: AppleSMCSensorSample?
        ) in
            let load = SystemSampler.sampleCPULoad()
            let cpu: CPUMetrics
            if let load, let prev = prevCPU {
                cpu = SystemMonitorMath.cpuMetrics(previous: prev, current: load)
            } else {
                cpu = .zero
            }
            let memory = SystemSampler.sampleMemory()
            let disk = shouldSampleDiskCapacity
                ? SystemSampler.sampleDisk(fileManager: fm, volumeURL: volume)
                : nil
            let diskCounters = shouldSampleSlowMetrics ? SystemSampler.sampleDiskCounters() : nil
            let counters = SystemSampler.sampleNetworkCounters()
            let privateIP = SystemSampler.samplePrivateIPv4Address()
            let gpu = shouldSampleSlowMetrics ? SystemSampler.sampleGPU() : nil
            let sensors = shouldSampleSlowMetrics ? AppleSMCSensorReader.sample(chipName: currentHardware.cpuName) : nil
            let network: NetworkMetrics
            if let prev = prevNet {
                let elapsed = now.timeIntervalSince(prev.at)
                let rates = SystemMonitorMath.networkRates(
                    previousReceived: prev.received,
                    previousSent: prev.sent,
                    currentReceived: counters.0,
                    currentSent: counters.1,
                    elapsedSeconds: elapsed
                )
                network = NetworkMetrics(
                    bytesReceived: counters.0,
                    bytesSent: counters.1,
                    receiveBytesPerSecond: rates.receive,
                    sendBytesPerSecond: rates.send
                )
            } else {
                network = NetworkMetrics(
                    bytesReceived: counters.0,
                    bytesSent: counters.1,
                    receiveBytesPerSecond: 0,
                    sendBytesPerSecond: 0
                )
            }
            return (load, cpu, memory, disk, diskCounters, counters, network, privateIP, gpu, sensors)
        }.value

        if let load = payload.cpuLoad {
            previousCPU = load
        }
        previousNetwork = (payload.netCounters.0, payload.netCounters.1, now)
        if let counters = payload.diskCounters {
            previousDisk = (counters.0, counters.1, now)
        }
        networkIdentity.privateIPv4Address = payload.privateIP
        if shouldSampleDiskCapacity {
            lastDiskCapacitySample = now
        }
        if shouldSampleSlowMetrics {
            lastSlowMetricsSample = now
            if let gpu = payload.gpu {
                cachedGPUMetrics = gpu
            }
            if let sensors = payload.sensors {
                cachedSensorSample = sensors
            }
        }
        if !didLoadHardware {
            didLoadHardware = true
            hardware = await Task.detached(priority: .utility) {
                readHardwareInfo()
            }.value
        }

        let memory = payload.memory ?? MemoryMetrics(
            totalBytes: 0,
            usedBytes: 0,
            freeBytes: 0,
            activeBytes: 0,
            inactiveBytes: 0,
            wiredBytes: 0,
            compressedBytes: 0,
            pressureRatio: 0
        )
        var disk = payload.disk ?? snapshot?.disk ?? DiskMetrics(
            totalBytes: 0,
            freeBytes: 0,
            usedBytes: 0,
            volumeURL: volumeURL
        )
        if let previous = prevDisk, let counters = payload.diskCounters {
            let rates = SystemMonitorMath.diskRates(
                previousRead: previous.read,
                previousWrite: previous.write,
                currentRead: counters.0,
                currentWrite: counters.1,
                elapsedSeconds: now.timeIntervalSince(previous.at)
            )
            disk.readBytesPerSecond = rates.read
            disk.writeBytesPerSecond = rates.write
        }

        let sensors = payload.sensors ?? cachedSensorSample ?? AppleSMCSensorSample(
            cpuTemperature: .unavailableByPublicAPI,
            gpuTemperature: .unavailableByPublicAPI,
            fan: .unavailable(reason: "AppleSMC 只读传感器不可用")
        )
        var cpu = payload.cpu
        cpu.temperature = sensors.cpuTemperature

        let gpu = payload.gpu ?? cachedGPUMetrics ?? .unavailable(reason: "当前 GPU 未提供可读取的性能统计")
        var finalGPU = gpu
        if case .available(var metrics) = finalGPU {
            metrics.temperature = sensors.gpuTemperature
            finalGPU = .available(metrics)
        }

        let snap = SystemMetricsSnapshot(
            sampledAt: now,
            hardware: hardware,
            cpu: cpu,
            memory: memory,
            disk: disk,
            network: payload.network,
            networkIdentity: networkIdentity,
            gpu: finalGPU,
            fan: sensors.fan
        )
        snapshot = snap
        history.append(cpu: cpu, gpu: gpu, network: payload.network)
        Task { [weak self] in
            await self?.refreshPublicIPAddressIfNeeded()
        }
        return snap
    }

    public func scanCleanupCandidates(
        kinds: Set<DiskCleanupKind> = Set(DiskCleanupKind.allCases),
        options: DiskCleanupScanOptions = .default
    ) async -> [DiskCleanupCandidate] {
        let fm = fileManager
        return await Task.detached(priority: .utility) {
            SystemDiskCleanup.scanCandidates(fileManager: fm, kinds: kinds, options: options)
        }.value
    }

    public func scanCleanupCandidatesWithProgress(
        kinds: Set<DiskCleanupKind> = Set(DiskCleanupKind.allCases),
        options: DiskCleanupScanOptions = .default,
        onProgress: @escaping @Sendable ([DiskCleanupCandidate]) -> Void
    ) async -> [DiskCleanupCandidate] {
        let fm = fileManager
        return await Task.detached(priority: .utility) {
            SystemDiskCleanup.scanCandidatesWithProgress(
                fileManager: fm,
                kinds: kinds,
                options: options,
                onProgress: onProgress
            )
        }.value
    }

    public func trashSelected(_ urls: [URL]) async -> DiskCleanupResult {
        let fm = fileManager
        let result = await Task.detached(priority: .utility) {
            SystemDiskCleanup.trashSelected(urls: urls, fileManager: fm)
        }.value
        await refresh()
        if result.successCount > 0 {
            schedulePostCleanupDiskRefresh()
        }
        return result
    }

    public func trashSelected(_ candidates: [DiskCleanupCandidate]) async -> DiskCleanupResult {
        let fm = fileManager
        let result = await Task.detached(priority: .utility) {
            SystemDiskCleanup.trashSelected(candidates: candidates, fileManager: fm)
        }.value
        await refresh()
        if result.successCount > 0 {
            schedulePostCleanupDiskRefresh()
        }
        return result
    }

    private func schedulePostCleanupDiskRefresh() {
        postCleanupDiskRefreshTask?.cancel()
        postCleanupDiskRefreshTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: postCleanupDiskRefreshDelay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            _ = await refresh()
        }
    }
}
