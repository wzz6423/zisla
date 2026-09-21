import AppKit
import Combine
import Foundation
import ZislaCore

/// File transfer source to display in the collapsed Dynamic Island.
public enum BrowserDownloadAgent: String, CaseIterable, Sendable {
    case airDrop
    case safari
    case chrome
    case edge
    case firefox
    case brave
    case vivaldi
    case opera
    case arc

    public var displayName: String {
        switch self {
        case .airDrop: "AirDrop"
        case .safari: "Safari"
        case .chrome: "Chrome"
        case .edge: "Microsoft Edge"
        case .firefox: "Firefox"
        case .brave: "Brave"
        case .vivaldi: "Vivaldi"
        case .opera: "Opera"
        case .arc: "Arc"
        }
    }

    /// Stable and preview releases of the same browser share download behavior; listed by priority.
    public var bundleIdentifiers: [String] {
        switch self {
        case .airDrop: ["com.apple.sharingd"]
        case .safari: ["com.apple.Safari", "com.apple.SafariTechnologyPreview"]
        case .chrome: ["com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.canary"]
        case .edge: ["com.microsoft.edgemac", "com.microsoft.edgemac.Beta"]
        case .firefox: ["org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition"]
        case .brave: ["com.brave.Browser", "com.brave.Browser.beta"]
        case .vivaldi: ["com.vivaldi.Vivaldi"]
        case .opera: ["com.operasoftware.Opera", "com.operasoftware.OperaGX"]
        case .arc: ["company.thebrowser.Browser"]
        }
    }

    public var bundleIdentifier: String { bundleIdentifiers[0] }

    public var symbolName: String {
        switch self {
        case .airDrop: "dot.radiowaves.left.and.right"
        default: "arrow.down.circle.fill"
        }
    }
}
/// Temp-file extension for browser downloads → possible download sources; same-family browsers share an extension, so quarantine or runtime state is needed to distinguish them.
enum BrowserDownloadTempExtension: String, CaseIterable, Sendable {
    case crdownload
    case download
    case part
    case opdownload

    /// Candidate sources for this extension, ordered by commonality.
    var candidates: [BrowserDownloadAgent] {
        switch self {
        case .crdownload: [.chrome, .edge, .brave, .arc, .vivaldi]
        case .download: [.safari]
        case .part: [.firefox]
        case .opdownload: [.opera]
        }
    }
}

/// The third field of `com.apple.quarantine` is the download agent name (e.g., `Chrome`, `Safari`), which lets us identify the browser precisely.
enum QuarantineAgentReader {
    static func agentName(ofFileAt url: URL) -> String? {
        let path = url.path
        let name = "com.apple.quarantine"
        let size = getxattr(path, name, nil, 0, 0, XATTR_NOFOLLOW)
        guard size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        let read = getxattr(path, name, &buffer, size, 0, XATTR_NOFOLLOW)
        guard read > 0,
            let value = String(bytes: buffer[0..<read], encoding: .utf8)
        else { return nil }
        let fields = value.split(separator: ";", omittingEmptySubsequences: false)
        guard fields.count >= 3 else { return nil }
        let agent = fields[2].trimmingCharacters(in: .whitespaces)
        return agent.isEmpty ? nil : agent
    }
}

/// Display snapshot of a browser download entry or its compact-island summary.
public struct BrowserDownloadSnapshot: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var agent: BrowserDownloadAgent?
    public var fileName: String
    /// 0...1; nil when total size is unknown.
    public var fraction: Double?
    public var isFinished: Bool

    public init(
        id: UUID = UUID(),
        agent: BrowserDownloadAgent?,
        fileName: String,
        fraction: Double?,
        isFinished: Bool
    ) {
        self.id = id
        self.agent = agent
        self.fileName = fileName
        self.fraction = fraction.flatMap {
            $0.isFinite ? min(max($0, 0), 1) : nil
        }
        self.isFinished = isFinished
    }

    /// Caps in-progress display at 99%, reserving 100% for the finished green checkmark so the two states look distinct.
    public var progressText: String {
        guard let fraction, fraction.isFinite else { return isFinished ? "100%" : "…" }
        if isFinished { return "100%" }
        return "\(min(99, Int(fraction * 100)))%"
    }

    /// The UI only uses source, file name, percentage text, and finished state; deduplicating on this key avoids refreshing the Dynamic Island on every poll cycle.
    var displayKey: String {
        "\(agent?.rawValue ?? "-")|\(fileName)|\(progressText)|\(isFinished)"
    }
}

/// Pure logic for resolving the download source, decoupled from `NSProgress` for unit testing.
enum BrowserDownloadAgentResolver {
    static func agent(
        forFileOperationKind kind: Progress.FileOperationKind?
    ) -> BrowserDownloadAgent? {
        kind == .receiving ? .airDrop : nil
    }

    /// The quarantine agent name may be a display name (`Google Chrome`), a short name (`Chrome`), or a bundle ID.
    static func agent(forQuarantineAgentName name: String) -> BrowserDownloadAgent? {
        let normalized = name.lowercased().trimmingCharacters(in: .whitespaces)
        guard !normalized.isEmpty else { return nil }
        for agent in BrowserDownloadAgent.allCases
        where agent.bundleIdentifiers.contains(where: { $0.lowercased() == normalized }) {
            return agent
        }
        // Whole-word match, not substring: short names like `arc` would otherwise match unrelated words like `search`.
        let tokens = Set(
            normalized
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map(String.init)
        )
        for agent in BrowserDownloadAgent.allCases where tokens.contains(agent.rawValue.lowercased()) {
            return agent
        }
        return nil
    }

    /// When quarantine info is absent, intersects the extension candidate set with currently running browsers.
    static func agent(
        forTempExtension tempExtension: BrowserDownloadTempExtension?,
        runningBundleIdentifiers: Set<String>
    ) -> BrowserDownloadAgent? {
        if let tempExtension {
            let candidates = tempExtension.candidates
            if candidates.count == 1 { return candidates[0] }
            if let running = candidates.first(where: {
                $0.bundleIdentifiers.contains(where: runningBundleIdentifiers.contains)
            }) {
                return running
            }
            return candidates.first
        }
        let running = BrowserDownloadAgent.allCases.filter {
            $0 != .airDrop
                && $0.bundleIdentifiers.contains(where: runningBundleIdentifiers.contains)
        }
        return running.count == 1 ? running[0] : nil
    }

    /// Display file name: strips intermediate extensions such as `.crdownload`.
    static func displayFileName(for url: URL) -> String {
        let name = url.lastPathComponent
        guard let tempExtension = BrowserDownloadTempExtension(rawValue: url.pathExtension.lowercased())
        else { return name }
        return String(name.dropLast(tempExtension.rawValue.count + 1))
    }
}
struct AirDropTransferItem: Sendable {
    var fileName: String
    var expectedByteCount: Int64?
    var destinationURL: URL?
    var completedURLs: [URL]
}

struct AirDropTransferSnapshot: Sendable {
    var identifier: String
    var batchFraction: Double?
    var items: [AirDropTransferItem]
}

enum AirDropTransferMetadataParser {
    static func items(
        from rawFiles: [Any],
        destinationURL: URL?,
        completedURLs: [URL]
    ) -> [AirDropTransferItem] {
        rawFiles.compactMap { rawFile in
            guard let values = rawFile as? NSDictionary else { return nil }
            guard let fileName = string(in: values, keys: ["FileName", "fileName"]),
                !fileName.isEmpty
            else { return nil }
            return AirDropTransferItem(
                fileName: fileName,
                expectedByteCount: number(in: values, keys: ["FileSize", "fileSize"]),
                destinationURL: destinationURL,
                completedURLs: completedURLs
            )
        }
    }

    private static func string(in values: NSDictionary, keys: [String]) -> String? {
        keys.lazy.compactMap { values[$0] as? String }.first
    }

    private static func number(in values: NSDictionary, keys: [String]) -> Int64? {
        keys.lazy.compactMap { (values[$0] as? NSNumber)?.int64Value }.first
    }
}

enum AirDropItemProgressResolver {
    static func fraction(
        for item: AirDropTransferItem,
        progressFileURL: URL?,
        fileByteCount: (URL) -> Int64?
    ) -> Double? {
        guard
            let expectedByteCount = item.expectedByteCount,
            expectedByteCount > 0
        else { return nil }
        for fileURL in candidateFileURLs(for: item, progressFileURL: progressFileURL) {
            guard let writtenByteCount = fileByteCount(fileURL), writtenByteCount >= 0 else {
                continue
            }
            return min(Double(writtenByteCount) / Double(expectedByteCount), 1)
        }
        return nil
    }

    static func privateFileURLs(for item: AirDropTransferItem) -> [URL] {
        guard isSafeFileName(item.fileName) else { return [] }
        var candidates = item.completedURLs.compactMap { url -> URL? in
            guard url.isFileURL, url.lastPathComponent == item.fileName else { return nil }
            return url.standardizedFileURL
        }
        if let destinationURL = item.destinationURL?.standardizedFileURL {
            if destinationURL.isFileURL {
                if destinationURL.lastPathComponent == item.fileName {
                    candidates.append(destinationURL)
                } else {
                    let candidate = destinationURL.appendingPathComponent(item.fileName)
                        .standardizedFileURL
                    if candidate.deletingLastPathComponent().standardizedFileURL == destinationURL {
                        candidates.append(candidate)
                    }
                }
            }
        }
        return deduplicated(candidates)
    }

    static func fileByteCount(at url: URL, fileManager: FileManager) -> Int64? {
        guard
            let attributes = try? fileManager.attributesOfItem(atPath: url.path),
            attributes[.type] as? FileAttributeType == .typeRegular,
            let size = attributes[.size] as? NSNumber
        else { return nil }
        let byteCount = size.int64Value
        return byteCount >= 0 ? byteCount : nil
    }

    private static func isSafeFileName(_ fileName: String) -> Bool {
        !fileName.isEmpty
            && fileName != "."
            && fileName != ".."
            && fileName == (fileName as NSString).lastPathComponent
    }

    private static func candidateFileURLs(
        for item: AirDropTransferItem,
        progressFileURL: URL?
    ) -> [URL] {
        guard isSafeFileName(item.fileName) else { return [] }
        let completedURLs = item.completedURLs.compactMap { url -> URL? in
            guard url.isFileURL, url.lastPathComponent == item.fileName else { return nil }
            return url.standardizedFileURL
        }
        if let progressFileURL = progressFileURL?.standardizedFileURL,
            progressFileURL.isFileURL,
            BrowserDownloadAgentResolver.displayFileName(for: progressFileURL) == item.fileName
        {
            return deduplicated(completedURLs + [progressFileURL])
        }
        return deduplicated(completedURLs + privateFileURLs(for: item))
    }

    private static func deduplicated(_ urls: [URL]) -> [URL] {
        var seen = Set<URL>()
        return urls.filter { seen.insert($0).inserted }
    }
}

/// State machine for browser download display: manages entry insertion/removal and brief retention after completion; does not depend on `NSProgress`.
struct BrowserDownloadTracker: Sendable {
    struct Entry: Sendable {
        var fileURL: URL?
        var agent: BrowserDownloadAgent?
        var fileName: String
        var fraction: Double?
        /// The aggregate Progress remains useful for the compact island but is never used by an AirDrop item card.
        var batchFraction: Double? = nil
        var startedAt: Date
    }

    private(set) var entries: [UUID: Entry] = [:]
    private var finishedSnapshot: BrowserDownloadSnapshot?

    var snapshots: [BrowserDownloadSnapshot] {
        let active = entries
            .sorted { $0.value.startedAt > $1.value.startedAt }
            .map { token, entry in
                BrowserDownloadSnapshot(
                    id: token,
                    agent: entry.agent,
                    fileName: entry.fileName,
                    fraction: entry.fraction,
                    isFinished: false
                )
            }
        return active.isEmpty ? finishedSnapshot.map { [$0] } ?? [] : active
    }

    /// Returns deduplicated browsers ordered by most recent download.
    var uniqueAgents: [BrowserDownloadAgent] {
        var seen = Set<BrowserDownloadAgent>()
        return snapshots.compactMap(\.agent).filter { seen.insert($0).inserted }
    }

    /// Multiple in-progress downloads are represented by one compact-island summary whose fraction is their arithmetic mean.
    var snapshot: BrowserDownloadSnapshot? {
        let active = snapshots
        guard !active.isEmpty else { return nil }
        if active.count == 1 {
            let activeSnapshot = active[0]
            guard let entry = entries[activeSnapshot.id], entry.agent == .airDrop else {
                return activeSnapshot
            }
            return BrowserDownloadSnapshot(
                id: activeSnapshot.id,
                agent: activeSnapshot.agent,
                fileName: activeSnapshot.fileName,
                fraction: entry.batchFraction ?? activeSnapshot.fraction,
                isFinished: false
            )
        }
        let knownFractions = active.compactMap { snapshot in
            guard let entry = entries[snapshot.id] else { return snapshot.fraction }
            return entry.agent == .airDrop ? entry.batchFraction ?? entry.fraction : entry.fraction
        }
        return BrowserDownloadSnapshot(
            agent: nil,
            fileName: AppLocalization.text("%ld 项下载", active.count),
            fraction: knownFractions.isEmpty
                ? nil
                : knownFractions.reduce(0, +) / Double(knownFractions.count),
            isFinished: false
        )
    }

    mutating func insert(token: UUID, entry: Entry) {
        finishedSnapshot = nil
        entries[token] = entry
    }

    mutating func update(token: UUID, fraction: Double?) {
        guard entries[token] != nil else { return }
        entries[token]?.fraction = fraction
    }

    mutating func update(token: UUID, agent: BrowserDownloadAgent?) {
        guard entries[token] != nil, let agent else { return }
        entries[token]?.agent = agent
    }

    mutating func update(token: UUID, batchFraction: Double?) {
        guard entries[token] != nil else { return }
        entries[token]?.batchFraction = batchFraction
    }

    mutating func update(token: UUID, fileURL: URL?, fileName: String?) {
        guard entries[token] != nil else { return }
        if let fileURL {
            entries[token]?.fileURL = fileURL
        }
        if let fileName {
            entries[token]?.fileName = fileName
        }
    }

    /// Removes the entry; on success, transitions to the hold state and returns true so the caller can schedule the clear timer.
    mutating func finish(token: UUID, succeeded: Bool) -> Bool {
        guard let entry = entries.removeValue(forKey: token) else { return false }
        guard succeeded else { return false }
        finishedSnapshot = BrowserDownloadSnapshot(
            id: token,
            agent: entry.agent,
            fileName: entry.fileName,
            fraction: 1,
            isFinished: true
        )
        return true
    }

    mutating func clearFinishedHold() {
        finishedSnapshot = nil
    }

    mutating func removeAll() {
        entries.removeAll()
        finishedSnapshot = nil
    }
}

struct BrowserDownloadMonitorLifecycle: Sendable {
    private(set) var generation: UInt64 = 0

    mutating func start() -> UInt64 {
        generation &+= 1
        return generation
    }

    mutating func stop() {
        generation &+= 1
    }

    func accepts(_ callbackGeneration: UInt64) -> Bool {
        generation == callbackGeneration
    }
}
/// Monitors `NSProgress` published by browsers to the downloads directory and shows an icon and percentage in the collapsed Dynamic Island.
///
/// Uses the system's public progress-publishing mechanism (Chrome, Safari, etc. publish progress during downloads).
/// AirDrop metadata is read through a runtime-checked system observer only to resolve the published item to its expected size.
@MainActor
public final class BrowserDownloadMonitor: ObservableObject {
    /// How long the green checkmark stays visible after a successful download.
    public static let finishedHoldDuration: Double = 3

    @Published public private(set) var snapshot: BrowserDownloadSnapshot?
    @Published public private(set) var snapshots: [BrowserDownloadSnapshot] = []
    public var uniqueAgents: [BrowserDownloadAgent] { tracker.uniqueAgents }

    private var tracker = BrowserDownloadTracker()
    private var subscriberTokens: [Any] = []
    private var progressBoxes: [UUID: ProgressBox] = [:]
    private var airDropObserver: AirDropTransferObserver?
    private var airDropTransfers: [String: AirDropTransferSnapshot] = [:]
    private var timer: AnyCancellable?
    private var finishedClearTask: Task<Void, Never>?
    private var lifecycle = BrowserDownloadMonitorLifecycle()
    private let directories: [URL]
    private let pollInterval: Double
    private let fileManager: FileManager
    private let holdSleeper: @Sendable (Duration) async throws -> Void

    public convenience init() {
        self.init(directories: [Self.defaultDownloadsDirectory].compactMap { $0 })
    }

    init(
        directories: [URL],
        pollInterval: Double = 0.35,
        fileManager: FileManager = .default,
        holdSleeper: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        }
    ) {
        self.directories = directories
        self.pollInterval = pollInterval
        self.fileManager = fileManager
        self.holdSleeper = holdSleeper
    }

    private static var defaultDownloadsDirectory: URL? {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
    }

    public func start() {
        guard subscriberTokens.isEmpty, !directories.isEmpty else { return }
        let callbackGeneration = lifecycle.start()
        startAirDropObservation(callbackGeneration: callbackGeneration)
        for directory in directories {
            let token = Progress.addSubscriber(forFileURL: directory) { [weak self] published in
                let entryToken = UUID()
                let box = ProgressBox(published)
                DispatchQueue.main.async { [weak self] in
                    MainActor.assumeIsolated {
                        guard let self, self.lifecycle.accepts(callbackGeneration) else { return }
                        self.register(token: entryToken, box: box)
                    }
                }
                let unregister: @MainActor @Sendable (Bool) -> Void = { [weak self] succeeded in
                    guard let self, self.lifecycle.accepts(callbackGeneration) else { return }
                    self.unregister(token: entryToken, succeeded: succeeded)
                }
                return {
                    // Connection is torn down after unpublish; read values synchronously here before hopping to the main thread.
                    let succeeded = box.progress.isFinished
                        || box.progress.fractionCompleted >= 0.999
                    // Keep teardown on the same serial queue as registration so a short-lived publication cannot finish first.
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated {
                            unregister(succeeded)
                        }
                    }
                }
            }
            subscriberTokens.append(token)
        }
    }

    public func stop() {
        lifecycle.stop()
        airDropObserver?.stop()
        airDropObserver = nil
        airDropTransfers.removeAll()
        for token in subscriberTokens { Progress.removeSubscriber(token) }
        subscriberTokens.removeAll()
        timer?.cancel()
        timer = nil
        finishedClearTask?.cancel()
        finishedClearTask = nil
        progressBoxes.removeAll()
        tracker.removeAll()
        snapshot = nil
        snapshots = []
    }
    private func register(token: UUID, box: ProgressBox) {
        let progress = box.progress
        let fileURL = box.publishedFileURL ?? Self.fileURL(for: progress)
        let operationKind = box.publishedFileOperationKind ?? progress.fileOperationKind
        let agent = BrowserDownloadAgentResolver.agent(forFileOperationKind: operationKind)
            ?? fileURL.flatMap { resolveAgent(forFileAt: $0) }
        let publishedFraction = Self.fraction(of: progress)
        let entry = BrowserDownloadTracker.Entry(
            fileURL: fileURL,
            agent: agent,
            fileName: fileURL.map(BrowserDownloadAgentResolver.displayFileName) ?? "下载",
            fraction: agent == .airDrop ? nil : publishedFraction,
            batchFraction: agent == .airDrop ? publishedFraction : nil,
            startedAt: Date()
        )
        progressBoxes[token] = box
        tracker.insert(token: token, entry: entry)
        startTimerIfNeeded()
        refresh()
    }

    private func unregister(token: UUID, succeeded: Bool) {
        progressBoxes.removeValue(forKey: token)
        if tracker.finish(token: token, succeeded: succeeded) {
            scheduleFinishedClear()
        }
        if !tracker.entries.values.contains(where: { $0.agent == .airDrop }) {
            airDropTransfers.removeAll()
        }
        if progressBoxes.isEmpty {
            timer?.cancel()
            timer = nil
        }
        refresh()
    }

    /// Returns nil when total size is unknown, to avoid staying stuck at 0% for a long time.
    private static func fraction(of progress: Progress) -> Double? {
        guard progress.totalUnitCount > 0 else { return nil }
        let fraction = progress.fractionCompleted
        return fraction.isFinite ? fraction : nil
    }

    /// `fileURL` is often nil at publication time; the real path is then carried in userInfo.
    private static func fileURL(for progress: Progress) -> URL? {
        progress.fileURL ?? progress.userInfo[.fileURLKey] as? URL
    }

    private func startTimerIfNeeded() {
        guard timer == nil else { return }
        timer = Timer.publish(every: pollInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.poll() }
            }
    }

    private func poll() {
        guard !progressBoxes.isEmpty else {
            timer?.cancel()
            timer = nil
            return
        }
        var runningBundleIdentifiers: Set<String>?
        for (token, box) in progressBoxes {
            let progress = box.progress
            let publishedFraction = Self.fraction(of: progress)
            if let agent = BrowserDownloadAgentResolver.agent(
                forFileOperationKind: progress.fileOperationKind
            ) {
                tracker.update(token: token, agent: agent)
            }
            // Update fileURL if it becomes available after initial registration
            let currentFileURL = Self.fileURL(for: progress)
            if let currentFileURL,
                let entry = tracker.entries[token],
                Self.shouldReplacePublishedFileURL(
                    entry.fileURL,
                    with: currentFileURL,
                    agent: entry.agent
                )
            {
                tracker.update(
                    token: token,
                    fileURL: currentFileURL,
                    fileName: BrowserDownloadAgentResolver.displayFileName(for: currentFileURL)
                )
            }
            // The temp file may appear on disk after progress is published; keep retrying while the source is unresolved.
            if tracker.entries[token]?.agent == nil,
                let fileURL = tracker.entries[token]?.fileURL {
                if runningBundleIdentifiers == nil {
                    runningBundleIdentifiers = Self.runningBundleIdentifiers()
                }
                tracker.update(
                    token: token,
                    agent: resolveAgent(
                        forFileAt: fileURL,
                        runningBundleIdentifiers: runningBundleIdentifiers ?? []
                    )
                )
            }
            guard let entry = tracker.entries[token] else { continue }
            if entry.agent == .airDrop {
                updateAirDropProgress(token: token, entry: entry, publishedFraction: publishedFraction)
            } else {
                tracker.update(token: token, fraction: publishedFraction)
            }
        }
        refresh()
    }

    nonisolated static func shouldReplacePublishedFileURL(
        _ existingURL: URL?,
        with currentURL: URL,
        agent: BrowserDownloadAgent?
    ) -> Bool {
        guard existingURL != currentURL else { return false }
        return agent != .airDrop || existingURL == nil
    }

    private func startAirDropObservation(callbackGeneration: UInt64) {
        let observer = AirDropTransferObserver(
            onUpdated: { [weak self] transfer in
                DispatchQueue.main.async { [weak self] in
                    MainActor.assumeIsolated {
                        guard let self, self.lifecycle.accepts(callbackGeneration) else { return }
                        self.airDropTransfers[transfer.identifier] = transfer
                        self.refreshAirDropProgress()
                        self.refresh()
                    }
                }
            }
        )
        guard observer.start() else { return }
        airDropObserver = observer
    }

    private func refreshAirDropProgress() {
        for (token, entry) in tracker.entries where entry.agent == .airDrop {
            updateAirDropProgress(token: token, entry: entry, publishedFraction: entry.batchFraction)
        }
    }

    private func updateAirDropProgress(
        token: UUID,
        entry: BrowserDownloadTracker.Entry,
        publishedFraction: Double?
    ) {
        guard let transferItem = airDropTransferItem(for: entry) else {
            tracker.update(token: token, fraction: nil)
            tracker.update(token: token, batchFraction: publishedFraction)
            return
        }
        tracker.update(
            token: token,
            batchFraction: publishedFraction ?? transferItem.batchFraction
        )
        tracker.update(
            token: token,
            fraction: AirDropItemProgressResolver.fraction(
                for: transferItem.item,
                progressFileURL: entry.fileURL.flatMap { temporaryFileURL(for: $0) ?? $0 },
                fileByteCount: { [fileManager] url in
                    AirDropItemProgressResolver.fileByteCount(at: url, fileManager: fileManager)
                }
            )
        )
    }

    private func airDropTransferItem(
        for entry: BrowserDownloadTracker.Entry
    ) -> (item: AirDropTransferItem, batchFraction: Double?)? {
        let candidates = airDropTransfers.values.flatMap { transfer in
            transfer.items
                .filter { $0.fileName == entry.fileName }
                .map { (item: $0, batchFraction: transfer.batchFraction) }
        }
        guard !candidates.isEmpty else { return nil }
        guard candidates.count > 1 else { return candidates[0] }
        guard let fileURL = entry.fileURL?.standardizedFileURL else { return nil }
        let matchingCandidates = candidates.filter {
            AirDropItemProgressResolver.privateFileURLs(for: $0.item).contains(fileURL)
        }
        return matchingCandidates.count == 1 ? matchingCandidates[0] : nil
    }

    private func scheduleFinishedClear() {
        finishedClearTask?.cancel()
        let sleeper = holdSleeper
        let duration = Self.finishedHoldDuration
        let callbackGeneration = lifecycle.generation
        finishedClearTask = Task { [weak self, sleeper] in
            do {
                try await sleeper(.seconds(duration))
            } catch {
                return
            }
            guard let self else { return }
            guard self.lifecycle.accepts(callbackGeneration) else { return }
            self.tracker.clearFinishedHold()
            self.refresh()
        }
    }

    private func refresh() {
        let nextSnapshots = tracker.snapshots
        if snapshots != nextSnapshots {
            snapshots = nextSnapshots
        }
        let next = tracker.snapshot
        guard snapshot?.displayKey != next?.displayKey else { return }
        snapshot = next
    }

    /// Quarantine gives a precise source; falls back to extension candidates intersected with running browsers when absent.
    private func resolveAgent(
        forFileAt url: URL,
        runningBundleIdentifiers: Set<String>? = nil
    ) -> BrowserDownloadAgent? {
        let tempURL = temporaryFileURL(for: url)
        if let name = QuarantineAgentReader.agentName(ofFileAt: tempURL ?? url),
            let agent = BrowserDownloadAgentResolver.agent(forQuarantineAgentName: name) {
            return agent
        }
        let tempExtension = (tempURL ?? url).pathExtension.lowercased()
        return BrowserDownloadAgentResolver.agent(
            forTempExtension: BrowserDownloadTempExtension(rawValue: tempExtension),
            runningBundleIdentifiers: runningBundleIdentifiers ?? Self.runningBundleIdentifiers()
        )
    }

    /// Progress is usually published with the final path; the temp file is a sibling in the same directory with an extension like `.crdownload`.
    private func temporaryFileURL(for url: URL) -> URL? {
        if BrowserDownloadTempExtension(rawValue: url.pathExtension.lowercased()) != nil {
            return url
        }
        for tempExtension in BrowserDownloadTempExtension.allCases {
            let candidate = url.appendingPathExtension(tempExtension.rawValue)
            if fileManager.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    private static func runningBundleIdentifiers() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }
}

private final class AirDropTransferObserver: NSObject, @unchecked Sendable {
    private static let frameworkPath = "/System/Library/PrivateFrameworks/Sharing.framework"
    private static let setDelegateSelector = NSSelectorFromString("setDelegate:")
    private static let activateSelector = NSSelectorFromString("activate")
    private static let invalidateSelector = NSSelectorFromString("invalidate")

    private let onUpdated: @Sendable (AirDropTransferSnapshot) -> Void
    private var observer: NSObject?

    init(onUpdated: @escaping @Sendable (AirDropTransferSnapshot) -> Void) {
        self.onUpdated = onUpdated
    }

    func start() -> Bool {
        guard observer == nil else { return true }
        guard Bundle(path: Self.frameworkPath)?.load() == true,
            let observerClass = NSClassFromString("SFAirDropTransferObserver") as? NSObject.Type
        else { return false }

        let observer = observerClass.init()
        guard observer.responds(to: Self.setDelegateSelector),
            observer.responds(to: Self.activateSelector),
            observer.responds(to: Self.invalidateSelector)
        else { return false }

        _ = observer.perform(Self.setDelegateSelector, with: self)
        _ = observer.perform(Self.activateSelector)
        self.observer = observer
        return true
    }

    func stop() {
        guard let observer else { return }
        _ = observer.perform(Self.invalidateSelector)
        _ = observer.perform(Self.setDelegateSelector, with: nil)
        self.observer = nil
    }

    deinit {
        stop()
    }

    @objc(updatedTransfer:)
    private func updatedTransfer(_ transfer: AnyObject) {
        guard let snapshot = Self.snapshot(from: transfer) else { return }
        onUpdated(snapshot)
    }

    private static func snapshot(from transfer: AnyObject) -> AirDropTransferSnapshot? {
        guard let identifier = identifier(from: transfer),
            let transferObject = transfer as? NSObject,
            let metadata = value(named: "metaData", from: transferObject) as? NSObject,
            let rawFiles = value(named: "rawFiles", from: metadata) as? NSArray
        else { return nil }

        let destinationURL = value(named: "customDestinationURL", from: transferObject) as? URL
        let completedURLs = (value(named: "completedURLs", from: transferObject) as? NSArray)?
            .compactMap { $0 as? URL } ?? []
        let progress = value(named: "transferProgress", from: transferObject) as? Progress
        let batchFraction: Double?
        if let progress, progress.totalUnitCount > 0, progress.fractionCompleted.isFinite {
            batchFraction = progress.fractionCompleted
        } else {
            batchFraction = nil
        }
        let items = AirDropTransferMetadataParser.items(
            from: rawFiles.map { $0 },
            destinationURL: destinationURL,
            completedURLs: completedURLs
        )
        guard !items.isEmpty else { return nil }
        return AirDropTransferSnapshot(
            identifier: identifier,
            batchFraction: batchFraction,
            items: items
        )
    }

    private static func identifier(from transfer: AnyObject) -> String? {
        guard let transferObject = transfer as? NSObject else { return nil }
        return value(named: "identifier", from: transferObject) as? String
    }

    private static func value(named name: String, from object: NSObject) -> AnyObject? {
        let selector = NSSelectorFromString(name)
        guard object.responds(to: selector) else { return nil }
        return object.perform(selector)?.takeUnretainedValue()
    }
}

/// `Progress` is not `Sendable`; this read-only box carries it across thread boundaries using only named accessors,
/// not `userInfo` enumeration (the publisher may mutate that dictionary concurrently).
private final class ProgressBox: @unchecked Sendable {
    let progress: Progress
    let publishedFileURL: URL?
    let publishedFileOperationKind: Progress.FileOperationKind?

    init(_ progress: Progress) {
        self.progress = progress
        publishedFileURL = progress.fileURL ?? progress.userInfo[.fileURLKey] as? URL
        publishedFileOperationKind = progress.fileOperationKind
    }
}
