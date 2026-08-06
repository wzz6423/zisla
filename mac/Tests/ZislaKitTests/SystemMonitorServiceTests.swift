import Darwin
import Foundation
import Testing

@testable import ZislaKit

// MARK: - Mock FileManager

/// Fake FileManager for dependency injection; never touches the real filesystem.
final class MockFileManager: SystemMonitorFileManaging, @unchecked Sendable {
    var existingPaths: Set<String> = []
    var directoryContents: [String: [URL]] = [:]
    var fileSystemAttributes: [String: [FileAttributeKey: Any]] = [:]
    var fileAttributes: [String: [FileAttributeKey: Any]] = [:]
    var volumeCapacities: [String: (total: UInt64, available: UInt64)] = [:]
    var trashResults: [URL: Result<URL, Error>] = [:]
    var homeDirectory: URL = URL(fileURLWithPath: "/Users/test")
    var temporaryDirectory: URL = URL(fileURLWithPath: "/private/var/folders/test/T")
    var searchPathResults: [FileManager.SearchPathDirectory: [URL]] = [:]
    var fileContentsData: [String: Data] = [:]

    func fileExists(atPath path: String) -> Bool {
        existingPaths.contains(path)
    }

    func urls(for directory: FileManager.SearchPathDirectory, in domainMask: FileManager.SearchPathDomainMask) -> [URL] {
        searchPathResults[directory] ?? []
    }

    func homeDirectoryForCurrentUser() -> URL {
        homeDirectory
    }

    func temporaryDirectoryForCurrentUser() -> URL {
        temporaryDirectory
    }

    func contentsOfDirectory(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]?,
        options: FileManager.DirectoryEnumerationOptions
    ) throws -> [URL] {
        directoryContents[url.path] ?? []
    }

    func attributesOfFileSystem(forPath path: String) throws -> [FileAttributeKey: Any] {
        guard let attrs = fileSystemAttributes[path] else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError, userInfo: nil)
        }
        return attrs
    }

    func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any] {
        guard let attrs = fileAttributes[path] else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError, userInfo: nil)
        }
        return attrs
    }
    func enumerator(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]?,
        options: FileManager.DirectoryEnumerationOptions
    ) -> FileManager.DirectoryEnumerator? {
        nil
    }

    func trashItem(at url: URL) throws -> URL {
        if let result = trashResults[url] {
            return try result.get()
        }
        throw NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError, userInfo: nil)
    }

    func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws {
        existingPaths.insert(url.path)
    }

    func removeItem(at url: URL) throws {
        existingPaths.remove(url.path)
    }

    func createFile(atPath path: String, contents data: Data?) -> Bool {
        existingPaths.insert(path)
        return true
    }

    func contents(atPath path: String) -> Data? {
        fileContentsData[path]
    }

    func volumeCapacity(for url: URL) -> (total: UInt64, available: UInt64)? {
        volumeCapacities[url.path]
    }
}

private struct FoundationVolumeCapacityFileManager: SystemMonitorFileManaging, @unchecked Sendable {
    private let fileManager = FileManager.default

    func fileExists(atPath path: String) -> Bool {
        fileManager.fileExists(atPath: path)
    }

    func urls(for directory: FileManager.SearchPathDirectory, in domainMask: FileManager.SearchPathDomainMask) -> [URL] {
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
        try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: options)
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
        fileManager.enumerator(at: url, includingPropertiesForKeys: keys, options: options)
    }

    func trashItem(at url: URL) throws -> URL {
        var result: NSURL?
        try fileManager.trashItem(at: url, resultingItemURL: &result)
        return (result as URL?) ?? url
    }

    func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: withIntermediateDirectories, attributes: nil)
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

private struct StubPublicIPProvider: PublicIPProviding {
    let address: String?

    func publicIPAddress() async -> String? { address }
}

/// Countable public-IP stub that returns addresses in order; tests drive it serially on MainActor, so no lock is needed.
private final class CountingPublicIPProvider: PublicIPProviding, @unchecked Sendable {
    private var addresses: [String?]
    private(set) var callCount = 0

    init(addresses: [String?]) {
        self.addresses = addresses
    }

    func publicIPAddress() async -> String? {
        callCount += 1
        if addresses.isEmpty {
            return nil
        }
        if addresses.count == 1 {
            return addresses[0]
        }
        return addresses.removeFirst()
    }
}

/// Controllable clock for tests; `dateProvider` is a `@Sendable` closure, and this class is only read/written on the serial test path.
private final class ControllableDateProvider: @unchecked Sendable {
    private var current: Date

    init(_ date: Date) {
        current = date
    }

    func now() -> Date { current }

    func advance(by seconds: TimeInterval) {
        current = current.addingTimeInterval(seconds)
    }
}

// MARK: - Tests
//
// Merged into a single suite so `swift test --filter SystemMonitorServiceTests`
// covers math, path safety, cleanup, and service integration cases.

@MainActor
struct SystemMonitorServiceTests {
    // MARK: SystemMonitorMath

    @Test
    func cpuMetricsComputesUsageFromTickDelta() {
        let prev = host_cpu_load_info(cpu_ticks: (100, 50, 800, 50))
        let curr = host_cpu_load_info(cpu_ticks: (150, 70, 850, 60))
        // Δ: user=50, system=20, idle=50, nice=10 → total=130
        let metrics = SystemMonitorMath.cpuMetrics(previous: prev, current: curr)

        #expect(metrics.usage > 0.61 && metrics.usage < 0.62)
        #expect(metrics.userFraction > 0.38 && metrics.userFraction < 0.39)
        #expect(metrics.systemFraction > 0.15 && metrics.systemFraction < 0.16)
        #expect(metrics.idleFraction > 0.38 && metrics.idleFraction < 0.39)
        #expect(metrics.niceFraction > 0.07 && metrics.niceFraction < 0.08)
    }

    @Test
    func cpuMetricsReturnsZeroWhenNoTickDelta() {
        let load = host_cpu_load_info(cpu_ticks: (100, 50, 800, 50))
        #expect(SystemMonitorMath.cpuMetrics(previous: load, current: load) == .zero)
    }

    @Test
    func networkRatesComputeBytesPerSecond() {
        let (rx, tx) = SystemMonitorMath.networkRates(
            previousReceived: 1000, previousSent: 500,
            currentReceived: 3000, currentSent: 1500,
            elapsedSeconds: 2.0
        )
        #expect(rx == 1000.0)
        #expect(tx == 500.0)
    }

    @Test
    func networkRatesHandleCounterRollover() {
        // On counter rollover, treat the current value as the delta
        let (rx, tx) = SystemMonitorMath.networkRates(
            previousReceived: 1000, previousSent: 500,
            currentReceived: 100, currentSent: 50,
            elapsedSeconds: 1.0
        )
        #expect(rx == 100.0)
        #expect(tx == 50.0)
    }

    @Test
    func networkRatesReturnZeroForZeroElapsed() {
        let (rx, tx) = SystemMonitorMath.networkRates(
            previousReceived: 1000, previousSent: 500,
            currentReceived: 3000, currentSent: 1500,
            elapsedSeconds: 0
        )
        #expect(rx == 0)
        #expect(tx == 0)
    }

    @Test
    func diskRatesUseCumulativeCounterDelta() {
        let (read, write) = SystemMonitorMath.diskRates(
            previousRead: 1_000,
            previousWrite: 500,
            currentRead: 7_000,
            currentWrite: 2_500,
            elapsedSeconds: 2
        )

        #expect(read == 3_000)
        #expect(write == 1_000)
    }

    @Test
    func memoryPressureRatioClampsBetweenZeroAndOne() {
        #expect(SystemMonitorMath.memoryPressureRatio(usedBytes: 0, totalBytes: 100) == 0)
        #expect(SystemMonitorMath.memoryPressureRatio(usedBytes: 50, totalBytes: 100) == 0.5)
        #expect(SystemMonitorMath.memoryPressureRatio(usedBytes: 100, totalBytes: 100) == 1.0)
        #expect(SystemMonitorMath.memoryPressureRatio(usedBytes: 150, totalBytes: 100) == 1.0)
        #expect(SystemMonitorMath.memoryPressureRatio(usedBytes: 50, totalBytes: 0) == 0)
    }

    @Test
    func appleSMCFloatReaderUsesLittleEndianFloatPayload() {
        let rpm = AppleSMCSensorReader.float32(from: [0x00, 0x60, 0x62, 0x45])
        let temperature = AppleSMCSensorReader.float32(from: [0x00, 0xF0, 0x87, 0x42])

        #expect(rpm == 3622)
        #expect(temperature == 67.96875)
    }

    @Test
    func appleSMCTemperatureAverageRejectsInvalidSensors() {
        let average = AppleSMCSensorReader.averageCelsius([68, 66, 0, 125])

        #expect(average == 67)
        #expect(AppleSMCSensorReader.averageCelsius([0, 125]) == nil)
    }

    @Test
    func appleSMCFanRPMAllowsStoppedFanAndRejectsInvalidValues() {
        #expect(AppleSMCSensorReader.isValidFanRPM(0))
        #expect(AppleSMCSensorReader.isValidFanRPM(20_000))
        #expect(!AppleSMCSensorReader.isValidFanRPM(-0.1))
        #expect(!AppleSMCSensorReader.isValidFanRPM(20_000.1))
        #expect(!AppleSMCSensorReader.isValidFanRPM(.nan))
    }

    @Test
    func metricHistoryKeepsBoundedLayeredSamples() {
        var history = SystemMetricHistory()
        let first = CPUMetrics(usage: 1.2, userFraction: 0.4, systemFraction: 0.3, idleFraction: 0.3, niceFraction: 0)
        let second = CPUMetrics(usage: 0.4, userFraction: 0.2, systemFraction: 0.2, idleFraction: 0.6, niceFraction: 0)
        let third = CPUMetrics(usage: 0.6, userFraction: 0.4, systemFraction: 0.2, idleFraction: 0.4, niceFraction: 0)
        let network = NetworkMetrics.zero

        history.append(
            cpu: first,
            gpu: .available(GPUUsageMetrics(usage: -0.5, rendererUsage: 0.2, tilerUsage: 0.1)),
            network: network,
            limit: 2
        )
        history.append(cpu: second, gpu: .unavailable(reason: "无读数"), network: network, limit: 2)
        history.append(
            cpu: third,
            gpu: .available(GPUUsageMetrics(usage: 0.8, rendererUsage: 0.7, tilerUsage: 0.4)),
            network: network,
            limit: 2
        )

        #expect(history.cpuUsage == [0.4, 0.6])
        #expect(history.gpuUsage == [0, 0.8])
        #expect(history.cpuUser == [0.2, 0.4])
        #expect(history.cpuSystem == [0.2, 0.2])
        #expect(history.cpuIdle == [0.6, 0.4])
        #expect(history.gpuRenderer == [0.2, 0.7])
        #expect(history.gpuTiler == [0.1, 0.4])
    }

    @Test
    func metricHistoryBoundsPercentagesAndPreservesNetworkRatesUnderNoisyInput() {
        var history = SystemMetricHistory()
        let cpu = CPUMetrics(
            usage: .nan,
            userFraction: -0.2,
            systemFraction: 1.3,
            idleFraction: 2,
            niceFraction: 0.8
        )
        let gpu = GPUMetrics.available(
            GPUUsageMetrics(usage: -0.4, rendererUsage: 1.6, tilerUsage: -0.3)
        )
        let network = NetworkMetrics(
            bytesReceived: 10,
            bytesSent: 20,
            receiveBytesPerSecond: -50,
            sendBytesPerSecond: 4_000
        )

        for _ in 0..<3 {
            history.append(cpu: cpu, gpu: gpu, network: network, limit: 0)
        }

        #expect(history.cpuUsage == [0])
        #expect(abs((history.cpuUser.first ?? -.infinity) - 0.6) < 0.000_001)
        #expect(history.cpuSystem == [1])
        #expect(history.cpuIdle == [1])
        #expect(history.gpuUsage == [0])
        #expect(history.gpuRenderer == [1])
        #expect(history.gpuTiler == [0])
        #expect(history.networkDownload == [0])
        #expect(history.networkUpload == [4_000])
    }

    @Test
    func hardwareInfoParsesSystemProfilerJSON() throws {
        let data = try #require(
            """
            {"SPHardwareDataType":[{"chip_type":"Apple M5 Pro","number_processors":"proc 15:5:10:0"}],"SPDisplaysDataType":[{"sppci_device_type":"spdisplays_gpu","sppci_model":"Apple M5 Pro","sppci_cores":"16"}]}
            """.data(using: .utf8)
        )

        let info = SystemHardwareInfoReader.parse(data) { _ in nil }

        #expect(info.cpuName == "Apple M5 Pro")
        #expect(info.gpuName == "Apple M5 Pro")
        #expect(info.gpuCoreCount == 16)
        #expect(info.cpuCoreCount == 15)
        #expect(info.cpuPerformanceCoreCount == nil)
        #expect(info.cpuEfficiencyCoreCount == nil)
    }

    @Test
    func hardwareInfoParsesPhysicalCoreCountFromNumberProcessorsVariants() {
        #expect(SystemHardwareInfoReader.physicalCoreCount(fromNumberProcessorsText: "proc 15:5:10:0") == 15)
        #expect(SystemHardwareInfoReader.physicalCoreCount(fromNumberProcessorsText: "  12  ") == 12)
        #expect(SystemHardwareInfoReader.physicalCoreCount(fromNumberProcessorsText: "proc") == nil)
        #expect(SystemHardwareInfoReader.physicalCoreCount(fromNumberProcessorsText: "") == nil)
        #expect(SystemHardwareInfoReader.physicalCoreCount(fromNumberProcessorsText: "unknown") == nil)
        #expect(
            SystemHardwareInfoReader.physicalCoreCount(
                fromHardwareDictionary: ["number_processors": 10]
            ) == 10
        )
        #expect(
            SystemHardwareInfoReader.physicalCoreCount(
                fromHardwareDictionary: ["number_processors": 0]
            ) == nil
        )
        #expect(SystemHardwareInfoReader.physicalCoreCount(fromHardwareDictionary: nil) == nil)
    }

    @Test
    func hardwareInfoReadsPerformanceAndEfficiencyCoresViaInjectedSysctl() throws {
        let data = try #require(
            """
            {"SPHardwareDataType":[{"chip_type":"Apple M5 Pro","number_processors":"proc 15:5:10:0"}],"SPDisplaysDataType":[]}
            """.data(using: .utf8)
        )

        let info = SystemHardwareInfoReader.parse(data) { name in
            switch name {
            case "hw.perflevel0.physicalcpu": return 5
            case "hw.perflevel1.physicalcpu": return 10
            default: return nil
            }
        }

        #expect(info.cpuCoreCount == 15)
        #expect(info.cpuPerformanceCoreCount == 5)
        #expect(info.cpuEfficiencyCoreCount == 10)
    }

    @Test
    func cpuCoreTopologyIgnoresMissingOrNonPositiveSysctlValues() {
        let missing = CPUCoreTopology.read { _ in nil }
        #expect(missing.performanceCoreCount == nil)
        #expect(missing.efficiencyCoreCount == nil)

        let nonPositive = CPUCoreTopology.read { name in
            switch name {
            case "hw.perflevel0.physicalcpu": return 0
            case "hw.perflevel1.physicalcpu": return -1
            default: return 99
            }
        }
        #expect(nonPositive.performanceCoreCount == nil)
        #expect(nonPositive.efficiencyCoreCount == nil)

        let onlyP = CPUCoreTopology.read { name in
            name == "hw.perflevel0.physicalcpu" ? 8 : nil
        }
        #expect(onlyP.performanceCoreCount == 8)
        #expect(onlyP.efficiencyCoreCount == nil)
    }

    @Test
    func privateIPv4RecognizesOnlyRFC1918Addresses() {
        #expect(SystemSampler.isPrivateIPv4Address("10.0.0.2"))
        #expect(SystemSampler.isPrivateIPv4Address("172.20.1.2"))
        #expect(SystemSampler.isPrivateIPv4Address("192.168.1.9"))
        #expect(!SystemSampler.isPrivateIPv4Address("172.32.1.2"))
        #expect(!SystemSampler.isPrivateIPv4Address("8.8.8.8"))
    }

    // MARK: SystemMonitorPathSafety

    @Test
    func pathWithinAllowedRootsAcceptsExactMatch() {
        let root = URL(fileURLWithPath: "/Users/test/Library/Caches")
        #expect(SystemMonitorPathSafety.isURL(root, withinAllowedRoots: [root]))
    }

    @Test
    func pathWithinAllowedRootsAcceptsDescendant() {
        let root = URL(fileURLWithPath: "/Users/test/Library/Caches")
        let child = URL(fileURLWithPath: "/Users/test/Library/Caches/com.example")
        #expect(SystemMonitorPathSafety.isURL(child, withinAllowedRoots: [root]))
    }

    @Test
    func pathWithinAllowedRootsRejectsOutside() {
        let root = URL(fileURLWithPath: "/Users/test/Library/Caches")
        let outside = URL(fileURLWithPath: "/Users/other/Library/Caches")
        #expect(!SystemMonitorPathSafety.isURL(outside, withinAllowedRoots: [root]))
    }

    @Test
    func pathWithinAllowedRootsRejectsSiblingPrefix() {
        // Prevent "/a/Caches" from treating "/a/Caches-evil" as a subpath
        let root = URL(fileURLWithPath: "/Users/test/Library/Caches")
        let sibling = URL(fileURLWithPath: "/Users/test/Library/Caches-evil")
        #expect(!SystemMonitorPathSafety.isURL(sibling, withinAllowedRoots: [root]))
    }

    @Test
    func pathWithinAllowedRootsRejectsNonFileURL() {
        let root = URL(fileURLWithPath: "/Users/test")
        let http = URL(string: "https://example.com")!
        #expect(!SystemMonitorPathSafety.isURL(http, withinAllowedRoots: [root]))
    }

    @Test
    func standardizedPathResolvesDotSegments() {
        let url = URL(fileURLWithPath: "/Users/test/./Library/../Library/Caches")
        #expect(SystemMonitorPathSafety.standardizedPath(url) == "/Users/test/Library/Caches")
    }

    @Test
    func pathWithinAllowedRootsRejectsTraversalEscapingRoot() {
        let root = URL(fileURLWithPath: "/Users/test/Library/Caches")
        let escaped = URL(fileURLWithPath: "/Users/test/Library/Caches/../../Secrets")

        #expect(!SystemMonitorPathSafety.isURL(escaped, withinAllowedRoots: [root]))
    }

    @Test
    func defaultAllowedRootsIncludesDeveloperCachesAndUserJunk() {
        let mock = MockFileManager()
        mock.homeDirectory = URL(fileURLWithPath: "/Users/test")
        mock.searchPathResults = [
            .cachesDirectory: [URL(fileURLWithPath: "/Users/test/Library/Caches")],
            .libraryDirectory: [URL(fileURLWithPath: "/Users/test/Library")],
            .trashDirectory: [URL(fileURLWithPath: "/Users/test/.Trash")],
        ]

        let roots = SystemMonitorPathSafety.defaultAllowedRoots(fileManager: mock)

        // Developer artifacts and package-manager caches
        #expect(roots.contains { $0.path.contains("DerivedData") })
        #expect(roots.contains { $0.path.contains("CoreSimulator/Caches") })
        #expect(roots.contains { $0.path.contains(".npm") })
        #expect(roots.contains { $0.path.contains("org.swift.swiftpm") })
        #expect(roots.contains { $0.path.contains(".bun/install/cache") })
        #expect(roots.contains { $0.path.contains(".cache/uv") })
        #expect(roots.contains { $0.path == "/private/var/folders/test/T" })
        // User caches, logs, and Trash
        #expect(roots.contains { $0.path == "/Users/test/Library/Caches" })
        #expect(roots.contains { $0.path == "/Users/test/Library/Logs" })
        #expect(roots.contains { $0.path == "/Users/test/.Trash" })
        // /private/tmp is added as a temporaryFiles root via the macOS /tmp alias
        #expect(roots.contains { $0.path == "/tmp" })
        // System-level paths remain excluded
        #expect(!roots.contains { $0.path == "/Library/Caches" })
        #expect(!roots.contains { $0.path == "/Library/Logs" })
    }

    @Test
    func defaultAllowedRootsRejectsOtherHomeDirectoryContent() {
        let mock = MockFileManager()
        mock.searchPathResults = [
            .cachesDirectory: [URL(fileURLWithPath: "/Users/test/Library/Caches")],
            .libraryDirectory: [URL(fileURLWithPath: "/Users/test/Library")],
            .trashDirectory: [URL(fileURLWithPath: "/Users/test/.Trash")],
        ]

        let roots = SystemMonitorPathSafety.defaultAllowedRoots(fileManager: mock)
        let documents = URL(fileURLWithPath: "/Users/test/Documents/private.txt")

        #expect(!SystemMonitorPathSafety.isURL(documents, withinAllowedRoots: roots))
    }

    // MARK: SystemDiskCleanup

    @Test
    func allowedScanRootsExcludesApplicationAndSystemData() {
        let mock = MockFileManager()
        mock.searchPathResults = [
            .cachesDirectory: [URL(fileURLWithPath: "/Users/test/Library/Caches")],
            .libraryDirectory: [URL(fileURLWithPath: "/Users/test/Library")],
            .trashDirectory: [URL(fileURLWithPath: "/Users/test/.Trash")],
        ]

        let roots = SystemDiskCleanup.allowedScanRoots(fileManager: mock)

        #expect(roots.contains { $0.kind == .developerArtifacts && $0.url.path.contains("DerivedData") })
        #expect(roots.contains { $0.kind == .packageManagerCache && $0.url.path.contains(".npm") })
        #expect(roots.contains { $0.kind == .packageManagerCache && $0.url.path.contains("go/pkg/mod") })
        #expect(roots.contains { $0.kind == .packageManagerCache && $0.url.path.contains("org.swift.swiftpm") })
        #expect(roots.contains { $0.kind == .packageManagerCache && $0.url.path.contains("org.carthage.CarthageKit") })
        #expect(roots.contains { $0.kind == .packageManagerCache && $0.url.path.contains(".bun/install/cache") })
        #expect(roots.contains { $0.kind == .packageManagerCache && $0.url.path.contains(".cache/pip") })
        // Newly added categories
        #expect(roots.contains { $0.kind == .appCache && $0.url.path == "/Users/test/Library/Caches" })
        #expect(roots.contains { $0.kind == .log && $0.url.path == "/Users/test/Library/Logs" })
        #expect(roots.contains { $0.kind == .crashReport && $0.url.path == "/Users/test/Library/Logs/DiagnosticReports" })
        #expect(roots.contains { $0.kind == .trash && $0.url.path == "/Users/test/.Trash" })
        // System-level and sensitive paths remain excluded
        let excludedPaths = [
            "/Users/test/Library/Application Support/CrashReporter",
            "/Users/test/Library/Developer/Xcode/Archives",
            "/Library/Caches",
            "/Library/Logs",
            "/usr/local/var/cache",
            "/opt/homebrew/var/cache",
        ]
        for path in excludedPaths {
            #expect(!roots.contains { $0.url.path == path })
        }
        // Application Support and user documents are not scan roots
        #expect(!roots.contains { $0.url.path.contains("Application Support") })
        #expect(!roots.contains { $0.url.path == "/Users/test/Documents" })
    }

    @Test
    func packageManagerRootsPreferFinerKindOverGenericCache() {
        let mock = MockFileManager()
        mock.homeDirectory = URL(fileURLWithPath: "/Users/test")
        mock.searchPathResults = [
            .cachesDirectory: [URL(fileURLWithPath: "/Users/test/Library/Caches")],
            .libraryDirectory: [URL(fileURLWithPath: "/Users/test/Library")],
            .trashDirectory: [URL(fileURLWithPath: "/Users/test/.Trash")],
        ]

        let roots = SystemDiskCleanup.allowedScanRoots(fileManager: mock)
        let swiftPM = roots.filter { $0.url.path.contains("org.swift.swiftpm") }
        #expect(swiftPM.count == 1)
        #expect(swiftPM.first?.kind == .packageManagerCache)
        // The same path must not be registered as both cache and packageManagerCache
        let path = swiftPM.first!.url.path
        #expect(roots.filter { $0.url.path == path }.count == 1)
    }

    @Test
    func scanCandidatesDeduplicatesPathPreferringFinerKind() {
        let cacheChild = URL(fileURLWithPath: "/Users/test/Library/Caches/org.swift.swiftpm")
        let coarse = DiskCleanupCandidate(
            url: cacheChild,
            kind: .cache,
            byteSize: 100,
            displayName: "org.swift.swiftpm"
        )
        let fine = DiskCleanupCandidate(
            url: cacheChild,
            kind: .packageManagerCache,
            byteSize: 100,
            displayName: "org.swift.swiftpm"
        )
        let deduped = SystemDiskCleanup.deduplicateCandidates([coarse, fine])
        #expect(deduped.count == 1)
        #expect(deduped.first?.kind == .packageManagerCache)
    }

    @Test
    func scanCandidatesSkipsDedicatedPackageRootUnderApplicationCache() {
        let mock = MockFileManager()
        mock.homeDirectory = URL(fileURLWithPath: "/Users/test")
        mock.searchPathResults = [
            .trashDirectory: [URL(fileURLWithPath: "/Users/test/.Trash")],
        ]
        let userCache = URL(fileURLWithPath: "/Users/test/Library/Caches")
        let packageRoot = userCache.appendingPathComponent("org.swift.swiftpm")
        let packageChild = packageRoot.appendingPathComponent("manifests")
        let genericChild = userCache.appendingPathComponent("com.example.app")

        mock.existingPaths = [userCache.path, packageRoot.path, packageChild.path, genericChild.path]
        mock.directoryContents[userCache.path] = [packageRoot, genericChild]
        mock.directoryContents[packageRoot.path] = [packageChild]
        mock.fileAttributes[packageChild.path] = [.size: NSNumber(value: 2048)]
        mock.fileAttributes[genericChild.path] = [.size: NSNumber(value: 1024)]

        let candidates = SystemDiskCleanup.scanCandidates(
            fileManager: mock,
            kinds: [.appCache, .packageManagerCache]
        )

        #expect(candidates.contains { $0.kind == .appCache && $0.displayName == "com.example.app 缓存" })
        #expect(candidates.contains { $0.kind == .packageManagerCache && $0.displayName == "manifests" })
        // The package root itself must not also appear as an app-cache child
        #expect(!candidates.contains { $0.kind == .appCache && $0.displayName == "org.swift.swiftpm 缓存" })
        #expect(candidates.filter { $0.url.path == packageChild.path }.count == 1)
    }

    @Test
    func allocatedByteSizeReturnsZeroForNonexistent() {
        let mock = MockFileManager()
        #expect(SystemDiskCleanup.allocatedByteSize(of: URL(fileURLWithPath: "/nope"), fileManager: mock) == 0)
    }

    @Test
    func scanCandidatesReturnsDirectChildrenSortedBySize() {
        let mock = MockFileManager()
        let cacheRoot = URL(fileURLWithPath: "/Users/test/.cache")
        let small = URL(fileURLWithPath: "/Users/test/.cache/app1")
        let big = URL(fileURLWithPath: "/Users/test/.cache/app2")

        mock.homeDirectory = URL(fileURLWithPath: "/Users/test")
        mock.searchPathResults = [
            .libraryDirectory: [URL(fileURLWithPath: "/Users/test/Library")],
            .trashDirectory: [],
        ]
        mock.existingPaths = [cacheRoot.path, small.path, big.path]
        mock.directoryContents[cacheRoot.path] = [small, big]
        mock.fileAttributes[small.path] = [.size: NSNumber(value: 1024)]
        mock.fileAttributes[big.path] = [.size: NSNumber(value: 8192)]

        let candidates = SystemDiskCleanup.scanCandidates(fileManager: mock, kinds: [.developerArtifacts])

        #expect(candidates.count == 2)
        #expect(candidates.allSatisfy { $0.kind == .developerArtifacts })
        // Sorted by size descending
        #expect(candidates.first?.displayName == "app2")
    }

    @Test
    func scanCandidatesExcludesSystemWideCacheChildren() {
        let mock = MockFileManager()
        let cacheRoot = URL(fileURLWithPath: "/Library/Caches")
        let candidate = cacheRoot.appendingPathComponent("shared-cache")
        mock.existingPaths = [cacheRoot.path, candidate.path]
        mock.directoryContents[cacheRoot.path] = [candidate]
        mock.fileAttributes[candidate.path] = [.size: NSNumber(value: 8192)]

        let candidates = SystemDiskCleanup.scanCandidates(fileManager: mock, kinds: [.cache])

        #expect(!candidates.contains { $0.url == candidate.standardizedFileURL })
    }

    @Test
    func scanCandidatesFindsApplicationCacheAndLogChildren() {
        let mock = MockFileManager()
        mock.homeDirectory = URL(fileURLWithPath: "/Users/test")
        mock.searchPathResults = [
            .trashDirectory: [URL(fileURLWithPath: "/Users/test/.Trash")],
        ]
        let userCache = URL(fileURLWithPath: "/Users/test/Library/Caches")
        let cacheChild = userCache.appendingPathComponent("com.example.app")
        let userLogs = URL(fileURLWithPath: "/Users/test/Library/Logs")
        let logChild = userLogs.appendingPathComponent("app.log")

        mock.existingPaths = [userCache.path, cacheChild.path, userLogs.path, logChild.path]
        mock.directoryContents[userCache.path] = [cacheChild]
        mock.directoryContents[userLogs.path] = [logChild]
        mock.fileAttributes[cacheChild.path] = [.size: NSNumber(value: 4096)]
        mock.fileAttributes[logChild.path] = [.size: NSNumber(value: 512)]

        let candidates = SystemDiskCleanup.scanCandidates(fileManager: mock, kinds: [.appCache, .log])

        #expect(candidates.contains { $0.kind == .appCache && $0.displayName == "com.example.app 缓存" })
        #expect(candidates.contains { $0.kind == .log && $0.displayName == "app.log" })
    }

    @Test
    func scanCandidatesFindsOnlyApplicationAndContainerCacheDirectories() {
        let mock = MockFileManager()
        let home = URL(fileURLWithPath: "/Users/test")
        mock.homeDirectory = home
        let libraryCaches = home.appendingPathComponent("Library/Caches")
        let desktopCache = libraryCaches.appendingPathComponent("com.example.desktop")
        let containers = home.appendingPathComponent("Library/Containers")
        let sandbox = containers.appendingPathComponent("com.example.sandbox")
        let sandboxCache = sandbox.appendingPathComponent("Data/Library/Caches", isDirectory: true)
        let sandboxSupport = sandbox.appendingPathComponent("Data/Library/Application Support")
        let groups = home.appendingPathComponent("Library/Group Containers")
        let group = groups.appendingPathComponent("group.com.example.shared")
        let groupCache = group.appendingPathComponent("Library/Caches", isDirectory: true)
        let groupSupport = group.appendingPathComponent("Library/Application Support")

        mock.existingPaths = [
            libraryCaches.path, desktopCache.path,
            containers.path, sandbox.path, sandboxCache.path, sandboxSupport.path,
            groups.path, group.path, groupCache.path, groupSupport.path,
        ]
        mock.directoryContents[libraryCaches.path] = [desktopCache]
        mock.directoryContents[containers.path] = [sandbox]
        mock.directoryContents[groups.path] = [group]
        mock.fileAttributes[desktopCache.path] = [.size: NSNumber(value: 4_096)]
        mock.fileAttributes[sandboxCache.path] = [.size: NSNumber(value: 8_192)]
        mock.fileAttributes[groupCache.path] = [.size: NSNumber(value: 16_384)]

        let candidates = SystemDiskCleanup.scanCandidates(fileManager: mock, kinds: [.appCache])

        #expect(candidates.map(\.url).contains(desktopCache.standardizedFileURL))
        #expect(candidates.map(\.url).contains(sandboxCache.standardizedFileURL))
        #expect(candidates.map(\.url).contains(groupCache.standardizedFileURL))
        #expect(candidates.allSatisfy { $0.kind == .appCache })
        #expect(candidates.contains { $0.displayName == "com.example.sandbox 缓存" })
        #expect(candidates.contains { $0.detail?.contains("沙盒应用缓存") == true })
        #expect(!candidates.map(\.url).contains(sandboxSupport.standardizedFileURL))
        #expect(!candidates.map(\.url).contains(groupSupport.standardizedFileURL))
    }

    @Test
    func applicationContainerCleanupRootsExcludeApplicationData() {
        let mock = MockFileManager()
        let home = URL(fileURLWithPath: "/Users/test")
        mock.homeDirectory = home
        let containers = home.appendingPathComponent("Library/Containers")
        let sandbox = containers.appendingPathComponent("com.example.sandbox")
        let cache = sandbox.appendingPathComponent("Data/Library/Caches", isDirectory: true)
        let applicationSupport = sandbox.appendingPathComponent("Data/Library/Application Support")
        mock.existingPaths = [containers.path, sandbox.path, cache.path, applicationSupport.path]
        mock.directoryContents[containers.path] = [sandbox]

        let roots = SystemDiskCleanup.allowedScanRoots(fileManager: mock)

        #expect(roots.contains { $0.kind == .appCache && $0.url == cache.standardizedFileURL })
        #expect(!roots.contains { $0.url == applicationSupport.standardizedFileURL })
        #expect(!SystemMonitorPathSafety.isURL(applicationSupport, withinAllowedRoots: roots.map(\.url)))
    }

    @Test
    func trashSelectedAllowsContainerCacheButRejectsNeighboringApplicationData() {
        let mock = MockFileManager()
        let home = URL(fileURLWithPath: "/Users/test")
        mock.homeDirectory = home
        let containers = home.appendingPathComponent("Library/Containers")
        let sandbox = containers.appendingPathComponent("com.example.sandbox")
        let cache = sandbox.appendingPathComponent("Data/Library/Caches")
        let cacheFile = cache.appendingPathComponent("thumbnail")
        let applicationSupport = sandbox.appendingPathComponent("Data/Library/Application Support")
        let userData = applicationSupport.appendingPathComponent("database.sqlite")
        mock.existingPaths = [
            containers.path, sandbox.path, cache.path, cacheFile.path, applicationSupport.path, userData.path,
        ]
        mock.directoryContents[containers.path] = [sandbox]
        mock.trashResults[cacheFile.standardizedFileURL] = .success(URL(fileURLWithPath: "/Users/test/.Trash/thumbnail"))

        let result = SystemDiskCleanup.trashSelected(
            urls: [cacheFile, userData],
            fileManager: mock,
            sizeProvider: { _ in 1 }
        )

        #expect(result.successCount == 1)
        #expect(result.failures.count == 1)
        #expect(result.failures.first?.url == userData.standardizedFileURL)
        #expect(result.failures.first?.message.contains("允许清理的用户目录") == true)
    }

    @Test
    func scanCandidatesFindsTrashItems() {
        let mock = MockFileManager()
        mock.homeDirectory = URL(fileURLWithPath: "/Users/test")
        let trashURL = URL(fileURLWithPath: "/Users/test/.Trash")
        mock.searchPathResults = [
            .trashDirectory: [trashURL],
        ]
        let trashedFile = trashURL.appendingPathComponent("old-file.zip")
        mock.existingPaths = [trashURL.path, trashedFile.path]
        mock.directoryContents[trashURL.path] = [trashedFile]
        mock.fileAttributes[trashedFile.path] = [.size: NSNumber(value: 1_048_576)]

        let candidates = SystemDiskCleanup.scanCandidates(fileManager: mock, kinds: [.trash])

        #expect(candidates.count == 1)
        #expect(candidates.first?.kind == .trash)
        #expect(candidates.first?.displayName == "old-file.zip")
    }

    @Test
    func scanCandidatesFindsOnlyStaleCurrentUserTemporaryFiles() {
        let mock = MockFileManager()
        let temporaryRoot = URL(fileURLWithPath: "/private/var/folders/test/T")
        let stale = temporaryRoot.appendingPathComponent("zisla-build-previous")
        let recent = temporaryRoot.appendingPathComponent("active-build")
        mock.temporaryDirectory = temporaryRoot
        mock.existingPaths = [temporaryRoot.path, stale.path, recent.path]
        mock.directoryContents[temporaryRoot.path] = [stale, recent]
        mock.fileAttributes[stale.path] = [
            .size: NSNumber(value: 4_096),
            .modificationDate: Date().addingTimeInterval(-8 * 24 * 3600),
        ]
        mock.fileAttributes[recent.path] = [
            .size: NSNumber(value: 2_048),
            .modificationDate: Date().addingTimeInterval(-2 * 24 * 3600),
        ]

        let candidates = SystemDiskCleanup.scanCandidates(fileManager: mock, kinds: [.temporaryFiles])

        #expect(candidates.count == 1)
        #expect(candidates.first?.kind == .temporaryFiles)
        #expect(candidates.first?.url == stale.standardizedFileURL)
        #expect(candidates.first?.detail?.contains("8 天未修改") == true)
    }

    @Test
    func allowedScanRootsIncludesPrivateTmpAsTemporaryFiles() {
        let mock = MockFileManager()
        mock.homeDirectory = URL(fileURLWithPath: "/Users/test")
        mock.searchPathResults = [
            .cachesDirectory: [URL(fileURLWithPath: "/Users/test/Library/Caches")],
            .libraryDirectory: [URL(fileURLWithPath: "/Users/test/Library")],
            .trashDirectory: [URL(fileURLWithPath: "/Users/test/.Trash")],
        ]

        let roots = SystemDiskCleanup.allowedScanRoots(fileManager: mock)

        // /private/tmp exists as a temporaryFiles root via the macOS /tmp alias
        #expect(roots.contains { $0.kind == .temporaryFiles && $0.url.path == "/tmp" })
        // /tmp (symlink) and /private/tmp resolve to the same path and must not both appear
        #expect(roots.filter { $0.url.path == "/private/tmp" || $0.url.path == "/tmp" }.count == 1)
    }

    @Test
    func scanCandidatesFindsOnlyStaleFilesInPrivateTmp() {
        let mock = MockFileManager()
        let tmpRoot = URL(fileURLWithPath: "/tmp")
        let stale = tmpRoot.appendingPathComponent("stale-session-cache")
        let recent = tmpRoot.appendingPathComponent("active-process-socket")
        // temporaryDirectory points at a user-private dir and must not stop /private/tmp from being a scan root
        mock.temporaryDirectory = URL(fileURLWithPath: "/private/var/folders/test/T")
        mock.existingPaths = [tmpRoot.path, stale.path, recent.path]
        mock.directoryContents[tmpRoot.path] = [stale, recent]
        mock.fileAttributes[stale.path] = [
            .size: NSNumber(value: 8_192),
            .modificationDate: Date().addingTimeInterval(-10 * 24 * 3600),
        ]
        mock.fileAttributes[recent.path] = [
            .size: NSNumber(value: 1_024),
            .modificationDate: Date().addingTimeInterval(-1 * 24 * 3600),
        ]

        let candidates = SystemDiskCleanup.scanCandidates(fileManager: mock, kinds: [.temporaryFiles])

        // Only stale files (≥7 days) are listed
        #expect(candidates.contains { $0.kind == .temporaryFiles && $0.url == stale.standardizedFileURL })
        #expect(!candidates.contains { $0.url == recent.standardizedFileURL })
    }

    @Test
    func scanDiskImagesFindsDmgAndPkgInDownloads() {
        let mock = MockFileManager()
        mock.homeDirectory = URL(fileURLWithPath: "/Users/test")
        let downloads = URL(fileURLWithPath: "/Users/test/Downloads")
        let dmg = downloads.appendingPathComponent("Xcode.dmg")
        let pkg = downloads.appendingPathComponent("Installer.pkg")
        let txt = downloads.appendingPathComponent("readme.txt")

        mock.searchPathResults = [
            .downloadsDirectory: [downloads],
            .trashDirectory: [URL(fileURLWithPath: "/Users/test/.Trash")],
        ]
        mock.existingPaths = [downloads.path, dmg.path, pkg.path, txt.path]
        mock.directoryContents[downloads.path] = [dmg, pkg, txt]
        mock.fileAttributes[dmg.path] = [.size: NSNumber(value: 10_000_000)]
        mock.fileAttributes[pkg.path] = [.size: NSNumber(value: 5_000_000)]
        mock.fileAttributes[txt.path] = [.size: NSNumber(value: 100)]

        let candidates = SystemDiskCleanup.scanCandidates(fileManager: mock, kinds: [.diskImage])

        #expect(candidates.count == 2)
        #expect(candidates.allSatisfy { $0.kind == .diskImage })
        #expect(candidates.contains { $0.displayName == "Xcode.dmg" })
        #expect(candidates.contains { $0.displayName == "Installer.pkg" })
        #expect(!candidates.contains { $0.displayName == "readme.txt" })
    }

    @Test
    func scanDuplicateFilesFindsIdenticalContent() {
        let mock = MockFileManager()
        mock.homeDirectory = URL(fileURLWithPath: "/Users/test")
        let downloads = URL(fileURLWithPath: "/Users/test/Downloads")
        let fileA = downloads.appendingPathComponent("photo.jpg")
        let fileB = downloads.appendingPathComponent("copy/photo.jpg")

        mock.searchPathResults = [
            .downloadsDirectory: [downloads],
            .trashDirectory: [URL(fileURLWithPath: "/Users/test/.Trash")],
        ]
        mock.existingPaths = [downloads.path, fileA.path, fileB.path]
        mock.directoryContents[downloads.path] = [fileA, downloads.appendingPathComponent("copy")]
        mock.directoryContents[downloads.appendingPathComponent("copy").path] = [fileB]
        mock.fileAttributes[fileA.path] = [.size: NSNumber(value: 2048)]
        mock.fileAttributes[fileB.path] = [.size: NSNumber(value: 2048)]

        let content = Data(repeating: 0xAB, count: 2048)
        mock.fileContentsData[fileA.path] = content
        mock.fileContentsData[fileB.path] = content

        let candidates = SystemDiskCleanup.scanCandidates(fileManager: mock, kinds: [.duplicateFile])

        #expect(candidates.count == 1)
        #expect(candidates.first?.kind == .duplicateFile)
        #expect(candidates.first?.detail?.contains("重复") == true)
    }

    @Test
    func trashSelectedMovesFilesAndSumsFreedBytes() {
        let mock = MockFileManager()
        let url1 = URL(fileURLWithPath: "/Users/test/Library/Caches/file1")
        let url2 = URL(fileURLWithPath: "/Users/test/Library/Caches/file2")

        mock.homeDirectory = URL(fileURLWithPath: "/Users/test")
        mock.existingPaths = [url1.path, url2.path]
        mock.trashResults[url1.standardizedFileURL] = .success(URL(fileURLWithPath: "/Users/test/.Trash/file1"))
        mock.trashResults[url2.standardizedFileURL] = .success(URL(fileURLWithPath: "/Users/test/.Trash/file2"))

        let result = SystemDiskCleanup.trashSelected(
            urls: [url1, url2],
            fileManager: mock,
            allowedRoots: [URL(fileURLWithPath: "/Users/test")],
            sizeProvider: { $0 == url1.standardizedFileURL ? 1000 : 2000 }
        )

        #expect(result.successCount == 2)
        #expect(result.freedBytes == 3000)
        #expect(result.failures.isEmpty)
    }

    @Test
    func trashSelectedRejectsPathOutsideAllowedRoots() {
        let mock = MockFileManager()
        let inside = URL(fileURLWithPath: "/Users/test/Library/Caches/ok")
        let outside = URL(fileURLWithPath: "/etc/passwd")

        mock.homeDirectory = URL(fileURLWithPath: "/Users/test")
        mock.existingPaths = [inside.path, outside.path]
        mock.trashResults[inside.standardizedFileURL] = .success(inside)

        let result = SystemDiskCleanup.trashSelected(
            urls: [inside, outside],
            fileManager: mock,
            allowedRoots: [URL(fileURLWithPath: "/Users/test")],
            sizeProvider: { _ in 10 }
        )

        #expect(result.successCount == 1)
        #expect(result.failures.count == 1)
        #expect(result.failures[0].url == outside.standardizedFileURL)
        #expect(result.failures[0].message.contains("允许清理的用户目录"))
    }

    @Test
    func defaultCleanupRootsRejectSystemCachesAndArbitrarySystemFiles() {
        let mock = MockFileManager()
        let cache = URL(fileURLWithPath: "/Library/Caches/shared-cache")
        let systemFile = URL(fileURLWithPath: "/etc/passwd")
        mock.existingPaths = [cache.path, systemFile.path]
        let result = SystemDiskCleanup.trashSelected(urls: [cache, systemFile], fileManager: mock)

        #expect(result.successCount == 0)
        #expect(result.failures.count == 2)
        #expect(result.failures.map(\.url).contains(cache.standardizedFileURL))
        #expect(result.failures.map(\.url).contains(systemFile.standardizedFileURL))
    }

    @Test
    func trashSelectedRejectsNonFileURL() {
        let mock = MockFileManager()
        let http = URL(string: "https://example.com")!

        let result = SystemDiskCleanup.trashSelected(
            urls: [http],
            fileManager: mock,
            allowedRoots: [URL(fileURLWithPath: "/Users/test")]
        )

        #expect(result.successCount == 0)
        #expect(result.failures.first?.message.contains("本地文件路径") == true)
    }

    @Test
    func trashSelectedRecordsMissingFileFailure() {
        let mock = MockFileManager()
        let missing = URL(fileURLWithPath: "/Users/test/Library/Caches/missing")
        mock.homeDirectory = URL(fileURLWithPath: "/Users/test")

        let result = SystemDiskCleanup.trashSelected(
            urls: [missing],
            fileManager: mock,
            allowedRoots: [URL(fileURLWithPath: "/Users/test")]
        )

        #expect(result.successCount == 0)
        #expect(result.failures.first?.message.contains("不存在") == true)
    }

    // MARK: SystemMonitorService

    @Test
    func serviceInitializesWithSaneDefaults() {
        let service = SystemMonitorService()
        #expect(service.samplingInterval == 1.5)
        #expect(service.snapshot == nil)
        #expect(!service.isSampling)
    }

    @Test
    func serviceClampsSamplingIntervalToMinimum() {
        #expect(SystemMonitorService(samplingInterval: 0.01).samplingInterval == 0.2)
    }

    @Test
    func defaultVolumeCapacityRefreshesCachedResourceValues() throws {
        let fileManager = FoundationVolumeCapacityFileManager()
        let foundation = FileManager.default
        let volumeURL = foundation.temporaryDirectory
        let fileURL = volumeURL.appendingPathComponent("zisla-capacity-\(UUID().uuidString)")
        defer { try? foundation.removeItem(at: fileURL) }

        let initial = try #require(fileManager.volumeCapacity(for: volumeURL))
        #expect(foundation.createFile(atPath: fileURL.path, contents: nil))
        let handle = try FileHandle(forWritingTo: fileURL)
        let chunk = Data(repeating: 0x5A, count: 4 * 1024 * 1024)
        for _ in 0..<16 {
            try handle.write(contentsOf: chunk)
        }
        try handle.synchronize()
        try handle.close()

        let expected = try #require(
            fileManager.volumeCapacity(for: URL(fileURLWithPath: volumeURL.path, isDirectory: true))
        )
        let refreshed = try #require(fileManager.volumeCapacity(for: volumeURL))
        let decrease = initial.available >= expected.available ? initial.available - expected.available : 0
        let staleDifference = refreshed.available >= expected.available
            ? refreshed.available - expected.available
            : expected.available - refreshed.available

        #expect(decrease >= 16 * 1024 * 1024)
        #expect(staleDifference < 8 * 1024 * 1024)
    }

    @Test
    func sampleOnceProducesDiskMetricsAndValidGPUFanData() async {
        let mock = MockFileManager()
        let volume = URL(fileURLWithPath: "/Users/test")
        mock.homeDirectory = volume
        mock.fileSystemAttributes[volume.path] = [
            .systemSize: NSNumber(value: 500_000_000_000),
            .systemFreeSize: NSNumber(value: 100_000_000_000),
        ]

        let service = SystemMonitorService(
            fileManager: mock,
            volumeURL: volume,
            publicIPProvider: StubPublicIPProvider(address: "203.0.113.8"),
            hardwareInfoProvider: { .unavailable }
        )
        let snapshot = await service.sampleOnce()

        #expect(snapshot.disk.totalBytes == 500_000_000_000)
        #expect(snapshot.disk.freeBytes == 100_000_000_000)
        #expect(snapshot.disk.usedBytes == 400_000_000_000)

        // GPU without readings must be explicitly unavailable; IOAccelerator readings stay in a valid range.
        switch snapshot.gpu {
        case let .unavailable(gpuReason): #expect(gpuReason.contains("GPU"))
        case let .available(metrics): #expect((0...1).contains(metrics.usage))
        }
        switch snapshot.fan {
        case let .unavailable(reason):
            #expect(!reason.isEmpty)
        case let .available(rpm, detail):
            #expect(!rpm.isEmpty)
            #expect(rpm.allSatisfy { (100...20_000).contains($0) })
            #expect(detail == "AppleSMC 只读")
        }

        // First sample has no history, so CPU and network rates are 0
        #expect(snapshot.cpu.usage == 0)
        #expect(snapshot.network.receiveBytesPerSecond == 0)
        #expect(snapshot.network.sendBytesPerSecond == 0)
        #expect(snapshot.networkIdentity.publicIPAddress == nil)
        #expect(service.snapshot == snapshot)

        await service.refreshPublicIPAddress()
        #expect(service.snapshot?.networkIdentity.publicIPAddress == "203.0.113.8")
    }


    @Test
    func scanCleanupCandidatesEmptyWithoutRoots() async {
        let mock = MockFileManager()
        mock.homeDirectory = URL(fileURLWithPath: "/Users/test")
        let service = SystemMonitorService(fileManager: mock)
        #expect(await service.scanCleanupCandidates().isEmpty)
    }

    @Test
    func scanCleanupCandidatesReturnsDeveloperCacheChild() async {
        let mock = MockFileManager()
        let cacheRoot = URL(fileURLWithPath: "/Users/test/.cache")
        let child = URL(fileURLWithPath: "/Users/test/.cache/app")
        mock.homeDirectory = URL(fileURLWithPath: "/Users/test")
        mock.existingPaths = [cacheRoot.path, child.path]
        mock.directoryContents[cacheRoot.path] = [child]
        mock.fileAttributes[child.path] = [.size: NSNumber(value: 4096)]

        let candidates = await SystemMonitorService(fileManager: mock).scanCleanupCandidates()

        #expect(candidates.count == 1)
        #expect(candidates.first?.kind == .developerArtifacts)
        #expect(candidates.first?.displayName == "app")
    }

    @Test
    func serviceTrashSelectedMovesFileToTrash() async {
        let mock = MockFileManager()
        let file = URL(fileURLWithPath: "/Users/test/.cache/temp")
        mock.homeDirectory = URL(fileURLWithPath: "/Users/test")
        mock.existingPaths = [file.path]
        mock.fileAttributes[file.path] = [.size: NSNumber(value: 1024)]
        mock.trashResults[file.standardizedFileURL] = .success(URL(fileURLWithPath: "/Users/test/.Trash/temp"))
        mock.volumeCapacities[mock.homeDirectory.path] = (total: 1_000, available: 400)

        let service = SystemMonitorService(fileManager: mock, hardwareInfoProvider: { .unavailable })
        _ = await service.sampleOnce()
        mock.volumeCapacities[mock.homeDirectory.path] = (total: 1_000, available: 700)

        let result = await service.trashSelected([file])

        #expect(result.successCount == 1)
        #expect(result.failures.isEmpty)
        #expect(service.snapshot?.disk.freeBytes == 700)
    }

    @Test
    func successfulCleanupRefreshesDiskCapacityAgainAfterConfiguredDelay() async {
        let mock = MockFileManager()
        let volume = URL(fileURLWithPath: "/Users/test")
        let file = volume.appendingPathComponent(".cache/temp")
        mock.homeDirectory = volume
        mock.existingPaths = [file.path]
        mock.fileAttributes[file.path] = [.size: NSNumber(value: 1024)]
        mock.trashResults[file.standardizedFileURL] = .success(URL(fileURLWithPath: "/Users/test/.Trash/temp"))
        mock.volumeCapacities[volume.path] = (total: 1_000, available: 400)

        let service = SystemMonitorService(
            fileManager: mock,
            volumeURL: volume,
            hardwareInfoProvider: { .unavailable },
            postCleanupDiskRefreshDelay: .milliseconds(10)
        )
        _ = await service.sampleOnce()
        mock.volumeCapacities[volume.path] = (total: 1_000, available: 700)

        _ = await service.trashSelected([file])
        mock.volumeCapacities[volume.path] = (total: 1_000, available: 900)

        await waitUntil(timeoutSeconds: 2) {
            service.snapshot?.disk.freeBytes == 900
        }
    }

    @Test
    func startThenStopTogglesSamplingFlag() {
        let mock = MockFileManager()
        mock.homeDirectory = URL(fileURLWithPath: "/Users/test")
        mock.fileSystemAttributes["/Users/test"] = [
            .systemSize: NSNumber(value: 1_000_000_000),
            .systemFreeSize: NSNumber(value: 500_000_000),
        ]
        let service = SystemMonitorService(samplingInterval: 10.0, fileManager: mock)

        #expect(!service.isSampling)
        service.start()
        #expect(service.isSampling)
        service.stop()
        #expect(!service.isSampling)
    }

    @Test
    func diskCapacityTimerRefreshesCapacityIndependentlyOfRegularSampling() async {
        let mock = MockFileManager()
        let volume = URL(fileURLWithPath: "/Users/test")
        mock.homeDirectory = volume
        mock.volumeCapacities[volume.path] = (total: 1_000, available: 400)
        let service = SystemMonitorService(
            samplingInterval: 10,
            fileManager: mock,
            volumeURL: volume,
            hardwareInfoProvider: { .unavailable },
            diskCapacityRefreshInterval: 0.01
        )
        _ = await service.sampleOnce()
        mock.volumeCapacities[volume.path] = (total: 1_000, available: 700)

        service.start()
        await waitUntil(timeoutSeconds: 2) {
            service.snapshot?.disk.freeBytes == 700
        }
        service.stop()

        #expect(service.snapshot?.disk.freeBytes == 700)
    }

    @Test
    func diskCapacityRefreshesAfterThreeMinutes() async {
        let mock = MockFileManager()
        let volume = URL(fileURLWithPath: "/Users/test")
        mock.homeDirectory = volume
        mock.volumeCapacities[volume.path] = (total: 1_000, available: 400)
        let clock = ControllableDateProvider(Date(timeIntervalSince1970: 1_700_000_000))
        let service = SystemMonitorService(
            fileManager: mock,
            volumeURL: volume,
            dateProvider: { clock.now() },
            publicIPProvider: StubPublicIPProvider(address: nil),
            hardwareInfoProvider: { .unavailable }
        )

        _ = await service.sampleOnce()
        #expect(service.snapshot?.disk.freeBytes == 400)
        mock.volumeCapacities[volume.path] = (total: 1_000, available: 700)
        clock.advance(by: 3 * 60 - 1)
        _ = await service.sampleOnce()
        #expect(service.snapshot?.disk.freeBytes == 400)

        clock.advance(by: 1)
        _ = await service.sampleOnce()
        #expect(service.snapshot?.disk.freeBytes == 700)
    }

    @Test
    func publicIPAutoRefreshesOnSampleAfterInterval() async {
        let mock = MockFileManager()
        let volume = URL(fileURLWithPath: "/Users/test")
        mock.homeDirectory = volume
        mock.fileSystemAttributes[volume.path] = [
            .systemSize: NSNumber(value: 1_000_000_000),
            .systemFreeSize: NSNumber(value: 500_000_000),
        ]

        let clock = ControllableDateProvider(Date(timeIntervalSince1970: 1_700_000_000))
        let provider = CountingPublicIPProvider(addresses: ["203.0.113.1", "203.0.113.2"])
        let service = SystemMonitorService(
            fileManager: mock,
            volumeURL: volume,
            dateProvider: { clock.now() },
            publicIPProvider: provider,
            hardwareInfoProvider: { .unavailable }
        )

        // sampleOnce schedules a background periodic query; the first call should write the public IP.
        _ = await service.sampleOnce()
        await waitUntil(timeoutSeconds: 2) {
            service.snapshot?.networkIdentity.publicIPAddress == "203.0.113.1"
        }
        #expect(provider.callCount == 1)
        #expect(service.snapshot?.networkIdentity.publicIPAddress == "203.0.113.1")
        #expect(service.publicIPAddress == "203.0.113.1")

        // Within the throttle window: another sample must not hit the provider.
        clock.advance(by: 5 * 60)
        _ = await service.sampleOnce()
        await Task.yield()
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(provider.callCount == 1)

        // After the period elapses, sampling should refresh automatically.
        clock.advance(by: 5 * 60)
        _ = await service.sampleOnce()
        await waitUntil(timeoutSeconds: 2) {
            service.snapshot?.networkIdentity.publicIPAddress == "203.0.113.2"
        }
        #expect(provider.callCount == 2)
        #expect(service.snapshot?.networkIdentity.publicIPAddress == "203.0.113.2")
        #expect(service.publicIPAddress == "203.0.113.2")
    }

    @Test
    func publicIPUserRefreshBypassesThrottleAndUpdatesSnapshot() async {
        let mock = MockFileManager()
        let volume = URL(fileURLWithPath: "/Users/test")
        mock.homeDirectory = volume
        mock.fileSystemAttributes[volume.path] = [
            .systemSize: NSNumber(value: 1_000_000_000),
            .systemFreeSize: NSNumber(value: 500_000_000),
        ]

        let clock = ControllableDateProvider(Date(timeIntervalSince1970: 1_700_000_000))
        let provider = CountingPublicIPProvider(addresses: ["198.51.100.1", "198.51.100.2"])
        let service = SystemMonitorService(
            fileManager: mock,
            volumeURL: volume,
            dateProvider: { clock.now() },
            publicIPProvider: provider,
            hardwareInfoProvider: { .unavailable }
        )
        _ = await service.sampleOnce()
        await waitUntil(timeoutSeconds: 2) {
            service.snapshot?.networkIdentity.publicIPAddress == "198.51.100.1"
        }
        #expect(provider.callCount == 1)
        #expect(service.snapshot?.networkIdentity.publicIPAddress == "198.51.100.1")

        // Explicit user refresh must call again and update the snapshot even if the background period has not elapsed.
        clock.advance(by: 1)
        await service.refreshPublicIPAddress()
        #expect(provider.callCount == 2)
        #expect(service.snapshot?.networkIdentity.publicIPAddress == "198.51.100.2")
        #expect(service.publicIPAddress == "198.51.100.2")
    }

    /// Poll until the condition holds or times out; used to wait for the public-IP task scheduled by sampleOnce.
    private func waitUntil(
        timeoutSeconds: TimeInterval,
        pollNanoseconds: UInt64 = 10_000_000,
        condition: () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(nanoseconds: pollNanoseconds)
        }
        #expect(condition())
    }
}
