import Foundation
import SwiftUI
import UIKit

extension AccountService {

    // MARK: - Backups

    /// Fetches the list of automatic server-side sync backups for this user
    /// (taken before every push and every restore — see `ios_user_backups`).
    func fetchBackups() async {
        guard isLoggedIn else { return }
        do {
            let data = try await makeRequest("/user/backups")
            struct Response: Decodable { let backups: [SyncBackup] }
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            backups = decoded.backups
        } catch let err as AccountError {
            errorMessage = err.message
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Deletes all of this user's automatic sync backups from the server.
    /// Does not affect the user's current favorites/playlists/settings —
    /// only the snapshot history shown in Backup History.
    func clearBackups() async {
        guard isLoggedIn else { return }
        appLog("Clearing all backups", category: "account")
        isSyncing = true
        errorMessage = nil
        defer { isSyncing = false }

        do {
            _ = try await makeRequest("/user/backups", method: "DELETE")
            backups = []
            ToastCenter.shared.show("Cleared backup history", category: .info, icon: "trash")
            appLog("Backups cleared", category: "account")
        } catch let err as AccountError {
            appError("Clear backups failed [\(err.statusCode)]: \(err.message)", category: "account")
            errorMessage = err.message
        } catch {
            appError("Clear backups error: \(error.localizedDescription)", category: "account")
            errorMessage = error.localizedDescription
        }
    }

    /// Restores a server-side backup, replacing this account's favorites/
    /// playlists/settings with the snapshot, then merges the restored data
    /// down to this device via the normal `pullSync` path.
    func restoreBackup(id: String, library: LibraryManager, player: AudioPlayerManager? = nil) async {
        guard isLoggedIn else { return }
        appLog("Restoring backup \(id)", category: "account")
        isSyncing = true
        errorMessage = nil
        defer { isSyncing = false }

        do {
            _ = try await makeRequest("/user/backups/\(id)/restore", method: "POST")
            await pullSync(library: library, player: player)
            await fetchBackups()
            appLog("Backup restore complete", category: "account")
        } catch let err as AccountError {
            appError("Backup restore failed [\(err.statusCode)]: \(err.message)", category: "account")
            errorMessage = err.message
        } catch {
            appError("Backup restore error: \(error.localizedDescription)", category: "account")
            errorMessage = error.localizedDescription
        }
    }
}
