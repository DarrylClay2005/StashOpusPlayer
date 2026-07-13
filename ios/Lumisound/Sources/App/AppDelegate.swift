import UIKit
import UserNotifications

/// Bridges UIKit's remote-notification callbacks into the app. SwiftUI's
/// `App` protocol has no equivalent hooks for APNs device-token delivery, so
/// a minimal `UIApplicationDelegate` is still required even though the rest
/// of the app is pure SwiftUI lifecycle. Actual registration is *triggered*
/// by `NotificationService.requestAuthorization()` (once local-notification
/// authorization is granted) — this class only forwards the OS's response
/// to the server via `AccountService`.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let tokenHex = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { await AccountService.shared?.registerPushToken(tokenHex) }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Expected on Simulator and on devices without a valid provisioning
        // profile/entitlement — not fatal, the app just keeps working with
        // in-app + server-inbox-poll notifications only.
        appWarn("APNs registration failed: \(error.localizedDescription)", category: "notifications")
    }

    /// Entry point for the "download_ready" silent/content-available push
    /// (see _send_push_best_effort's content_available param on the bridge)
    /// — lets a finished background download reach the library within
    /// seconds of completing, instead of waiting for the user to next open
    /// the app or for the next opportunistic BGAppRefreshTask run. Requires
    /// `remote-notification` in UIBackgroundModes (see Info.plist) to be
    /// invoked while the app isn't in the foreground. iOS still shows the
    /// alert banner itself; this only handles the accompanying background
    /// fetch. beginBackgroundTask covers the (typically few-second) fetch +
    /// import, since Apple's own budget for this callback is short and not
    /// guaranteed to cover a network round-trip on its own.
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        guard (userInfo["type"] as? String) == "download_ready", let streaming = StreamingService.shared else {
            completionHandler(.noData)
            return
        }
        let bgTask = application.beginBackgroundTask(withName: "lumisound.download.reconcile") {
            // Expiration fallback — nothing to cancel cleanly mid-fetch here,
            // just make sure the background task itself always ends.
        }
        Task {
            let imported = await streaming.reconcilePendingDownloads()
            if bgTask != .invalid {
                application.endBackgroundTask(bgTask)
            }
            completionHandler(imported > 0 ? .newData : .noData)
        }
    }

    /// Shows the alert banner/sound even while the app is in the foreground —
    /// otherwise both local notifications and mirrored server pushes would
    /// silently do nothing while the user already has the app open.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }
}
