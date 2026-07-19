import Foundation
import SwiftUI
import UIKit

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

    // MARK: - Banner

    /// Uploads raw picker data (straight from `PhotosPicker`) as the profile
    /// banner, preserving animation if it's a GIF — same "sniff raw bytes
    /// before any UIImage conversion" reasoning as
    /// `AccountService.uploadAvatarData(_:)`, since decoding first would
    /// silently flatten a GIF to its first frame. Non-GIF data (HEIC/PNG/
    /// whatever the picker handed back) gets decoded and re-encoded as JPEG,
    /// same as the avatar path, since the bridge only accepts GIF or JPEG
    /// bytes.
    func uploadBannerData(_ data: Data) async {
        guard let account, account.isLoggedIn else { return }
        if isGIFData(data) {
            guard data.count <= 5_242_880 else {
                errorMessage = "GIF banners must be under 5MB."
                return
            }
            await sendBanner(data, contentType: "image/gif", account: account)
            return
        }
        guard let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.8) else {
            appWarn("uploadBannerData: could not decode/encode image data", category: "social")
            return
        }
        guard jpeg.count <= 2_097_152 else {
            errorMessage = "Banner must be under 2MB."
            return
        }
        await sendBanner(jpeg, contentType: "image/jpeg", account: account)
    }

    private func sendBanner(_ data: Data, contentType: String, account: AccountService) async {
        guard var req = account.makeBaseRequest("/api/social/profile/banner", method: "POST") else { return }
        req.setValue(contentType, forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else {
                appWarn("uploadBannerData: HTTP \(status)", category: "social")
                errorMessage = "Couldn't upload banner (HTTP \(status))."
                return
            }
            appLog("uploadBannerData: uploaded \(data.count / 1024)KB (\(contentType))", category: "social")
        } catch {
            handle(error)
        }
    }

    func removeBanner() async {
        guard let account, account.isLoggedIn else { return }
        do {
            _ = try await account.makeRequest("/api/social/profile/banner", method: "DELETE")
        } catch {
            handle(error)
        }
    }

    /// Fetches another (or this) user's banner image, or `nil` if they
    /// haven't set one (a 404 is the normal "no banner" case, not an error —
    /// callers fall back to the plain accent-gradient banner).
    static func loadBanner(userId: String) async -> UIImage? {
        guard let account = AccountService.shared,
              let req = account.makeBaseRequest("/api/social/profile/banner/\(userId)", method: "GET")
        else { return nil }
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode)
        else { return nil }
        if isGIFData(data) { return await UIImage.gifImageAsync(data: data) }
        return UIImage(data: data)
    }

    // MARK: - User search (add-friend flow)

    /// Guards against out-of-order completions — a caller firing this once
    /// per keystroke (even debounced) can still have a slower response for
    /// an *earlier* query land after a faster one for a *later* query, which
    /// would otherwise silently overwrite `searchResults` with results that
    /// don't match what's currently typed.
    private var searchGeneration = 0

    func searchUsers(query: String) async {
        searchGeneration += 1
        let generation = searchGeneration
        guard let account, account.isLoggedIn, !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchResults = []
            return
        }
        do {
            let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
            let data = try await account.makeRequest("/api/social/users/search?q=\(encoded)")
            struct Response: Decodable { let users: [SocialUserRef] }
            let users = try JSONDecoder().decode(Response.self, from: data).users
            guard generation == searchGeneration else { return }
            searchResults = users
        } catch {
            guard generation == searchGeneration else { return }
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
