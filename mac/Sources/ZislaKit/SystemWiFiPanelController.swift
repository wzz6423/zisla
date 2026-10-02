import AppKit
import Combine

@MainActor
public final class SystemWiFiPanelController: ObservableObject {
    public enum Activity: Equatable {
        case idle
        case scanning
        case updatingPower
        case connecting(WiFiNetwork.ID)
        case authorizing
    }

    public enum SettingsDestination {
        case location
        case wifi
    }

    @Published public private(set) var isPresented = false
    @Published public private(set) var snapshot: WiFiNetworkSnapshot?
    @Published public private(set) var activity = Activity.idle
    @Published public private(set) var failure: WiFiNetworkFailure?
    @Published public private(set) var authorization: WiFiNetworkAuthorizationState
    @Published public private(set) var passwordNetwork: WiFiNetwork?

    public var isBusy: Bool { activity != .idle }
    public var canSetPower: Bool { snapshot != nil && (activity == .idle || activity == .scanning) }

    private let backend: any WiFiNetworkBackend
    private let authorizer: any WiFiNetworkAuthorizing
    private let openURL: @MainActor (URL) -> Bool
    private var operationID: UUID?
    private(set) var operationTask: Task<Void, Never>?

    public convenience init() {
        self.init(
            backend: CoreWLANWiFiNetworkBackend(),
            authorizer: CoreLocationWiFiNetworkAuthorizer(),
            openURL: { NSWorkspace.shared.open($0) }
        )
    }

    init(
        backend: any WiFiNetworkBackend,
        authorizer: any WiFiNetworkAuthorizing,
        openURL: @escaping @MainActor (URL) -> Bool
    ) {
        self.backend = backend
        self.authorizer = authorizer
        self.openURL = openURL
        authorization = authorizer.status
        authorizer.onChange = { [weak self] in
            guard let self else { return }
            let updatedAuthorization = self.authorizer.status
            guard authorization != updatedAuthorization else { return }
            authorization = updatedAuthorization
            guard isPresented else { return }
            operationTask?.cancel()
            activity = .idle
            snapshot = nil
            refresh()
        }
    }

    public func openPanel() {
        guard !isPresented else { return }
        isPresented = true
        refresh()
    }

    public func closePanel() {
        isPresented = false
        operationID = nil
        operationTask?.cancel()
        operationTask = nil
        activity = .idle
        passwordNetwork = nil
        failure = nil
        snapshot = nil
        authorizer.cancel()
    }

    public func refresh() {
        guard isPresented, !isBusy else { return }
        authorization = authorizer.status
        passwordNetwork = nil
        start(.refresh, activity: .scanning)
    }

    public func requestLocationAuthorization() {
        guard isPresented, !isBusy, authorization == .notDetermined else { return }
        failure = nil
        activity = .authorizing
        authorizer.request()
    }

    public func setPower(_ enabled: Bool) {
        guard isPresented, canSetPower, let snapshot, snapshot.powerOn != enabled else { return }
        operationTask?.cancel()
        passwordNetwork = nil
        start(.power(enabled), activity: .updatingPower)
    }

    public func selectNetwork(_ network: WiFiNetwork) {
        guard isPresented, !isBusy, snapshot?.powerOn == true, authorization == .authorized else { return }
        guard let current = snapshot?.networks.first(where: { $0.id == network.id }) else {
            failure = .networkUnavailable
            return
        }
        guard !current.isConnected else { return }
        failure = nil
        switch current.id.security {
        case .open:
            start(.connect(current.id, nil), activity: .connecting(current.id))
        case .personal:
            passwordNetwork = current
        case .enterprise, .unsupported:
            failure = .requiresSystemSettings
        }
    }

    public func cancelPasswordEntry() {
        passwordNetwork = nil
        failure = nil
    }

    public func connect(password: String) {
        guard isPresented, !isBusy, let network = passwordNetwork else { return }
        guard !password.isEmpty else {
            failure = .passwordRequired
            return
        }
        passwordNetwork = nil
        start(.connect(network.id, password), activity: .connecting(network.id))
    }

    public func openSettings(_ destination: SettingsDestination) -> Bool {
        let address = switch destination {
        case .location:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"
        case .wifi:
            "x-apple.systempreferences:com.apple.wifi-settings-extension"
        }
        guard openURL(URL(string: address)!) else {
            failure = .settingsUnavailable
            return false
        }
        closePanel()
        return true
    }

    private enum Request {
        case refresh
        case power(Bool)
        case connect(WiFiNetwork.ID, String?)
    }

    private func start(_ request: Request, activity: Activity) {
        let id = UUID()
        operationID = id
        self.activity = activity
        failure = nil
        operationTask = Task { [weak self] in
            guard let self else { return }
            do {
                try Task.checkCancellation()
                let result = try await perform(request)
                try Task.checkCancellation()
                guard operationID == id else { return }
                snapshot = result
            } catch {
                guard !Task.isCancelled, operationID == id else { return }
                failure = (error as? WiFiNetworkFailure) ?? fallbackFailure
            }
            guard operationID == id else { return }
            self.activity = .idle
            operationTask = nil
            operationID = nil
        }
    }

    private func perform(_ request: Request) async throws -> WiFiNetworkSnapshot {
        switch request {
        case .refresh:
            let state = try await backend.readState(scan: false)
            try Task.checkCancellation()
            snapshot = state
            guard state.powerOn, authorization == .authorized else { return state }
            return try await backend.readState(scan: true)
        case .power(let enabled):
            let state = try await backend.setPower(enabled)
            try Task.checkCancellation()
            guard state.powerOn == enabled else { throw WiFiNetworkFailure.powerChangeFailed }
            snapshot = state
            guard enabled, authorization == .authorized else { return state }
            activity = .scanning
            return try await backend.readState(scan: true)
        case .connect(let id, let password):
            let state = try await backend.connect(to: id, password: password)
            try Task.checkCancellation()
            guard state.networks.contains(where: { $0.id == id && $0.isConnected }) else {
                throw WiFiNetworkFailure.connectionFailed
            }
            return state
        }
    }

    private var fallbackFailure: WiFiNetworkFailure {
        switch activity {
        case .updatingPower: .powerChangeFailed
        case .connecting: .connectionFailed
        default: .scanFailed
        }
    }
}
