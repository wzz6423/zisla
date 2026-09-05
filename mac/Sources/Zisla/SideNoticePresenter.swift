import AppKit
import Combine
import ZislaCore
import ZislaKit
import SwiftUI

@MainActor
final class SideNoticePresenter {
    private let queue: SideNoticeQueue
    private let media: NowPlayingService
    private let browserDownloads: BrowserDownloadMonitor
    private let settingsStore: FeatureSettingsStore
    private let languageStore: AppLanguageStore
    private let layoutEngine = SideNoticeLayoutEngine()
    private var panelsByDisplayID: [CGDirectDisplayID: DisplayPanels] = [:]
    private var cancellables: Set<AnyCancellable> = []
    private var configuredDisplayIDs: Set<UInt32>
    private var suppression = SideNoticeSuppression()
    private var isScreenshotActive = false
    /// Display where the last voice recording happened; the post-recording processing indicator stays scoped to it.
    private var voiceProcessingDisplayID: UInt32?

    init(
        queue: SideNoticeQueue,
        media: NowPlayingService,
        browserDownloads: BrowserDownloadMonitor,
        settingsStore: FeatureSettingsStore,
        languageStore: AppLanguageStore,
        displayIDs: Set<UInt32> = []
    ) {
        self.queue = queue
        self.media = media
        self.browserDownloads = browserDownloads
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
        NSWorkspace.shared.notificationCenter.addObserver(
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

    /// Records which display the voice session belongs to. `nil` keeps the legacy behavior of
    /// showing the processing indicator on every display.
    func setVoiceProcessingDisplayID(_ displayID: UInt32?) {
        guard voiceProcessingDisplayID != displayID else { return }
        voiceProcessingDisplayID = displayID
        updatePanels()
    }

    func stop() {
        NotificationCenter.default.removeObserver(
            self,
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.removeObserver(
            self,
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: NSWorkspace.shared
        )
        hideAllPanels()
        panelsByDisplayID.removeAll()
        cancellables.removeAll()
    }

    func setIslandExpanded(_ expanded: Bool) {
        updateSuppression { $0.isIslandExpanded = expanded }
    }

    func setVoiceRecording(_ recording: Bool) {
        updateSuppression { $0.isVoiceRecording = recording }
    }

    /// A transient message borrows the collapsed pill the way recording does, so the status wings
    /// give way instead of crowding the row that just replaced them.
    func setTransientNoticePresented(_ presented: Bool) {
        updateSuppression { $0.isTransientNoticePresented = presented }
    }

    /// The clipboard assistant takes over the notch row, so notices give way while it is up.
    func setClipboardAssistantVisible(_ visible: Bool) {
        updateSuppression { $0.isClipboardAssistantVisible = visible }
    }

    private func updateSuppression(_ mutate: (inout SideNoticeSuppression) -> Void) {
        var updated = suppression
        mutate(&updated)
        guard updated != suppression else { return }
        suppression = updated
        if updated.hidesNotices {
            hideAllPanels()
        } else {
            updatePanels()
        }
    }

    func setScreenshotActive(_ active: Bool) {
        guard isScreenshotActive != active else { return }
        isScreenshotActive = active
        for panels in panelsByDisplayID.values {
            panels.left?.level = active ? IslandPanel.onBottomLevel : IslandPanel.onTopLevel
            panels.right?.level = active ? IslandPanel.onBottomLevel : IslandPanel.onTopLevel
            panels.compactBar?.level = active ? IslandPanel.onBottomLevel : IslandPanel.onTopLevel
        }
    }

    private func updatePanels(rejoiningActiveSpace: Bool = false) {
        guard !suppression.hidesNotices else {
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
            displayState.hidesVoiceProcessingIndicator = hidesVoiceProcessingIndicator(
                on: snapshot.displayID
            )
            var compactNotices = queue.left + queue.right
            if displayState.hidesVoiceProcessingIndicator {
                compactNotices = Self.noticesWithoutVoiceProcessing(compactNotices)
            }
            let compactBarFrame = layoutEngine.compactBarFrame(
                for: snapshot,
                notices: compactNotices,
                settings: settingsStore.settings
            ) ?? layoutEngine.compactBarFrame(for: snapshot)
            displayState.compactWingsEnabled = false
            displayState.compactWingHeight = compactBarFrame.height
            displayState.reserveCompactWing = false
            updateCompactBar(
                screen: snapshot,
                panels: panels,
                rejoiningActiveSpace: rejoiningActiveSpace
            )
            updatePanel(
                side: .left,
                notices: queue.left,
                screen: snapshot,
                panels: panels,
                rejoiningActiveSpace: rejoiningActiveSpace
            )
            updatePanel(
                side: .right,
                notices: queue.right,
                screen: snapshot,
                panels: panels,
                rejoiningActiveSpace: rejoiningActiveSpace
            )
        }
    }

    private func hidesVoiceProcessingIndicator(on displayID: CGDirectDisplayID) -> Bool {
        guard let voiceProcessingDisplayID else { return false }
        return UInt32(displayID) != voiceProcessingDisplayID
    }

    private static func noticesWithoutVoiceProcessing(_ notices: [IslandNotice]) -> [IslandNotice] {
        notices.filter { !$0.id.hasPrefix("voice-processing-") }
    }

    private func updateCompactBar(
        screen snapshot: ScreenSnapshot,
        panels: DisplayPanels,
        rejoiningActiveSpace: Bool
    ) {
        let displayState = panels.displayState
        var compactNotices = queue.left + queue.right
        if displayState.hidesVoiceProcessingIndicator {
            compactNotices = Self.noticesWithoutVoiceProcessing(compactNotices)
        }
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
        guard let frame = layoutEngine.compactBarFrame(
            for: snapshot,
            notices: compactNotices,
            settings: settingsStore.settings
        ) else {
            panels.compactBar?.orderOut(nil)
            return
        }
        let topology = ScreenLayoutEngine().layout(for: snapshot).topology
        // Detailed mode left/right content must avoid the physical notch; simulated-island devices have no obstruction, so no center gap.
        displayState.compactBarCenterInset = topology.hasPhysicalNotch
            ? topology.anchorFrame.width
            : 0
        let panel = ensureCompactBarPanel(in: panels)
        panel.level = isScreenshotActive ? IslandPanel.onBottomLevel : IslandPanel.onTopLevel
        if panel.frame != frame {
            panel.setFrame(frame, display: true)
        }
        if Self.shouldOrderPanelFront(
            isVisible: panel.isVisible,
            rejoiningActiveSpace: rejoiningActiveSpace
        ) {
            panel.orderFrontRegardless()
        }
    }

    private func updatePanel(
        side: NoticeSide,
        notices: [IslandNotice],
        screen snapshot: ScreenSnapshot,
        panels: DisplayPanels,
        rejoiningActiveSpace: Bool
    ) {
        let displayState = panels.displayState
        let notices = displayState.hidesVoiceProcessingIndicator
            ? Self.noticesWithoutVoiceProcessing(notices)
            : notices
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
        panel.level = isScreenshotActive ? IslandPanel.onBottomLevel : IslandPanel.onTopLevel
        let frame = layoutEngine.frame(side: side, presentation: presentation, screen: snapshot)
        if panel.frame != frame {
            panel.setFrame(frame, display: true)
        }
        if Self.shouldOrderPanelFront(
            isVisible: panel.isVisible,
            rejoiningActiveSpace: rejoiningActiveSpace
        ) {
            panel.orderFrontRegardless()
        }
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
            browserDownloads: browserDownloads,
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

    static func shouldOrderPanelFront(
        isVisible: Bool,
        rejoiningActiveSpace: Bool
    ) -> Bool {
        !isVisible || rejoiningActiveSpace
    }

    private static func isCompactNotice(_ notice: IslandNotice) -> Bool {
        notice.id.hasPrefix("ai-active-")
            || notice.id.hasPrefix("update-available-")
            || notice.id.hasPrefix("media-active-")
            || notice.id.hasPrefix("background-sound-")
            || notice.id.hasPrefix("focus-countdown-")
            || notice.id.hasPrefix("focus-mode-")
            || notice.id.hasPrefix("mail-notification-")
            || isTransientCompactNotice(notice)
            || notice.id.hasPrefix("toolbox-reminder-")
            || notice.id.hasPrefix("browser-download-")
            || notice.id.hasPrefix("video-download-")
            || notice.id.hasPrefix("voice-processing-")
    }

    private static func isTransientCompactNotice(_ notice: IslandNotice) -> Bool {
        notice.id.hasPrefix("focus-transition") || notice.style == .headphone
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
        updatePanels(rejoiningActiveSpace: true)
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
