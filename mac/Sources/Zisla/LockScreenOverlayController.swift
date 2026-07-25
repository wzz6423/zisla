import AppKit
import Combine
import CoreGraphics
import Foundation
import SkyLightWindow
import SwiftUI

enum LockScreenOverlayKind: CaseIterable, Hashable {
    case header
    case status
    case player

    var size: CGSize {
        switch self {
        case .header: CGSize(width: 560, height: 72)
        case .status: CGSize(width: 560, height: 46)
        case .player: CGSize(width: 420, height: 176)
        }
    }

    var ignoresMouseEvents: Bool {
        self != .player
    }
}

@MainActor
final class LockScreenOverlayController {
    private let model: AppModel
    private var windows: [LockScreenOverlayKind: LockScreenOverlayWindow] = [:]
    private var notificationObservers: [NSObjectProtocol] = []
    private var settingsCancellable: AnyCancellable?
    private var mediaCancellable: AnyCancellable?
    private var sessionPoller: Timer?
    private var isScreenLocked = false

    init(model: AppModel) {
        self.model = model
    }

    func start() {
        guard notificationObservers.isEmpty else { return }
        let center = DistributedNotificationCenter.default()
        notificationObservers = [
            center.addObserver(
                forName: Notification.Name("com.apple.screenIsLocked"),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.setScreenLocked(true)
                }
            },
            center.addObserver(
                forName: Notification.Name("com.apple.screenIsUnlocked"),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.setScreenLocked(false)
                }
            },
            NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.layoutWindows()
                }
            },
        ]
        settingsCancellable = model.settingsStore.$settings
            .map(\.lockScreenInfoEnabled)
            .removeDuplicates()
            .sink { [weak self] enabled in
                Task { @MainActor [weak self] in
                    self?.updateVisibility(enabled: enabled)
                }
            }
        mediaCancellable = model.media.$snapshot
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.updatePlayerVisibility()
                }
            }
        sessionPoller = Timer.scheduledTimer(
            withTimeInterval: 2,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshSessionLockState()
            }
        }
        refreshSessionLockState()
    }

    func stop() {
        sessionPoller?.invalidate()
        sessionPoller = nil
        settingsCancellable?.cancel()
        settingsCancellable = nil
        mediaCancellable?.cancel()
        mediaCancellable = nil
        for observer in notificationObservers {
            DistributedNotificationCenter.default().removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
        notificationObservers.removeAll()
        hideWindows()
        windows.values.forEach { $0.close() }
        windows.removeAll()
    }

    private func refreshSessionLockState() {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any],
              let locked = session["CGSSessionScreenIsLocked"] as? Bool else { return }
        setScreenLocked(locked)
    }

    private func setScreenLocked(_ locked: Bool) {
        guard isScreenLocked != locked else { return }
        isScreenLocked = locked
        updateVisibility(enabled: model.settingsStore.settings.lockScreenInfoEnabled)
    }

    private func updateVisibility(enabled: Bool) {
        guard isScreenLocked, enabled else {
            hideWindows()
            return
        }
        model.media.refresh()
        model.battery.refresh()
        if model.settingsStore.settings.weatherEnabled, model.weather == nil {
            model.refreshWeather()
        }
        showWindows()
    }

    private func showWindows() {
        for kind in LockScreenOverlayKind.allCases {
            guard kind != .player || shouldShowPlayer else {
                windows[kind]?.orderOut(nil)
                continue
            }
            let window = window(for: kind)
            updateFrame(of: window, kind: kind)
            window.orderFrontRegardless()
        }
    }

    private func hideWindows() {
        windows.values.forEach { $0.orderOut(nil) }
    }

    private var shouldShowPlayer: Bool {
        model.settingsStore.settings.mediaEnabled && model.media.snapshot != nil
    }

    private func updatePlayerVisibility() {
        guard isScreenLocked, model.settingsStore.settings.lockScreenInfoEnabled,
              shouldShowPlayer else {
            windows[.player]?.orderOut(nil)
            return
        }
        let player = window(for: .player)
        updateFrame(of: player, kind: .player)
        player.orderFrontRegardless()
    }

    private func layoutWindows() {
        guard isScreenLocked else { return }
        for (kind, window) in windows {
            updateFrame(of: window, kind: kind)
        }
    }

    private func window(for kind: LockScreenOverlayKind) -> LockScreenOverlayWindow {
        if let window = windows[kind] { return window }
        let window = LockScreenOverlayWindow(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = kind.ignoresMouseEvents
        window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        window.collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .fullScreenAuxiliary,
            .ignoresCycle,
        ]

        let hostingView = NSHostingView(
            rootView: LockScreenOverlayView(model: model, kind: kind)
        )
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        window.contentView = hostingView
        SkyLightOperator.shared.delegateWindow(window)
        windows[kind] = window
        return window
    }

    private func updateFrame(of window: NSWindow, kind: LockScreenOverlayKind) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let size = CGSize(
            width: min(kind.size.width, max(1, screen.frame.width - 32)),
            height: kind.size.height
        )
        let headerCenterY = screen.frame.minY + screen.frame.height * 0.73
        let y: CGFloat
        switch kind {
        case .header:
            y = headerCenterY
        case .status:
            // 紧接在 header（农历）下方，间距与签名和农历之间的间距一致（5pt）
            let headerBottom = headerCenterY - LockScreenOverlayKind.header.size.height / 2
            y = headerBottom - 5 - size.height / 2
        case .player:
            y = screen.frame.minY + screen.frame.height * 0.34
        }
        let frame = CGRect(
            x: screen.frame.midX - size.width / 2,
            y: y - size.height / 2,
            width: size.width,
            height: size.height
        )
        window.setFrame(frame, display: true)
    }
}

@MainActor
private final class LockScreenOverlayWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
