import Foundation
import ZislaCore
import ZislaKit

struct SystemMonitorHeadphoneTransient: Equatable {
    static let duration: TimeInterval = 3
    private(set) var connection: HeadphoneConnection?

    mutating func receive(_ connection: HeadphoneConnection, enabled: Bool, settings: FeatureSettings) {
        guard enabled, settings.supportsHeadphoneConnectionAnimation,
              connection.device.isHeadphones, connection.device.isBluetoothAudio else { return }
        self.connection = connection
    }

    mutating func expire(connectionID: UUID) {
        guard connection?.id == connectionID else { return }
        connection = nil
    }

    mutating func reconcile(enabled: Bool, settings: FeatureSettings, devices: [AudioOutputDevice]) {
        guard enabled, settings.supportsHeadphoneConnectionAnimation,
              let connection, devices.contains(where: { $0.id == connection.device.id }) else {
            self.connection = nil
            return
        }
    }

    @MainActor
    static func updateConnectionNotices(
        settings: FeatureSettings,
        queue: SideNoticeQueue,
        connection: HeadphoneConnection? = nil
    ) {
        guard settings.supportsHeadphoneConnectionAnimation else {
            queue.removeAll(withIDPrefix: "headphone-connection-")
            return
        }
        guard settings.sideNoticesEnabled, let connection else { return }
        queue.enqueue(
            IslandNotice(
                id: "headphone-connection-\(connection.id.uuidString)",
                title: connection.device.name,
                detail: "已连接",
                kind: .info,
                side: .right,
                style: .headphone,
                symbolName: connection.device.isAirPodsMax ? "headphones" : nil,
                batteryLevels: connection.battery?.noticeLevels,
                metadata: connection.productID.map {
                    [HeadphoneConnection.productIDMetadataKey: String($0)]
                }
            ),
            expiresAfter: duration
        )
    }
}
