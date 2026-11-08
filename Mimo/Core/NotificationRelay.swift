import Foundation
import UserNotifications

/// Shows Mimo's own notifications (like timers) even while the app is open,
/// and lets the character announce them out loud.
final class NotificationRelay: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationRelay()

    /// Called on the main actor with the notification's text.
    @MainActor var onDeliver: ((String) -> Void)?

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        let content = notification.request.content
        let text = content.body.isEmpty ? content.title : content.body
        await MainActor.run { self.onDeliver?(text) }
        return [.banner, .sound, .list]
    }
}
