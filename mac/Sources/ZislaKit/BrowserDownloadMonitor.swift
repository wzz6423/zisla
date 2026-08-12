import AppKit
import Combine
import Foundation
import ZislaCore

/// Browser download source to display in the collapsed Dynamic Island.
public enum BrowserDownloadAgent: String, CaseIterable, Sendable {
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
        self.fraction = fraction.map { min(max($0, 0), 1) }
        self.isFinished = isFinished
    }

    /// Caps in-progress display at 99%, reserving 100% for the finished green checkmark so the two states look distinct.
    public var progressText: String {
        guard let fraction else { return isFinished ? "100%" : "…" }
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
        for agent in BrowserDownloadAgent.allCases where tokens.contains(agent.rawValue) {
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
            $0.bundleIdentifiers.contains(where: runningBundleIdentifiers.contains)
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
/// State machine for browser download display: manages entry insertion/removal and brief retention after completion; does not depend on `NSProgress`.
struct BrowserDownloadTracker: Sendable {
    struct Entry: Sendable {
        var fileURL: URL?
        var agent: BrowserDownloadAgent?
        var fileName: String
        var fraction: Double?
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

    /// 按最近下载优先顺序返回去重后的浏览器。
    var uniqueAgents: [BrowserDownloadAgent] {
        var seen = Set<BrowserDownloadAgent>()
        return snapshots.compactMap(\.agent).filter { seen.insert($0).inserted }
    }

    /// Multiple in-progress downloads are represented by one compact-island summary whose fraction is their arithmetic mean.
    var snapshot: BrowserDownloadSnapshot? {
        let active = snapshots
        guard !active.isEmpty else { return nil }
        if active.count == 1 { return active[0] }
        let knownFractions = active.compactMap(\.fraction)
        return BrowserDownloadSnapshot(
            agent: nil,
            fileName: "\(active.count) 项下载",
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
/// Monitors `NSProgress` published by browsers to the downloads directory and shows an icon and percentage in the collapsed Dynamic Island.
///
/// Uses the system's public progress-publishing mechanism (Chrome, Safari, etc. publish progress during downloads),
/// does not read browser history databases, and makes no network requests.
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
    private var timer: AnyCancellable?
    private var finishedClearTask: Task<Void, Never>?
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
        for directory in directories {
            let token = Progress.addSubscriber(forFileURL: directory) { [weak self] published in
                let entryToken = UUID()
                let box = ProgressBox(published)
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self?.register(token: entryToken, box: box) }
                }
                return {
                    // Connection is torn down after unpublish; read values synchronously here before hopping to the main thread.
                    let succeeded = box.progress.isFinished
                        || box.progress.fractionCompleted >= 0.999
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated {
                            self?.unregister(token: entryToken, succeeded: succeeded)
                        }
                    }
                }
            }
            subscriberTokens.append(token)
        }
    }

    public func stop() {
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
        // `fileURL` is often nil at publish time; the real path is in userInfo.
        let fileURL = progress.fileURL ?? progress.userInfo[.fileURLKey] as? URL
        let entry = BrowserDownloadTracker.Entry(
            fileURL: fileURL,
            agent: fileURL.flatMap { resolveAgent(forFileAt: $0) },
            fileName: fileURL.map(BrowserDownloadAgentResolver.displayFileName) ?? "下载",
            fraction: Self.fraction(of: progress),
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
        if progressBoxes.isEmpty {
            timer?.cancel()
            timer = nil
        }
        refresh()
    }

    /// Returns nil when total size is unknown, to avoid staying stuck at 0% for a long time.
    private static func fraction(of progress: Progress) -> Double? {
        guard progress.totalUnitCount > 0 else { return nil }
        return progress.fractionCompleted
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
        for (token, box) in progressBoxes {
            tracker.update(token: token, fraction: Self.fraction(of: box.progress))
            // The temp file may appear on disk after progress is published; keep retrying while the source is unresolved.
            if tracker.entries[token]?.agent == nil,
                let fileURL = tracker.entries[token]?.fileURL {
                tracker.update(token: token, agent: resolveAgent(forFileAt: fileURL))
            }
        }
        refresh()
    }

    private func scheduleFinishedClear() {
        finishedClearTask?.cancel()
        let sleeper = holdSleeper
        let duration = Self.finishedHoldDuration
        finishedClearTask = Task { [weak self, sleeper] in
            do {
                try await sleeper(.seconds(duration))
            } catch {
                return
            }
            guard let self else { return }
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
    private func resolveAgent(forFileAt url: URL) -> BrowserDownloadAgent? {
        let tempURL = temporaryFileURL(for: url)
        if let name = QuarantineAgentReader.agentName(ofFileAt: tempURL ?? url),
            let agent = BrowserDownloadAgentResolver.agent(forQuarantineAgentName: name) {
            return agent
        }
        let tempExtension = (tempURL ?? url).pathExtension.lowercased()
        return BrowserDownloadAgentResolver.agent(
            forTempExtension: BrowserDownloadTempExtension(rawValue: tempExtension),
            runningBundleIdentifiers: Self.runningBundleIdentifiers()
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

    init(_ progress: Progress) {
        self.progress = progress
    }
}
