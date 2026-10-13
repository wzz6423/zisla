import Foundation
import Testing
import ZislaKit
@testable import Zisla

struct SystemMonitorHeadphoneTransientTests {
    @Test
    func startsEmptyAndOnlyNewBluetoothHeadphoneEventsAreShown() {
        var state = SystemMonitorHeadphoneTransient()
        let connected = Self.connection()
        state.reconcile(enabled: true, devices: [connected.device])
        #expect(state.connection == nil)
        state.receive(connected, enabled: false)
        #expect(state.connection == nil)
        state.receive(Self.connection(name: "Speaker"), enabled: true)
        #expect(state.connection == nil)
        state.receive(Self.connection(bluetooth: false), enabled: true)
        #expect(state.connection == nil)
        state.receive(connected, enabled: true)
        #expect(state.connection == connected)
        #expect(SystemMonitorHeadphoneTransient.duration == 3)
    }

    @Test
    func expiryRestoresWiFiAndAnOldTimerCannotHideTheNewConnection() {
        var state = SystemMonitorHeadphoneTransient()
        let first = Self.connection()
        let second = Self.connection()
        state.receive(first, enabled: true)
        state.receive(second, enabled: true)
        state.expire(connectionID: first.id)
        #expect(state.connection == second)
        state.expire(connectionID: second.id)
        #expect(state.connection == nil)
        state.expire(connectionID: second.id)
        #expect(state.connection == nil)
    }

    @Test
    func disconnectDisableAndStopClearTheTransientWithoutReplayingConnections() {
        let event = Self.connection()
        for (enabled, devices) in [(true, [AudioOutputDevice]()), (false, [event.device])] {
            var state = SystemMonitorHeadphoneTransient()
            state.receive(event, enabled: true)
            state.reconcile(enabled: true, devices: [event.device])
            #expect(state.connection == event)
            state.reconcile(enabled: enabled, devices: devices)
            #expect(state.connection == nil)
            state.reconcile(enabled: true, devices: [event.device])
            #expect(state.connection == nil)
        }
    }

    private static func connection(name: String = "AirPods Pro", bluetooth: Bool = true) -> HeadphoneConnection {
        HeadphoneConnection(device: AudioOutputDevice(id: 1, name: name, isBluetoothAudio: bluetooth), battery: nil, productID: 0x200E)
    }
}
