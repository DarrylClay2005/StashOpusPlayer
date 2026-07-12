import Foundation
import UIKit
import UserNotifications

// MARK: - NotificationService
//
// Real on-device notifications via `UNUserNotificationCenter`. Uses LOCAL
// notifications (no Apple Push certificate / APNs entitlement required), which
// is sufficient to actually deliver alerts to the user's device — both while
// the app is backgrounded and, for in-app events, immediately.
//
// Two delivery paths:
//   1. In-app events (download finished, achievement unlocked, sleep-timer
//      expiry, update available) call `notify(...)` directly.
//   2. Server-side inbox notifications (GET /user/notifications — achievements,
//      artist uploads, collaborator activity) are mirrored to a device
//      notification exactly once via `syncServerNotifications(_:)`, which
//      dedupes against the set of ids it has already surfaced.

@MainActor
final class NotificationService: ObservableObject {

    static let shared = NotificationService()

    /// Master user toggle (Settings → Notifications). When off, `notify` and
    /// `syncServerNotifications` become no-ops. Persisted in UserDefaults.
    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Keys.enabled) }
    }

    /// Whether the OS-level authorization has been granted. Updated by
    /// `requestAuthorization()` / `refreshAuthorizationStatus()`.
    @Published private(set) var isAuthorized = false

    private enum Keys {
        static let enabled = "notifications_enabled"
        static let surfacedIDs = "notifications_surfaced_ids_v1"
    }

    /// Server notification ids already mirrored to a device notification, so a
    /// repeated `/user/notifications` fetch doesn't re-alert for the same item.
    private var surfacedServerIDs: Set<String>

    private init() {
        // Default ON the first time (no stored value) so notifications work out
        // of the box once authorization is granted.
        if UserDefaults.standard.object(forKey: Keys.enabled) == nil {
            isEnabled = true
        } else {
            isEnabled = UserDefaults.standard.bool(forKey: Keys.enabled)
        }
        if let data = UserDefaults.standard.data(forKey: Keys.surfacedIDs),
           let decoded = try? JSONDecoder().decode(Set<String>.self, from: data) {
            surfacedServerIDs = decoded
        } else {
            surfacedServerIDs = []
        }
    }

    // MARK: - Authorization

    /// Requests alert/sound/badge authorization if not already determined, and
    /// records the result. Safe to call repeatedly (e.g. on every launch).
    func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            isAuthorized = granted
        case .authorized, .provisional, .ephemeral:
            isAuthorized = true
        default:
            isAuthorized = false
        }
        // Ask the OS for an APNs device token whenever we hold real alert
        // authorization, so real (background) push delivery stays wired up
        // to the current authorization state on every launch — registering
        // again with an already-valid token is a harmless no-op.
        if isAuthorized {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    /// Re-reads the current OS authorization status without prompting.
    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        isAuthorized = [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus)
    }

    // MARK: - Posting

    /// Posts a local notification now (a 0.1s trigger so it delivers reliably
    /// even from the foreground). No-op when the user has notifications
    /// disabled or authorization wasn't granted.
    func notify(title: String, body: String, identifier: String = UUID().uuidString, categoryID: String? = nil) {
        guard isEnabled, isAuthorized else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let categoryID { content.categoryIdentifier = categoryID }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                appWarn("NotificationService.notify failed: \(error.localizedDescription)", category: "notifications")
            }
        }
    }

    // MARK: - Server Inbox Mirroring

    /// Fires a device notification for any server inbox item not yet surfaced.
    /// Caller passes the freshly-fetched `/user/notifications` list (typically
    /// the unread ones). Already-surfaced ids are skipped so re-fetching never
    /// double-alerts.
    func syncServerNotifications(_ notifications: [AppNotification]) {
        guard isEnabled, isAuthorized else { return }
        var didChange = false
        for notification in notifications where notification.isUnread && !surfacedServerIDs.contains(notification.id) {
            notify(
                title: notification.title,
                body: notification.body ?? "",
                identifier: "server-\(notification.id)"
            )
            surfacedServerIDs.insert(notification.id)
            didChange = true
        }
        // Cap the dedupe set so it can't grow unbounded across the app's life.
        if surfacedServerIDs.count > 500 {
            surfacedServerIDs = Set(surfacedServerIDs.suffix(500))
            didChange = true
        }
        if didChange { persistSurfacedIDs() }
    }

    private func persistSurfacedIDs() {
        if let data = try? JSONEncoder().encode(surfacedServerIDs) {
            UserDefaults.standard.set(data, forKey: Keys.surfacedIDs)
        }
    }
}
