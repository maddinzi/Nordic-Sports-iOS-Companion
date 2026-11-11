import UserNotifications

/// Opens the activity a new-activity notification is about when the athlete taps it
/// (`Companion.notifyNewActivity` puts its id in the notification). The screens pick it up from
/// `Companion.openActivityId`.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationRouter()

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        // A database from a newer build: nothing may create Companion.shared (DatabaseGuard).
        if DatabaseGuard.tooNew {
            completionHandler()
            return
        }
        if let id = info["sensorRecordId"] as? String, !id.isEmpty {
            Task { @MainActor in Companion.shared.openSensorRecordId = id }
        } else if let id = info["activityId"] as? String, !id.isEmpty {
            let target = (info["target"] as? String).flatMap(ActivityTarget.init(rawValue:))
            Task { @MainActor in
                Companion.shared.openActivityTarget = target
                Companion.shared.openActivityId = id
            }
        }
        completionHandler()
    }
}
