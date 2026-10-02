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

    @Test
    func menuBarEventRunsBeforeNoticeGateAndUsesTheSameDuration() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let model = try String(contentsOf: root.appendingPathComponent("Sources/Zisla/AppModel.swift"), encoding: .utf8)
        let start = try #require(model.range(of: "  private func consumeHeadphoneConnection("))
        let event = String(model[start.lowerBound...])
        let transient = try #require(event.range(of: "systemMonitorHeadphoneTransient.receive"))
        let noticeGate = try #require(event.range(of: "guard settingsStore.settings.sideNoticesEnabled"))
        #expect(transient.lowerBound < noticeGate.lowerBound)
        #expect(event.contains("Task.sleep(for: .seconds(SystemMonitorHeadphoneTransient.duration))"))
        #expect(event.contains("expiresAfter: SystemMonitorHeadphoneTransient.duration"))
        #expect(event.contains("guard !Task.isCancelled, let self else { return }"))
        #expect(model.contains("headphoneTransientLifecycleActive = false"))
        #expect(model.contains("headphoneTransientTask?.cancel()"))
        let app = try String(contentsOf: root.appendingPathComponent("Sources/Zisla/ZislaApp.swift"), encoding: .utf8)
        #expect(app.contains("model.$systemMonitorHeadphoneTransient"))
        #expect(app.contains("headphoneOptions.replacesNetworkIcon = headphoneOptions.replacesNetworkIcon && connection != nil"))
        #expect(!app.contains("SystemMonitorHeadphonePresentation.rows"))
        #expect(app.contains("isVolumeMetric: metric == .volume && audioOutput.selectedDevice?.isBluetoothAudio == true"))
    }

    private static func connection(name: String = "AirPods Pro", bluetooth: Bool = true) -> HeadphoneConnection {
        HeadphoneConnection(device: AudioOutputDevice(id: 1, name: name, isBluetoothAudio: bluetooth), battery: nil, productID: 0x200E)
    }
}
