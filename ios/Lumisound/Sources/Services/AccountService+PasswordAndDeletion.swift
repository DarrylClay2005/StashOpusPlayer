import Foundation
import SwiftUI
import UIKit

extension AccountService {

    // MARK: - Password / Account deletion

    /// Changes the account password. On success, every other device is
    /// signed out by the server (see POST /auth/change-password).
    func changePassword(currentPassword: String, newPassword: String) async -> Bool {
        guard isLoggedIn else { return false }
        struct Body: Encodable { let current_password: String; let new_password: String }
        do {
            _ = try await makeRequest(
                "/auth/change-password", method: "POST",
                body: Body(current_password: currentPassword, new_password: newPassword)
            )
            errorMessage = nil
            return true
        } catch let err as AccountError {
            errorMessage = err.message
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Permanently deletes the account and all server-side data. Requires
    /// the current password. Clears the local session on success.
    func deleteAccount(password: String) async -> Bool {
        guard isLoggedIn else { return false }
        struct Body: Encodable { let password: String }
        do {
            _ = try await makeRequest("/auth/delete-account", method: "POST", body: Body(password: password))
            appLog("Account deleted", category: "account")
            clearSession()
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
