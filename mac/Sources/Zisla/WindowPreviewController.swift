import AppKit
import ApplicationServices
import ScreenCaptureKit
import SwiftUI
import ZislaKit

enum WindowPreviewSource {
    case dock
    case switcher
}

struct WindowPreviewLayout {
    static func quartzPoint(for appKitPoint: CGPoint, mainScreenTop: CGFloat) -> CGPoint {
        CGPoint(x: appKitPoint.x, y: mainScreenTop - appKitPoint.y)
    }

    static func appKitFrame(for quartzFrame: CGRect, mainScreenTop: CGFloat) -> CGRect {
        CGRect(
            x: quartzFrame.minX,
            y: mainScreenTop - quartzFrame.maxY,
            width: quartzFrame.width,
            height: quartzFrame.height
        )
    }

    static func frame(
        anchor: CGRect,
        size: CGSize,
        visibleFrame: CGRect,
        isSwitcher: Bool
    ) -> CGRect {
        let gap: CGFloat = 10
        let center = CGPoint(x: anchor.midX, y: anchor.midY)
        let origin: CGPoint
        if isSwitcher {
            let above = anchor.maxY + gap
            let y = above + size.height <= visibleFrame.maxY
                ? above : anchor.minY - size.height - gap
            origin = CGPoint(x: center.x - size.width / 2, y: y)
        } else {
            let distances = [
                anchor.minY - visibleFrame.minY,
                visibleFrame.maxY - anchor.maxY,
                anchor.minX - visibleFrame.minX,
                visibleFrame.maxX - anchor.maxX,
            ]
            switch distances.enumerated().min(by: { $0.element < $1.element })?.offset {
            case 1:
                origin = CGPoint(x: center.x - size.width / 2, y: anchor.minY - size.height - gap)
            case 2:
                origin = CGPoint(x: anchor.maxX + gap, y: center.y - size.height / 2)
            case 3:
                origin = CGPoint(x: anchor.minX - size.width - gap, y: center.y - size.height / 2)
            default:
                origin = CGPoint(x: center.x - size.width / 2, y: anchor.maxY + gap)
            }
        }
        return CGRect(
            x: min(max(origin.x, visibleFrame.minX), visibleFrame.maxX - size.width),
            y: min(max(origin.y, visibleFrame.minY), visibleFrame.maxY - size.height),
            width: size.width,
            height: size.height
        )
    }
}

struct WindowPreviewSelection {
    let processIdentifier: pid_t
    let appName: String
    let icon: NSImage?
    let anchor: CGRect
    let source: WindowPreviewSource
}

struct WindowPreviewSnapshot: Identifiable {
    let id: CGWindowID
    let title: String
    let frame: CGRect
    let image: NSImage?
}

struct WindowPreviewWindowMatch {
    static func currentTarget(
        windowID: CGWindowID,
        processIdentifier: pid_t,
        windowInfo: [[String: Any]],
        mainScreenTop: CGFloat
    ) -> (title: String, frame: CGRect)? {
        guard let info = windowInfo.first(where: {
            ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == windowID
                && ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == processIdentifier
        }), let bounds = info[kCGWindowBounds as String] as? NSDictionary,
            let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return nil }
        return (
            info[kCGWindowName as String] as? String ?? "",
            WindowPreviewLayout.appKitFrame(for: frame, mainScreenTop: mainScreenTop)
        )
    }

    static func index(
        title: String,
        frame: CGRect,
        candidates: [(title: String?, frame: CGRect?)]
    ) -> Int? {
        let matches = candidates.indices.filter {
            candidates[$0].title == title || (title.isEmpty && candidates[$0].title == nil)
        }
        if matches.count == 1 { return matches.first }
        let ranked = matches.sorted {
            distance(candidates[$0].frame, to: frame) < distance(candidates[$1].frame, to: frame)
        }
        guard let first = ranked.first,
              distance(candidates[first].frame, to: frame).isFinite,
              distance(candidates[first].frame, to: frame) < distance(candidates[ranked[1]].frame, to: frame)
        else { return nil }
        return first
    }

    private static func distance(_ candidate: CGRect?, to target: CGRect) -> CGFloat {
        guard let candidate else { return .infinity }
        return abs(candidate.minX - target.minX) + abs(candidate.minY - target.minY)
            + abs(candidate.width - target.width) + abs(candidate.height - target.height)
    }
}

@MainActor
final class WindowPreviewController: ObservableObject {
    @MainActor
    struct Dependencies {
        var hasPermissions: () -> Bool = {
            AccessibilityPermission.isTrusted && CGPreflightScreenCaptureAccess()
        }
        var requestPermissions: () -> Void = {
            _ = AccessibilityPermission.promptIfNeeded()
            if !CGPreflightScreenCaptureAccess() { _ = CGRequestScreenCaptureAccess() }
        }
        var addGlobalMonitor: (@escaping (NSEvent) -> Void) -> Any? = {
            NSEvent.addGlobalMonitorForEvents(matching: eventMask, handler: $0)
        }
        var addLocalMonitor: (@escaping (NSEvent) -> NSEvent?) -> Any? = {
            NSEvent.addLocalMonitorForEvents(matching: eventMask, handler: $0)
        }
        var removeMonitor: (Any) -> Void = { NSEvent.removeMonitor($0) }
        var timer: (TimeInterval, Bool, @escaping @MainActor () -> Void) -> Timer = { interval, repeats, action in
            Timer.scheduledTimer(withTimeInterval: interval, repeats: repeats) { _ in
                MainActor.assumeIsolated { action() }
            }
        }
        var captureWindows: (pid_t) async throws -> [WindowPreviewSnapshot] = {
            try await WindowPreviewController.captureWindows(processIdentifier: $0)
        }
        var dockSelection: () -> WindowPreviewSelection? = { WindowPreviewController.dockSelectionAtPointer() }
        var switcherSelection: () -> WindowPreviewSelection? = { WindowPreviewController.switcherSelection() }
        var commandPressed: () -> Bool = { CGEventSource.flagsState(.combinedSessionState).contains(.maskCommand) }
        var present: (WindowPreviewController, WindowPreviewSelection?) -> Void = { controller, selection in
            if let selection { controller.updatePanel(for: selection) } else { controller.panel?.orderOut(nil) }
        }
        var activate: (pid_t, WindowPreviewSnapshot) -> Void = { WindowPreviewController.activate($1, processIdentifier: $0) }
    }

    private static let eventMask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDown, .rightMouseDown, .keyDown, .flagsChanged]
    @Published private(set) var appName = ""
    @Published private(set) var appIcon: NSImage?
    @Published private(set) var windows: [WindowPreviewSnapshot] = []

    private var enabled = false
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var switcherTimer: Timer?
    private var hoverTimer: Timer?
    private var dismissTimer: Timer?
    private var captureTimer: Timer?
    private(set) var captureTask: Task<Void, Never>?
    private var generation = 0
    private var lastPointerProbe: TimeInterval = 0
    private var selection: WindowPreviewSelection?
    private var panel: NSPanel?
    private let dependencies: Dependencies

    init(dependencies: Dependencies = Dependencies()) {
        self.dependencies = dependencies
    }

    func configure(enabled: Bool, requestPermissions: Bool = false) {
        let wasEnabled = self.enabled
        self.enabled = enabled
        if enabled {
            if !wasEnabled && requestPermissions { dependencies.requestPermissions() }
            refreshPermissions()
        } else {
            stopMonitoring()
        }
    }

    func refreshPermissions() {
        guard enabled else { return }
        if dependencies.hasPermissions() {
            startMonitoring()
        } else {
            stopMonitoring()
        }
    }

    func stop() {
        enabled = false
        stopMonitoring()
    }

    private func startMonitoring() {
        guard globalMonitor == nil else { return }
        globalMonitor = dependencies.addGlobalMonitor { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }
        localMonitor = dependencies.addLocalMonitor { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
            return event
        }
        if globalMonitor == nil || localMonitor == nil { stopMonitoring() }
    }

    private func stopMonitoring() {
        if let globalMonitor { dependencies.removeMonitor(globalMonitor) }
        if let localMonitor { dependencies.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        switcherTimer?.invalidate()
        switcherTimer = nil
        hoverTimer?.invalidate()
        hoverTimer = nil
        dismissTimer?.invalidate()
        dismissTimer = nil
        clearSelection()
    }

    private func handle(_ event: NSEvent) {
        if event.type == .mouseMoved {
            guard switcherTimer == nil,
                  event.timestamp - lastPointerProbe >= 0.08 else { return }
            lastPointerProbe = event.timestamp
        }
        guard enabled, dependencies.hasPermissions() else {
            stopMonitoring()
            return
        }
        switch event.type {
        case .mouseMoved:
            handlePointer()
        case .keyDown:
            if event.keyCode == 48 && event.modifierFlags.contains(.command) {
                beginSwitcher()
            } else if event.keyCode == 53 && switcherTimer != nil {
                endSwitcher()
            }
        case .flagsChanged:
            if event.modifierFlags.contains(.command) {
                beginSwitcher()
            } else if switcherTimer != nil {
                endSwitcher()
            }
        case .leftMouseDown, .rightMouseDown:
            if switcherTimer == nil && panel?.frame.contains(NSEvent.mouseLocation) != true {
                scheduleDismiss()
            }
        default:
            break
        }
    }

    private func handlePointer() {
        if panel?.frame.contains(NSEvent.mouseLocation) == true {
            dismissTimer?.invalidate()
            dismissTimer = nil
            return
        }
        guard let hovered = dependencies.dockSelection() else {
            hoverTimer?.invalidate()
            hoverTimer = nil
            scheduleDismiss()
            return
        }
        dismissTimer?.invalidate()
        dismissTimer = nil
        if selection?.source == .dock && selection?.processIdentifier == hovered.processIdentifier {
            return
        }
        hoverTimer?.invalidate()
        let processIdentifier = hovered.processIdentifier
        hoverTimer = dependencies.timer(0.22, false) { [weak self] in
            guard let self, let current = self.dependencies.dockSelection(),
                  current.processIdentifier == processIdentifier else { return }
            self.hoverTimer = nil
            self.select(current)
        }
    }

    func scheduleDismiss() {
        guard selection?.source == .dock, dismissTimer == nil else { return }
        dismissTimer = dependencies.timer(0.25, false) { [weak self] in
            self?.dismissTimer = nil
            self?.clearSelection()
        }
    }

    func beginSwitcher() {
        guard switcherTimer == nil else { return }
        hoverTimer?.invalidate()
        hoverTimer = nil
        clearSelection()
        switcherTimer = dependencies.timer(0.12, true) { [weak self] in
            guard let self else { return }
            guard self.enabled, self.dependencies.hasPermissions() else {
                self.stopMonitoring()
                return
            }
            if !self.dependencies.commandPressed() {
                self.endSwitcher()
                return
            }
            if let selected = self.dependencies.switcherSelection() {
                self.select(selected)
            } else {
                self.clearSelection()
            }
        }
        switcherTimer?.fire()
    }

    private func endSwitcher() {
        switcherTimer?.invalidate()
        switcherTimer = nil
        clearSelection()
    }

    func select(_ next: WindowPreviewSelection) {
        guard enabled, dependencies.hasPermissions() else {
            stopMonitoring()
            return
        }
        if selection?.processIdentifier == next.processIdentifier && selection?.source == next.source {
            return
        }
        clearSelection()
        selection = next
        appName = next.appName
        appIcon = next.icon
        captureTimer = dependencies.timer(1, true) { [weak self] in
            self?.refreshWindows()
        }
        refreshWindows()
    }

    private func clearSelection() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        generation &+= 1
        captureTask?.cancel()
        captureTask = nil
        captureTimer?.invalidate()
        captureTimer = nil
        selection = nil
        windows = []
        appName = ""
        appIcon = nil
        dependencies.present(self, nil)
    }

    private func refreshWindows() {
        guard enabled, dependencies.hasPermissions() else {
            stopMonitoring()
            return
        }
        guard let selection, captureTask == nil else { return }
        let currentGeneration = generation
        let captureWindows = dependencies.captureWindows
        captureTask = Task { [weak self] in
            defer {
                if self?.generation == currentGeneration { self?.captureTask = nil }
            }
            do {
                try Task.checkCancellation()
                let snapshots = try await captureWindows(selection.processIdentifier)
                guard !Task.isCancelled, let self, self.generation == currentGeneration else { return }
                guard self.dependencies.hasPermissions() else {
                    self.stopMonitoring()
                    return
                }
                self.windows = snapshots
                self.dependencies.present(self, selection)
            } catch {
                guard !Task.isCancelled, let self, self.generation == currentGeneration else { return }
                if !self.dependencies.hasPermissions() {
                    self.stopMonitoring()
                } else {
                    self.windows = []
                    self.dependencies.present(self, nil)
                }
            }
        }
    }

    private static func captureWindows(processIdentifier: pid_t) async throws -> [WindowPreviewSnapshot] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        try Task.checkCancellation()
        let candidates = content.windows.filter {
            $0.owningApplication?.processID == processIdentifier && $0.windowLayer == 0
                && $0.frame.width >= 80 && $0.frame.height >= 50
        }
        var snapshots: [WindowPreviewSnapshot] = []
        for window in candidates {
            try Task.checkCancellation()
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let configuration = SCStreamConfiguration()
            let scale = min(420 / window.frame.width, 260 / window.frame.height, 1)
            configuration.width = max(1, Int(window.frame.width * scale))
            configuration.height = max(1, Int(window.frame.height * scale))
            configuration.showsCursor = false
            let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            try Task.checkCancellation()
            snapshots.append(WindowPreviewSnapshot(
                id: window.windowID,
                title: window.title ?? "",
                frame: WindowPreviewLayout.appKitFrame(
                    for: window.frame,
                    mainScreenTop: NSScreen.screens.first?.frame.maxY ?? 0
                ),
                image: image.map { NSImage(cgImage: $0, size: window.frame.size) }
            ))
        }
        return snapshots
    }

    private func updatePanel(for selection: WindowPreviewSelection) {
        guard !windows.isEmpty else {
            panel?.orderOut(nil)
            return
        }
        let screen = NSScreen.screens.first { $0.frame.intersects(selection.anchor) }
            ?? WindowPlacement.screenUnderMouse()
        guard let screen else { return }
        let width = min(CGFloat(windows.count) * 202 + 24, min(screen.visibleFrame.width - 24, 840))
        let frame = WindowPreviewLayout.frame(
            anchor: selection.anchor,
            size: CGSize(width: width, height: 188),
            visibleFrame: screen.visibleFrame,
            isSwitcher: selection.source == .switcher
        )
        let panel = panel ?? makePanel()
        panel.setFrame(frame, display: true)
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: WindowPreviewView(controller: self))
        self.panel = panel
        return panel
    }

    private static func dockSelectionAtPointer() -> WindowPreviewSelection? {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
        else { return nil }
        let pointer = NSEvent.mouseLocation
        let quartzPoint = WindowPreviewLayout.quartzPoint(
            for: pointer,
            mainScreenTop: NSScreen.screens.first?.frame.maxY ?? 0
        )
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(
            AXUIElementCreateApplication(dock.processIdentifier),
            Float(quartzPoint.x), Float(quartzPoint.y), &hit
        ) == .success,
              let item = hit,
              Self.attributeString(kAXSubroleAttribute, from: item) == "AXApplicationDockItem",
              let frame = Self.frame(of: item),
              frame.insetBy(dx: -6, dy: -6).contains(pointer) else { return nil }
        return selection(for: item, source: .dock, anchor: frame)
    }

    private static func switcherSelection() -> WindowPreviewSelection? {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first,
              let list = Self.findSwitcher(in: AXUIElementCreateApplication(dock.processIdentifier), depth: 5),
              let selected = Self.attribute(kAXSelectedChildrenAttribute, from: list) as? [AXUIElement],
              let item = selected.first else { return nil }
        return selection(for: item, source: .switcher, anchor: Self.frame(of: list))
    }

    private static func selection(
        for element: AXUIElement,
        source: WindowPreviewSource,
        anchor: CGRect? = nil
    ) -> WindowPreviewSelection? {
        let url = (Self.attribute(kAXURLAttribute, from: element) as? NSURL)?.absoluteURL
        let bundleIdentifier = url.flatMap { Bundle(url: $0)?.bundleIdentifier }
        let title = Self.attributeString(kAXTitleAttribute, from: element)
        let app = bundleIdentifier.flatMap {
            NSRunningApplication.runningApplications(withBundleIdentifier: $0).first
        } ?? NSWorkspace.shared.runningApplications.first { $0.localizedName == title }
        guard let app, !app.isTerminated else { return nil }
        let point = NSEvent.mouseLocation
        return WindowPreviewSelection(
            processIdentifier: app.processIdentifier,
            appName: app.localizedName ?? title ?? "",
            icon: app.icon,
            anchor: anchor ?? Self.frame(of: element) ?? CGRect(x: point.x, y: point.y, width: 1, height: 1),
            source: source
        )
    }

    private static func findSwitcher(in element: AXUIElement, depth: Int) -> AXUIElement? {
        if attributeString(kAXSubroleAttribute, from: element) == "AXProcessSwitcherList" { return element }
        guard depth > 0,
              let children = attribute(kAXChildrenAttribute, from: element) as? [AXUIElement] else { return nil }
        for child in children {
            if let found = findSwitcher(in: child, depth: depth - 1) { return found }
        }
        return nil
    }

    private static func attribute(_ name: String, from element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private static func attributeString(_ name: String, from element: AXUIElement) -> String? {
        attribute(name, from: element) as? String
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        guard let position = attribute(kAXPositionAttribute, from: element),
              let size = attribute(kAXSizeAttribute, from: element),
              CFGetTypeID(position) == AXValueGetTypeID(),
              CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin),
              AXValueGetValue(size as! AXValue, .cgSize, &dimensions) else { return nil }
        let mainTop = NSScreen.screens.first?.frame.maxY ?? 0
        return WindowPreviewLayout.appKitFrame(
            for: CGRect(origin: origin, size: dimensions),
            mainScreenTop: mainTop
        )
    }

    func activate(_ snapshot: WindowPreviewSnapshot) {
        guard let selection, let current = windows.first(where: { $0.id == snapshot.id }) else { return }
        endSwitcher()
        dependencies.activate(selection.processIdentifier, current)
    }

    private static func activate(_ snapshot: WindowPreviewSnapshot, processIdentifier: pid_t) {
        guard let app = NSRunningApplication(processIdentifier: processIdentifier),
              let windowInfo = CGWindowListCopyWindowInfo(.optionIncludingWindow, snapshot.id) as? [[String: Any]],
              let target = WindowPreviewWindowMatch.currentTarget(
                  windowID: snapshot.id,
                  processIdentifier: processIdentifier,
                  windowInfo: windowInfo,
                  mainScreenTop: NSScreen.screens.first?.frame.maxY ?? 0
              ) else { return }
        let appElement = AXUIElementCreateApplication(processIdentifier)
        let axWindows = Self.attribute(kAXWindowsAttribute, from: appElement) as? [AXUIElement] ?? []
        let candidates = axWindows.map {
            (title: Self.attributeString(kAXTitleAttribute, from: $0), frame: Self.frame(of: $0))
        }
        let index = WindowPreviewWindowMatch.index(
            title: target.title,
            frame: target.frame,
            candidates: candidates
        )
        guard let index else { return }
        _ = app.activate()
        let window = axWindows[index]
        _ = AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        _ = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }
}

private struct WindowPreviewView: View {
    @ObservedObject var controller: WindowPreviewController

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                if let icon = controller.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 18, height: 18)
                }
                Text(controller.appName)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(controller.windows) { snapshot in
                        Button {
                            controller.activate(snapshot)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Group {
                                    if let image = snapshot.image {
                                        Image(nsImage: image)
                                            .resizable()
                                            .scaledToFit()
                                    } else {
                                        Image(systemName: "macwindow")
                                            .font(.system(size: 32))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(width: 190, height: 114)
                                .background(Color.black.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
                                Text(snapshot.title.isEmpty ? controller.appName : snapshot.title)
                                    .font(.system(size: 10))
                                    .lineLimit(1)
                            }
                            .frame(width: 190)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
