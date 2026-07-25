import Combine
import CryptoKit
import Darwin
import Foundation
import IOKit
import SystemConfiguration

// MARK: - Snapshots

public struct CPUMetrics: Equatable, Sendable {
    /// 0...1 的整体占用（user + system）/ total
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

/// 温度仅在系统提供明确、可验证的传感器读数时展示；不将热状态映射成摄氏温度。
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
    /// 自启动以来累计字节
    public var bytesReceived: UInt64
    public var bytesSent: UInt64
    /// 相对上一采样的速率（B/s）；首次采样为 0
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

/// 硬件名称只在启动时读取一次，避免把固定信息放进每秒采样路径。
public struct SystemHardwareInfo: Equatable, Sendable {
    public var cpuName: String?
    public var gpuName: String?
    public var gpuCoreCount: Int?
    /// CPU 总物理核数（来自 system_profiler JSON；不可得时为 nil）
    public var cpuCoreCount: Int?
    /// Apple Silicon 性能核（hw.perflevel0.physicalcpu）；不可得时为 nil
    public var cpuPerformanceCoreCount: Int?
    /// Apple Silicon 能效核（hw.perflevel1.physicalcpu）；不可得时为 nil
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

/// GPU 历史读数。`IORegistry` 键没有公开稳定契约，调用方必须标注为实验性。
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

/// GPU 无稳定公开 API 时显式不可用，禁止伪造数值。
public enum GPUMetrics: Equatable, Sendable {
    case unavailable(reason: String)
    case available(GPUUsageMetrics)
}

/// 风扇无稳定公开 API 时显式不可用，禁止伪造数值。
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
    public var byteSize: UInt64
    public var displayName: String
    public var detail: String?

    public init(url: URL, kind: DiskCleanupKind, byteSize: UInt64, displayName: String, detail: String? = nil) {
        self.url = url
        self.kind = kind
        self.byteSize = byteSize
        self.displayName = displayName
        self.detail = detail
    }
}

public enum DiskCleanupKind: String, Equatable, Sendable, CaseIterable {
    case cache
    case log
    case trash
    case developerArtifacts
    case temporaryFiles
    /// 包管理器与语言工具链的可重建缓存（非用户项目目录）。
    case packageManagerCache
    case crashReport
    case diskImage
    case largeFile
    case duplicateFile

    /// 同一路径出现在多类扫描时，数值更大者优先保留（更细分类）。
    public var classificationPriority: Int {
        switch self {
        case .crashReport: 90
        case .temporaryFiles: 85
        case .packageManagerCache: 80
        case .developerArtifacts: 70
        case .diskImage: 60
        case .duplicateFile: 50
        case .largeFile: 40
        case .cache: 30
        case .log: 20
        case .trash: 10
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

    public var errorDescription: String? {
        switch self {
        case .pathOutsideAllowedRoots: "目标不在允许清理的用户目录内"
        case .notAFileURL: "仅支持本地文件路径"
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
    /// 返回卷的总容量与可用空间（含可清除空间，匹配 macOS 系统设置）。
    /// 默认实现使用 URLResourceValues；测试 mock 可返回 nil 以回退到 attributesOfFileSystem。
    func volumeCapacity(for url: URL) -> (total: UInt64, available: UInt64)?
}

public extension SystemMonitorFileManaging {
    /// 使用 `volumeAvailableCapacityForImportantUsageKey` 获取可用空间，
    /// 该值包含 APFS 可清除空间（本地快照、缓存等），与 macOS 系统设置一致。
    func volumeCapacity(for url: URL) -> (total: UInt64, available: UInt64)? {
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
        ]
        guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
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
}

// MARK: - Pure helpers (testable without live host)

public enum SystemMonitorMath {
    /// 由两次 host_cpu_load_info 差分计算占用。
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
    /// 判断 `url` 是否位于任一允许根目录内（标准化后前缀匹配）。
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

        // used ≈ active + wired + compressed（与 Activity Monitor 思路接近，非私有 API）
        let used = active + wired + compressed
        // 可用 = 空闲 + 非活跃（可回收）+ 投机，与多数第三方监控口径一致（= total - used）
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

        // 优先用 URLResourceValues（含 APFS 可清除空间，匹配 macOS 系统设置的「可用」）
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

        // 回退到 statfs（attributesOfFileSystem），不含可清除空间
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

    /// 读取内置 NVMe/SSD 温度；无法验证读数时返回不可用。
    static func sampleDiskTemperature() -> TemperatureMetric {
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

    /// 读取 IORegistry 的累计磁盘 I/O 计数；无法验证读数时返回 nil。
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
            // 跳过 loopback
            if name.hasPrefix("lo") {
                cursor = current.pointee.ifa_next
                continue
            }
            if current.pointee.ifa_addr?.pointee.sa_family == UInt8(AF_LINK) {
                current.pointee.ifa_data.withMemoryRebound(to: if_data.self, capacity: 1) { data in
                    // ifa_data 对 AF_LINK 指向 if_data
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

/// State 在 Apple Silicon 上使用的 AppleSMC 只读请求布局；不包含任何写入或调速命令。
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

    /// Apple Silicon 各代 CPU/GPU 温度 SMC 键。
    /// 来源：exelban/stats + MacThrottle 实测（https://stanislas.blog/2025/12/macos-thermal-throttling-app/）。
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
                // 能效核 + 性能核
                ["Tp09", "Tp0T", "Tp01", "Tp05", "Tp0D", "Tp0H", "Tp0L", "Tp0P", "Tp0X", "Tp0b"]
            case .m2:
                // 能效核 + 性能核
                ["Tp1h", "Tp1t", "Tp1p", "Tp1l",
                 "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0X", "Tp0b", "Tp0f", "Tp0j"]
            case .m3:
                // Te (能效) + Tf (性能)
                ["Te05", "Te0L", "Te0P", "Te0S",
                 "Tf04", "Tf09", "Tf0A", "Tf0B", "Tf0D", "Tf0E",
                 "Tf44", "Tf49", "Tf4A", "Tf4B", "Tf4D", "Tf4E"]
            case .m4:
                // Te (能效) + Tp (性能)
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
                // M5 GPU 键尚无公开验证数据，暂用 M4 键作为候选占位
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
                  (100...20_000).contains(rpm)
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
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["-json", "SPHardwareDataType", "SPDisplaysDataType"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return .unavailable }
            return parse(output.fileHandleForReading.readDataToEndOfFile(), sysctlInt: sysctlInt)
        } catch {
            return .unavailable
        }
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

    /// system_profiler 常见为 `"proc 15:5:10:0"`（总核:性能:能效:...）；缺字段时不猜测。
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

/// 通过 sysctl 读取 Apple Silicon 性能/能效物理核；键不存在时保持 nil。
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

        // 用户专属临时目录（/private/var/folders/...）
        let temporaryDirectory = fileManager.temporaryDirectoryForCurrentUser().standardizedFileURL
        if isCurrentUserTemporaryDirectory(temporaryDirectory) {
            append(.temporaryFiles, temporaryDirectory)
        }
        // /tmp 是 /private/tmp 的符号链接（macOS 已知别名）；两者均加入，去重后以 /tmp 扫描。
        append(.temporaryFiles, URL(fileURLWithPath: "/tmp", isDirectory: true))
        append(.temporaryFiles, URL(fileURLWithPath: "/private/tmp", isDirectory: true))

        // Xcode / 模拟器：可安全重建的构建与设备支持缓存
        let developerPaths = [
            "Library/Developer/Xcode/DerivedData",
            "Library/Developer/Xcode/iOS DeviceSupport",
            "Library/Developer/Xcode/watchOS DeviceSupport",
            "Library/Developer/CoreSimulator/Caches",
            "Library/Developer/CoreSimulator/Devices",
            ".cache",
        ]
        for path in developerPaths {
            append(.developerArtifacts, home.appendingPathComponent(path, isDirectory: true))
        }

        // 包管理器 / 语言工具链缓存（仅缓存与可重建存储，不含用户工程）
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

        // 用户缓存：应用生成的缓存目录，可安全重建
        append(.cache, home.appendingPathComponent("Library/Caches", isDirectory: true))

        // 用户日志：应用运行日志，清理不影响功能
        append(.log, home.appendingPathComponent("Library/Logs", isDirectory: true))

        // 崩溃报告：崩溃与诊断报告，清理不影响功能
        append(.crashReport, home.appendingPathComponent("Library/Logs/DiagnosticReports", isDirectory: true))

        // 废纸篓：已删除但未清空的文件
        if let trashURL = fileManager.urls(for: .trashDirectory, in: .userDomainMask).first {
            append(.trash, trashURL)
        }

        // 用户文件目录：用于磁盘镜像、大文件和重复文件扫描（不将目录本身当清理候选项）
        for searchPath in [FileManager.SearchPathDirectory.downloadsDirectory, .desktopDirectory, .documentDirectory] {
            if let url = fileManager.urls(for: searchPath, in: .userDomainMask).first {
                append(.diskImage, url)
            }
        }

        // 同一路径只保留更细的分类根；/tmp 与 /private/tmp 是 macOS 已知别名，统一规范为 /tmp。
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

    public static func allocatedByteSize(of url: URL, fileManager: SystemMonitorFileManaging) -> UInt64 {
        guard fileManager.fileExists(atPath: url.path) else { return 0 }
        // 用资源值优先
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
            // 粗判目录：若 contents 可枚举则递归
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
            return 0
        }
        var total: UInt64 = 0
        for case let fileURL as URL in enumerator {
            if let values = try? fileURL.resourceValues(forKeys: [
                .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey,
            ]) {
                if values.isRegularFile == true {
                    if let s = values.totalFileAllocatedSize {
                        total += UInt64(s)
                    } else if let s = values.fileAllocatedSize {
                        total += UInt64(s)
                    }
                }
            } else if let attrs = try? fileManager.attributesOfItem(atPath: fileURL.path),
                      let size = attrs[.size] as? NSNumber {
                total += size.uint64Value
            }
        }
        return total
    }

    /// 扫描各类可清理候选项；同路径去重后按体积降序返回。
    public static func scanCandidates(
        fileManager: SystemMonitorFileManaging,
        kinds: Set<DiskCleanupKind> = Set(DiskCleanupKind.allCases),
        maxDepthChildrenOnly: Bool = true
    ) -> [DiskCleanupCandidate] {
        var result: [DiskCleanupCandidate] = []

        // 目录型扫描：列出已知根目录的直接子项
        let directoryKinds: Set<DiskCleanupKind> = [
            .cache, .log, .trash, .developerArtifacts, .temporaryFiles, .packageManagerCache, .crashReport,
        ]
        let activeDirKinds = kinds.intersection(directoryKinds)
        if !activeDirKinds.isEmpty {
            result.append(contentsOf: scanDirectoryChildren(fileManager: fileManager, kinds: activeDirKinds))
        }

        // 磁盘镜像：Downloads 下的 .dmg/.iso/.pkg/.ipsw
        if kinds.contains(.diskImage) {
            result.append(contentsOf: scanDiskImages(fileManager: fileManager))
        }

        // 大文件/旧文件：Downloads/Desktop/Documents 下 >100MB 且 90 天未修改
        if kinds.contains(.largeFile) {
            result.append(contentsOf: scanLargeOldFiles(fileManager: fileManager))
        }

        // 重复文件：Downloads/Desktop/Documents 下内容相同的文件
        if kinds.contains(.duplicateFile) {
            result.append(contentsOf: scanDuplicateFiles(fileManager: fileManager))
        }

        return deduplicateCandidates(result).sorted { $0.byteSize > $1.byteSize }
    }

    /// 同一路径只保留分类更细的一条候选项。
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

    /// 目录型扫描：列出已知根目录的直接子项（安全候选项）。
    private static func scanDirectoryChildren(
        fileManager: SystemMonitorFileManaging,
        kinds: Set<DiskCleanupKind>
    ) -> [DiskCleanupCandidate] {
        let allRoots = allowedScanRoots(fileManager: fileManager)
        let roots = allRoots.filter { kinds.contains($0.kind) }
        let allowed = SystemMonitorPathSafety.defaultAllowedRoots(fileManager: fileManager)
        // 已是独立扫描根的路径：不作为更粗父根的直接子项列出，避免重复与体积双计
        let dedicatedRootPaths = Set(allRoots.map { $0.url.path })
        var result: [DiskCleanupCandidate] = []

        for (kind, root) in roots {
            guard fileManager.fileExists(atPath: root.path) else { continue }
            guard SystemMonitorPathSafety.isURL(root, withinAllowedRoots: allowed) else { continue }
            let children: [URL]
            do {
                children = try fileManager.contentsOfDirectory(
                    at: root,
                    includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .totalFileAllocatedSizeKey],
                    options: [.skipsHiddenFiles]
                )
            } catch {
                continue
            }
            for child in children {
                let standardized = child.standardizedFileURL
                guard SystemMonitorPathSafety.isURL(standardized, withinAllowedRoots: allowed) else { continue }
                if dedicatedRootPaths.contains(standardized.path), standardized.path != root.path {
                    continue
                }
                let temporaryDetail = temporaryCandidateDetail(for: standardized, kind: kind, fileManager: fileManager)
                if kind == .temporaryFiles, temporaryDetail == nil {
                    continue
                }
                let size = allocatedByteSize(of: standardized, fileManager: fileManager)
                result.append(
                    DiskCleanupCandidate(
                        url: standardized,
                        kind: kind,
                        byteSize: size,
                        displayName: standardized.lastPathComponent,
                        detail: temporaryDetail
                    )
                )
            }
        }
        return result
    }

    private static let temporaryFileMinAge: TimeInterval = 7 * 24 * 3600

    private static func isCurrentUserTemporaryDirectory(_ url: URL) -> Bool {
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        return path.hasPrefix("/private/var/folders/") || path.hasPrefix("/var/folders/")
    }

    private static func temporaryCandidateDetail(
        for url: URL,
        kind: DiskCleanupKind,
        fileManager: SystemMonitorFileManaging
    ) -> String? {
        guard kind == .temporaryFiles else { return nil }
        guard let modificationDate = try? fileManager.attributesOfItem(atPath: url.path)[.modificationDate] as? Date else {
            return nil
        }
        let age = Date().timeIntervalSince(modificationDate)
        guard age >= temporaryFileMinAge else { return nil }
        return "\(Int(age / 86400)) 天未修改"
    }

    private static let diskImageExtensions: Set<String> = ["dmg", "iso", "pkg", "ipsw"]

    /// 扫描 Downloads 目录下的磁盘镜像和安装包。
    private static func scanDiskImages(fileManager: SystemMonitorFileManaging) -> [DiskCleanupCandidate] {
        let allowed = SystemMonitorPathSafety.defaultAllowedRoots(fileManager: fileManager)
        guard let downloadsURL = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            return []
        }
        guard SystemMonitorPathSafety.isURL(downloadsURL, withinAllowedRoots: allowed) else { return [] }
        guard fileManager.fileExists(atPath: downloadsURL.path) else { return [] }

        let children: [URL]
        do {
            children = try fileManager.contentsOfDirectory(
                at: downloadsURL,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .totalFileAllocatedSizeKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            return []
        }

        var result: [DiskCleanupCandidate] = []
        for child in children {
            let standardized = child.standardizedFileURL
            guard SystemMonitorPathSafety.isURL(standardized, withinAllowedRoots: allowed) else { continue }
            let ext = standardized.pathExtension.lowercased()
            guard diskImageExtensions.contains(ext) else { continue }
            let size = allocatedByteSize(of: standardized, fileManager: fileManager)
            result.append(
                DiskCleanupCandidate(
                    url: standardized,
                    kind: .diskImage,
                    byteSize: size,
                    displayName: standardized.lastPathComponent
                )
            )
        }
        return result
    }

    /// 大文件阈值：100 MB
    private static let largeFileThreshold: UInt64 = 100 * 1024 * 1024
    /// 旧文件阈值：90 天
    private static let oldFileDays: TimeInterval = 90 * 24 * 3600

    /// 扫描 Downloads/Desktop/Documents 下超过 100MB 且 90 天未修改的文件。
    private static func scanLargeOldFiles(fileManager: SystemMonitorFileManaging) -> [DiskCleanupCandidate] {
        let allowed = SystemMonitorPathSafety.defaultAllowedRoots(fileManager: fileManager)
        let searchDirs = userFileDirectories(fileManager: fileManager)
        let cutoff = Date().addingTimeInterval(-oldFileDays)
        var result: [DiskCleanupCandidate] = []

        for dir in searchDirs {
            guard SystemMonitorPathSafety.isURL(dir, withinAllowedRoots: allowed) else { continue }
            let files = collectFilesRecursively(at: dir, fileManager: fileManager, maxDepth: 5, allowed: allowed)
            for fileURL in files {
                let size = allocatedByteSize(of: fileURL, fileManager: fileManager)
                guard size >= largeFileThreshold else { continue }
                guard let attrs = try? fileManager.attributesOfItem(atPath: fileURL.path),
                      let modDate = attrs[.modificationDate] as? Date else { continue }
                guard modDate < cutoff else { continue }
                let days = Int(Date().timeIntervalSince(modDate) / 86400)
                result.append(
                    DiskCleanupCandidate(
                        url: fileURL,
                        kind: .largeFile,
                        byteSize: size,
                        displayName: fileURL.lastPathComponent,
                        detail: "\(days) 天前修改"
                    )
                )
            }
        }
        return result
    }

    /// 扫描 Downloads/Desktop/Documents 下的重复文件（SHA256 内容比对）。
    private static func scanDuplicateFiles(fileManager: SystemMonitorFileManaging) -> [DiskCleanupCandidate] {
        let allowed = SystemMonitorPathSafety.defaultAllowedRoots(fileManager: fileManager)
        let searchDirs = userFileDirectories(fileManager: fileManager)
        var allFiles: [(url: URL, size: UInt64)] = []

        for dir in searchDirs {
            guard SystemMonitorPathSafety.isURL(dir, withinAllowedRoots: allowed) else { continue }
            let files = collectFilesRecursively(at: dir, fileManager: fileManager, maxDepth: 5, allowed: allowed)
            for fileURL in files {
                let size = allocatedByteSize(of: fileURL, fileManager: fileManager)
                guard size > 0 else { continue }
                allFiles.append((fileURL, size))
            }
        }

        // 按文件大小分组，仅对大小相同的文件做哈希
        var sizeGroups: [UInt64: [URL]] = [:]
        for entry in allFiles {
            sizeGroups[entry.size, default: []].append(entry.url)
        }

        var result: [DiskCleanupCandidate] = []
        for (_, urls) in sizeGroups where urls.count > 1 {
            // 计算哈希，按哈希分组
            var hashGroups: [String: [URL]] = [:]
            for url in urls {
                let hash = sha256(of: url, fileManager: fileManager)
                guard !hash.isEmpty else { continue }
                hashGroups[hash, default: []].append(url)
            }
            for (_, group) in hashGroups where group.count > 1 {
                // 保留第一个，其余标记为重复
                let original = group[0]
                for i in 1..<group.count {
                    let dup = group[i]
                    result.append(
                        DiskCleanupCandidate(
                            url: dup,
                            kind: .duplicateFile,
                            byteSize: allFiles.first(where: { $0.url == dup })?.size ?? 0,
                            displayName: dup.lastPathComponent,
                            detail: "与 \(original.lastPathComponent) 重复"
                        )
                    )
                }
            }
        }
        return result
    }

    // MARK: - File helpers

    /// 获取用户文件目录：Downloads / Desktop / Documents
    private static func userFileDirectories(fileManager: SystemMonitorFileManaging) -> [URL] {
        let dirs: [FileManager.SearchPathDirectory] = [.downloadsDirectory, .desktopDirectory, .documentDirectory]
        return dirs.compactMap { fileManager.urls(for: $0, in: .userDomainMask).first }
    }

    /// 递归收集目录下的文件（非目录），最多深入 maxDepth 层。
    private static func collectFilesRecursively(
        at url: URL,
        fileManager: SystemMonitorFileManaging,
        maxDepth: Int,
        allowed: [URL]
    ) -> [URL] {
        guard maxDepth > 0 else { return [] }
        guard SystemMonitorPathSafety.isURL(url, withinAllowedRoots: allowed) else { return [] }

        let children: [URL]
        do {
            children = try fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        } catch {
            return []
        }

        var files: [URL] = []
        for child in children {
            let standardized = child.standardizedFileURL
            guard SystemMonitorPathSafety.isURL(standardized, withinAllowedRoots: allowed) else { continue }

            if isDirectory(standardized, fileManager: fileManager) {
                files.append(contentsOf: collectFilesRecursively(at: standardized, fileManager: fileManager, maxDepth: maxDepth - 1, allowed: allowed))
            } else {
                files.append(standardized)
            }
        }
        return files
    }

    /// 判断 URL 是否为目录：优先用 resourceValues，回退到 contentsOfDirectory。
    private static func isDirectory(_ url: URL, fileManager: SystemMonitorFileManaging) -> Bool {
        if let isDir = try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory {
            return isDir
        }
        // 回退：尝试列出子项；有子项则为目录
        let children = (try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return !children.isEmpty
    }

    /// 计算文件 SHA256 哈希；读取失败返回空字符串。
    private static func sha256(of url: URL, fileManager: SystemMonitorFileManaging) -> String {
        guard let data = fileManager.contents(atPath: url.path) else { return "" }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// 将选中 URL 移入废纸篓；绝不永久删除。越界 URL 记为失败。
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
}

// MARK: - Service

/// 面向 SwiftUI 的系统采样与安全清理服务；实验读数均为只读且可显式降级。
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
    private var previousCPU: host_cpu_load_info?
    private var previousNetwork: (received: UInt64, sent: UInt64, at: Date)?
    private var previousDisk: (read: UInt64, write: UInt64, at: Date)?
    private var networkIdentity = NetworkIdentity()
    private var lastPublicIPRefresh: Date?
    private var hardware = SystemHardwareInfo.unavailable
    private var didLoadHardware = false

    public init(
        samplingInterval: TimeInterval = 2.0,
        fileManager: (any SystemMonitorFileManaging)? = nil,
        volumeURL: URL? = nil,
        dateProvider: @escaping @Sendable () -> Date = { Date() },
        publicIPProvider: (any PublicIPProviding)? = nil,
        hardwareInfoProvider: (@Sendable () -> SystemHardwareInfo)? = nil
    ) {
        let fileManager = fileManager ?? DefaultSystemMonitorFileManager()
        self.samplingInterval = max(0.2, samplingInterval)
        self.fileManager = fileManager
        self.dateProvider = dateProvider
        self.publicIPProvider = publicIPProvider ?? DefaultPublicIPProvider()
        self.hardwareInfoProvider = hardwareInfoProvider ?? { SystemHardwareInfoReader.read() }
        self.volumeURL = volumeURL
            ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser()
    }

    public func start() {
        guard timer == nil else { return }
        isSampling = true
        // 立即采一次，再按间隔
        Task { await self.sampleOnce() }
        timer = Timer.publish(every: samplingInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.sampleOnce() }
            }
    }

    public func stop() {
        timer?.cancel()
        timer = nil
        isSampling = false
    }

    /// 只释放 Zisla 进程自身可归还的缓存页，不干预其他应用或系统内存。
    @discardableResult
    public func releaseAppMemoryCaches() -> UInt64 {
        URLCache.shared.removeAllCachedResponses()
        return UInt64(malloc_zone_pressure_relief(malloc_default_zone(), 0))
    }

    /// 通过制造短期内存压力迫使内核回收系统级 inactive/compressed 页面。
    /// 机制与 State 等工具一致：分配并触摸大块内存，迫使内核释放非活跃缓存页，
    /// 随后归还这片临时内存；返回整理前后的可用内存增量。
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
                // 触摸每一页触发物理分配，制造内存压力迫使内核回收其他进程的非活跃页
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

    /// 手动刷新始终重新查询，避免用户操作被后台轮询节流忽略。
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

    /// 单次采样；CPU/网络 计算在协作线程上完成以避免长时间占用主线程。
    @discardableResult
    public func sampleOnce() async -> SystemMetricsSnapshot {
        let now = dateProvider()
        let fm = fileManager
        let volume = volumeURL
        let prevCPU = previousCPU
        let prevNet = previousNetwork
        let prevDisk = previousDisk
        let readHardwareInfo = hardwareInfoProvider
        let currentHardware = hardware

        let payload = await Task.detached(priority: .utility) { () -> (
            cpuLoad: host_cpu_load_info?,
            cpu: CPUMetrics,
            memory: MemoryMetrics?,
            disk: DiskMetrics?,
            diskCounters: (UInt64, UInt64)?,
            netCounters: (UInt64, UInt64),
            network: NetworkMetrics,
            privateIP: String?,
            gpu: GPUMetrics,
            sensors: AppleSMCSensorSample
        ) in
            let load = SystemSampler.sampleCPULoad()
            let cpu: CPUMetrics
            if let load, let prev = prevCPU {
                cpu = SystemMonitorMath.cpuMetrics(previous: prev, current: load)
            } else {
                cpu = .zero
            }
            let memory = SystemSampler.sampleMemory()
            let disk = SystemSampler.sampleDisk(fileManager: fm, volumeURL: volume)
            let diskCounters = SystemSampler.sampleDiskCounters()
            let counters = SystemSampler.sampleNetworkCounters()
            let privateIP = SystemSampler.samplePrivateIPv4Address()
            let gpu = SystemSampler.sampleGPU()
            let sensors = AppleSMCSensorReader.sample(chipName: currentHardware.cpuName)
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
        } else {
            previousDisk = nil
        }
        networkIdentity.privateIPv4Address = payload.privateIP
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
        var disk = payload.disk ?? DiskMetrics(
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
        var cpu = payload.cpu
        cpu.temperature = payload.sensors.cpuTemperature

        var gpu = payload.gpu
        if case .available(var metrics) = gpu {
            metrics.temperature = payload.sensors.gpuTemperature
            gpu = .available(metrics)
        }

        let snap = SystemMetricsSnapshot(
            sampledAt: now,
            hardware: hardware,
            cpu: cpu,
            memory: memory,
            disk: disk,
            network: payload.network,
            networkIdentity: networkIdentity,
            gpu: gpu,
            fan: payload.sensors.fan
        )
        snapshot = snap
        history.append(cpu: cpu, gpu: payload.gpu, network: payload.network)
        Task { [weak self] in
            await self?.refreshPublicIPAddressIfNeeded()
        }
        return snap
    }

    public func scanCleanupCandidates(
        kinds: Set<DiskCleanupKind> = Set(DiskCleanupKind.allCases)
    ) async -> [DiskCleanupCandidate] {
        let fm = fileManager
        return await Task.detached(priority: .utility) {
            SystemDiskCleanup.scanCandidates(fileManager: fm, kinds: kinds)
        }.value
    }

    public func trashSelected(_ urls: [URL]) async -> DiskCleanupResult {
        let fm = fileManager
        return await Task.detached(priority: .utility) {
            SystemDiskCleanup.trashSelected(urls: urls, fileManager: fm)
        }.value
    }
}
