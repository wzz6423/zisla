import AppKit
import Combine
import ZislaCore
import ZislaKit
import SwiftUI

@MainActor
final class SideNoticePresenter {
    private let queue: SideNoticeQueue
    private let media: NowPlayingService
    private let settingsStore: FeatureSettingsStore
    private let languageStore: AppLanguageStore
    private let layoutEngine = SideNoticeLayoutEngine()
    private var panelsByDisplayID: [CGDirectDisplayID: DisplayPanels] = [:]
    private var cancellables: Set<AnyCancellable> = []
    private var configuredDisplayIDs: Set<UInt32>
    private var isIslandExpanded = false

    init(
        queue: SideNoticeQueue,
        media: NowPlayingService,
        settingsStore: FeatureSettingsStore,
        languageStore: AppLanguageStore,
        displayIDs: Set<UInt32> = []
    ) {
        self.queue = queue
        self.media = media
        self.settingsStore = settingsStore
        self.languageStore = languageStore
        configuredDisplayIDs = displayIDs
        queue.$left
            .combineLatest(queue.$right)
            .sink { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.updatePanels() }
            }
            .store(in: &cancellables)
        // A settings change can switch the winning compact status and its required width.
        settingsStore.$settings
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.updatePanels() }
            }
            .store(in: &cancellables)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(activeSpaceDidChange),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: NSWorkspace.shared
        )
    }

    func setDisplayIDs(_ displayIDs: Set<UInt32>) {
        guard configuredDisplayIDs != displayIDs else { return }
        configuredDisplayIDs = displayIDs
        updatePanels()
    }

    func stop() {
        NotificationCenter.default.removeObserver(self)
        hideAllPanels()
        panelsByDisplayID.removeAll()
        cancellables.removeAll()
    }

    func setIslandExpanded(_ expanded: Bool) {
        guard expanded != isIslandExpanded else { return }
        isIslandExpanded = expanded
        if expanded {
            hideAllPanels()
        } else {
            updatePanels()
        }
    }

    private func updatePanels() {
        guard !isIslandExpanded else {
            hideAllPanels()
            return
        }
        let snapshots = NSScreen.screens.compactMap(ScreenSnapshot.init(screen:))
        guard !snapshots.isEmpty else {
            hideAllPanels()
            panelsByDisplayID.removeAll()
            return
        }

        let connectedDisplayIDs = Set(snapshots.map { UInt32($0.displayID) })
        let displayIDs = resolvedDisplayIDs(from: connectedDisplayIDs)
        removePanels(except: displayIDs)

        for snapshot in snapshots where displayIDs.contains(UInt32(snapshot.displayID)) {
            let panels = panels(for: snapshot.displayID)
            let displayState = panels.displayState
            let compactBarFrame = layoutEngine.compactBarFrame(for: snapshot)
            displayState.compactWingsEnabled = false
            displayState.compactWingHeight = compactBarFrame.height
            displayState.reserveCompactWing = false
            updateCompactBar(screen: snapshot, panels: panels)
            updatePanel(
                side: .left,
                notices: queue.left,
                screen: snapshot,
                panels: panels
            )
            updatePanel(
                side: .right,
                notices: queue.right,
                screen: snapshot,
                panels: panels
            )
        }
    }

    private func updateCompactBar(screen snapshot: ScreenSnapshot, panels: DisplayPanels) {
        let displayState = panels.displayState
        let compactNotices = queue.left + queue.right
        let compactStatusIDs = Set(compactNotices.filter(Self.isCompactNotice).map(\.id))
        if compactStatusIDs != displayState.compactStatusIDs {
            displayState.compactStatusIDs = compactStatusIDs
            displayState.compactStatusHidden = false
        }
        if CompactStatusVisibilityPolicy.mustRemainVisible(
            notices: compactNotices,
            activityDuration: settingsStore.settings.activityNoticeDisplayDuration,
            focusDuration: settingsStore.settings.focusModeNoticeDisplayDuration
        ) {
            displayState.compactStatusHidden = false
        }
        guard !displayState.compactStatusHidden,
            compactNotices.contains(where: Self.isCompactNotice)
        else {
            if compactStatusIDs.isEmpty {
                displayState.compactStatusHidden = false
            }
            panels.compactBar?.orderOut(nil)
            return
        }
        let selectedPriority = selectedCompactStatusPriority(for: compactNotices)
        let extendsForCompactStatus = selectedPriority == .transient
            || selectedPriority == .focusCountdown
        let usesDetailedMedia = selectedPriority == .media
            && settingsStore.settings.mediaCompactStyle == .detailed
        let frame = layoutEngine.compactBarFrame(
            for: snapshot,
            extendsForFocusCountdown: extendsForCompactStatus,
            expandsForDetailedMedia: usesDetailedMedia
        )
        guard frame != .zero else {
            panels.compactBar?.orderOut(nil)
            return
        }
        let topology = ScreenLayoutEngine().layout(for: snapshot).topology
        // Detailed mode left/right content must avoid the physical notch; simulated-island devices have no obstruction, so no center gap.
        displayState.compactBarCenterInset = topology.hasPhysicalNotch
            ? topology.anchorFrame.width
            : 0
        let panel = ensureCompactBarPanel(in: panels)
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }

    private func updatePanel(
        side: NoticeSide,
        notices: [IslandNotice],
        screen snapshot: ScreenSnapshot,
        panels: DisplayPanels
    ) {
        let displayState = panels.displayState
        guard !notices.isEmpty || displayState.reserveCompactWing else {
            panel(for: side, in: panels)?.orderOut(nil)
            return
        }
        let presentation = layoutEngine.presentation(
            for: notices,
            compactWingsEnabled: displayState.compactWingsEnabled,
            compactWingHeight: max(1, displayState.compactWingHeight),
            reserveCompactWing: displayState.reserveCompactWing
        )
        guard presentation.panelSize != .zero else {
            panel(for: side, in: panels)?.orderOut(nil)
            return
        }
        let panel = ensurePanel(for: side, in: panels)
        let frame = layoutEngine.frame(side: side, presentation: presentation, screen: snapshot)
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }

    private func ensurePanel(for side: NoticeSide, in panels: DisplayPanels) -> IslandPanel {
        if let panel = panel(for: side, in: panels) { return panel }
        let rootView = SideNoticeRootView(
            queue: queue,
            displayState: panels.displayState,
            side: side
        )
        let hostingView = NSHostingView(
            rootView: AppLanguageEnvironment(languageStore: languageStore, content: rootView)
        )
        hostingView.sizingOptions = []
        let panel = IslandPanel(
            contentView: hostingView,
            frame: CGRect(x: 0, y: 0, width: 40, height: 34)
        )
        if side == .left { panels.left = panel } else { panels.right = panel }
        return panel
    }

    private func ensureCompactBarPanel(in panels: DisplayPanels) -> IslandPanel {
        if let compactBar = panels.compactBar { return compactBar }
        let rootView = CompactStatusBarView(
            queue: queue,
            displayState: panels.displayState,
            media: media,
            settingsStore: settingsStore,
            onStatusHidden: { [weak self] in self?.updatePanels() }
        )
        let hostingView = NSHostingView(
            rootView: AppLanguageEnvironment(languageStore: languageStore, content: rootView)
        )
        hostingView.sizingOptions = []
        let panel = IslandPanel(
            contentView: hostingView,
            frame: CGRect(x: 0, y: 0, width: 240, height: 34)
        )
        panels.compactBar = panel
        return panel
    }

    private static func isCompactNotice(_ notice: IslandNotice) -> Bool {
        notice.id.hasPrefix("ai-active-")
            || notice.id.hasPrefix("media-active-")
            || notice.id.hasPrefix("focus-countdown-")
            || notice.id.hasPrefix("focus-mode-")
            || isTransientCompactNotice(notice)
            || notice.id.hasPrefix("toolbox-reminder-")
            || notice.id.hasPrefix("browser-download-")
            || notice.id.hasPrefix("video-download-")
    }

    private static func isTransientCompactNotice(_ notice: IslandNotice) -> Bool {
        notice.id.hasPrefix("focus-transition") || notice.style == .headphone
    }

    private func selectedCompactStatusPriority(for notices: [IslandNotice]) -> CompactStatusPriority? {
        settingsStore.settings.compactStatusPriority.first { priority in
            switch priority {
            case .transient:
                notices.contains(where: Self.isTransientCompactNotice)
            case .videoDownload:
                notices.contains { $0.id.hasPrefix("video-download-") }
            case .browserDownload:
                notices.contains { $0.id.hasPrefix("browser-download-") }
            case .focusCountdown:
                notices.contains { $0.id.hasPrefix("focus-countdown-") }
            case .toolboxReminder:
                notices.contains { $0.id.hasPrefix("toolbox-reminder-") }
            case .aiActivity:
                notices.contains { $0.id.hasPrefix("ai-active-") }
            case .media:
                notices.contains { $0.id.hasPrefix("media-active-") }
            case .focusMode:
                notices.contains { $0.id.hasPrefix("focus-mode-") }
            }
        }
    }

    private func panel(for side: NoticeSide, in panels: DisplayPanels) -> IslandPanel? {
        side == .left ? panels.left : panels.right
    }

    private func panels(for displayID: CGDirectDisplayID) -> DisplayPanels {
        if let panels = panelsByDisplayID[displayID] { return panels }
        let panels = DisplayPanels()
        panelsByDisplayID[displayID] = panels
        return panels
    }

    private func resolvedDisplayIDs(from connectedDisplayIDs: Set<UInt32>) -> Set<UInt32> {
        let selected = configuredDisplayIDs.intersection(connectedDisplayIDs)
        return selected.isEmpty ? connectedDisplayIDs : selected
    }

    private func removePanels(except displayIDs: Set<UInt32>) {
        let removedIDs = panelsByDisplayID.keys.filter { !displayIDs.contains(UInt32($0)) }
        for displayID in removedIDs {
            panelsByDisplayID.removeValue(forKey: displayID)?.orderOut()
        }
    }

    private func hideAllPanels() {
        for panels in panelsByDisplayID.values {
            panels.orderOut()
        }
    }

    @objc private func screenParametersChanged(_ notification: Notification) {
        updatePanels()
    }

    @objc private func activeSpaceDidChange(_ notification: Notification) {
        updatePanels()
    }
}

@MainActor
private final class DisplayPanels {
    let displayState = SideNoticeDisplayState()
    var left: IslandPanel?
    var right: IslandPanel?
    var compactBar: IslandPanel?

    func orderOut() {
        left?.orderOut(nil)
        right?.orderOut(nil)
        compactBar?.orderOut(nil)
    }
}
