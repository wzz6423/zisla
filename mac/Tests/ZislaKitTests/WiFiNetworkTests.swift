import CoreWLAN
import Foundation
import Testing
@testable import ZislaKit

struct WiFiNetworkTests {
    @Test
    func scanMergesRadiosWithoutMergingSecurityOrReplacingTheConnectedRadio() {
        let current = WiFiScanFixture(rssi: -80, bssid: "aa:bb:cc:dd:ee:ff")
        let strong = WiFiScanFixture(rssi: -40, bssid: "11:22:33:44:55:66")
        let open = WiFiScanFixture(rssi: -30, bssid: "22:33:44:55:66:77", security: .none)
        for inputs in [[strong, current, open], [current, strong, open]] {
            let networks = CoreWLANWiFiNetworkBackend.scanCandidates(inputs, currentBSSID: "AA:BB:CC:DD:EE:FF")
            #expect(networks.count == 2)
            #expect(networks[.init(ssid: Data("Office".utf8), security: .personal)] === current)
            #expect(networks[.init(ssid: Data("Office".utf8), security: .open)] === open)
        }
        let networks = CoreWLANWiFiNetworkBackend.scanCandidates([current, strong], currentBSSID: nil)
        #expect(networks.values.first === strong)
    }

    @Test
    func redactedAndHiddenScanEntriesNeverBecomeJoinableRows() {
        let hidden = WiFiScanFixture(rssi: -40, bssid: "11:22:33:44:55:66")
        hidden.fixtureSSID = Data()
        let redacted = WiFiScanFixture(rssi: -40, bssid: "22:33:44:55:66:77")
        redacted.fixtureName = nil
        #expect(CoreWLANWiFiNetworkBackend.scanCandidates([hidden, redacted], currentBSSID: nil).isEmpty)
    }

    @Test
    func onlyConfirmedHotspotsUseTheHotspotSectionAndEachNetworkAppearsOnce() {
        var hotspot = network("Hotspot", rssi: -60, known: true, connected: true)
        hotspot.isPersonalHotspot = true
        var regular = network("Office", rssi: -50, known: true)
        regular.isPersonalHotspot = false
        let unknown = network("Unknown", rssi: -40)
        let snapshot = WiFiNetworkSnapshot(powerOn: true, networks: [hotspot, regular, unknown])
        #expect(snapshot.personalHotspots.map(\.name) == ["Hotspot"])
        #expect(snapshot.knownNetworks.map(\.name) == ["Office"])
        #expect(snapshot.otherNetworks.map(\.name) == ["Unknown"])
        #expect(snapshot.personalHotspots.count + snapshot.knownNetworks.count + snapshot.otherNetworks.count == 3)
    }

    @Test
    func identicalNamesWithDifferentSecurityKeepSeparateIdentities() {
        let ssid = Data("Office".utf8)
        let open = WiFiNetwork.ID(ssid: ssid, security: .open)
        let secured = WiFiNetwork.ID(ssid: ssid, security: .personal)
        #expect(Set([open, secured]).count == 2)
    }

    @Test
    func currentAndKnownNetworksPrecedeStrongerUnknownNetworks() {
        let current = network("Current", rssi: -85, connected: true)
        let known = network("Known", rssi: -80, known: true)
        let strong = network("Strong", rssi: -40)
        let weak = network("Weak", rssi: -70)
        let sorted = WiFiNetworkSnapshot.sorted([weak, strong, known, current])
        #expect(sorted.map(\.name) == ["Current", "Known", "Strong", "Weak"])
        #expect(WiFiNetworkSnapshot.sorted([]).isEmpty)
    }

    @Test(arguments: [Int.min, -150, -100, -75, -50, -1, 0, 1, Int.max])
    func signalSymbolsUseTheExistingBoundedWiFiStrength(rssi: Int) {
        let strength = network("Signal", rssi: rssi).signalStrength
        #expect(strength.isFinite)
        #expect((0...1).contains(strength))
        if rssi == -75 { #expect(strength == 0.5) }
        if rssi >= 0 { #expect(strength == 0) }
    }

    @Test
    func enterpriseAndUnknownSecurityNeverBecomePasswordOnlyNetworks() {
        #expect(CoreWLANWiFiNetworkBackend.security(.none) == .open)
        #expect(CoreWLANWiFiNetworkBackend.security(.wpa2Personal) == .personal)
        #expect(CoreWLANWiFiNetworkBackend.security(.wpa3Personal) == .personal)
        #expect(CoreWLANWiFiNetworkBackend.security(.wpa3Transition) == .personal)
        #expect(CoreWLANWiFiNetworkBackend.security(.dynamicWEP) == .enterprise)
        #expect(CoreWLANWiFiNetworkBackend.security(.wpa2Enterprise) == .enterprise)
        #expect(CoreWLANWiFiNetworkBackend.security(.wpa3Enterprise) == .enterprise)
        #expect(CoreWLANWiFiNetworkBackend.security(.unknown) == .unsupported)
    }

    private func network(
        _ name: String, rssi: Int, known: Bool = false, connected: Bool = false
    ) -> WiFiNetwork {
        WiFiNetwork(
            id: .init(ssid: Data(name.utf8), security: .personal), name: name,
            rssi: rssi, isKnown: known, isConnected: connected
        )
    }
}

private final class WiFiScanFixture: CWNetwork {
    var fixtureSSID: Data? = Data("Office".utf8)
    var fixtureName: String? = "Office"
    let fixtureRSSI: Int
    let fixtureBSSID: String
    let fixtureSecurity: CWSecurity

    init(rssi: Int, bssid: String, security: CWSecurity = .wpa2Personal) {
        fixtureRSSI = rssi
        fixtureBSSID = bssid
        fixtureSecurity = security
        super.init()
    }

    required init?(coder: NSCoder) { fatalError("Fixtures are not decoded") }
    override var ssidData: Data? { fixtureSSID }
    override var ssid: String? { fixtureName }
    override var bssid: String? { fixtureBSSID }
    override var rssiValue: Int { fixtureRSSI }
    override func supportsSecurity(_ security: CWSecurity) -> Bool { security == fixtureSecurity }
}
