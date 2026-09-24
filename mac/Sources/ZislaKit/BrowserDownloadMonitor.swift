import AppKit
import Combine
import Foundation
import ZislaCore

public extension FeatureSettings {
    var showsBrowserDownloadProgress: Bool {
        sideNoticesEnabled && browserDownloadIslandEnabled
    }

    var observesBrowserDownloads: Bool {
        showsBrowserDownloadProgress || clipboardAssistantEnabled
    }
}

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
struct AirDropBatch: Sendable {
    var id: UUID
    var fileNames: [String]
    var fraction: Double?
    var startedAt: Date

    var snapshot: BrowserDownloadSnapshot {
        BrowserDownloadSnapshot(
            id: id,
            agent: .airDrop,
            fileName: fileNames.count == 1 ? fileNames[0] : AppLocalization.text("%ld 项下载", fileNames.count),
            fraction: fraction,
            isFinished: false
        )
    }
}

enum AirDropBatchParser {
    static func batches(from data: Data) -> [AirDropBatch]? {
        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let received = payload["receiveTransfers"] as? [[String: Any]]
        else { return nil }
        // Swift encodes this UUID-keyed dictionary as alternating keys and transfer values.
        return received.compactMap { transfer in
            guard let identifier = (transfer["receiveID"] as? String).flatMap(UUID.init(uuidString:)),
                let request = transfer["askRequest"] as? [String: Any],
                let items = request["items"] as? [[String: Any]],
                let state = transfer["state"] as? [String: Any],
                let receiving = state["transferring"] as? [String: Any]
            else { return nil }
            let fileNames = items.compactMap { $0["fileName"] as? String }
            guard !fileNames.isEmpty else { return nil }
            let progress = (receiving["progress"] as? [String: Any])?["transferring"] as? [String: Any]
            let total = (progress?["totalBytes"] as? NSNumber)?.doubleValue ?? 0
            let completed = (progress?["bytesCopied"] as? NSNumber)?.doubleValue
            return AirDropBatch(
                id: identifier,
                fileNames: fileNames,
                fraction: total > 0 ? completed.map { $0 / total } : nil,
                startedAt: Date(timeIntervalSinceReferenceDate: (transfer["startDate"] as? Double) ?? 0)
            )
        }
    }
}

/// State machine for download cards and the compact-island summary.
struct BrowserDownloadTracker: Sendable {
    struct Entry: Sendable {
        var fileURL: URL?
        var agent: BrowserDownloadAgent?
        var fileName: String
        var fraction: Double?
        var startedAt: Date
    }

    private(set) var entries: [UUID: Entry] = [:]
    private var airDropBatches: [AirDropBatch] = []
    private var airDropSummaryID = UUID()
    private var airDropItemCount = 0
    private var finishedSnapshot: BrowserDownloadSnapshot?

    var snapshots: [BrowserDownloadSnapshot] {
        var cards = entries.compactMap { token, entry -> (BrowserDownloadSnapshot, Date)? in
            guard entry.agent != .airDrop else { return nil }
            return (
                BrowserDownloadSnapshot(
                    id: token, agent: entry.agent, fileName: entry.fileName,
                    fraction: entry.fraction, isFinished: false
                ),
                entry.startedAt
            )
        }
        if !airDropBatches.isEmpty {
            cards += airDropBatches.map { ($0.snapshot, $0.startedAt) }
        } else {
            let airDropEntries = entries.values.filter { $0.agent == .airDrop }
            if let latest = airDropEntries.max(by: { $0.startedAt < $1.startedAt }) {
                let fractions = airDropEntries.compactMap(\.fraction)
                // Repeated copies of one batch must not lose a percentage point through summation error.
                let fraction = fractions.first.map { baseline in
                    baseline + fractions.reduce(0) { $0 + ($1 - baseline) } / Double(fractions.count)
                }
                cards.append((
                    BrowserDownloadSnapshot(
                        id: airDropSummaryID,
                        agent: .airDrop,
                        fileName: airDropItemCount == 1 ? latest.fileName : AppLocalization.text("%ld 项下载", airDropItemCount),
                        fraction: fraction,
                        isFinished: false
                    ),
                    latest.startedAt
                ))
            }
        }
        let active = cards.sorted { $0.1 > $1.1 }.map(\.0)
        return active.isEmpty ? finishedSnapshot.map { [$0] } ?? [] : active
    }

    var uniqueAgents: [BrowserDownloadAgent] {
        var seen = Set<BrowserDownloadAgent>()
        return snapshots.compactMap(\.agent).filter { seen.insert($0).inserted }
    }

    var hasActiveAirDrop: Bool {
        !airDropBatches.isEmpty || entries.values.contains { $0.agent == .airDrop }
    }

    var activeAirDropBatchIDs: Set<UUID> { Set(airDropBatches.map(\.id)) }

    func airDropBatchID(for fileName: String) -> UUID? {
        let matches = airDropBatches.filter { $0.fileNames.contains(fileName) }
        return matches.count == 1 ? matches[0].id : nil
    }

    var snapshot: BrowserDownloadSnapshot? {
        let active = snapshots
        guard !active.isEmpty else { return nil }
        guard active.count > 1 else { return active[0] }
        let fractions = active.compactMap(\.fraction)
        return BrowserDownloadSnapshot(
            agent: nil,
            fileName: AppLocalization.text("%ld 项下载", active.count),
            fraction: fractions.isEmpty ? nil : fractions.reduce(0, +) / Double(fractions.count),
            isFinished: false
        )
    }

    mutating func insert(token: UUID, entry: Entry) {
        finishedSnapshot = nil
        entries[token] = entry
        if entry.agent == .airDrop { rememberAirDropItemCount() }
    }

    mutating func update(token: UUID, fraction: Double?) {
        entries[token]?.fraction = fraction
    }

    mutating func update(token: UUID, agent: BrowserDownloadAgent?) {
        guard let existing = entries[token], let agent, existing.agent != agent else { return }
        entries[token]?.agent = agent
        if agent == .airDrop { rememberAirDropItemCount() }
    }

    mutating func updateAirDropBatches(_ batches: [AirDropBatch]) {
        airDropBatches = batches
        if !batches.isEmpty { finishedSnapshot = nil }
    }

    mutating func update(token: UUID, fileURL: URL?, fileName: String?) {
        guard entries[token] != nil else { return }
        if let fileURL { entries[token]?.fileURL = fileURL }
        if let fileName { entries[token]?.fileName = fileName }
    }

    mutating func finish(token: UUID, succeeded: Bool) -> Bool {
        guard let entry = entries[token] else { return false }
        let batch = entry.agent == .airDrop
            ? airDropBatches.first(where: { $0.fileNames.contains(entry.fileName) })?.snapshot
                ?? snapshots.first(where: { $0.agent == .airDrop })
            : nil
        entries.removeValue(forKey: token)
        guard succeeded else { return false }
        finishedSnapshot = BrowserDownloadSnapshot(
            id: batch?.id ?? token,
            agent: entry.agent,
            fileName: batch?.fileName ?? entry.fileName,
            fraction: 1,
            isFinished: true
        )
        return true
    }

    mutating func clearFinishedHold() { finishedSnapshot = nil }

    mutating func removeAll() {
        entries.removeAll()
        airDropBatches.removeAll()
        airDropItemCount = 0
        finishedSnapshot = nil
    }

    private mutating func rememberAirDropItemCount() {
        let count = entries.values.filter { $0.agent == .airDrop }.count
        if count == 1 {
            airDropSummaryID = UUID()
            airDropItemCount = 1
        } else {
            airDropItemCount = max(airDropItemCount, count)
        }
    }
}

public struct BrowserCompletedTransfer: Equatable, Sendable {
    public let id: UUID
    public let fileName: String
    public let directoryURL: URL
}

struct BrowserDownloadCompletionTracker {
    static let resolutionWindow: TimeInterval = 10

    private struct Candidate {
        var token: UUID
        var sourceURL: URL
        var agent: BrowserDownloadAgent
        var fileName: String
        var airDropBatchID: UUID?
        var resolutionStartedAt: Date?
    }

    private var candidates: [Candidate] = []

    var hasPending: Bool { !candidates.isEmpty }

    mutating func record(
        token: UUID,
        entry: BrowserDownloadTracker.Entry?,
        succeeded: Bool,
        airDropBatchID: UUID? = nil,
        at date: Date
    ) {
        guard succeeded, let entry, let agent = entry.agent,
            let url = entry.fileURL, url.isFileURL else { return }
        candidates.append(Candidate(
            token: token, sourceURL: url, agent: agent, fileName: entry.fileName,
            airDropBatchID: airDropBatchID,
            resolutionStartedAt: agent == .airDrop ? nil : date
        ))
    }

    mutating func resolve(
        at date: Date,
        directories: [URL],
        hasActiveAirDrop: Bool,
        activeAirDropBatchIDs: Set<UUID> = [],
        fileManager: FileManager = .default
    ) -> BrowserCompletedTransfer? {
        for index in candidates.indices.reversed() {
            let candidate = candidates[index]
            if candidate.agent == .airDrop {
                if let batchID = candidate.airDropBatchID {
                    guard !activeAirDropBatchIDs.contains(batchID) else { continue }
                } else {
                    guard !hasActiveAirDrop else { continue }
                }
            }
            let startedAt = candidate.resolutionStartedAt ?? date
            candidates[index].resolutionStartedAt = startedAt
            guard date.timeIntervalSince(startedAt) < Self.resolutionWindow else {
                candidates.remove(at: index)
                continue
            }
            guard let fileURL = completedFileURL(
                    for: candidate, directories: directories, fileManager: fileManager
                ) else { continue }
            candidates.removeSubrange(...index)
            return BrowserCompletedTransfer(
                id: candidate.token,
                fileName: fileURL.lastPathComponent,
                directoryURL: fileURL.deletingLastPathComponent()
            )
        }
        return nil
    }

    mutating func removeAll() {
        candidates.removeAll()
    }

    private func completedFileURL(
        for candidate: Candidate,
        directories: [URL],
        fileManager: FileManager
    ) -> URL? {
        let source = candidate.sourceURL.standardizedFileURL
        let isAirDropStaging = candidate.agent == .airDrop
            && source.pathComponents.contains { $0.hasPrefix("NSIRD_") }
        if isAirDropStaging, fileManager.fileExists(atPath: source.path) { return nil }
        if !isAirDropStaging {
            let finalURL = candidate.agent != .airDrop
                && BrowserDownloadTempExtension(rawValue: source.pathExtension.lowercased()) != nil
                ? source.deletingPathExtension() : source
            if fileManager.fileExists(atPath: finalURL.path) { return finalURL }
        }
        guard candidate.agent == .airDrop,
            candidate.fileName != "/",
            candidate.fileName == URL(fileURLWithPath: candidate.fileName).lastPathComponent
        else { return nil }
        return directories.lazy
            .map { $0.appendingPathComponent(candidate.fileName).standardizedFileURL }
            .first { fileManager.fileExists(atPath: $0.path) }
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
/// Modern AirDrop batches come from a read-only system event stream; public item publications provide a grouped fallback.
@MainActor
public final class BrowserDownloadMonitor: ObservableObject {
    /// How long the green checkmark stays visible after a successful download.
    public static let finishedHoldDuration: Double = 3

    @Published public private(set) var snapshot: BrowserDownloadSnapshot?
    @Published public private(set) var snapshots: [BrowserDownloadSnapshot] = []
    public var uniqueAgents: [BrowserDownloadAgent] { tracker.uniqueAgents }
    public var onCompletedTransfer: (@MainActor (BrowserCompletedTransfer) -> Void)?

    private var tracker = BrowserDownloadTracker()
    private var completionTracker = BrowserDownloadCompletionTracker()
    private var subscriberTokens: [Any] = []
    private var progressBoxes: [UUID: ProgressBox] = [:]
    private var airDropEventStream: AirDropTransferEventStream?
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
                let unregister: @MainActor @Sendable (Bool, URL?) -> Void = { [weak self] succeeded, fileURL in
                    guard let self, self.lifecycle.accepts(callbackGeneration) else { return }
                    self.unregister(token: entryToken, succeeded: succeeded, publishedFileURL: fileURL)
                }
                return {
                    // Connection is torn down after unpublish; read values synchronously here before hopping to the main thread.
                    let succeeded = Self.completedSuccessfully(box.progress)
                    let fileURL = box.progress.fileURL ?? box.progress.userInfo[.fileURLKey] as? URL
                    // Keep teardown on the same serial queue as registration so a short-lived publication cannot finish first.
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated {
                            unregister(succeeded, fileURL)
                        }
                    }
                }
            }
            subscriberTokens.append(token)
        }
    }

    public func stop() {
        lifecycle.stop()
        airDropEventStream?.stop()
        airDropEventStream = nil
        for token in subscriberTokens { Progress.removeSubscriber(token) }
        subscriberTokens.removeAll()
        timer?.cancel()
        timer = nil
        finishedClearTask?.cancel()
        finishedClearTask = nil
        progressBoxes.removeAll()
        tracker.removeAll()
        completionTracker.removeAll()
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
            fraction: publishedFraction,
            startedAt: Date()
        )
        progressBoxes[token] = box
        tracker.insert(token: token, entry: entry)
        startTimerIfNeeded()
        refresh()
    }

    private func unregister(token: UUID, succeeded: Bool, publishedFileURL: URL?) {
        if let publishedFileURL,
            let entry = tracker.entries[token],
            Self.shouldReplacePublishedFileURL(
                entry.fileURL, with: publishedFileURL, agent: entry.agent
            ) {
            tracker.update(
                token: token,
                fileURL: publishedFileURL,
                fileName: BrowserDownloadAgentResolver.displayFileName(for: publishedFileURL)
            )
        }
        completionTracker.record(
            token: token, entry: tracker.entries[token], succeeded: succeeded,
            airDropBatchID: tracker.entries[token].flatMap { tracker.airDropBatchID(for: $0.fileName) },
            at: Date()
        )
        progressBoxes.removeValue(forKey: token)
        if tracker.finish(token: token, succeeded: succeeded) {
            scheduleFinishedClear()
        }
        if progressBoxes.isEmpty && !completionTracker.hasPending {
            timer?.cancel()
            timer = nil
        }
        if completionTracker.hasPending { startTimerIfNeeded() }
        resolveCompletedTransfers()
        refresh()
    }

    nonisolated static func completedSuccessfully(_ progress: Progress) -> Bool {
        !progress.isCancelled && progress.isFinished
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
        guard !progressBoxes.isEmpty || completionTracker.hasPending else {
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
            tracker.update(token: token, fraction: publishedFraction)
        }
        refresh()
        resolveCompletedTransfers()
        if progressBoxes.isEmpty && !completionTracker.hasPending {
            timer?.cancel()
            timer = nil
        }
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
        let stream = AirDropTransferEventStream(onEvent: { [weak self] data in
            guard let self, self.lifecycle.accepts(callbackGeneration),
                let batches = AirDropBatchParser.batches(from: data)
            else { return }
            self.tracker.updateAirDropBatches(batches)
            self.resolveCompletedTransfers()
            self.refresh()
        }, onUnavailable: { [weak self] in
            guard let self, self.lifecycle.accepts(callbackGeneration) else { return }
            self.tracker.updateAirDropBatches([])
            self.resolveCompletedTransfers()
            self.refresh()
        })
        if stream.start() { airDropEventStream = stream }
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

    private func resolveCompletedTransfers() {
        if let transfer = completionTracker.resolve(
            at: Date(), directories: directories, hasActiveAirDrop: tracker.hasActiveAirDrop,
            activeAirDropBatchIDs: tracker.activeAirDropBatchIDs,
            fileManager: fileManager
        ) {
            onCompletedTransfer?(transfer)
        }
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
