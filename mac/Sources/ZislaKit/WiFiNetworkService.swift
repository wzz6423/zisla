import AppKit
import CoreLocation
import CoreWLAN

public struct WiFiNetwork: Identifiable, Equatable, Sendable {
    public enum Security: Hashable, Sendable {
        case open
        case personal
        case enterprise
        case unsupported
    }

    public struct ID: Hashable, Sendable {
        public let ssid: Data
        public let security: Security
    }

    public let id: ID
    public let name: String
    public let rssi: Int
    public var isKnown = false
    public var isConnected = false
    public var isPersonalHotspot: Bool?

    public var signalStrength: Double {
        if case .connected(let strength) = MenuBarSystemLevelReader.wifiState(powerOn: true, rssi: rssi) {
            return strength
        }
        return 0
    }
}

public struct WiFiNetworkSnapshot: Equatable, Sendable {
    public var powerOn: Bool
    public var isConnected = false
    public var networks: [WiFiNetwork] = []

    public var personalHotspots: [WiFiNetwork] { networks.filter { $0.isPersonalHotspot == true } }
    public var knownNetworks: [WiFiNetwork] {
        networks.filter { $0.isPersonalHotspot != true && ($0.isKnown || $0.isConnected) }
    }
    public var otherNetworks: [WiFiNetwork] {
        networks.filter { $0.isPersonalHotspot != true && !$0.isKnown && !$0.isConnected }
    }

    static func sorted(_ networks: [WiFiNetwork]) -> [WiFiNetwork] {
        networks.sorted {
            if $0.isConnected != $1.isConnected { return $0.isConnected }
            if $0.isKnown != $1.isKnown { return $0.isKnown }
            if $0.rssi != $1.rssi { return $0.rssi > $1.rssi }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
}

public enum WiFiNetworkFailure: Error, Equatable, Sendable {
    case interfaceUnavailable
    case scanFailed
    case powerChangeFailed
    case connectionFailed
    case requiresSystemSettings
    case networkUnavailable
    case passwordRequired
    case settingsUnavailable

    public var messageKey: String {
        switch self {
        case .interfaceUnavailable: "Wi-Fi 不可用"
        case .scanFailed: "无法扫描 Wi-Fi 网络，请重试。"
        case .powerChangeFailed: "无法更改 Wi-Fi 状态，请重试。"
        case .connectionFailed: "无法连接此网络，请检查密码后重试。"
        case .requiresSystemSettings: "此网络需要在系统 Wi-Fi 设置中连接。"
        case .networkUnavailable: "此网络已不可用，请刷新后重试。"
        case .passwordRequired: "请输入网络密码"
        case .settingsUnavailable: "无法打开系统设置，请手动打开。"
        }
    }
}

protocol WiFiNetworkBackend: Sendable {
    func readState(scan: Bool) async throws -> WiFiNetworkSnapshot
    func setPower(_ enabled: Bool) async throws -> WiFiNetworkSnapshot
    func connect(to id: WiFiNetwork.ID, password: String?) async throws -> WiFiNetworkSnapshot
}

actor CoreWLANWiFiNetworkBackend: WiFiNetworkBackend {
    private var scanResults: [WiFiNetwork.ID: CWNetwork] = [:]

    func readState(scan: Bool) async throws -> WiFiNetworkSnapshot {
        try Task.checkCancellation()
        let interface = try currentInterface()
        guard interface.powerOn() else {
            scanResults = [:]
            return WiFiNetworkSnapshot(powerOn: false)
        }
        guard scan else { return snapshot(for: interface, includeIdentity: false) }

        // CoreWLAN scans and association block; this actor keeps them off the main actor and serializes writes.
        let networks = try interface.scanForNetworks(withName: nil)
        try Task.checkCancellation()
        scanResults = Self.scanCandidates(Array(networks), currentBSSID: interface.bssid())
        return snapshot(for: interface, includeIdentity: true)
    }

    static func scanCandidates(_ networks: [CWNetwork], currentBSSID: String?) -> [WiFiNetwork.ID: CWNetwork] {
        var results: [WiFiNetwork.ID: CWNetwork] = [:]
        for network in networks {
            guard let id = Self.identity(for: network) else { continue }
            if let existing = results[id] {
                if let currentBSSID {
                    if existing.bssid?.caseInsensitiveCompare(currentBSSID) == .orderedSame { continue }
                    if network.bssid?.caseInsensitiveCompare(currentBSSID) == .orderedSame {
                        results[id] = network
                        continue
                    }
                }
                if existing.rssiValue >= network.rssiValue { continue }
            }
            results[id] = network
        }
        return results
    }

    func setPower(_ enabled: Bool) async throws -> WiFiNetworkSnapshot {
        try Task.checkCancellation()
        let interface = try currentInterface()
        try Task.checkCancellation()
        try interface.setPower(enabled)
        try Task.checkCancellation()
        guard interface.powerOn() == enabled else { throw WiFiNetworkFailure.powerChangeFailed }
        if !enabled { scanResults = [:] }
        return snapshot(for: interface, includeIdentity: false)
    }

    func connect(to id: WiFiNetwork.ID, password: String?) async throws -> WiFiNetworkSnapshot {
        try Task.checkCancellation()
        let interface = try currentInterface()
        guard interface.powerOn(), let network = scanResults[id] else {
            throw WiFiNetworkFailure.networkUnavailable
        }
        switch id.security {
        case .open: break
        case .personal:
            guard let password, !password.isEmpty else { throw WiFiNetworkFailure.passwordRequired }
        case .enterprise, .unsupported:
            throw WiFiNetworkFailure.requiresSystemSettings
        }
        try Task.checkCancellation()
        try interface.associate(to: network, password: password)
        try Task.checkCancellation()
        return snapshot(for: interface, includeIdentity: true)
    }

    private func currentInterface() throws -> CWInterface {
        guard let interface = CWWiFiClient.shared().interface() else {
            throw WiFiNetworkFailure.interfaceUnavailable
        }
        return interface
    }

    private func snapshot(for interface: CWInterface, includeIdentity: Bool) -> WiFiNetworkSnapshot {
        let powerOn = interface.powerOn()
        let wifiState = MenuBarSystemLevelReader.wifiState(
            powerOn: powerOn, rssi: powerOn ? interface.rssiValue() : 0
        )
        let connected: Bool
        if case .connected = wifiState { connected = true } else { connected = false }
        guard powerOn, includeIdentity else {
            return WiFiNetworkSnapshot(powerOn: powerOn, isConnected: connected)
        }

        let profiles = interface.configuration()?.networkProfiles.array as? [CWNetworkProfile] ?? []
        let knownIDs = Set(profiles.compactMap { profile -> WiFiNetwork.ID? in
            guard let ssid = profile.ssidData, !ssid.isEmpty else { return nil }
            return WiFiNetwork.ID(ssid: ssid, security: Self.security(profile.security))
        })
        let currentID = interface.ssidData().flatMap { ssid -> WiFiNetwork.ID? in
            guard connected, !ssid.isEmpty else { return nil }
            return WiFiNetwork.ID(ssid: ssid, security: Self.security(interface.security()))
        }
        let currentBSSID = interface.bssid()
        let currentHotspot = MenuBarSystemLevelReader.currentPersonalHotspot(
            ssidData: currentID?.ssid, bssid: currentBSSID,
            networks: Array(interface.cachedScanResults() ?? [])
        )
        var networks = scanResults.compactMap { id, network -> WiFiNetwork? in
            guard let name = network.ssid else { return nil }
            let isCurrent = id == currentID
            return WiFiNetwork(
                id: id, name: name, rssi: network.rssiValue,
                isKnown: knownIDs.contains(id), isConnected: isCurrent,
                isPersonalHotspot: isCurrent ? currentHotspot : MenuBarSystemLevelReader.isPersonalHotspot(network)
            )
        }
        if let currentID, let name = interface.ssid(), !networks.contains(where: { $0.id == currentID }) {
            networks.append(WiFiNetwork(
                id: currentID, name: name, rssi: interface.rssiValue(),
                isKnown: knownIDs.contains(currentID), isConnected: true,
                isPersonalHotspot: currentHotspot
            ))
        }
        return WiFiNetworkSnapshot(
            powerOn: powerOn, isConnected: connected, networks: WiFiNetworkSnapshot.sorted(networks)
        )
    }

    private static func identity(for network: CWNetwork) -> WiFiNetwork.ID? {
        guard let ssid = network.ssidData, !ssid.isEmpty, network.ssid != nil else { return nil }
        let modes: [CWSecurity] = [
            .wpa3Personal, .wpa3Transition, .wpa2Personal, .wpaPersonalMixed, .wpaPersonal, .WEP,
            .wpa3Enterprise, .wpa2Enterprise, .wpaEnterpriseMixed, .wpaEnterprise, .dynamicWEP,
            .none, .OWE, .oweTransition
        ]
        let mode = modes.first { network.supportsSecurity($0) } ?? .unknown
        return WiFiNetwork.ID(ssid: ssid, security: security(mode))
    }

    static func security(_ security: CWSecurity) -> WiFiNetwork.Security {
        switch security {
        case .none, .OWE, .oweTransition: .open
        case .WEP, .wpaPersonal, .wpaPersonalMixed, .wpa2Personal, .personal, .wpa3Personal, .wpa3Transition:
            .personal
        case .dynamicWEP, .wpaEnterprise, .wpaEnterpriseMixed, .wpa2Enterprise, .enterprise, .wpa3Enterprise:
            .enterprise
        default: .unsupported
        }
    }
}

public enum WiFiNetworkAuthorizationState: Equatable, Sendable {
    case notDetermined
    case denied
    case authorized
}

@MainActor
protocol WiFiNetworkAuthorizing: AnyObject {
    var status: WiFiNetworkAuthorizationState { get }
    var onChange: (@MainActor () -> Void)? { get set }
    func request()
    func cancel()
}

@MainActor
final class CoreLocationWiFiNetworkAuthorizer: NSObject, WiFiNetworkAuthorizing, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var promptHost: NSWindow?
    var onChange: (@MainActor () -> Void)?

    override init() {
        super.init()
        manager.delegate = self
    }

    var status: WiFiNetworkAuthorizationState {
        guard CLLocationManager.locationServicesEnabled() else { return .denied }
        switch manager.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .authorizedAlways, .authorizedWhenInUse: return .authorized
        default: return .denied
        }
    }

    func request() {
        guard status == .notDetermined else {
            onChange?()
            return
        }
        promptHost = WindowPlacement.authorizationPromptHost()
        manager.requestWhenInUseAuthorization()
    }

    func cancel() {
        promptHost?.orderOut(nil)
        promptHost?.close()
        promptHost = nil
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            if status != .notDetermined { cancel() }
            onChange?()
        }
    }
}
