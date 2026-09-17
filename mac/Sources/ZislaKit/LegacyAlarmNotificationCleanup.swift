@preconcurrency import UserNotifications

public enum LegacyAlarmNotificationCleanup {
    private static let identifierPrefix = "zisla.alarm."

    /// Old builds may have left scheduled alarms behind after the feature was removed.
    public static func removeScheduledNotifications() {
        let notificationCenter = UNUserNotificationCenter.current()
        notificationCenter.getPendingNotificationRequests { requests in
            let identifiers = identifiersToRemove(from: requests.map(\.identifier))
            guard !identifiers.isEmpty else { return }
            notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiers)
        }
        notificationCenter.getDeliveredNotifications { notifications in
            let identifiers = identifiersToRemove(from: notifications.map(\.request.identifier))
            guard !identifiers.isEmpty else { return }
            notificationCenter.removeDeliveredNotifications(withIdentifiers: identifiers)
        }
    }

    static func identifiersToRemove(from identifiers: [String]) -> [String] {
        identifiers.filter { $0.hasPrefix(identifierPrefix) }
    }
}
