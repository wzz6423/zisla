import Foundation
import ZislaKit

struct SystemMonitorHeadphoneTransient: Equatable {
    static let duration: TimeInterval = 3
    private(set) var connection: HeadphoneConnection?

    mutating func receive(_ connection: HeadphoneConnection, enabled: Bool) {
        guard enabled, connection.device.isHeadphones, connection.device.isBluetoothAudio else { return }
        self.connection = connection
    }

    mutating func expire(connectionID: UUID) {
        guard connection?.id == connectionID else { return }
        connection = nil
    }

    mutating func reconcile(enabled: Bool, devices: [AudioOutputDevice]) {
        guard enabled, let connection, devices.contains(where: { $0.id == connection.device.id }) else {
            self.connection = nil
            return
        }
    }
}
