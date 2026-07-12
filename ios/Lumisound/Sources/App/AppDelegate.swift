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
