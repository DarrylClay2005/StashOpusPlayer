import Foundation
import SwiftUI
import UIKit

extension AccountService {

    // MARK: - Notifications

    /// Fetches recent in-app notifications (achievements, subscriptions, etc.).
    func fetchNotifications(unreadOnly: Bool = false) async -> [AppNotification] {
        guard isLoggedIn else { return [] }
        do {
            let path = "/user/notifications" + (unreadOnly ? "?unread_only=true" : "")
            let data = try await makeRequest(path)
            return try JSONDecoder().decode([AppNotification].self, from: data)
        } catch let err as AccountError {
            errorMessage = err.message
            return []
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    /// Marks a single notification as read.
    func markNotificationRead(id: String) async {
        guard isLoggedIn else { return }
        do {
            _ = try await makeRequest("/user/notifications/\(id)/read", method: "POST")
        } catch {
            // Best-effort; the inbox will simply show it as unread next time.
        }
    }

    /// Marks all notifications as read.
    func markAllNotificationsRead() async {
        guard isLoggedIn else { return }
        do {
            _ = try await makeRequest("/user/notifications/read-all", method: "POST")
        } catch {
            // Best-effort.
        }
    }

    private static let deviceTokenKey = "apns_device_token_hex"

    /// Registers this device's APNs token for push notifications. Also
    /// remembered locally (not tied to a session) so `logout()` can
    /// unregister it without needing a fresh callback from the OS.
    func registerPushToken(_ deviceToken: String) async {
        UserDefaults.standard.set(deviceToken, forKey: Self.deviceTokenKey)
        guard isLoggedIn else { return }
        struct Body: Encodable { let device_token: String; let platform: String }
        do {
            _ = try await makeRequest("/user/push-token", method: "POST", body: Body(device_token: deviceToken, platform: "ios"))
        } catch {
            // Best-effort; will retry on next launch.
        }
    }

    /// Unregisters this device's APNs token (e.g. on logout).
    func unregisterPushToken(_ deviceToken: String) async {
        guard isLoggedIn else { return }
        do {
            _ = try await makeRequest("/user/push-token/\(deviceToken)", method: "DELETE")
        } catch {
            // Best-effort.
        }
    }

    /// Unregisters whatever APNs token this device last registered, if any —
    /// so a logged-out device stops receiving another account's pushes.
    func unregisterCurrentDeviceToken() async {
        guard let token = UserDefaults.standard.string(forKey: Self.deviceTokenKey) else { return }
        await unregisterPushToken(token)
    }

    /// Re-sends this device's already-obtained APNs token to the server, if
    /// it has one cached. `registerPushToken(_:)` above intentionally skips
    /// its network call while logged out — which is the common case, since
    /// APNs registration typically completes (and caches the token here)
    /// before the user has signed in on a fresh install. Without this, that
    /// token was never actually reaching the server even after the user
    /// later logged in, silently leaving that device unable to receive real
    /// pushes until its token happened to change. `NotificationService`
    /// calls this whenever `isLoggedIn` flips to `true`; it's a harmless
    /// no-op otherwise (nothing logged in, or no token cached yet).
    func resendStoredPushTokenIfNeeded() async {
        guard isLoggedIn, let token = UserDefaults.standard.string(forKey: Self.deviceTokenKey) else { return }
        await registerPushToken(token)
    }
}
