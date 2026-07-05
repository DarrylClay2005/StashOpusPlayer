import Foundation
import SwiftUI
import UIKit

extension AccountService {

    // MARK: - Collaborative playlists

    /// Adds (or updates) a collaborator on a playlist this user owns.
    /// `role` must be "editor" or "viewer". Returns true on success.
    func addCollaborator(playlistId: String, username: String, role: String) async -> Bool {
        guard isLoggedIn else { return false }
        struct Body: Encodable { let username: String; let role: String }
        do {
            _ = try await makeRequest("/user/playlists/\(playlistId)/collaborators", method: "POST", body: Body(username: username, role: role))
            return true
        } catch let err as AccountError {
            errorMessage = err.message
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Lists collaborators on a playlist (owner or collaborator can view).
    func fetchCollaborators(playlistId: String) async -> [PlaylistCollaborator] {
        guard isLoggedIn else { return [] }
        do {
            let data = try await makeRequest("/user/playlists/\(playlistId)/collaborators")
            return try JSONDecoder().decode([PlaylistCollaborator].self, from: data)
        } catch let err as AccountError {
            errorMessage = err.message
            return []
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    /// Removes a collaborator. The owner can remove anyone; a collaborator can remove themselves.
    func removeCollaborator(playlistId: String, userId: String) async -> Bool {
        guard isLoggedIn else { return false }
        do {
            _ = try await makeRequest("/user/playlists/\(playlistId)/collaborators/\(userId)", method: "DELETE")
            return true
        } catch let err as AccountError {
            errorMessage = err.message
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Playlists owned by other users that this user can view/edit (GET /user/playlists/shared-with-me).
    func fetchSharedPlaylists() async -> [SharedWithMePlaylist] {
        guard isLoggedIn else { return [] }
        do {
            let data = try await makeRequest("/user/playlists/shared-with-me")
            return try JSONDecoder().decode([SharedWithMePlaylist].self, from: data)
        } catch let err as AccountError {
            errorMessage = err.message
            return []
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    /// Fetches a single playlist (with tracks) — used to open a shared playlist.
    func fetchPlaylistDetail(playlistId: String) async -> SharedPlaylistDetail? {
        guard isLoggedIn else { return nil }
        do {
            let data = try await makeRequest("/user/playlists/\(playlistId)")
            return try JSONDecoder().decode(SharedPlaylistDetail.self, from: data)
        } catch let err as AccountError {
            errorMessage = err.message
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}
