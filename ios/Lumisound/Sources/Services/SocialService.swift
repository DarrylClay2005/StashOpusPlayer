import Foundation
import SwiftUI

// MARK: - SocialService
//
// Profiles, friends, blocks, and the friends-only activity feed for the new
// Social Ecosystem feature. Presence (online/offline + now-playing polling)
// lives in its own `PresenceService` — kept separate since presence runs a
// standing timer for the whole app session while this service is purely
// request/response, driven by whichever social screen is currently open.
//
// Networking goes through `AccountService.shared` (the same ambient-singleton
// pattern `AudioPlayerManager` already uses to push playback state) rather
// than duplicating the retry/401-handling/error-mapping logic in
// AccountService+PrivateHelpers.swift — `makeRequest` there is `internal`,
// so any type in the app module can call it directly.
@MainActor
final class SocialService: ObservableObject {

    @Published var myProfile: MySocialProfile? = nil
    @Published var friends: [SocialFriend] = []
    @Published var incomingRequests: [SocialFriendRequest] = []
    @Published var outgoingRequests: [SocialFriendRequest] = []
    @Published var blockedUsers: [BlockedUserRef] = []
    @Published var suggestions: [SocialFriendSuggestion] = []
    @Published var friendsActivity: [SocialActivityEntry] = []
    @Published var searchResults: [SocialUserRef] = []
    @Published var errorMessage: String? = nil
    @Published var isLoading = false

    private var account: AccountService? { AccountService.shared }

    // MARK: - Profile

    func fetchMyProfile() async {
        guard let account, account.isLoggedIn else { return }
        do {
            let data = try await account.makeRequest("/api/social/profile/me")
            myProfile = try JSONDecoder().decode(MySocialProfile.self, from: data)
        } catch {
            handle(error)
        }
    }

    func fetchPublicProfile(userId: String) async -> PublicSocialProfile? {
        guard let account, account.isLoggedIn else { return nil }
        do {
            let data = try await account.makeRequest("/api/social/profile/\(userId)")
            return try JSONDecoder().decode(PublicSocialProfile.self, from: data)
        } catch {
            handle(error)
            return nil
        }
    }

    func updateProfile(bio: String? = nil, mainAccentHex: String? = nil, subAccentHex: String? = nil, shareNowPlaying: Bool? = nil) async {
        guard let account, account.isLoggedIn else { return }
        struct Body: Encodable {
            let bio: String?
            let main_accent_hex: String?
            let sub_accent_hex: String?
            let share_now_playing: Bool?
        }
        do {
            _ = try await account.makeRequest(
                "/api/social/profile", method: "PUT",
                body: Body(bio: bio, main_accent_hex: mainAccentHex, sub_accent_hex: subAccentHex, share_now_playing: shareNowPlaying)
            )
            await fetchMyProfile()
        } catch {
            handle(error)
        }
    }

    func setPinnedTracks(_ tracks: [PinnedTrack]) async {
        guard let account, account.isLoggedIn else { return }
        struct Body: Encodable { let tracks: [PinnedTrack] }
        do {
            _ = try await account.makeRequest("/api/social/profile/pinned-tracks", method: "PUT", body: Body(tracks: tracks))
            await fetchMyProfile()
        } catch {
            handle(error)
        }
    }

    // MARK: - User search (add-friend flow)

    func searchUsers(query: String) async {
        guard let account, account.isLoggedIn, !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchResults = []
            return
        }
        do {
            let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
            let data = try await account.makeRequest("/api/social/users/search?q=\(encoded)")
            struct Response: Decodable { let users: [SocialUserRef] }
            searchResults = try JSONDecoder().decode(Response.self, from: data).users
        } catch {
            handle(error)
        }
    }

    // MARK: - Friend requests

    func sendFriendRequest(toUserId: String? = nil, toUsername: String? = nil) async -> Bool {
        guard let account, account.isLoggedIn else { return false }
        struct Body: Encodable { let to_user_id: String?; let to_username: String? }
        do {
            _ = try await account.makeRequest(
                "/api/social/friends/request", method: "POST",
                body: Body(to_user_id: toUserId, to_username: toUsername)
            )
            await fetchFriendRequests()
            return true
        } catch {
            handle(error)
            return false
        }
    }

    func acceptRequest(_ requestId: String) async {
        await respond(requestId: requestId, action: "accept")
    }

    func declineRequest(_ requestId: String) async {
        await respond(requestId: requestId, action: "decline")
    }

    func cancelRequest(_ requestId: String) async {
        await respond(requestId: requestId, action: "cancel")
    }

    private func respond(requestId: String, action: String) async {
        guard let account, account.isLoggedIn else { return }
        do {
            _ = try await account.makeRequest("/api/social/friends/request/\(requestId)/\(action)", method: "POST")
            async let requests: () = fetchFriendRequests()
            async let friendsList: () = fetchFriends()
            _ = await (requests, friendsList)
        } catch {
            handle(error)
        }
    }

    func fetchFriendRequests() async {
        guard let account, account.isLoggedIn else { return }
        do {
            let data = try await account.makeRequest("/api/social/friends/requests")
            let response = try JSONDecoder().decode(SocialFriendRequestsResponse.self, from: data)
            incomingRequests = response.incoming
            outgoingRequests = response.outgoing
        } catch {
            handle(error)
        }
    }

    // MARK: - Friends list

    func fetchFriends() async {
        guard let account, account.isLoggedIn else { return }
        do {
            let data = try await account.makeRequest("/api/social/friends")
            struct Response: Decodable { let friends: [SocialFriend] }
            friends = try JSONDecoder().decode(Response.self, from: data).friends
        } catch {
            handle(error)
        }
    }

    func removeFriend(_ userId: String) async {
        guard let account, account.isLoggedIn else { return }
        do {
            _ = try await account.makeRequest("/api/social/friends/\(userId)", method: "DELETE")
            await fetchFriends()
        } catch {
            handle(error)
        }
    }

    // MARK: - Blocking

    func blockUser(_ userId: String) async {
        guard let account, account.isLoggedIn else { return }
        do {
            _ = try await account.makeRequest("/api/social/block/\(userId)", method: "POST")
            async let friendsList: () = fetchFriends()
            async let requests: () = fetchFriendRequests()
            async let blocked: () = fetchBlockedUsers()
            _ = await (friendsList, requests, blocked)
        } catch {
            handle(error)
        }
    }

    func unblockUser(_ userId: String) async {
        guard let account, account.isLoggedIn else { return }
        do {
            _ = try await account.makeRequest("/api/social/block/\(userId)", method: "DELETE")
            await fetchBlockedUsers()
        } catch {
            handle(error)
        }
    }

    func fetchBlockedUsers() async {
        guard let account, account.isLoggedIn else { return }
        do {
            let data = try await account.makeRequest("/api/social/block")
            struct Response: Decodable { let blocked: [SocialUserRef] }
            blockedUsers = try JSONDecoder().decode(Response.self, from: data).blocked.map(BlockedUserRef.init)
        } catch {
            handle(error)
        }
    }

    // MARK: - Extra feature: mutual-friend suggestions

    func fetchSuggestions() async {
        guard let account, account.isLoggedIn else { return }
        do {
            let data = try await account.makeRequest("/api/social/friends/suggestions")
            struct Response: Decodable { let suggestions: [SocialFriendSuggestion] }
            suggestions = try JSONDecoder().decode(Response.self, from: data).suggestions
        } catch {
            handle(error)
        }
    }

    // MARK: - Extra feature: friends-only activity feed

    func fetchFriendsActivity() async {
        guard let account, account.isLoggedIn else { return }
        do {
            let data = try await account.makeRequest("/api/social/activity/friends")
            struct Response: Decodable { let activity: [SocialActivityEntry] }
            friendsActivity = try JSONDecoder().decode(Response.self, from: data).activity
        } catch {
            handle(error)
        }
    }

    // MARK: - Helpers

    private func handle(_ error: Error) {
        if let err = error as? AccountError {
            errorMessage = err.message
        } else {
            errorMessage = error.localizedDescription
        }
        appWarn("SocialService error: \(errorMessage ?? "")", category: "social")
    }
}

/// GET /api/social/block's entries wrapped as Identifiable — same shape as
/// `SocialUserRef`, just named distinctly so a blocked-users list and a
/// search-results list are never accidentally interchangeable at the type level.
struct BlockedUserRef: Identifiable, Equatable {
    let userId: String
    let username: String
    let displayName: String?
    let avatarURL: String?
    var id: String { userId }

    init(_ ref: SocialUserRef) {
        userId = ref.userId
        username = ref.username
        displayName = ref.displayName
        avatarURL = ref.avatarURL
    }
}
