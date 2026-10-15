import AppKit
import AVFoundation
import Combine
import CoreBluetooth
import CoreGraphics
import CoreLocation
import EventKit
import Speech
import UserNotifications

public enum OnboardingPermissionID: String, CaseIterable, Identifiable, Sendable {
    case accessibility
    case inputMonitoring = "input_monitoring"
    case screenRecording = "screen_recording"
    case systemAudio = "system_audio"
    case microphone, camera
    case speechRecognition = "speech_recognition"
    case calendar, reminders, location, notifications, bluetooth, automation, files
    case fullDiskAccess = "full_disk_access"

    public var id: String { rawValue }
    public var requiresManualSetup: Bool {
        switch self {
        case .systemAudio, .automation, .files, .fullDiskAccess: true
        default: false
        }
    }
    public var titleKey: String { "onboarding.permission.\(rawValue).title" }
    public var bodyKey: String { "onboarding.permission.\(rawValue).body" }
    public var settingsURL: URL {
        let pane: String
        switch self {
        case .accessibility: pane = "com.apple.preference.security?Privacy_Accessibility"
        case .inputMonitoring: pane = "com.apple.preference.security?Privacy_ListenEvent"
        case .screenRecording, .systemAudio: pane = "com.apple.preference.security?Privacy_ScreenCapture"
        case .microphone: pane = "com.apple.preference.security?Privacy_Microphone"
        case .camera: pane = "com.apple.preference.security?Privacy_Camera"
        case .speechRecognition: pane = "com.apple.preference.security?Privacy_SpeechRecognition"
        case .calendar: pane = "com.apple.preference.security?Privacy_Calendars"
        case .reminders: pane = "com.apple.preference.security?Privacy_Reminders"
        case .location: pane = "com.apple.preference.security?Privacy_LocationServices"
        case .notifications: pane = "com.apple.preference.notifications"
        case .bluetooth: pane = "com.apple.preference.security?Privacy_Bluetooth"
        case .automation: pane = "com.apple.preference.security?Privacy_Automation"
        case .files: pane = "com.apple.preference.security?Privacy_FilesAndFolders"
        case .fullDiskAccess: pane = "com.apple.preference.security?Privacy_AllFiles"
        }
        return URL(string: "x-apple.systempreferences:\(pane)")!
    }
}

public enum OnboardingPermissionStatus: Equatable, Sendable {
    case notDetermined, denied, restricted, granted, requesting, manual, unavailable

    public var localizationKey: String {
        switch self {
        case .notDetermined, .denied: "onboarding.not_granted"
        case .restricted: "onboarding.restricted"
        case .granted: "onboarding.granted"
        case .requesting: "onboarding.requesting"
        case .manual: "onboarding.manual"
        case .unavailable: "onboarding.unavailable"
        }
    }
}

public struct OnboardingPermissionItem: Identifiable, Equatable, Sendable {
    public let id: OnboardingPermissionID
    public let status: OnboardingPermissionStatus
    public var titleKey: String { id.titleKey }
    public var bodyKey: String { id.bodyKey }
    public var settingsURL: URL { id.settingsURL }
    public var actionKey: String {
        switch status {
        case .denied, .restricted, .manual: "onboarding.open_settings"
        case .unavailable: "onboarding.retry"
        default: "onboarding.grant"
        }
    }
}

@MainActor
public final class OnboardingPermissionCoordinator: ObservableObject {
    public typealias Completion = @MainActor @Sendable (OnboardingPermissionStatus) -> Void
    public typealias RequestCompletion = @MainActor @Sendable (Result<OnboardingPermissionStatus, Error>) -> Void

    public struct Dependencies {
        public var read: (OnboardingPermissionID, @escaping Completion) -> Void
        public var request: (OnboardingPermissionID, @escaping RequestCompletion) -> Void
        public var cancel: () -> Void
        public var openSettings: (URL) -> Bool

        public init(
            read: @escaping (OnboardingPermissionID, @escaping Completion) -> Void,
            request: @escaping (OnboardingPermissionID, @escaping RequestCompletion) -> Void,
            cancel: @escaping () -> Void,
            openSettings: @escaping (URL) -> Bool
        ) {
            self.read = read
            self.request = request
            self.cancel = cancel
            self.openSettings = openSettings
        }
    }

    @Published public private(set) var permissions = OnboardingPermissionID.allCases.map {
        OnboardingPermissionItem(id: $0, status: $0.requiresManualSetup ? .manual : .notDetermined)
    }
    @Published public private(set) var requesting: OnboardingPermissionID?
    public private(set) var isClosed = false
    private let dependencies: Dependencies
    private var generation = UUID()
    private var refreshGeneration = UUID()

    public convenience init() {
        let system = OnboardingSystemPermissions()
        self.init(dependencies: Dependencies(
            read: { system.read($0, completion: $1) },
            request: { system.request($0, completion: $1) },
            cancel: { system.cancel() },
            openSettings: { NSWorkspace.shared.open($0) }
        ))
    }

    public init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    /// Call when presenting the flow and whenever the application returns to the foreground.
    public func refresh() {
        guard !isClosed else { return }
        refreshGeneration = UUID()
        let token = refreshGeneration
        for id in OnboardingPermissionID.allCases where id != requesting {
            dependencies.read(id) { [weak self] status in
                guard let self, !self.isClosed, self.refreshGeneration == token,
                      self.requesting != id else { return }
                self.update(id, status: status)
            }
        }
    }

    @discardableResult
    public func request(_ id: OnboardingPermissionID) -> Bool {
        guard !isClosed, requesting == nil,
              let item = permissions.first(where: { $0.id == id }),
              item.status == .notDetermined || item.status == .unavailable else { return false }
        refreshGeneration = UUID()
        generation = UUID()
        let token = generation
        let previousStatus = item.status
        requesting = id
        update(id, status: .requesting)
        dependencies.read(id) { [weak self] status in
            guard let self, !self.isClosed, self.generation == token, self.requesting == id else { return }
            guard status == .notDetermined || status == .unavailable else {
                self.requesting = nil
                self.update(id, status: status)
                return
            }
            self.dependencies.request(id) { [weak self] result in
                guard let self, !self.isClosed, self.generation == token, self.requesting == id else { return }
                self.requesting = nil
                self.dependencies.cancel()
                switch result {
                case .success(let status): self.update(id, status: status)
                case .failure: self.update(id, status: previousStatus)
                }
            }
        }
        return true
    }

    @discardableResult
    public func openSettings(for id: OnboardingPermissionID) -> Bool {
        guard !isClosed else { return false }
        return dependencies.openSettings(id.settingsURL)
    }

    public func cancelCurrentRequest() {
        generation = UUID()
        refreshGeneration = UUID()
        let id = requesting
        requesting = nil
        dependencies.cancel()
        if let id { update(id, status: .notDetermined) }
        refresh()
    }

    /// Terminal: create a new coordinator if the user opens another onboarding flow.
    public func close() {
        guard !isClosed else { return }
        isClosed = true
        generation = UUID()
        refreshGeneration = UUID()
        let id = requesting
        requesting = nil
        dependencies.cancel()
        if let id { update(id, status: .notDetermined) }
    }

    private func update(_ id: OnboardingPermissionID, status: OnboardingPermissionStatus) {
        guard let index = permissions.firstIndex(where: { $0.id == id }) else { return }
        if status == .notDetermined, permissions[index].status == .denied,
           id == .accessibility || id == .inputMonitoring || id == .screenRecording {
            // Boolean preflight APIs cannot distinguish a denial from an unasked permission.
            return
        }
        permissions[index] = OnboardingPermissionItem(id: id, status: status)
    }
}

@MainActor
private final class OnboardingSystemPermissions: NSObject,
    @preconcurrency CLLocationManagerDelegate, @preconcurrency CBCentralManagerDelegate {
    private var locationManager: CLLocationManager?
    private var bluetoothManager: CBCentralManager?
    private var pending: OnboardingPermissionCoordinator.RequestCompletion?
    private var timeout: Task<Void, Never>?
    private var host: NSWindow?

    func read(_ id: OnboardingPermissionID, completion: @escaping OnboardingPermissionCoordinator.Completion) {
        switch id {
        case .accessibility: completion(AccessibilityPermission.isTrusted ? .granted : .notDetermined)
        case .inputMonitoring: completion(GlobalHotkeyManager.hasInputMonitoringAccess ? .granted : .notDetermined)
        case .screenRecording: completion(CGPreflightScreenCaptureAccess() ? .granted : .notDetermined)
        case .microphone, .camera:
            switch AVCaptureDevice.authorizationStatus(for: id == .camera ? .video : .audio) {
            case .authorized: completion(.granted)
            case .denied: completion(.denied)
            case .restricted: completion(.restricted)
            case .notDetermined: completion(.notDetermined)
            @unknown default: completion(.unavailable)
            }
        case .speechRecognition:
            switch SFSpeechRecognizer.authorizationStatus() {
            case .authorized: completion(.granted)
            case .denied: completion(.denied)
            case .restricted: completion(.restricted)
            case .notDetermined: completion(.notDetermined)
            @unknown default: completion(.unavailable)
            }
        case .calendar, .reminders:
            switch EKEventStore.authorizationStatus(for: id == .calendar ? .event : .reminder) {
            case .fullAccess, .authorized: completion(.granted)
            case .writeOnly, .denied: completion(.denied)
            case .restricted: completion(.restricted)
            case .notDetermined: completion(.notDetermined)
            @unknown default: completion(.unavailable)
            }
        case .location:
            completion(CLLocationManager.locationServicesEnabled()
                ? Self.locationStatus(CLLocationManager().authorizationStatus) : .unavailable)
        case .notifications:
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                let status: OnboardingPermissionStatus
                switch settings.authorizationStatus {
                case .authorized, .provisional, .ephemeral: status = .granted
                case .denied: status = .denied
                case .notDetermined: status = .notDetermined
                @unknown default: status = .unavailable
                }
                Task { @MainActor in completion(status) }
            }
        case .bluetooth:
            completion(Self.bluetoothStatus())
        case .systemAudio, .automation, .files, .fullDiskAccess:
            // These permissions have no global public preflight/request API.
            completion(.manual)
        }
    }

    func request(_ id: OnboardingPermissionID, completion: @escaping OnboardingPermissionCoordinator.RequestCompletion) {
        pendingToken = UUID()
        pending = completion
        host = WindowPlacement.authorizationPromptHost()
        let timeoutToken = pendingToken
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
            self?.finish(.failure(CancellationError()), matching: timeoutToken)
        }
        switch id {
        case .accessibility:
            _ = AccessibilityPermission.promptIfNeeded()
            finish(.success(AccessibilityPermission.isTrusted ? .granted : .denied))
        case .inputMonitoring:
            _ = GlobalHotkeyManager.requestInputMonitoringAccess()
            finish(.success(GlobalHotkeyManager.hasInputMonitoringAccess ? .granted : .denied))
        case .screenRecording:
            _ = CGRequestScreenCaptureAccess()
            finish(.success(CGPreflightScreenCaptureAccess() ? .granted : .denied))
        case .microphone, .camera:
            let media: AVMediaType = id == .camera ? .video : .audio
            let token = pendingToken
            Task.detached { [weak self] in
                let granted = await AVCaptureDevice.requestAccess(for: media)
                await self?.finish(.success(granted ? .granted : .denied), matching: token)
            }
        case .speechRecognition:
            let token = pendingToken
            Self.requestSpeech { [weak self] in
                Task { @MainActor in
                    guard let self, self.pendingToken == token else { return }
                    self.read(.speechRecognition) { self.finish(.success($0), matching: token) }
                }
            }
        case .calendar, .reminders, .notifications:
            let token = pendingToken
            Task { [weak self] in
                do {
                    let granted: Bool
                    switch id {
                    case .calendar: granted = try await EKEventStore().requestFullAccessToEvents()
                    case .reminders: granted = try await EKEventStore().requestFullAccessToReminders()
                    default: granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                    }
                    self?.finish(.success(granted ? .granted : .denied), matching: token)
                } catch { self?.finish(.failure(error), matching: token) }
            }
        case .location:
            let manager = CLLocationManager()
            locationManager = manager
            manager.delegate = self
            manager.requestWhenInUseAuthorization()
        case .bluetooth:
            bluetoothManager = CBCentralManager(delegate: self, queue: .main, options: [CBCentralManagerOptionShowPowerAlertKey: false])
        case .systemAudio, .automation, .files, .fullDiskAccess: finish(.success(.manual))
        }
    }

    private var pendingToken = UUID()

    func cancel() {
        pendingToken = UUID()
        pending = nil
        timeout?.cancel()
        timeout = nil
        locationManager?.delegate = nil
        locationManager?.stopUpdatingLocation()
        locationManager = nil
        bluetoothManager?.delegate = nil
        bluetoothManager = nil
        host?.orderOut(nil)
        host?.close()
        host = nil
    }

    private func finish(_ result: Result<OnboardingPermissionStatus, Error>, matching token: UUID? = nil) {
        if let token, token != pendingToken { return }
        let completion = pending
        cancel()
        completion?(result)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager === locationManager else { return }
        let status = Self.locationStatus(manager.authorizationStatus)
        if status != .notDetermined { finish(.success(status)) }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central === bluetoothManager else { return }
        let status = Self.bluetoothStatus()
        if status != .notDetermined { finish(.success(status)) }
        else if central.state == .unsupported || central.state == .poweredOff {
            finish(.success(.unavailable))
        }
    }

    private static func locationStatus(_ status: CLAuthorizationStatus) -> OnboardingPermissionStatus {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse: .granted
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notDetermined
        @unknown default: .unavailable
        }
    }

    private static func bluetoothStatus() -> OnboardingPermissionStatus {
        switch CBManager.authorization {
        case .allowedAlways: .granted
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notDetermined
        @unknown default: .unavailable
        }
    }

    nonisolated private static func requestSpeech(_ completion: @escaping @Sendable () -> Void) {
        SFSpeechRecognizer.requestAuthorization { _ in completion() }
    }
}
