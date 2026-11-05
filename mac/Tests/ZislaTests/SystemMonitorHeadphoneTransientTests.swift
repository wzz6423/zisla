import Foundation
import Testing
import ZislaCore
import ZislaKit
@testable import Zisla

struct SystemMonitorHeadphoneTransientTests {
    @Test
    func islandRoutingClearsTheTransientAndOnlyANewConnectionRestartsIt() {
        var state = SystemMonitorHeadphoneTransient()
        var settings = FeatureSettings.default
        let first = Self.connection()
        state.receive(first, enabled: true, settings: settings)
        #expect(state.connection == first)
        settings.islandLayoutStyle = .pill
        settings.islandPlacement.mode = .custom
        state.reconcile(enabled: true, settings: settings, devices: [first.device])
        #expect(state.connection == nil)
        state.receive(first, enabled: true, settings: settings)
        #expect(state.connection == nil)
        settings.statusIconDestination = .menuBar
        state.reconcile(enabled: true, settings: settings, devices: [first.device])
        #expect(state.connection == nil)
        let second = Self.connection()
        state.receive(second, enabled: true, settings: settings)
        #expect(state.connection == second)
        settings.statusIconDestination = .island
        settings.islandPlacement.mode = .camera
        state.reconcile(enabled: true, settings: settings, devices: [second.device])
        #expect(state.connection == second)
    }

    @Test @MainActor
    func islandRoutingClearsHeadphoneNoticesAndReturningToTheMenuBarWaitsForANewConnection() throws {
        let queue = SideNoticeQueue()
        defer { queue.removeAll() }
        var settings = FeatureSettings.default
        let first = Self.connection()
        let unrelated = IslandNotice(id: "fixture", title: "Unrelated")
        queue.enqueue(unrelated, expiresAfter: nil)
        SystemMonitorHeadphoneTransient.updateConnectionNotices(settings: settings, queue: queue, connection: first)
        let notice = try #require(queue.right.first { $0.style == .headphone })
        #expect(notice.title == first.device.name)
        #expect(notice.metadata?[HeadphoneConnection.productIDMetadataKey] == "8206")
        settings.islandLayoutStyle = .pill
        settings.islandPlacement.mode = .custom
        SystemMonitorHeadphoneTransient.updateConnectionNotices(settings: settings, queue: queue)
        #expect(queue.left + queue.right == [unrelated])
        SystemMonitorHeadphoneTransient.updateConnectionNotices(settings: settings, queue: queue, connection: first)
        #expect(queue.left + queue.right == [unrelated])
        settings.statusIconDestination = .menuBar
        SystemMonitorHeadphoneTransient.updateConnectionNotices(settings: settings, queue: queue)
        #expect(queue.left + queue.right == [unrelated], "Returning to the menu bar must not replay a connection")
        let second = Self.connection()
        SystemMonitorHeadphoneTransient.updateConnectionNotices(settings: settings, queue: queue, connection: second)
        #expect(queue.right.contains { $0.id == "headphone-connection-\(second.id.uuidString)" })
        queue.removeAll()
        settings.sideNoticesEnabled = false
        SystemMonitorHeadphoneTransient.updateConnectionNotices(settings: settings, queue: queue, connection: second)
        #expect(queue.left.isEmpty && queue.right.isEmpty)
    }

    @Test
    func startsEmptyAndOnlyNewBluetoothHeadphoneEventsAreShown() {
        var state = SystemMonitorHeadphoneTransient()
        let connected = Self.connection()
        state.reconcile(enabled: true, settings: .default, devices: [connected.device])
        #expect(state.connection == nil)
        state.receive(connected, enabled: false, settings: .default)
        #expect(state.connection == nil)
        state.receive(Self.connection(name: "Speaker"), enabled: true, settings: .default)
        #expect(state.connection == nil)
        state.receive(Self.connection(bluetooth: false), enabled: true, settings: .default)
        #expect(state.connection == nil)
        state.receive(connected, enabled: true, settings: .default)
        #expect(state.connection == connected)
        #expect(SystemMonitorHeadphoneTransient.duration == 3)
    }

    @Test
    func expiryRestoresWiFiAndAnOldTimerCannotHideTheNewConnection() {
        var state = SystemMonitorHeadphoneTransient()
        let first = Self.connection()
        let second = Self.connection()
        state.receive(first, enabled: true, settings: .default)
        state.receive(second, enabled: true, settings: .default)
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
            state.receive(event, enabled: true, settings: .default)
            state.reconcile(enabled: true, settings: .default, devices: [event.device])
            #expect(state.connection == event)
            state.reconcile(enabled: enabled, settings: .default, devices: devices)
            #expect(state.connection == nil)
            state.reconcile(enabled: true, settings: .default, devices: [event.device])
            #expect(state.connection == nil)
        }
    }

    private static func connection(name: String = "AirPods Pro", bluetooth: Bool = true) -> HeadphoneConnection {
        HeadphoneConnection(device: AudioOutputDevice(id: 1, name: name, isBluetoothAudio: bluetooth), battery: nil, productID: 0x200E)
    }
}
