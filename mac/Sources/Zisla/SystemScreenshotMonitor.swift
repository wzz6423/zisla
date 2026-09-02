import AppKit
import Darwin
import Foundation

struct SystemScreenshotSession {
    private static let bundleIdentifiers: Set<String> = [
        "com.apple.screenshot.launcher",
        "com.apple.screencaptureui",
    ]

    static let defaultMissingWindowPollLimit = 3

    private let missingWindowPollLimit: Int
    private(set) var activeProcessIdentifiers: Set<pid_t> = []
    private(set) var isActive = false
    private var consecutiveMissingWindowPolls = 0

    init(missingWindowPollLimit: Int = Self.defaultMissingWindowPollLimit) {
        self.missingWindowPollLimit = max(1, missingWindowPollLimit)
    }

    static func matches(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return Self.bundleIdentifiers.contains(bundleIdentifier)
    }

    mutating func applicationStarted(processIdentifier: pid_t) -> Bool {
        guard processIdentifier > 0 else { return false }
        activeProcessIdentifiers.insert(processIdentifier)
        consecutiveMissingWindowPolls = 0
        return setActive(true)
    }

    mutating func applicationTerminated(processIdentifier: pid_t) {
        activeProcessIdentifiers.remove(processIdentifier)
    }

    mutating func updateWindowVisibility(_ visible: Bool, hasRunningProcess: Bool) -> Bool {
        if visible {
            consecutiveMissingWindowPolls = 0
            return setActive(true)
        }

        if hasRunningProcess {
            consecutiveMissingWindowPolls = 0
            return setActive(true)
        }

        consecutiveMissingWindowPolls += 1
        guard consecutiveMissingWindowPolls >= missingWindowPollLimit else { return false }
        activeProcessIdentifiers.removeAll()
        return setActive(false)
    }

    mutating func stop() -> Bool {
        activeProcessIdentifiers.removeAll()
        consecutiveMissingWindowPolls = 0
        return setActive(false)
    }

    private mutating func setActive(_ active: Bool) -> Bool {
        guard isActive != active else { return false }
        isActive = active
        return true
    }
}

struct SystemScreenshotWindowCandidate: Equatable, Sendable {
    let ownerProcessIdentifier: pid_t
    let alpha: Double
    let bounds: CGRect
    let ownerBundleIdentifier: String?
    let ownerProcessIsRunning: Bool

    init(
        ownerProcessIdentifier: pid_t,
        alpha: Double,
        bounds: CGRect,
        ownerBundleIdentifier: String? = nil,
        ownerProcessIsRunning: Bool = false
    ) {
        self.ownerProcessIdentifier = ownerProcessIdentifier
        self.alpha = alpha
        self.bounds = bounds
        self.ownerBundleIdentifier = ownerBundleIdentifier
        self.ownerProcessIsRunning = ownerProcessIsRunning
    }
}

enum SystemScreenshotWindowDetector {
    static func isEligibleOwner(
        processIdentifier: pid_t,
        ownedBy processIdentifiers: Set<pid_t>,
        currentBundleIdentifier: String?,
        processIsRunning: Bool
    ) -> Bool {
        guard processIdentifiers.contains(processIdentifier) else { return false }
        guard processIsRunning else { return true }
        return SystemScreenshotSession.matches(bundleIdentifier: currentBundleIdentifier)
    }

    static func hasVisibleSystemScreenshotWindow(
        _ candidates: [SystemScreenshotWindowCandidate],
        ownedBy processIdentifiers: Set<pid_t>
    ) -> Bool {
        candidates.contains {
            isEligibleOwner(
                processIdentifier: $0.ownerProcessIdentifier,
                ownedBy: processIdentifiers,
                currentBundleIdentifier: $0.ownerBundleIdentifier,
                processIsRunning: $0.ownerProcessIsRunning
            )
                && $0.alpha > 0.01
                && $0.bounds.width > 1
                && $0.bounds.height > 1
        }
    }
}

@MainActor
final class SystemScreenshotMonitor {
    static let pollInterval: Duration = .milliseconds(100)

    private let workspace: NSWorkspace
    private let notificationCenter: NotificationCenter
    private var session = SystemScreenshotSession()
    private var launchObserver: NSObjectProtocol?
    private var activationObserver: NSObjectProtocol?
    private var terminationObserver: NSObjectProtocol?
    private var windowPollingTask: Task<Void, Never>?
    private var isMonitoring = false
    private var monitorGeneration: UInt64 = 0

    var onSystemScreenshotStateChanged: ((Bool) -> Void)?

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
        notificationCenter = workspace.notificationCenter
    }

    func start() {
        guard !isMonitoring,
              launchObserver == nil,
              activationObserver == nil,
              terminationObserver == nil else { return }
        monitorGeneration &+= 1
        let generation = monitorGeneration
        isMonitoring = true
        launchObserver = observe(
            NSWorkspace.didLaunchApplicationNotification,
            handler: Self.processIdentifier(from:),
            generation: generation
        ) { [weak self] processIdentifier in
            self?.applicationStarted(processIdentifier: processIdentifier, generation: generation)
        }
        activationObserver = observe(
            NSWorkspace.didActivateApplicationNotification,
            handler: Self.processIdentifier(from:),
            generation: generation
        ) { [weak self] processIdentifier in
            self?.applicationStarted(processIdentifier: processIdentifier, generation: generation)
        }
        terminationObserver = observe(
            NSWorkspace.didTerminateApplicationNotification,
            handler: Self.processIdentifier(from:),
            generation: generation
        ) { [weak self] processIdentifier in
            self?.applicationTerminated(processIdentifier: processIdentifier, generation: generation)
        }
        for application in workspace.runningApplications where SystemScreenshotSession.matches(bundleIdentifier: application.bundleIdentifier) {
            applicationStarted(processIdentifier: application.processIdentifier, generation: generation)
        }
    }

    func stop() {
        isMonitoring = false
        monitorGeneration &+= 1
        [launchObserver, activationObserver, terminationObserver].compactMap { $0 }.forEach(notificationCenter.removeObserver)
        launchObserver = nil
        activationObserver = nil
        terminationObserver = nil
        windowPollingTask?.cancel()
        windowPollingTask = nil
        publishIfNeeded(session.stop())
    }

    private func observe(
        _ name: NSNotification.Name,
        handler: @escaping @Sendable (Notification) -> pid_t?,
        generation: UInt64,
        onProcessIdentifier: @escaping @MainActor (pid_t) -> Void
    ) -> NSObjectProtocol {
        notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
            guard let processIdentifier = handler(notification) else { return }
            Task { @MainActor [weak self] in
                guard let self,
                      self.isMonitoring,
                      self.monitorGeneration == generation else { return }
                onProcessIdentifier(processIdentifier)
            }
        }
    }

    nonisolated private static func processIdentifier(from notification: Notification) -> pid_t? {
        guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              SystemScreenshotSession.matches(bundleIdentifier: application.bundleIdentifier),
              application.processIdentifier > 0
        else { return nil }
        return application.processIdentifier
    }

    private func applicationStarted(processIdentifier: pid_t, generation: UInt64) {
        guard isMonitoring, monitorGeneration == generation else { return }
        publishIfNeeded(session.applicationStarted(processIdentifier: processIdentifier))
        startWindowPolling(generation: generation)
    }

    private func applicationTerminated(processIdentifier: pid_t, generation: UInt64) {
        guard isMonitoring, monitorGeneration == generation else { return }
        session.applicationTerminated(processIdentifier: processIdentifier)
    }

    private func startWindowPolling(generation: UInt64) {
        guard isMonitoring, monitorGeneration == generation, windowPollingTask == nil else { return }
        windowPollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self,
                      self.isMonitoring,
                      self.monitorGeneration == generation else { return }
                let processIdentifiers = self.session.activeProcessIdentifiers
                let snapshot = await Task.detached(priority: .utility) {
                    let hasRunningProcess = Self.hasAnyProcessRunning(processIdentifiers)
                    let candidates = hasRunningProcess
                        ? []
                        : Self.onScreenWindowCandidates(ownedBy: processIdentifiers)
                    return (hasRunningProcess, candidates)
                }.value
                guard !Task.isCancelled,
                      self.isMonitoring,
                      self.monitorGeneration == generation else { return }
                self.refreshWindowVisibility(
                    hasRunningProcess: snapshot.0,
                    candidates: snapshot.1,
                    generation: generation
                )
                do {
                    try await Task.sleep(for: Self.pollInterval)
                } catch {
                    return
                }
            }
        }
    }

    private func refreshWindowVisibility(
        hasRunningProcess: Bool,
        candidates: [SystemScreenshotWindowCandidate],
        generation: UInt64
    ) {
        guard isMonitoring, monitorGeneration == generation else { return }
        let hasVisibleWindow = !hasRunningProcess && SystemScreenshotWindowDetector.hasVisibleSystemScreenshotWindow(
            candidates,
            ownedBy: session.activeProcessIdentifiers
        )
        publishIfNeeded(session.updateWindowVisibility(hasVisibleWindow, hasRunningProcess: hasRunningProcess))
        if session.activeProcessIdentifiers.isEmpty, !session.isActive {
            windowPollingTask?.cancel()
            windowPollingTask = nil
        }
    }

    nonisolated private static func hasAnyProcessRunning(_ processIdentifiers: Set<pid_t>) -> Bool {
        processIdentifiers.contains { processIdentifier in
            guard let application = NSRunningApplication(processIdentifier: processIdentifier) else { return false }
            return SystemScreenshotSession.matches(bundleIdentifier: application.bundleIdentifier)
        }
    }

    nonisolated private static func onScreenWindowCandidates(
        ownedBy processIdentifiers: Set<pid_t>
    ) -> [SystemScreenshotWindowCandidate] {
        guard !processIdentifiers.isEmpty,
              let windows = CGWindowListCopyWindowInfo(
                  [.optionOnScreenOnly, .excludeDesktopElements],
                  kCGNullWindowID
              ) as? [[String: Any]]
        else { return [] }

        return windows.compactMap { window in
            guard let processIdentifier = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value else {
                return nil
            }
            let application = NSRunningApplication(processIdentifier: processIdentifier)
            guard SystemScreenshotWindowDetector.isEligibleOwner(
                processIdentifier: processIdentifier,
                ownedBy: processIdentifiers,
                currentBundleIdentifier: application?.bundleIdentifier,
                processIsRunning: application != nil
            ) else { return nil }
            guard
                  let boundsDictionary = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary)
            else { return nil }
            return SystemScreenshotWindowCandidate(
                ownerProcessIdentifier: processIdentifier,
                alpha: (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1,
                bounds: bounds,
                ownerBundleIdentifier: application?.bundleIdentifier,
                ownerProcessIsRunning: application != nil
            )
        }
    }

    private func publishIfNeeded(_ didChange: Bool) {
        guard didChange else { return }
        onSystemScreenshotStateChanged?(session.isActive)
    }
}
