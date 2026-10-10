import BabyCore
import UIKit
import UserNotifications

@MainActor final class NotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    weak var store: AppStore? { didSet { if let store { for action in pending { apply(action, to: store) }; pending = [] } } }
    private var pending: [CareNotification] = []
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        let done = UNNotificationAction(identifier: "reminder-done", title: "Done", options: [])
        let snooze = UNNotificationAction(identifier: "reminder-snooze", title: "Snooze 15 min", options: [])
        UNUserNotificationCenter.current().setNotificationCategories([UNNotificationCategory(identifier: "BABYTRACK_REMINDER", actions: [done, snooze], intentIdentifiers: [], options: [])])
        if UserDefaults.standard.bool(forKey: "notificationsEnabled") {
            application.registerForRemoteNotifications()
        }
        return true
    }

    func application(_: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        if let store {
            Task { await SleepCoordinator.shared.receivePushToken(deviceToken, store: store) }
        }
    }

    nonisolated func userNotificationCenter(_: UNUserNotificationCenter,
                                            willPresent _: UNNotification) async -> UNNotificationPresentationOptions
    {
        [
            .banner,
            .sound,
        ]
    }
    nonisolated func userNotificationCenter(_: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let id = response.notification.request.content.userInfo["recordID"] as? String
        let identifier = response.actionIdentifier == UNNotificationDefaultActionIdentifier ? "default" : response.actionIdentifier
        guard let action = CareNotification(recordID: id, action: identifier) else { return }
        await MainActor.run {
            if let store = self.store { self.apply(action, to: store) }
            else { self.pending.append(action) }
        }
    }
    private func apply(_ action: CareNotification, to store: AppStore) {
        switch action { case let .open(id): store.handle(.record(id)); case let .done(id): store.reminder(id, snooze: false); case let .snooze(id): store.reminder(id, snooze: true) }
    }
}
