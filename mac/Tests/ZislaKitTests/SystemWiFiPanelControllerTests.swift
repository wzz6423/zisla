import Foundation
import Testing
@testable import ZislaKit

@Suite(.timeLimit(.minutes(1)))
@MainActor
struct SystemWiFiPanelControllerTests {
    @Test
    func thePanelOpensImmediatelyWhileItsFirstScanIsPending() async {
        let backend = FakeWiFiNetworkBackend()
        let gate = WiFiRequestGate()
        backend.gate = gate
        let controller = makeController(backend: backend)

        controller.openPanel()
        #expect(controller.isPresented)
        await gate.waitUntilSuspended()
        #expect(controller.isBusy)
        #expect(controller.snapshot == nil)

        gate.resume()
        await controller.operationTask?.value
        #expect(controller.snapshot == backend.state)
        #expect(!controller.isBusy)
    }

    @Test
    func openingThePanelDoesNotChangeTheNetworkOrPromptForPermission() async {
        let backend = FakeWiFiNetworkBackend()
        let authorization = FakeWiFiNetworkAuthorization()
        let controller = makeController(backend: backend, authorization: authorization)
        controller.openPanel()
        await controller.operationTask?.value

        #expect(backend.scans == [false, true])
        #expect(backend.powerRequests.isEmpty)
        #expect(backend.connections.isEmpty)
        #expect(authorization.requests == 0)
    }

    @Test(arguments: [WiFiNetworkAuthorizationState.notDetermined, .denied])
    func missingLocationAuthorizationShowsPowerWithoutScanning(status: WiFiNetworkAuthorizationState) async {
        let backend = FakeWiFiNetworkBackend()
        let authorization = FakeWiFiNetworkAuthorization(status: status)
        let controller = makeController(backend: backend, authorization: authorization)
        controller.openPanel()
        await controller.operationTask?.value

        #expect(controller.isPresented)
        #expect(controller.snapshot?.powerOn == true)
        #expect(controller.authorization == status)
        #expect(backend.scans == [false])
        #expect(authorization.requests == 0)
    }

    @Test
    func authorizationDenialReleasesBusyStateAndLaterGrantRefreshes() async {
        let backend = FakeWiFiNetworkBackend()
        let authorization = FakeWiFiNetworkAuthorization(status: .notDetermined)
        let controller = makeController(backend: backend, authorization: authorization)
        controller.openPanel()
        await controller.operationTask?.value
        controller.requestLocationAuthorization()
        #expect(controller.activity == .authorizing)
        #expect(authorization.requests == 1)

        authorization.change(to: .denied)
        await controller.operationTask?.value
        #expect(!controller.isBusy)
        #expect(controller.authorization == .denied)
        #expect(!backend.scans.contains(true))

        authorization.change(to: .authorized)
        await controller.operationTask?.value
        #expect(controller.authorization == .authorized)
        #expect(backend.scans.last == true)
    }

    @Test
    func cancelledAuthorizationDoesNotStartALateScan() async {
        let backend = FakeWiFiNetworkBackend()
        let authorization = FakeWiFiNetworkAuthorization(status: .notDetermined)
        let controller = makeController(backend: backend, authorization: authorization)
        controller.openPanel()
        await controller.operationTask?.value
        controller.requestLocationAuthorization()
        controller.closePanel()
        authorization.change(to: .authorized)

        #expect(!controller.isPresented)
        #expect(!controller.isBusy)
        #expect(backend.scans == [false])
        #expect(authorization.cancellations > 0)
    }

    @Test
    func aPendingAuthorizationCallbackDoesNotStartASecondPromptOrScan() async {
        let backend = FakeWiFiNetworkBackend()
        let authorization = FakeWiFiNetworkAuthorization(status: .notDetermined)
        let controller = makeController(backend: backend, authorization: authorization)
        controller.openPanel()
        await controller.operationTask?.value
        controller.requestLocationAuthorization()
        authorization.change(to: .notDetermined)
        controller.requestLocationAuthorization()
        #expect(controller.activity == .authorizing)
        #expect(authorization.requests == 1)
        #expect(backend.scans == [false])
        controller.closePanel()
    }

    @Test
    func aScanFailureLeavesThePanelOpenAndRetryRecovers() async {
        let backend = FakeWiFiNetworkBackend()
        backend.failure = WiFiNetworkFailure.scanFailed
        backend.failOnlyOnScan = true
        let controller = makeController(backend: backend)
        controller.openPanel()
        await controller.operationTask?.value
        #expect(controller.isPresented)
        #expect(controller.failure == .scanFailed)
        #expect(controller.snapshot?.powerOn == true)
        #expect(!controller.isBusy)

        backend.failure = nil
        controller.refresh()
        await controller.operationTask?.value
        #expect(controller.failure == nil)
        #expect(controller.snapshot == backend.state)
    }

    @Test
    func missingHardwareDoesNotPretendWiFiIsOff() async {
        let backend = FakeWiFiNetworkBackend()
        backend.failure = WiFiNetworkFailure.interfaceUnavailable
        let controller = makeController(backend: backend)
        controller.openPanel()
        await controller.operationTask?.value
        #expect(controller.snapshot == nil)
        #expect(controller.failure == .interfaceUnavailable)
        controller.setPower(true)
        #expect(backend.powerRequests.isEmpty)
    }

    @Test
    func concurrentRefreshAndOpenDoNotStartDuplicateScans() async {
        let backend = FakeWiFiNetworkBackend()
        let gate = WiFiRequestGate()
        backend.gate = gate
        let controller = makeController(backend: backend)
        controller.openPanel()
        await gate.waitUntilSuspended()
        controller.openPanel()
        controller.refresh()
        #expect(backend.scans == [false])
        gate.resume()
        await controller.operationTask?.value
    }

    @Test
    func closingBeforeWorkStartsHasNoBackendSideEffects() async {
        let backend = FakeWiFiNetworkBackend()
        let controller = makeController(backend: backend)
        controller.openPanel()
        let task = controller.operationTask
        controller.closePanel()
        await task?.value
        #expect(backend.scans.isEmpty)
        #expect(controller.snapshot == nil)
        #expect(!controller.isBusy)
    }

    @Test
    func aLateCancelledScanCannotOverwriteAReopenedPanel() async {
        let backend = FakeWiFiNetworkBackend()
        let gate = WiFiRequestGate()
        backend.gate = gate
        let controller = makeController(backend: backend)
        controller.openPanel()
        await gate.waitUntilSuspended()
        let staleTask = controller.operationTask

        controller.closePanel()
        backend.gate = nil
        backend.state = WiFiNetworkSnapshot(powerOn: false)
        controller.openPanel()
        await controller.operationTask?.value
        gate.resume()
        await staleTask?.value
        #expect(controller.isPresented)
        #expect(controller.snapshot?.powerOn == false)
        #expect(controller.failure == nil)
        #expect(!controller.isBusy)
    }

    @Test
    func powerChangesPublishObservedStateAndTurnOnRefreshesTheList() async {
        let backend = FakeWiFiNetworkBackend()
        let controller = makeController(backend: backend)
        controller.openPanel()
        await controller.operationTask?.value
        controller.setPower(false)
        await controller.operationTask?.value
        #expect(controller.snapshot?.powerOn == false)
        #expect(controller.snapshot?.networks.isEmpty == true)

        controller.setPower(true)
        await controller.operationTask?.value
        #expect(controller.snapshot?.powerOn == true)
        #expect(backend.powerRequests == [false, true])
        #expect(backend.scans == [false, true, true])
    }

    @Test(arguments: [false, true])
    func powerCanBeChangedWhileScanningWithoutPublishingTheCancelledResult(rejectPowerChange: Bool) async {
        let backend = FakeWiFiNetworkBackend()
        let gate = WiFiRequestGate()
        backend.scanGate = gate
        let controller = makeController(backend: backend)
        controller.openPanel()
        await gate.waitUntilSuspended()
        let scanTask = controller.operationTask
        #expect(controller.snapshot?.powerOn == true)
        #expect(controller.activity == .scanning)

        if rejectPowerChange { backend.failure = WiFiNetworkFailure.powerChangeFailed }
        controller.setPower(false)
        #expect(controller.activity == .updatingPower)
        #expect(scanTask?.isCancelled == true)
        let powerTask = controller.operationTask
        gate.resume()
        await powerTask?.value
        await scanTask?.value

        #expect(backend.powerRequests == [false])
        #expect(controller.snapshot?.powerOn == rejectPowerChange)
        #expect(controller.snapshot?.networks.isEmpty == true)
        #expect(controller.failure == (rejectPowerChange ? .powerChangeFailed : nil))
        #expect(!controller.isBusy)
        controller.closePanel()
    }

    @Test
    func aRejectedPowerChangeDoesNotOptimisticallyFlipTheToggle() async {
        let backend = FakeWiFiNetworkBackend()
        let controller = makeController(backend: backend)
        controller.openPanel()
        await controller.operationTask?.value
        backend.failure = WiFiNetworkFailure.powerChangeFailed
        controller.setPower(false)
        await controller.operationTask?.value
        #expect(controller.snapshot?.powerOn == true)
        #expect(controller.failure == .powerChangeFailed)
        #expect(!controller.isBusy)
    }

    @Test
    func selectingTheCurrentNetworkDoesNotDisconnectIt() async {
        let backend = FakeWiFiNetworkBackend()
        backend.state = WiFiNetworkSnapshot(powerOn: true, networks: [network(connected: true)])
        let controller = makeController(backend: backend)
        controller.openPanel()
        await controller.operationTask?.value
        controller.selectNetwork(backend.state.networks[0])
        #expect(backend.connections.isEmpty)
        #expect(controller.passwordNetwork == nil)
    }

    @Test
    func selectingAnOpenNetworkConnectsWithoutAPassword() async {
        let backend = FakeWiFiNetworkBackend()
        backend.state = WiFiNetworkSnapshot(powerOn: true, networks: [network(security: .open)])
        let controller = makeController(backend: backend)
        controller.openPanel()
        await controller.operationTask?.value
        controller.selectNetwork(backend.state.networks[0])
        await controller.operationTask?.value
        #expect(backend.connections.count == 1)
        #expect(backend.connections[0].password == nil)
        #expect(controller.snapshot?.networks.first?.isConnected == true)
    }

    @Test
    func aKnownSecuredNetworkRequiresAnExplicitPassword() async {
        let backend = FakeWiFiNetworkBackend()
        let controller = makeController(backend: backend)
        controller.openPanel()
        await controller.operationTask?.value
        controller.selectNetwork(backend.state.networks[0])
        #expect(controller.passwordNetwork?.isKnown == true)
        #expect(backend.connections.isEmpty)
        controller.connect(password: "")
        #expect(controller.failure == .passwordRequired)
        #expect(backend.connections.isEmpty)

        controller.connect(password: "test-wifi-password")
        #expect(controller.passwordNetwork == nil)
        await controller.operationTask?.value
        #expect(backend.connections.count == 1)
        #expect(backend.connections[0].password == "test-wifi-password")
        #expect(controller.snapshot?.networks.first?.isConnected == true)
    }

    @Test
    func cancellingPasswordEntryDoesNotJoinANetwork() async {
        let backend = FakeWiFiNetworkBackend()
        let controller = makeController(backend: backend)
        controller.openPanel()
        await controller.operationTask?.value
        controller.selectNetwork(backend.state.networks[0])
        controller.cancelPasswordEntry()
        controller.connect(password: "discarded-password")
        #expect(controller.passwordNetwork == nil)
        #expect(backend.connections.isEmpty)
    }

    @Test
    func closingBeforeTheConnectionStartsDiscardsTheQueuedPassword() async {
        let backend = FakeWiFiNetworkBackend()
        let controller = makeController(backend: backend)
        controller.openPanel()
        await controller.operationTask?.value
        controller.selectNetwork(backend.state.networks[0])
        controller.connect(password: "discarded-password")
        let task = controller.operationTask
        controller.closePanel()
        await task?.value
        #expect(backend.connections.isEmpty)
        #expect(controller.passwordNetwork == nil)
        #expect(controller.snapshot == nil)
    }

    @Test
    func aFailedConnectionCanBeRetriedWithoutReopeningThePanel() async {
        let backend = FakeWiFiNetworkBackend()
        let controller = makeController(backend: backend)
        controller.openPanel()
        await controller.operationTask?.value
        let network = backend.state.networks[0]
        backend.failure = WiFiNetworkFailure.connectionFailed
        controller.selectNetwork(network)
        controller.connect(password: "incorrect-fixture-password")
        await controller.operationTask?.value
        #expect(controller.failure == .connectionFailed)
        backend.failure = nil
        controller.selectNetwork(network)
        controller.connect(password: "correct-fixture-password")
        await controller.operationTask?.value
        #expect(controller.failure == nil)
        #expect(controller.snapshot?.networks.first?.isConnected == true)
        #expect(backend.connections.count == 2)
    }

    @Test(arguments: [WiFiNetwork.Security.enterprise, .unsupported])
    func unsupportedAuthenticationUsesAnExplicitSettingsRoute(security: WiFiNetwork.Security) async {
        let backend = FakeWiFiNetworkBackend()
        backend.state = WiFiNetworkSnapshot(powerOn: true, networks: [network(security: security)])
        let controller = makeController(backend: backend)
        controller.openPanel()
        await controller.operationTask?.value
        controller.selectNetwork(backend.state.networks[0])
        #expect(controller.failure == .requiresSystemSettings)
        #expect(controller.passwordNetwork == nil)
        #expect(backend.connections.isEmpty)
    }

    @Test
    func aStaleNetworkCannotBeJoinedAfterItDisappears() async {
        let backend = FakeWiFiNetworkBackend()
        let controller = makeController(backend: backend)
        controller.openPanel()
        await controller.operationTask?.value
        let oldNetwork = backend.state.networks[0]
        backend.state = WiFiNetworkSnapshot(powerOn: true)
        controller.refresh()
        await controller.operationTask?.value
        controller.selectNetwork(oldNetwork)
        #expect(controller.failure == .networkUnavailable)
        #expect(backend.connections.isEmpty)
    }

    @Test
    func aConnectionErrorNeverDisplaysUnderlyingCredentialDetails() async {
        let backend = FakeWiFiNetworkBackend()
        let controller = makeController(backend: backend)
        controller.openPanel()
        await controller.operationTask?.value
        controller.selectNetwork(backend.state.networks[0])
        backend.failure = NSError(domain: "fixture", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "secret test-wifi-password"
        ])
        controller.connect(password: "test-wifi-password")
        await controller.operationTask?.value
        #expect(controller.failure == .connectionFailed)
        #expect(controller.failure?.messageKey.contains("test-wifi-password") == false)
        #expect(controller.passwordNetwork == nil)
        #expect(controller.snapshot?.networks.first?.isConnected == false)
    }

    @Test
    func connectionSuccessRequiresMatchingObservedState() async {
        let backend = FakeWiFiNetworkBackend()
        backend.observesConnection = false
        let controller = makeController(backend: backend)
        controller.openPanel()
        await controller.operationTask?.value
        controller.selectNetwork(backend.state.networks[0])
        controller.connect(password: "test-wifi-password")
        await controller.operationTask?.value
        #expect(controller.failure == .connectionFailed)
        #expect(controller.snapshot?.networks.first?.isConnected == false)
    }

    @Test
    func onlyExplicitSettingsActionsOpenURLsAndFailureRemainsVisible() async {
        let backend = FakeWiFiNetworkBackend()
        var urls: [URL] = []
        let controller = SystemWiFiPanelController(
            backend: backend, authorizer: FakeWiFiNetworkAuthorization(),
            openURL: { urls.append($0); return urls.count > 1 }
        )
        controller.openPanel()
        await controller.operationTask?.value
        #expect(urls.isEmpty)
        #expect(!controller.openSettings(.wifi))
        #expect(controller.failure == .settingsUnavailable)
        #expect(controller.isPresented)
        #expect(controller.openSettings(.location))
        #expect(!controller.isPresented)
        #expect(urls.map(\.absoluteString) == [
            "x-apple.systempreferences:com.apple.wifi-settings-extension",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"
        ])
    }

    @Test
    func revokingAuthorizationDuringAScanDiscardsLateIdentities() async {
        let backend = FakeWiFiNetworkBackend()
        let authorization = FakeWiFiNetworkAuthorization()
        let gate = WiFiRequestGate()
        backend.scanGate = gate
        let controller = makeController(backend: backend, authorization: authorization)
        controller.openPanel()
        await gate.waitUntilSuspended()
        let staleTask = controller.operationTask

        authorization.change(to: .denied)
        #expect(controller.snapshot == nil)
        #expect(staleTask?.isCancelled == true)
        gate.resume()
        await controller.operationTask?.value
        await staleTask?.value
        #expect(controller.authorization == .denied)
        #expect(controller.snapshot?.networks.isEmpty == true)
        #expect(!controller.isBusy)
        #expect(controller.failure == nil)
    }

    @Test
    func revokingAuthorizationDiscardsThePasswordSelectionImmediately() async {
        let backend = FakeWiFiNetworkBackend()
        let authorization = FakeWiFiNetworkAuthorization()
        let controller = makeController(backend: backend, authorization: authorization)
        controller.openPanel()
        await controller.operationTask?.value
        controller.selectNetwork(backend.state.networks[0])
        authorization.change(to: .denied)
        #expect(controller.passwordNetwork == nil)
        controller.connect(password: "discarded-fixture-password")
        await controller.operationTask?.value
        #expect(backend.connections.isEmpty)
        #expect(controller.snapshot?.networks.isEmpty == true)
    }

    @Test
    func duplicateAuthorizationNotificationsPreservePasswordEntry() async {
        let backend = FakeWiFiNetworkBackend()
        let authorization = FakeWiFiNetworkAuthorization()
        let controller = makeController(backend: backend, authorization: authorization)
        controller.openPanel()
        await controller.operationTask?.value
        controller.selectNetwork(backend.state.networks[0])
        authorization.change(to: .authorized)
        #expect(controller.passwordNetwork?.id == backend.state.networks[0].id)
        #expect(!controller.isBusy)
        await controller.operationTask?.value
    }

    private func makeController(
        backend: FakeWiFiNetworkBackend,
        authorization: FakeWiFiNetworkAuthorization = FakeWiFiNetworkAuthorization()
    ) -> SystemWiFiPanelController {
        SystemWiFiPanelController(backend: backend, authorizer: authorization, openURL: { _ in false })
    }

    private func network(
        security: WiFiNetwork.Security = .personal,
        connected: Bool = false
    ) -> WiFiNetwork {
        WiFiNetwork(
            id: .init(ssid: Data("Test Network".utf8), security: security),
            name: "Test Network", rssi: -60, isKnown: true, isConnected: connected
        )
    }
}

@MainActor
private final class FakeWiFiNetworkBackend: WiFiNetworkBackend {
    var state = WiFiNetworkSnapshot(powerOn: true, networks: [
        WiFiNetwork(
            id: .init(ssid: Data("Test Network".utf8), security: .personal),
            name: "Test Network", rssi: -60, isKnown: true
        )
    ])
    var failure: (any Error)?
    var failOnlyOnScan = false
    var gate: WiFiRequestGate?
    var scanGate: WiFiRequestGate?
    var observesConnection = true
    var scans: [Bool] = []
    var powerRequests: [Bool] = []
    var connections: [(id: WiFiNetwork.ID, password: String?)] = []

    func readState(scan: Bool) async throws -> WiFiNetworkSnapshot {
        scans.append(scan)
        let captured = scan ? state : WiFiNetworkSnapshot(powerOn: state.powerOn, isConnected: state.isConnected)
        if scan, let scanGate {
            self.scanGate = nil
            await scanGate.suspend()
        }
        if let gate {
            self.gate = nil
            await gate.suspend()
        }
        if let failure, !failOnlyOnScan || scan { throw failure }
        return captured
    }

    func setPower(_ enabled: Bool) async throws -> WiFiNetworkSnapshot {
        powerRequests.append(enabled)
        if let failure { throw failure }
        state = WiFiNetworkSnapshot(powerOn: enabled)
        return state
    }

    func connect(to id: WiFiNetwork.ID, password: String?) async throws -> WiFiNetworkSnapshot {
        connections.append((id, password))
        if let failure { throw failure }
        if observesConnection {
            state.isConnected = true
            state.networks = state.networks.map {
                var network = $0
                network.isConnected = network.id == id
                return network
            }
        }
        return state
    }
}

@MainActor
private final class FakeWiFiNetworkAuthorization: WiFiNetworkAuthorizing {
    var status: WiFiNetworkAuthorizationState
    var onChange: (@MainActor () -> Void)?
    var requests = 0
    var cancellations = 0

    init(status: WiFiNetworkAuthorizationState = .authorized) { self.status = status }
    func request() { requests += 1 }
    func cancel() { cancellations += 1 }
    func change(to status: WiFiNetworkAuthorizationState) {
        self.status = status
        onChange?()
    }
}

@MainActor
private final class WiFiRequestGate {
    private var suspended: CheckedContinuation<Void, Never>?
    private var startWaiter: CheckedContinuation<Void, Never>?

    func suspend() async {
        await withCheckedContinuation { continuation in
            suspended = continuation
            startWaiter?.resume()
            startWaiter = nil
        }
    }

    func waitUntilSuspended() async {
        guard suspended == nil else { return }
        await withCheckedContinuation { startWaiter = $0 }
    }

    func resume() {
        suspended?.resume()
        suspended = nil
    }
}
