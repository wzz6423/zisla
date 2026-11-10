import Combine
import Foundation
import ZislaCore

@MainActor
public final class AutomaticPowerModeService: ObservableObject {
    @Published public private(set) var error: BatteryPowerModeError?
    @Published public private(set) var manualPaused = false

    private let controller: BatteryPowerModeController
    private let defaults: UserDefaults
    private let notificationCenter: NotificationCenter
    private let onFailure: (BatteryPowerModeError) -> Void
    private let phaseKey = "automatic-power-mode-phase-v1"
    private var observer: NSObjectProtocol?
    private var configuration: Configuration?
    private var phase: Phase?
    private var request: Request?
    private var pending = false
    private(set) var updateTask: Task<Void, Never>?

    public init(
        controller: BatteryPowerModeController = BatteryPowerModeController(),
        defaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default,
        onFailure: @escaping (BatteryPowerModeError) -> Void = { _ in }
    ) {
        self.controller = controller
        self.defaults = defaults
        self.notificationCenter = notificationCenter
        self.onFailure = onFailure
        if let data = defaults.data(forKey: phaseKey),
           let saved = try? JSONDecoder().decode(Phase.self, from: data) {
            phase = saved
            manualPaused = saved.manualPaused
        }
    }

    isolated deinit {
        stop()
    }

    public func apply(settings: FeatureSettings, snapshot: BatterySnapshot?) {
        let previous = configuration
        let configuration = Configuration(settings)
        self.configuration = configuration
        if previous != configuration { updateTask?.cancel() }
        if !configuration.enabled {
            request = nil
            pending = false
            updateTask?.cancel()
            if let observer {
                notificationCenter.removeObserver(observer)
                self.observer = nil
            }
            guard phase != nil else { return }
        }
        guard let snapshot, snapshot.level.isFinite, (0...1).contains(snapshot.level) else {
            request = nil
            pending = false
            updateTask?.cancel()
            return
        }
        let source: BatteryPowerSource = snapshot.isPluggedIn ? .powerAdapter : .battery
        if phase?.source != source.rawValue {
            updateTask?.cancel()
            phase = Phase(source: source.rawValue, mode: nil, manualPaused: false, blocked: false)
            manualPaused = false
            error = nil
            persistPhase()
        }
        if previous?.enabled == false, configuration.enabled {
            phase?.blocked = false
            error = nil
            persistPhase()
        }
        guard configuration.enabled else { return }
        observeManualChanges()
        let target = configuration.lowBatteryEnabled && snapshot.level <= 0.20
            ? .lowPower : (source == .powerAdapter ? configuration.adapter : configuration.battery)
        let request = Request(source: source, mode: target)
        if self.request != request { updateTask?.cancel() }
        self.request = request
        pending = true
        scheduleUpdate()
    }

    public func stop() {
        updateTask?.cancel()
        configuration = nil
        request = nil
        pending = false
        if let observer {
            notificationCenter.removeObserver(observer)
            self.observer = nil
        }
    }

    private func observeManualChanges() {
        guard observer == nil else { return }
        observer = notificationCenter.addObserver(
            forName: BatteryPowerModeController.manualModeChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.pauseForManualChange() }
        }
    }

    private func scheduleUpdate() {
        guard updateTask == nil, pending, let request,
              phase?.manualPaused == false, phase?.blocked == false else { return }
        pending = false
        let controller = controller
        updateTask = Task { [weak self] in
            defer {
                self?.updateTask = nil
                self?.scheduleUpdate()
            }
            guard !Task.isCancelled else { return }
            await controller.refresh()
            guard !Task.isCancelled,
                  let before = self?.prepareChange(request: request) else { return }
            let changed = await controller.setMode(request.mode, expectedState: (request.source, before))
            if Task.isCancelled {
                self?.recordCancelledChange(request: request, changed: changed)
                return
            }
            self?.finishChange(request: request, before: before, changed: changed)
        }
    }

    private func prepareChange(request: Request) -> BatteryPowerMode? {
        if let error = controller.error { fail(error); return nil }
        guard controller.powerSource == request.source, let current = controller.currentMode else {
            fail(.stateUnavailable)
            return nil
        }
        if let previous = phase?.mode, previous != current {
            phase?.mode = current
            pauseForManualChange()
            return nil
        }
        phase?.mode = current
        persistPhase()
        guard current != request.mode else { return nil }
        return current
    }

    private func finishChange(request: Request, before: BatteryPowerMode, changed: Bool) {
        if changed {
            phase?.mode = request.mode
            persistPhase()
        } else if controller.powerSource == request.source, controller.currentMode != before,
                  controller.error == nil {
            phase?.mode = controller.currentMode
            pauseForManualChange()
        } else {
            fail(controller.error ?? .stateUnavailable)
        }
    }

    private func recordCancelledChange(request: Request, changed: Bool) {
        // A submitted pmset command can finish after cancellation; recognize its verified result before applying the latest rule.
        guard changed, configuration?.enabled == true,
              phase?.source == request.source.rawValue, phase?.manualPaused == false else { return }
        phase?.mode = request.mode
        persistPhase()
    }

    private func pauseForManualChange() {
        phase?.manualPaused = true
        manualPaused = true
        pending = false
        updateTask?.cancel()
        persistPhase()
    }

    private func fail(_ error: BatteryPowerModeError) {
        phase?.blocked = true
        self.error = error
        pending = false
        persistPhase()
        onFailure(error)
    }

    private func persistPhase() {
        if let phase, let data = try? JSONEncoder().encode(phase) {
            defaults.set(data, forKey: phaseKey)
        }
    }

    private struct Phase: Codable {
        let source: String
        var mode: BatteryPowerMode?
        var manualPaused: Bool
        var blocked: Bool
    }

    private struct Request: Equatable {
        let source: BatteryPowerSource
        let mode: BatteryPowerMode
    }

    private struct Configuration: Equatable {
        let enabled: Bool
        let adapter: BatteryPowerMode
        let battery: BatteryPowerMode
        let lowBatteryEnabled: Bool

        init(_ settings: FeatureSettings) {
            enabled = settings.systemMonitorEnabled && settings.automaticPowerModeEnabled
            adapter = settings.powerAdapterDefaultMode
            battery = settings.batteryDefaultMode
            lowBatteryEnabled = settings.lowBatteryPowerModeEnabled
        }
    }
}
