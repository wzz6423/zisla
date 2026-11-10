import AppKit
import ApplicationServices
import Foundation
import ZislaCore

@MainActor
public final class ApplicationOpenFailureMonitor {
    struct Alert {
        var identifier: Int
        var messages: [String]
        var applicationURLs: [URL]
    }

    struct Dependencies {
        var isTrusted: () -> Bool
        var processes: () -> [pid_t]
        var observeProcesses: (@escaping @MainActor () -> Void) -> () -> Void
        var observeAlerts: (pid_t, @escaping @MainActor (Alert) -> Void) -> (() -> Void)?
        var finderSelection: () -> [URL]
        var templates: () -> [String]
        var applicationNames: (URL) -> [String]
    }

    private let dependencies: Dependencies
    private var stopObservingProcesses: (() -> Void)?
    private var observers: [pid_t: () -> Void] = [:]
    private var seen: [String] = []
    private var generation = 0
    private var onApplication: ((URL) -> Void)?

    public convenience init() {
        self.init(dependencies: Self.liveDependencies)
    }

    init(dependencies: Dependencies) { self.dependencies = dependencies }

    isolated deinit { stop() }

    /// Requires existing Accessibility access; only an unambiguous system-alert target reaches the callback.
    public func setEnabled(_ enabled: Bool, onApplication: @escaping (URL) -> Void) {
        guard enabled, dependencies.isTrusted() else { stop(); return }
        self.onApplication = onApplication
        guard stopObservingProcesses == nil else { reconcile(); return }
        stopObservingProcesses = dependencies.observeProcesses { [weak self] in self?.reconcile() }
        reconcile()
    }

    public func stop() {
        generation += 1
        stopObservingProcesses?()
        stopObservingProcesses = nil
        for stop in observers.values { stop() }
        observers.removeAll()
        seen.removeAll()
        onApplication = nil
    }

    private func reconcile() {
        guard dependencies.isTrusted(), onApplication != nil else { stop(); return }
        let processes = Set(dependencies.processes())
        for pid in observers.keys where !processes.contains(pid) {
            observers.removeValue(forKey: pid)?()
            seen.removeAll { $0.hasPrefix("\(pid):") }
        }
        let generation = generation
        for pid in processes where observers[pid] == nil {
            observers[pid] = dependencies.observeAlerts(pid) { [weak self] alert in
                guard let self, generation == self.generation, self.onApplication != nil,
                      self.observers[pid] != nil else { return }
                guard self.dependencies.isTrusted() else { self.stop(); return }
                let candidates = alert.applicationURLs.isEmpty ? self.dependencies.finderSelection() : []
                guard let url = Self.application(for: alert, templates: self.dependencies.templates(),
                    candidates: candidates, names: self.dependencies.applicationNames) else { return }
                let key = "\(pid):\(alert.identifier):\(url.path)"
                guard !self.seen.contains(key) else { return }
                self.seen.append(key)
                if self.seen.count > 32 { self.seen.removeFirst() }
                self.onApplication?(url)
            }
        }
    }

    static func application(for alert: Alert, templates: [String], candidates: [URL], names: (URL) -> [String]) -> URL? {
        let matches = Set(alert.messages.flatMap { message in
            templates.compactMap { template -> String? in
                let parts = template.components(separatedBy: "%@")
                guard parts.count == 2, !parts[0].isEmpty || !parts[1].isEmpty,
                      message.hasPrefix(parts[0]), message.hasSuffix(parts[1]),
                      message.count > parts[0].count + parts[1].count else { return nil }
                return String(message.dropFirst(parts[0].count).dropLast(parts[1].count))
            }
        })
        guard matches.count == 1, let name = matches.first, name.count <= 256,
              !name.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) else { return nil }
        let urls = alert.applicationURLs.isEmpty ? candidates : alert.applicationURLs
        let applications = Set(urls.filter { $0.isFileURL && $0.pathExtension.lowercased() == "app" }
            .map(\.standardizedFileURL))
        guard applications.count == 1, let url = applications.first,
              names(url).contains(name) else { return nil }
        return url
    }

    private static let agentURL = URL(fileURLWithPath: "/System/Library/CoreServices/CoreServicesUIAgent.app")

    private static var liveDependencies: Dependencies {
        Dependencies(
            isTrusted: { AccessibilityPermission.isTrusted },
            processes: {
                NSWorkspace.shared.runningApplications.filter {
                    $0.bundleIdentifier == "com.apple.coreservices.uiagent" && $0.bundleURL == agentURL
                }.map(\.processIdentifier)
            },
            observeProcesses: { changed in
                // Running-application KVO includes LSUIElement agents omitted from launch notifications.
                let observation = NSWorkspace.shared.observe(\.runningApplications, options: [.new]) { _, _ in
                    Task { @MainActor in changed() }
                }
                return { observation.invalidate() }
            },
            observeAlerts: { pid, receive in
                guard let observer = AlertObserver(processIdentifier: pid, receive: receive) else { return nil }
                return { observer.stop() }
            },
            finderSelection: selectedFinderApplications,
            templates: {
                guard let bundle = Bundle(url: agentURL) else { return [] }
                // The installed system catalog follows the macOS language, independently of Zisla's language.
                return [
                    ("QuarantineHeadlines", "Q_HEADLINE_CASPIAN_BAD_SIGNATURE"),
                    ("QuarantineHeadlines", "Q_HEADLINE_CASPIAN_V1_SIGNATURE"),
                    ("QuarantineHeadlines", "Q_HEADLINE_CASPIAN_REVOKED"),
                    ("QuarantineHeadlines", "Q_HEADLINE_SUNFISH_NOT_VERIFIED"),
                    ("LaunchErrors", "-10827.message"), ("LaunchErrors", "-10810.message"),
                    ("LaunchErrors", "default.message"),
                ].map { bundle.localizedString(forKey: $0.1, value: nil, table: $0.0) }
            },
            applicationNames: { url in
                let bundle = Bundle(url: url)
                return [url.lastPathComponent, url.deletingPathExtension().lastPathComponent,
                    FileManager.default.displayName(atPath: url.path),
                    bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
                    bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String].compactMap { $0 }
            }
        )
    }

    private static func attribute(_ name: String, from element: AXUIElement) -> CFTypeRef? {
        AXUIElementSetMessagingTimeout(element, 0.02)
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    private static func applicationURL(_ value: CFTypeRef?) -> URL? {
        let url: URL?
        if let value = value as? URL { url = value }
        else if let value = value as? String, value.hasPrefix("file:") { url = URL(string: value) }
        else { url = nil }
        return url.flatMap { $0.isFileURL && $0.pathExtension.lowercased() == "app" ? $0 : nil }
    }

    private static func selectedFinderApplications() -> [URL] {
        guard let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first else { return [] }
        let application = AXUIElementCreateApplication(finder.processIdentifier)
        guard let value = attribute(kAXFocusedWindowAttribute, from: application),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return [] }
        var urls: [URL] = []
        walk(value as! AXUIElement, children: childElements) { element in
            for child in attribute(kAXSelectedChildrenAttribute, from: element) as? [AXUIElement] ?? [] {
                if let url = applicationURL(attribute(kAXURLAttribute, from: child)) { urls.append(url) }
            }
            if attribute(kAXSelectedAttribute, from: element) as? Bool == true,
               let url = applicationURL(attribute(kAXURLAttribute, from: element)) { urls.append(url) }
        }
        return urls
    }

    private static func childElements(_ element: AXUIElement) -> [AXUIElement] {
        var children: CFArray?
        AXUIElementSetMessagingTimeout(element, 0.02)
        guard AXUIElementCopyAttributeValues(element, kAXChildrenAttribute as CFString, 0, 64, &children) == .success else { return [] }
        return children as? [AXUIElement] ?? []
    }

    static func walk<Node>(_ root: Node, children: (Node) -> [Node],
                           now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
                           visit: (Node) -> Void) {
        var queue = [root]
        var index = 0
        let deadline = now() + 0.2
        while index < queue.count, now() < deadline {
            let element = queue[index]
            index += 1
            visit(element)
            queue.append(contentsOf: children(element).prefix(64 - queue.count))
        }
    }

    @MainActor
    private final class AlertObserver {
        private let observer: AXObserver
        private let application: AXUIElement
        private let receive: (Alert) -> Void

        init?(processIdentifier: pid_t, receive: @escaping (Alert) -> Void) {
            var observer: AXObserver?
            guard AXObserverCreate(processIdentifier, { _, _, _, context in
                guard let context else { return }
                MainActor.assumeIsolated {
                    Unmanaged<AlertObserver>.fromOpaque(context).takeUnretainedValue().readAlerts()
                }
            }, &observer) == .success, let observer else { return nil }
            self.observer = observer
            self.application = AXUIElementCreateApplication(processIdentifier)
            self.receive = receive
            let context = Unmanaged.passUnretained(self).toOpaque()
            guard AXObserverAddNotification(observer, application, kAXWindowCreatedNotification as CFString, context) == .success else { return nil }
            // The creation event can precede the alert text; subsequent title/focus events complete the snapshot.
            _ = AXObserverAddNotification(observer, application, kAXFocusedWindowChangedNotification as CFString, context)
            _ = AXObserverAddNotification(observer, application, kAXTitleChangedNotification as CFString, context)
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }

        func stop() { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }

        isolated deinit { stop() }

        private func readAlerts() {
            for window in (attribute(kAXWindowsAttribute, from: application) as? [AXUIElement] ?? []).prefix(4) {
                var alert = Alert(identifier: Int(truncatingIfNeeded: CFHash(window)), messages: [], applicationURLs: [])
                walk(window, children: childElements) { element in
                    if let title = attribute(kAXTitleAttribute, from: element) as? String { alert.messages.append(title) }
                    if attribute(kAXRoleAttribute, from: element) as? String == kAXStaticTextRole,
                       let value = attribute(kAXValueAttribute, from: element) as? String { alert.messages.append(value) }
                    for key in [kAXDocumentAttribute, kAXURLAttribute] {
                        if let url = applicationURL(attribute(key, from: element)) { alert.applicationURLs.append(url) }
                    }
                }
                receive(alert)
            }
        }
    }
}
