import Foundation
import SwiftUI
import UIKit

extension AccountService {

    // MARK: - Discord "Now Playing" Webhook

    /// Fetches the current Discord webhook configuration (URL is masked).
    func fetchDiscordWebhook() async -> DiscordWebhookStatus? {
        guard isLoggedIn else { return nil }
        do {
            let data = try await makeRequest("/user/discord-webhook")
            return try JSONDecoder().decode(DiscordWebhookStatus.self, from: data)
        } catch let err as AccountError {
            errorMessage = err.message
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Sets (or updates) the Discord "Now Playing" webhook URL and enabled state.
    /// Pass `url: nil` to toggle `enabled` without changing an already-configured URL.
    func setDiscordWebhook(url: String?, enabled: Bool) async -> Bool {
        guard isLoggedIn else { return false }
        struct Body: Encodable { let webhook_url: String?; let enabled: Bool }
        do {
            _ = try await makeRequest("/user/discord-webhook", method: "PUT", body: Body(webhook_url: url, enabled: enabled))
            return true
        } catch let err as AccountError {
            errorMessage = err.message
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Removes the Discord webhook configuration entirely.
    func deleteDiscordWebhook() async -> Bool {
        guard isLoggedIn else { return false }
        do {
            _ = try await makeRequest("/user/discord-webhook", method: "DELETE")
            return true
        } catch let err as AccountError {
            errorMessage = err.message
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
