import Foundation
import UIKit

// MARK: - PresenceService
//
// Lightweight polling-based presence: this device periodically tells the
// bridge "I'm online, here's what I'm playing" (POST /api/social/presence),
// and separately polls a *batched* endpoint for friends' presence
// (GET /api/social/presence/friends) — one request covers every friend, so
// a long friends list never means one network call per friend on a timer
// (that exact per-item-synchronous-call-in-a-loop shape is a known main-
// thread-hang bug class in this codebase; see hasLocalCopy(of:) history).
//
// Two independent timers:
//   - `heartbeatTimer` — this device's own "I'm online" signal. Started by
//     ContentView (the one view mounted for the app's entire foreground
//     lifetime) on appear/login, stopped on logout. A best-effort
//     "going offline" beacon fires from ContentView's background/terminate
//     handling via `sendGoingOffline`.
//   - `friendsPollTimer` — only runs while some screen actually wants to
//     *display* friends' presence (FriendsListView, PublicProfileView).
//     Those views start/stop it in onAppear/onDisappear so it doesn't poll
//     forever in the background for no on-screen reason.
@MainActor
final class PresenceService: ObservableObject {

    @Published private(set) var friendsPresence: [SocialPresence] = []

    /// How often this device reports its own state while foregrounded.
    static let heartbeatInterval: TimeInterval = 45
    /// How often a visible friends/presence screen refreshes the batch.
    static let friendsPollInterval: TimeInterval = 30

    private var heartbeatTimer: Timer?
    private var friendsPollTimer: Timer?

    // MARK: - Self heartbeat

    func startHeartbeat(account: AccountService, player: AudioPlayerManager) {
        stopHeartbeat()
        guard account.isLoggedIn else { return }
        Task { [weak self, weak account, weak player] in
            guard let self, let account, let player else { return }
            await self.sendHeartbeat(account: account, player: player)
        }
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: Self.heartbeatInterval, repeats: true) { [weak self, weak account, weak player] _ in
            Task { @MainActor [weak self, weak account, weak player] in
                guard let self, let account, let player, account.isLoggedIn,
                      UIApplication.shared.applicationState == .active else { return }
                await self.sendHeartbeat(account: account, player: player)
            }
        }
    }

    func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    /// Best-effort "going offline" signal — fired from `didEnterBackground`.
    /// Not guaranteed to complete (the process may suspend mid-request), but
    /// costs nothing to try; if it never lands, the 90s server-side
    /// freshness window (see `_SOCIAL_PRESENCE_FRESH_SECONDS` in main.py)
    /// still makes this device read as offline shortly after this device
    /// simply stops sending heartbeats.
    func sendGoingOffline(account: AccountService) {
        guard account.isLoggedIn else { return }
        struct Body: Encodable {
            let is_playing = false
            let now_playing_title: String? = nil
            let now_playing_artist: String? = nil
            let going_offline = true
        }
        Task { [weak account] in
            guard let account else { return }
            _ = try? await account.makeRequest("/api/social/presence", method: "POST", body: Body())
        }
    }

    private func sendHeartbeat(account: AccountService, player: AudioPlayerManager) async {
        struct Body: Encodable {
            let is_playing: Bool
            let now_playing_title: String?
            let now_playing_artist: String?
            let going_offline: Bool = false
        }
        let song = player.currentSong
        let body = Body(
            is_playing: player.isPlaying && song != nil,
            now_playing_title: song?.title,
            now_playing_artist: (song?.artist.isEmpty ?? true) ? nil : song?.artist
        )
        do {
            _ = try await account.makeRequest("/api/social/presence", method: "POST", body: body)
        } catch {
            // Silent — same "don't spam logs/interrupt playback" reasoning as
            // AccountService+Avatar's pushPlaybackState, since this fires
            // repeatedly on a timer regardless of network state.
        }
    }

    // MARK: - Friends' presence (batched)

    func startFriendsPolling(account: AccountService) {
        stopFriendsPolling()
        guard account.isLoggedIn else { return }
        Task { [weak self, weak account] in
            guard let self, let account else { return }
            await self.fetchFriendsPresence(account: account)
        }
        friendsPollTimer = Timer.scheduledTimer(withTimeInterval: Self.friendsPollInterval, repeats: true) { [weak self, weak account] _ in
            Task { @MainActor [weak self, weak account] in
                guard let self, let account, account.isLoggedIn else { return }
                await self.fetchFriendsPresence(account: account)
            }
        }
    }

    func stopFriendsPolling() {
        friendsPollTimer?.invalidate()
        friendsPollTimer = nil
    }

    func fetchFriendsPresence(account: AccountService) async {
        guard account.isLoggedIn else { return }
        do {
            let data = try await account.makeRequest("/api/social/presence/friends")
            friendsPresence = try JSONDecoder().decode(SocialFriendsPresenceResponse.self, from: data).presence
        } catch {
            appWarn("PresenceService: friends presence fetch failed: \(error.localizedDescription)", category: "social")
        }
    }

    /// Single-user lookup — used by `PublicProfileView` for one profile at a
    /// time (not on a tight loop; the view's own onAppear/onDisappear starts
    /// and stops a normal single-target poll, same shape as the friends one).
    func fetchPresence(userId: String, account: AccountService) async -> SocialPresence? {
        guard account.isLoggedIn else { return nil }
        do {
            let data = try await account.makeRequest("/api/social/presence/\(userId)")
            return try JSONDecoder().decode(SocialPresence.self, from: data)
        } catch {
            appWarn("PresenceService: presence fetch failed for \(userId): \(error.localizedDescription)", category: "social")
            return nil
        }
    }

    deinit {
        heartbeatTimer?.invalidate()
        friendsPollTimer?.invalidate()
    }
}
