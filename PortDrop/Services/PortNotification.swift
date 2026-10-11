import UserNotifications

/// The "new service" notification's buttons. Which ones a notification gets is decided by its category.
enum PortNotification {
    static let openAction = "open"
    static let killAction = "kill"
    static let openAndKill = "port.open.kill"
    static let openOnly = "port.open"
    static let killOnly = "port.kill"
    /// userInfo key holding the `ListeningPort.id` the notification is about.
    static let portIDKey = "portID"

    /// Docker rows never get Kill: the process behind them is the backend that serves every container.
    static func category(canOpen: Bool, isDocker: Bool) -> String? {
        switch (canOpen, isDocker) {
        case (true, false): openAndKill
        case (false, false): killOnly
        case (true, true): openOnly
        case (false, true): nil
        }
    }

    static var categories: Set<UNNotificationCategory> {
        let open = UNNotificationAction(identifier: openAction, title: "Open")
        let kill = UNNotificationAction(identifier: killAction, title: "Kill", options: [.destructive])
        return [
            UNNotificationCategory(identifier: openAndKill, actions: [open, kill], intentIdentifiers: []),
            UNNotificationCategory(identifier: openOnly, actions: [open], intentIdentifiers: []),
            UNNotificationCategory(identifier: killOnly, actions: [kill], intentIdentifiers: []),
        ]
    }
}

/// Forwards notification button presses, and lets banners show while PortDrop itself is the active app
/// (it is, for as long as the panel was the last thing clicked).
final class NotificationResponder: NSObject, UNUserNotificationCenterDelegate, Sendable {
    private let handle: @Sendable (_ action: String, _ portID: String) async -> Void

    init(handle: @escaping @Sendable (_ action: String, _ portID: String) async -> Void) {
        self.handle = handle
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let id = response.notification.request.content.userInfo[PortNotification.portIDKey] as? String else { return }
        await handle(response.actionIdentifier, id)
    }
}
