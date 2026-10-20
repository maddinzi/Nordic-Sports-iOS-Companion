import UserNotifications

/// Opens the activity a new-activity notification is about when the athlete taps it
/// (`Companion.notifyNewActivity` puts its id in the notification). The screens pick it up from
/// `Companion.openActivityId`.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationRouter()

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let id = response.notification.request.content.userInfo["activityId"] as? String, !id.isEmpty {
            Task { @MainActor in Companion.shared.openActivityId = id }
        }
        completionHandler()
    }
}
