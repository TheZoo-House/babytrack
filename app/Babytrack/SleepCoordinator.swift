import ActivityKit
import BabyCore
import Foundation
import UIKit
import UserNotifications

@MainActor final class SleepCoordinator {
    static let shared = SleepCoordinator()
    private var observing = false
    private var watched = Set<String>()
    private var startToken: String?
    private var pushToken: String?
    private var activityToken: String?
    private var sessionID: String?
    var deviceID: String {
        if let id = UserDefaults.standard.string(forKey: "deviceID") {
            return id
        }
        let id = UUID().uuidString; UserDefaults.standard.set(id, forKey: "deviceID"); return id
    }

    func observe(store: AppStore) async {
        guard !observing else { return }; observing = true
        Task {
            for await token in Activity<SleepAttributes>.pushToStartTokenUpdates {
                startToken = token.map { String(format: "%02x", $0) }.joined()
                await register(store: store)
            }
        }
        Task {
            for await activity in Activity<SleepAttributes>.activityUpdates {
                watch(activity, store: store)
            }
        }
        for activity in Activity<SleepAttributes>.activities {
            watch(activity, store: store)
        }
        await reconcile(store: store)
    }

    func reconcile(store: AppStore) async {
        let sessions = store.entities.filter { $0.type == "sleep" && $0.end == nil }
        for activity in Activity<SleepAttributes>.activities
            where !sessions.contains(where: { $0.id == activity.attributes.sessionID })
        {
            await activity.end(
                ActivityContent(state: SleepAttributes.ContentState(
                    startedAt: activity.content.state.startedAt,
                    ended: true
                ), staleDate: nil),
                dismissalPolicy: .immediate
            )
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        if sessions.isEmpty {
            sessionID = nil; activityToken = nil; await register(store: store); return
        }
        for active in sessions {
            guard let child = store.children.first(where: { $0.id == active.childID }) else { continue }
            if let existing = Activity<SleepAttributes>.activities
                .first(where: { $0.attributes.sessionID == active.id })
            {
                watch(existing, store: store); continue
            }
            do {
                let attributes = SleepAttributes(sessionID: active.id, childID: child.id, childName: child.title)
                let activity = try Activity.request(
                    attributes: attributes,
                    content: ActivityContent(state: SleepAttributes.ContentState(startedAt: active.at),
                                             staleDate: .now.addingTimeInterval(86400)),
                    pushType: .token
                )
                watch(activity, store: store)
            } catch { store.notice = "Sleep is saved. Live Activity could not start on this device." }
        }
    }

    private func watch(_ activity: Activity<SleepAttributes>, store: AppStore) {
        guard !watched.contains(activity.id) else { return }; watched.insert(activity.id)
        Task {
            for await token in activity.pushTokenUpdates {
                sessionID = activity.attributes.sessionID; activityToken = token.map { String(format: "%02x", $0) }
                    .joined()
                await register(store: store)
            }
            watched.remove(activity.id)
        }
    }

    func receivePushToken(_ token: Data, store: AppStore) async {
        pushToken = token.map { String(format: "%02x", $0) }.joined(); await register(store: store)
    }

    func setNotifications(_ enabled: Bool, store: AppStore) async {
        if enabled {
            do { let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [
                .alert,
                .sound,
                .badge,
            ]); store
                .notificationsEnabled = granted; if granted
            {
                UIApplication.shared.registerForRemoteNotifications()
            }
            } catch { store.notificationsEnabled = false; store.error = error.localizedDescription }
        } else {
            store.notificationsEnabled = false
        }
        UserDefaults.standard.set(store.notificationsEnabled, forKey: "notificationsEnabled")
        await register(store: store)
    }

    func register(store: AppStore) async {
        guard store.signedIn else { return }
        #if DEBUG
            let environment = "sandbox"
        #else
            let environment = "production"
        #endif
        var object: [String: Any] = ["id": deviceID, "enabled": store.notificationsEnabled, "environment": environment]
        if let pushToken {
            object["pushToken"] = pushToken
        }
        if let startToken {
            object["startToken"] = startToken
        }
        if let activityToken,
           let sessionID
        {
            object["activityToken"] = activityToken; object["activityID"] = sessionID
        }
        do { let _: [String: Bool] = try await store.request("/v1/devices", body: store.body(object)) } catch {
        /* Cached state remains usable until the next registration. */ }
    }
}

@MainActor final class NotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    weak var store: AppStore?
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
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
}
