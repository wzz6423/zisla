import AppKit
import Foundation

/// An installed application that clipboard text can resolve to.
public struct InstalledApplication: Equatable, Sendable {
    public var bundleIdentifier: String
    /// Name shown in the assistant toast, preferring the system-localized one.
    public var displayName: String
    /// Normalized names the copied text is matched against: the localized display
    /// name, the bundle name, and the `.app` file name without extension.
    public var matchKeys: Set<String>

    public init(bundleIdentifier: String, displayName: String, matchKeys: Set<String>) {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.matchKeys = matchKeys
    }
}

/// Indexes locally installed applications so copied names like "Safari" or "访达"
/// can offer a launch action. Scanning runs on a background queue and publishes
/// snapshots through `start(onUpdate:)`. Between scans the app directories are
/// watched cheaply via top-level modification dates, so newly installed or
/// removed applications are picked up without rereading every Info.plist.
public final class InstalledApplicationCatalog: @unchecked Sendable {
    public static let shared = InstalledApplicationCatalog()

    private let lock = NSLock()
    private var applications: [InstalledApplication] = []
    private var directorySignatures: [String: DirectorySignature] = [:]
    private var updateHandler: (@MainActor ([InstalledApplication]) -> Void)?
    private var monitorTimer: DispatchSourceTimer?
    private let scanDirectories: [URL]
    private let scanQueue: DispatchQueue

    /// Interval between cheap directory-signature checks.
    static let monitorInterval: TimeInterval = 30

    struct DirectorySignature: Equatable {
        var modificationDate: Date?
        var entryCount: Int
    }

    /// Top-level directories that hold application bundles, user locations first
    /// so a user-installed copy wins when several share a name.
    public static var defaultScanDirectories: [URL] {
        var directories = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/Applications/Utilities"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Applications/Utilities"),
            URL(fileURLWithPath: "/System/Library/CoreServices"),
        ]
        directories.append(
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications", isDirectory: true)
        )
        return directories
    }

    public init(
        scanDirectories: [URL] = InstalledApplicationCatalog.defaultScanDirectories,
        scanQueue: DispatchQueue = DispatchQueue(
            label: "dev.wzz.zisla.installed-application-catalog", qos: .utility
        )
    ) {
        self.scanDirectories = scanDirectories
        self.scanQueue = scanQueue
    }

    /// Latest published snapshot; empty until the first scan finishes.
    public var currentApplications: [InstalledApplication] {
        lock.lock()
        defer { lock.unlock() }
        return applications
    }

    /// Subscribes to snapshot updates (delivered on the main actor), kicks off an
    /// immediate scan, and starts the periodic directory watch. Safe to call
    /// repeatedly; the latest handler wins.
    public func start(onUpdate: @escaping @MainActor ([InstalledApplication]) -> Void) {
        lock.lock()
        updateHandler = onUpdate
        lock.unlock()
        startMonitorIfNeeded()
        scanQueue.async { [weak self] in
            self?.scanIfNeeded(force: true)
        }
    }

    /// Requests a scan that skips work when the watched directories are unchanged.
    public func refresh() {
        scanQueue.async { [weak self] in
            self?.scanIfNeeded(force: false)
        }
    }

    /// Exact, case/diacritic/full-width-insensitive lookup of copied text against
    /// the provided snapshot. Pure function — callers pass the snapshot they hold.
    public static func application(
        named text: String,
        in applications: [InstalledApplication]
    ) -> InstalledApplication? {
        let key = matchKey(for: text)
        guard !key.isEmpty else { return nil }
        return applications.first { $0.matchKeys.contains(key) }
    }

    /// Normalization shared by copied text and indexed application names.
    public static func matchKey(for name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    // MARK: - Scanning

    private func startMonitorIfNeeded() {
        lock.lock()
        guard monitorTimer == nil else {
            lock.unlock()
            return
        }
        let timer = DispatchSource.makeTimerSource(queue: scanQueue)
        timer.schedule(deadline: .now() + Self.monitorInterval, repeating: Self.monitorInterval)
        timer.setEventHandler { [weak self] in
            self?.scanIfNeeded(force: false)
        }
        timer.resume()
        monitorTimer = timer
        lock.unlock()
    }

    private func scanIfNeeded(force: Bool) {
        let directories = scanDirectories
        let signatures = Self.directorySignatures(for: directories)
        lock.lock()
        let known = directorySignatures
        lock.unlock()
        guard force || signatures != known else { return }

        let applications = Self.scanApplications(directories: directories)
        lock.lock()
        directorySignatures = signatures
        self.applications = applications
        let handler = updateHandler
        lock.unlock()
        if let handler {
            Task { @MainActor in handler(applications) }
        }
    }

    static func directorySignatures(for directories: [URL]) -> [String: DirectorySignature] {
        var signatures: [String: DirectorySignature] = [:]
        for directory in directories {
            let path = directory.path
            let attributes = try? FileManager.default.attributesOfItem(atPath: path)
            let modificationDate = attributes?[.modificationDate] as? Date
            let entryCount = (try? FileManager.default.contentsOfDirectory(atPath: path).count) ?? 0
            signatures[path] = DirectorySignature(
                modificationDate: modificationDate,
                entryCount: entryCount
            )
        }
        return signatures
    }

    static func scanApplications(directories: [URL]) -> [InstalledApplication] {
        var applications: [InstalledApplication] = []
        var seenBundleIdentifiers = Set<String>()
        for directory in directories {
            let contents = (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
            )) ?? []
            for url in contents where url.pathExtension == "app" {
                guard let application = installedApplication(at: url) else { continue }
                if seenBundleIdentifiers.insert(application.bundleIdentifier).inserted {
                    applications.append(application)
                }
            }
        }
        return applications
    }

    static func installedApplication(at url: URL) -> InstalledApplication? {
        let bundle = Bundle(url: url)
        guard let bundleIdentifier = bundle?.bundleIdentifier, !bundleIdentifier.isEmpty else {
            return nil
        }
        let info = bundle?.infoDictionary ?? [:]
        let localizedInfo = bundle?.localizedInfoDictionary ?? [:]
        let fileBaseName = url.deletingPathExtension().lastPathComponent
        // Localized display names come first so the toast reads in the system
        // language; the remaining candidates widen what copied text can match.
        let candidates = [
            localizedInfo["CFBundleDisplayName"] as? String,
            localizedInfo["CFBundleName"] as? String,
            info["CFBundleDisplayName"] as? String,
            info["CFBundleName"] as? String,
            fileBaseName,
        ].compactMap { $0 }
        guard let displayName = candidates.first else { return nil }
        return InstalledApplication(
            bundleIdentifier: bundleIdentifier,
            displayName: displayName,
            matchKeys: Set(candidates.map(matchKey(for:)))
        )
    }
}
