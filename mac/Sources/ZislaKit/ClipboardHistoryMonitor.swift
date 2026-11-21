import AppKit

@MainActor
public final class ClipboardHistoryMonitor {
    public typealias CaptureHandler = @MainActor @Sendable (ClipboardHistoryContent, ClipboardSourceApp?) -> Void
    public typealias SourceAppProvider = @Sendable (Notification?) -> ClipboardSourceApp?
    public typealias SourceAppResolver = @MainActor (String) -> ClipboardSourceApp?

    public private(set) var isEnabled = false
    public var onContentCaptured: CaptureHandler?

    private let pasteboard: NSPasteboard
    private let pollInterval: TimeInterval
    private let workspaceNotificationCenter: NotificationCenter
    private let sourceAppProvider: SourceAppProvider
    private let sourceAppResolver: SourceAppResolver
    private var lastPasteboardChangeCount: Int?
    private var timer: Timer?
    private var applicationObserver: NSObjectProtocol?
    private var trackedSourceApp: ClipboardSourceApp?

    public init(
        pasteboard: NSPasteboard = .general,
        pollInterval: TimeInterval = 1,
        workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        sourceAppProvider: SourceAppProvider? = nil,
        sourceAppResolver: SourceAppResolver? = nil,
        onContentCaptured: CaptureHandler? = nil
    ) {
        self.pasteboard = pasteboard
        self.pollInterval = max(pollInterval, 0.25)
        self.workspaceNotificationCenter = workspaceNotificationCenter
        self.sourceAppProvider = sourceAppProvider ?? Self.currentSourceApp
        self.sourceAppResolver = sourceAppResolver ?? Self.resolveSourceApp
        self.onContentCaptured = onContentCaptured
    }

    isolated deinit {
        timer?.invalidate()
        if let applicationObserver {
            workspaceNotificationCenter.removeObserver(applicationObserver)
        }
    }

    public func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        if enabled {
            lastPasteboardChangeCount = pasteboard.changeCount
            trackedSourceApp = sourceAppProvider(nil)
            let sourceAppProvider = sourceAppProvider
            applicationObserver = workspaceNotificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let sourceApp = sourceAppProvider(notification)
                MainActor.assumeIsolated {
                    guard let self else { return }
                    // Activation already names the new app; capture pending content with the previous app first.
                    self.pollNow()
                    self.trackedSourceApp = sourceApp
                }
            }
            let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.pollNow() }
            }
            timer.tolerance = min(0.2, pollInterval / 2)
            self.timer = timer
            RunLoop.main.add(timer, forMode: .common)
        } else {
            timer?.invalidate()
            timer = nil
            lastPasteboardChangeCount = nil
            if let applicationObserver {
                workspaceNotificationCenter.removeObserver(applicationObserver)
                self.applicationObserver = nil
            }
            trackedSourceApp = nil
        }
    }

    public func pollNow() {
        guard isEnabled else { return }
        let changeCount = pasteboard.changeCount
        guard changeCount != lastPasteboardChangeCount else { return }
        lastPasteboardChangeCount = changeCount
        guard let content = ClipboardHistoryPasteboard.readContent(from: pasteboard) else { return }
        let sourceApp: ClipboardSourceApp?
        if pasteboard.types?.contains(ClipboardHistoryPasteboard.sourceAppMarkerType) == true {
            sourceApp = ClipboardHistoryPasteboard.readSourceApp(from: pasteboard)
        } else if let bundleIdentifier = pasteboard.string(forType: ClipboardHistoryPasteboard.sourceAppType),
                  let resolved = sourceAppResolver(bundleIdentifier) {
            sourceApp = resolved
        } else {
            sourceApp = trackedSourceApp
        }
        onContentCaptured?(content, sourceApp)
    }

    nonisolated private static func currentSourceApp(_ notification: Notification?) -> ClipboardSourceApp? {
        let application: NSRunningApplication?
        if let notification {
            application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        } else {
            application = NSWorkspace.shared.frontmostApplication
        }
        return sourceApp(for: application)
    }

    private static func resolveSourceApp(_ bundleIdentifier: String) -> ClipboardSourceApp? {
        sourceApp(for: NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first)
    }

    nonisolated private static func sourceApp(for application: NSRunningApplication?) -> ClipboardSourceApp? {
        guard let application,
              let bundleIdentifier = application.bundleIdentifier,
              let name = application.localizedName else { return nil }
        return ClipboardSourceApp(bundleIdentifier: bundleIdentifier, name: name)
    }
}
