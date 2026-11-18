import AppKit
import CoreGraphics
import ZislaCore

@MainActor
final class PermissionSettingsAssistant: NSObject, NSWindowDelegate {
    static let shared = PermissionSettingsAssistant()

    private let applicationURL: URL
    private let openURL: @MainActor (URL) -> Bool
    private let icon: @MainActor (URL) -> NSImage
    private let placement: @MainActor () -> (settingsFrame: CGRect?, visibleFrame: CGRect)
    private let orderFront: @MainActor (NSPanel) -> Void
    private let language: @MainActor () -> AppLanguage
    private var generation = UUID()
    private var awaitingSettings = false
    private(set) var panel: NSPanel?

    init(
        applicationURL: URL = Bundle.main.bundleURL,
        openURL: @escaping @MainActor (URL) -> Bool = { NSWorkspace.shared.open($0) },
        icon: @escaping @MainActor (URL) -> NSImage = { NSWorkspace.shared.icon(forFile: $0.path) },
        placement: @escaping @MainActor () -> (settingsFrame: CGRect?, visibleFrame: CGRect) = PermissionSettingsAssistant.currentPlacement,
        orderFront: @escaping @MainActor (NSPanel) -> Void = { $0.orderFrontRegardless() },
        language: @escaping @MainActor () -> AppLanguage = { AppLocalization.currentLanguage },
        notificationCenter: NotificationCenter = .default,
        workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
    ) {
        self.applicationURL = applicationURL
        self.openURL = openURL
        self.icon = icon
        self.placement = placement
        self.orderFront = orderFront
        self.language = language
        super.init()
        notificationCenter.addObserver(self, selector: #selector(applicationDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification, object: nil)
        workspaceNotificationCenter.addObserver(self, selector: #selector(workspaceDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
    }

    static func supportsDragging(for id: OnboardingPermissionID) -> Bool {
        switch id {
        case .accessibility, .inputMonitoring, .screenRecording, .systemAudio, .fullDiskAccess: true
        default: false
        }
    }

    func openSettings(_ url: URL) -> Bool {
        dismiss()
        guard openURL(url) else { return false }
        guard let id = OnboardingPermissionID.allCases.first(where: { $0.settingsURL == url }),
              prepare(for: id) else { return true }
        let token = generation
        // Opening Settings can activate its window on the next run loop; keep the helper nonactivating.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.generation == token else { return }
            self.showPreparedAssistant()
        }
        return true
    }

    @discardableResult
    func prepare(for id: OnboardingPermissionID) -> Bool {
        dismiss()
        guard Self.supportsDragging(for: id), applicationURL.isFileURL,
              applicationURL.pathExtension.lowercased() == "app",
              FileManager.default.fileExists(atPath: applicationURL.path) else { return false }
        awaitingSettings = true
        return true
    }

    func dismiss() {
        generation = UUID()
        awaitingSettings = false
        panel?.close()
        panel = nil
    }

    func cancelPreparation() {
        awaitingSettings = false
    }

    func windowWillClose(_ notification: Notification) {
        generation = UUID()
        awaitingSettings = false
        panel = nil
    }

    @objc private func applicationDidBecomeActive() {
        if panel != nil { dismiss() }
    }

    @objc private func workspaceDidActivate(_ notification: Notification) {
        guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        if application.bundleIdentifier == "com.apple.systempreferences" {
            settingsDidActivate()
        } else if application.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            cancelPreparation()
        }
    }

    func settingsDidActivate() {
        if awaitingSettings { showPreparedAssistant() }
        else { reposition() }
    }

    private func showPreparedAssistant() {
        guard awaitingSettings else { return }
        awaitingSettings = false
        present()
    }

    private func present() {
        let currentLanguage = language()
        let instruction = AppLocalization.string("permission.drag_app.body", language: currentLanguage)
        let image = FileShelfDraggingView(frame: NSRect(x: 0, y: 0, width: 72, height: 72))
        image.payload = .file(applicationURL)
        image.image = icon(applicationURL)
        image.setAccessibilityLabel("zisla")
        image.setAccessibilityHelp(instruction)
        image.makeContextMenu = { NSMenu() }
        image.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([image.widthAnchor.constraint(equalToConstant: 72), image.heightAnchor.constraint(equalToConstant: 72)])

        let label = NSTextField(wrappingLabelWithString: instruction)
        label.baseWritingDirection = currentLanguage.isRightToLeft ? .rightToLeft : .leftToRight
        label.alignment = .center
        label.font = .systemFont(ofSize: NSFont.systemFontSize)
        label.textColor = .secondaryLabelColor
        label.preferredMaxLayoutWidth = 226

        let stack = NSStackView(views: [image, label])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
            stack.widthAnchor.constraint(equalToConstant: 226),
        ])
        content.layoutSubtreeIfNeeded()

        let helper = PermissionSettingsAssistantPanel(contentRect: NSRect(origin: .zero, size: content.fittingSize),
            styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel], backing: .buffered, defer: false)
        helper.title = AppLocalization.string("权限", language: currentLanguage)
        helper.contentView = content
        helper.isReleasedWhenClosed = false
        helper.hidesOnDeactivate = false
        helper.isMovableByWindowBackground = true
        helper.level = .floating
        helper.collectionBehavior = [.moveToActiveSpace, .transient, .ignoresCycle]
        helper.delegate = self
        panel = helper
        reposition()
        orderFront(helper)
    }

    func reposition() {
        guard let panel else { return }
        let destination = placement()
        panel.setFrame(Self.frame(size: panel.frame.size, settingsFrame: destination.settingsFrame,
            visibleFrame: destination.visibleFrame), display: true)
    }

    static func frame(size: CGSize, settingsFrame: CGRect?, visibleFrame: CGRect) -> CGRect {
        let gap: CGFloat = 12
        var result = CGRect(origin: CGPoint(x: visibleFrame.maxX - size.width - gap,
            y: visibleFrame.midY - size.height / 2), size: size)
        if let settingsFrame {
            result.origin.y = settingsFrame.midY - size.height / 2
            result.origin.x = settingsFrame.maxX + gap
            if result.maxX > visibleFrame.maxX - gap {
                result.origin.x = settingsFrame.minX - size.width - gap
            }
        }
        result.origin.x = max(visibleFrame.minX + gap, min(result.minX, visibleFrame.maxX - size.width - gap))
        result.origin.y = max(visibleFrame.minY + gap, min(result.minY, visibleFrame.maxY - size.height - gap))
        return result
    }

    private static func currentPlacement() -> (settingsFrame: CGRect?, visibleFrame: CGRect) {
        let settings = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences").first
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let settingsFrame = settings.flatMap {
            systemSettingsFrame(windowInfo: windows, processIdentifier: $0.processIdentifier, mainScreenTop: NSScreen.screens.first?.frame.maxY ?? 0)
        }
        let screen = settingsFrame.flatMap { frame in
            NSScreen.screens.first { $0.frame.contains(CGPoint(x: frame.midX, y: frame.midY)) }
        } ?? WindowPlacement.screenUnderMouse()
        return (settingsFrame, screen?.visibleFrame ?? .zero)
    }

    static func systemSettingsFrame(windowInfo: [[String: Any]], processIdentifier: pid_t, mainScreenTop: CGFloat) -> CGRect? {
        for window in windowInfo {
            guard (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == processIdentifier,
                  (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let dictionary = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dictionary as CFDictionary), bounds.width > 100, bounds.height > 100 else { continue }
            return CGRect(x: bounds.minX, y: mainScreenTop - bounds.maxY, width: bounds.width, height: bounds.height)
        }
        return nil
    }
}

@MainActor
private final class PermissionSettingsAssistantPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
