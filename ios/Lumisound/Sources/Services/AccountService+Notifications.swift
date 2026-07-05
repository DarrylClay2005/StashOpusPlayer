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

    /// Registers this device's APNs token for push notifications.
    func registerPushToken(_ deviceToken: String) async {
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
}
