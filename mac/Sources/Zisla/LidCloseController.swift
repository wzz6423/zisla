import AppKit
import Combine
import Foundation
import QuartzCore
import ZislaKit

extension Notification.Name {
    /// Asks `LidCloseController` to play the effect once on the current screen
    /// contents, so Settings can preview it without closing the lid.
    static let lidCloseAnimationPreview = Notification.Name("dev.wzz.zisla.lidCloseAnimationPreview")
}

/// Translates lid-angle samples into the Mac Duo inspired close animation.
///
/// The controller deliberately requires recent downward movement before it
/// triggers. This avoids covering the display when zisla launches while a
/// laptop is already partially closed. `LidCloseMotion` holds that decision.
@MainActor
final class LidCloseController: NSObject {
    private enum Tuning {
        /// Degrees above the trigger angle at which polling speeds up.
        static let fastPollMargin = 30.0
        /// Lid travel the effect spans before it reaches full depth.
        static let fullEffectSpan = 60.0
        static let idlePollInterval: TimeInterval = 1.0 / 8
        static let activePollInterval: TimeInterval = 1.0 / 30
        /// Failed reads in a row after which a running effect is torn down.
        static let failedReadLimit = 8
    }

    /// A scripted angle sweep, so Settings can show the effect without the lid
    /// moving. It feeds the same path the sensor feeds.
    private struct PreviewRun {
        /// Reset when the picture is actually up, so the capture latency does
        /// not eat into the sweep.
        var startedAt: CFTimeInterval
        let open: Double
        let shut: Double
        let closing: CFTimeInterval = 1.4
        let hold: CFTimeInterval = 0.8
        let opening: CFTimeInterval = 0.6

        /// `nil` once the run is over.
        func angle(at now: CFTimeInterval) -> Double? {
            let elapsed = now - startedAt
            if elapsed < closing { return open + (shut - open) * (elapsed / closing) }
            if elapsed < closing + hold { return shut }
            if elapsed < closing + hold + opening {
                return shut + (open - shut) * ((elapsed - closing - hold) / opening)
            }
            return nil
        }
    }

    private let settingsStore: FeatureSettingsStore
    private let sensor = LidAngleSensor()
    private let overlay = LidCloseOverlay()

    private var pollTimer: Timer?
    private var displayLink: CADisplayLink?
    private var settingsCancellable: AnyCancellable?
    private var workspaceNotificationObservers: [NSObjectProtocol] = []
    private var applicationNotificationObservers: [NSObjectProtocol] = []
    private var captureTask: Task<Void, Never>?

    private var motion = LidCloseMotion()
    private var visualAngle = 0.0
    private var lastFrameTime = CACurrentMediaTime()
    private var isEffectActive = false
    private var isSuspended = false
    private var isStarted = false
    private var consecutiveFailedReads = 0
    private var preview: PreviewRun?

    init(settingsStore: FeatureSettingsStore) {
        self.settingsStore = settingsStore
        super.init()
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        isSuspended = false
        resetMotionState()
        observeSettings()
        observeSystemEvents()
        applicationNotificationObservers.append(
            NotificationCenter.default.addObserver(
                forName: .lidCloseAnimationPreview, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.runPreview() }
            }
        )
        guard sensor.isAvailable else { return }
        // Compiling the fragment shader at the trigger angle would delay the
        // first frame, so the pipeline is built while the lid is still open.
        if settingsStore.settings.lidCloseAnimationEnabled {
            overlay.warmUp()
        }
        poll()
        schedulePolling(interval: Tuning.idlePollInterval)
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        pollTimer?.invalidate()
        pollTimer = nil
        stopDisplayLink()
        captureTask?.cancel()
        captureTask = nil
        overlay.dismiss(animated: false)
        isEffectActive = false
        isSuspended = false
        resetMotionState()
        settingsCancellable?.cancel()
        settingsCancellable = nil
        workspaceNotificationObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        workspaceNotificationObservers.removeAll()
        applicationNotificationObservers.forEach(NotificationCenter.default.removeObserver)
        applicationNotificationObservers.removeAll()
    }

    private func observeSettings() {
        settingsCancellable = settingsStore.$settings
            .map(\.lidCloseAnimationEnabled)
            .removeDuplicates()
            .sink { [weak self] enabled in
                guard let self else { return }
                if !enabled {
                    self.endEffect(animated: true)
                }
            }
    }

    private func observeSystemEvents() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceNotificationObservers = [
            workspaceCenter.addObserver(
                forName: NSWorkspace.willSleepNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.suspend() }
            },
            workspaceCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.resume() }
            },
        ]
        applicationNotificationObservers = [
            NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.endEffect(animated: false) }
            },
        ]
    }

    private func schedulePolling(interval: TimeInterval) {
        pollTimer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = interval * 0.15
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func poll() {
        guard !isSuspended, sensor.isAvailable else { return }
        guard settingsStore.settings.lidCloseAnimationEnabled else {
            endEffect(animated: true)
            return
        }
        guard let angle = sensor.angle() else {
            consecutiveFailedReads += 1
            if isEffectActive, consecutiveFailedReads >= Tuning.failedReadLimit {
                endEffect(animated: false)
            }
            return
        }
        consecutiveFailedReads = 0
        // A scripted sweep owns the effect while it runs; the open lid must
        // not release it through the ordinary rules.
        guard preview == nil else { return }

        let now = CACurrentMediaTime()
        motion.record(angle: angle, at: now)
        if !isEffectActive {
            let shouldPollFast = angle < motion.tuning.thresholdAngle + Tuning.fastPollMargin
            let interval = shouldPollFast ? Tuning.activePollInterval : Tuning.idlePollInterval
            if pollTimer?.timeInterval != interval {
                schedulePolling(interval: interval)
            }
            guard motion.shouldEngage(at: now) else { return }
            beginEffect()
            return
        }

        if motion.shouldRelease(angle: angle) {
            endEffect(animated: true)
        }
    }

    /// Plays the effect once on the current screen contents, so the animation
    /// can be checked from Settings without closing the lid.
    func runPreview() {
        guard isStarted, !isEffectActive, !isSuspended else { return }
        guard settingsStore.settings.lidCloseAnimationEnabled else { return }
        let threshold = motion.tuning.thresholdAngle
        preview = PreviewRun(
            startedAt: CACurrentMediaTime(),
            open: min(threshold + 35, 130),
            shut: max(threshold - Tuning.fullEffectSpan * 1.15, 5)
        )
        beginEffect()
    }

    /// Whether the overlay is on screen right now.
    var isOverlayVisible: Bool { overlay.isVisible }

    /// Steps the overlay aside so a screenshot taken while the effect shows
    /// captures the contents behind it instead of the folded picture, and the
    /// frozen selection frame is not covered by the live overlay. Mac Duo
    /// keeps its overlay out of captures for the same reason.
    func dismissOverlayForScreenshot() {
        endEffect(animated: false)
    }

    private func beginEffect() {
        guard !isEffectActive else { return }
        isEffectActive = true
        visualAngle = preview?.open ?? motion.rawAngle
        captureTask?.cancel()
        captureTask = Task { [weak self] in
            guard let self, let screen = self.builtInScreen else {
                self?.endEffect(animated: false)
                return
            }
            do {
                let frame = try await ScreenshotCaptureService.capture(
                    screen: screen,
                    excludingApplicationWithProcessIdentifier: ProcessInfo.processInfo.processIdentifier
                )
                guard !Task.isCancelled, self.isEffectActive else { return }
                // The sweep starts once the picture is up, so the capture
                // latency does not eat into it.
                self.preview?.startedAt = CACurrentMediaTime()
                self.overlay.present(
                    image: frame.cgImage,
                    on: screen,
                    startAngle: self.motion.tuning.thresholdAngle
                )
                self.startDisplayLink()
            } catch {
                self.endEffect(animated: false)
            }
        }
    }

    private var builtInScreen: NSScreen? {
        NSScreen.screens.first { screen in
            guard let displayID = ScreenshotCaptureService.displayID(for: screen) else { return false }
            return CGDisplayIsBuiltin(displayID) != 0
        }
    }

    private func startDisplayLink() {
        stopDisplayLink()
        guard let window = overlay.hostWindow else { return }
        let link = window.displayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        lastFrameTime = CACurrentMediaTime()
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func step(_ link: CADisplayLink) {
        guard isEffectActive else {
            stopDisplayLink()
            return
        }
        let now = CACurrentMediaTime()
        let elapsed = min(max(now - lastFrameTime, 1.0 / 240), 1.0 / 20)
        lastFrameTime = now
        let targetAngle: Double
        if let preview {
            guard let scripted = preview.angle(at: now) else {
                self.preview = nil
                endEffect(animated: true)
                return
            }
            targetAngle = scripted
        } else {
            targetAngle = motion.rawAngle
        }
        visualAngle += (targetAngle - visualAngle) * min(elapsed * 14, 1)
        let threshold = motion.tuning.thresholdAngle
        let progress = min(max((threshold - visualAngle) / Tuning.fullEffectSpan, 0), 1)
        // The geometry takes the lid angle itself, so only the blur saturates.
        overlay.update(progress: progress, currentAngle: visualAngle)
    }

    private func endEffect(animated: Bool) {
        guard isEffectActive || overlay.isVisible else { return }
        isEffectActive = false
        preview = nil
        captureTask?.cancel()
        captureTask = nil
        stopDisplayLink()
        overlay.dismiss(animated: animated)
    }

    private func suspend() {
        isSuspended = true
        endEffect(animated: false)
    }

    private func resume() {
        isSuspended = false
        resetMotionState()
    }

    private func resetMotionState() {
        let angle = sensor.angle()
        motion.reset(angle: angle)
        consecutiveFailedReads = 0
        if let angle {
            visualAngle = angle
        }
    }
}
