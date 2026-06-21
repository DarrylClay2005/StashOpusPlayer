import Foundation
import SwiftUI
import UIKit

// MARK: - Models

struct AppUser: Codable, Equatable {
    let id: String
    let username: String
    let displayName: String?
    let email: String?
    let avatarURL: String?
    let dateOfBirth: String?   // ISO YYYY-MM-DD, nil if not set
    var shareListeningActivity: Bool = false

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case displayName  = "display_name"
        case email
        case avatarURL    = "avatar_url"
        case dateOfBirth  = "date_of_birth"
        case shareListeningActivity = "share_listening_activity"
    }
}

struct SyncData: Codable {
    var favorites: [SyncFavorite]
    var playlists: [SyncPlaylist]
    var audioSettingsJSON: String?
    var trackAudioSettingsJSON: String?
    var themeColor: String?
    var vinylDiscEnabled: Bool?
    var showQueuePreview: Bool?
    var songsPerRow: Int?
    var albumsPerRow: Int?
    var bgAnimation: String?
    var bgOpacity: Double?
    var bgEnabled: Bool?
    var bgBlurRadius: Double?
    var bgShuffleInterval: Double?
    var preferredAudioFormat: String?
    var downloadPath: String?
    var carModeEnabled: Bool?
    var libraryArtistsColumns: Int?
    var nowPlayingArtworkStyle: String?
    var nowPlayingSeekerStyle: String?
    var earnedBadgesJSON: String?
    /// JSON-encoded bag of additional UserDefaults-backed prefs (card style,
    /// auto-radio, notifications toggle, Liquid Glass customization, …) so they
    /// ride along in the per-user auto backup without a column each. See
    /// `AccountService.extraBackupKeys`.
    var extraSettingsJSON: String?

    enum CodingKeys: String, CodingKey {
        case favorites
        case playlists
        case audioSettingsJSON      = "audio_settings_json"
        case trackAudioSettingsJSON = "track_audio_settings_json"
        case themeColor             = "theme_color"
        case vinylDiscEnabled       = "vinyl_disc_enabled"
        case showQueuePreview       = "show_queue_preview"
        case songsPerRow            = "songs_per_row"
        case albumsPerRow           = "albums_per_row"
        case bgAnimation            = "bg_animation"
        case bgOpacity              = "bg_opacity"
        case bgEnabled              = "bg_enabled"
        case bgBlurRadius           = "bg_blur_radius"
        case bgShuffleInterval      = "bg_shuffle_interval"
        case preferredAudioFormat   = "preferred_audio_format"
        case downloadPath           = "download_path"
        case carModeEnabled         = "car_mode_enabled"
        case libraryArtistsColumns  = "library_artists_columns"
        case nowPlayingArtworkStyle = "now_playing_artwork_style"
        case nowPlayingSeekerStyle  = "now_playing_seeker_style"
        case earnedBadgesJSON       = "earned_badges_json"
        case extraSettingsJSON      = "extra_settings_json"
    }
}

// MARK: - Folder Structure Backup (item 3)

/// One track inside a backed-up watched folder, as pushed to/pulled from
/// `/user/folder-backups`. `sourceTrackID` (the `LUMISOUND_ID`-style identifier,
/// e.g. "youtube:dQw4w9WgXcQ") is what makes a track auto-redownloadable on
/// restore; tracks without one were local-only imports and can only have their
/// folder recreated (empty) for the user to re-add manually.
struct FolderBackupTrack: Codable, Hashable {
    var filename: String
    var title: String?
    var artist: String?
    var durationSeconds: Double?
    var sourceTrackID: String?

    enum CodingKeys: String, CodingKey {
        case filename
        case title
        case artist
        case durationSeconds = "duration_seconds"
        case sourceTrackID   = "source_track_id"
    }
}

/// One watched/imported folder's backed-up structure: its path relative to the
/// app's Documents directory, plus the tracks that lived inside it.
struct FolderBackupEntry: Codable, Hashable {
    var folderPath: String
    var tracks: [FolderBackupTrack]

    enum CodingKeys: String, CodingKey {
        case folderPath = "folder_path"
        case tracks
    }
}

struct SyncFavorite: Codable {
    let songId: String
    let title: String?
    let artist: String?
    let album: String?

    enum CodingKeys: String, CodingKey {
        case songId = "song_id"
        case title
        case artist
        case album
    }
}

struct SyncPlaylist: Codable {
    let id: String
    let name: String
    let description: String?
    var folder: String?
    var tags: [String]
    var tracks: [SyncTrack]

    enum CodingKeys: String, CodingKey {
        case id, name, description, folder, tags, tracks
    }

    init(id: String, name: String, description: String?, folder: String? = nil, tags: [String] = [], tracks: [SyncTrack]) {
        self.id = id
        self.name = name
        self.description = description
        self.folder = folder
        self.tags = tags
        self.tracks = tracks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        folder = try container.decodeIfPresent(String.self, forKey: .folder)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        tracks = try container.decodeIfPresent([SyncTrack].self, forKey: .tracks) ?? []
    }
}

/// Metadata for an automatic server-side backup of this user's sync data
/// (favorites/playlists/settings), taken before every push (and before every
/// restore). See `ios_user_backups` / GET+POST `/user/backups...` on the bridge.
struct SyncBackup: Codable, Identifiable {
    let id: String
    let reason: String
    let createdAt: String
    let favoriteCount: Int
    let playlistCount: Int

    enum CodingKeys: String, CodingKey {
        case id
        case reason
        case createdAt     = "created_at"
        case favoriteCount = "favorite_count"
        case playlistCount = "playlist_count"
    }

    /// `created_at` parsed as a `Date`, for display with relative formatting.
    var date: Date? {
        ISO8601DateFormatter().date(from: createdAt)
    }

    var reasonDisplayName: String {
        switch reason {
        case "pre_push":    return "Before sync"
        case "pre_restore": return "Before restore"
        default:            return reason
        }
    }
}

/// A single entry in the "what others are listening to" feed (GET /social/activity).
/// Only ever contains title/artist/played_at plus public profile info — never
/// file contents or URLs.
struct ActivityEntry: Codable, Identifiable {
    let username: String
    let displayName: String?
    let avatarURL: String?
    let title: String?
    let artist: String?
    let playedAt: String?

    var id: String { "\(username)-\(playedAt ?? "")-\(title ?? "")" }

    enum CodingKeys: String, CodingKey {
        case username
        case displayName = "display_name"
        case avatarURL   = "avatar_url"
        case title
        case artist
        case playedAt    = "played_at"
    }

    var date: Date? {
        guard let playedAt else { return nil }
        return ISO8601DateFormatter().date(from: playedAt)
    }
}

/// A trending track from GET /social/discover — aggregated across users who've
/// opted in to sharing listening activity.
struct TrendingTrack: Codable, Identifiable {
    let title: String
    let artist: String?
    let playCount: Int
    let listenerCount: Int

    var id: String { "\(title)-\(artist ?? "")" }

    enum CodingKeys: String, CodingKey {
        case title
        case artist
        case playCount     = "play_count"
        case listenerCount = "listener_count"
    }
}

/// One active login (device/session) for this account — GET /auth/sessions.
struct AccountSession: Codable, Identifiable {
    let tokenId: String
    let deviceName: String?
    let createdAt: String
    let expiresAt: String?
    let isCurrent: Bool

    var id: String { tokenId }

    enum CodingKeys: String, CodingKey {
        case tokenId    = "token_id"
        case deviceName = "device_name"
        case createdAt  = "created_at"
        case expiresAt  = "expires_at"
        case isCurrent  = "is_current"
    }

    var createdDate: Date? {
        ISO8601DateFormatter().date(from: createdAt)
    }
}

/// Lifetime listening stats from GET /user/stats.
struct AccountStats: Codable {
    let totalPlays: Int
    let totalListenSeconds: Int
    let topArtists: [TopArtist]
    let topTracks: [TopTrack]

    enum CodingKeys: String, CodingKey {
        case totalPlays         = "total_plays"
        case totalListenSeconds = "total_listen_seconds"
        case topArtists         = "top_artists"
        case topTracks          = "top_tracks"
    }

    struct TopArtist: Codable, Identifiable {
        let artist: String
        let playCount: Int
        var id: String { artist }
        enum CodingKeys: String, CodingKey { case artist, playCount = "play_count" }
    }

    struct TopTrack: Codable, Identifiable {
        let title: String
        let artist: String?
        let playCount: Int
        var id: String { "\(title)-\(artist ?? "")" }
        enum CodingKeys: String, CodingKey { case title, artist, playCount = "play_count" }
    }
}

/// One collaborator entry from GET /user/playlists/{id}/collaborators.
struct PlaylistCollaborator: Decodable, Identifiable {
    let userId: String
    let username: String
    let role: String
    let addedAt: String?

    var id: String { userId }

    enum CodingKeys: String, CodingKey {
        case userId   = "user_id"
        case username
        case role
        case addedAt  = "added_at"
    }
}

/// One entry from GET /user/playlists/shared-with-me.
struct SharedWithMePlaylist: Decodable, Identifiable {
    let id: String
    let name: String
    let description: String?
    let role: String
    let ownerUsername: String
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, description, role
        case ownerUsername = "owner_username"
        case updatedAt     = "updated_at"
    }
}

/// One track within GET /user/playlists/{id}.
struct SharedPlaylistTrack: Decodable {
    let trackUrl: String?
    let localSongId: String?
    let title: String
    let artist: String?
    let album: String?
    let durationSeconds: Int?

    enum CodingKeys: String, CodingKey {
        case trackUrl        = "track_url"
        case localSongId     = "local_song_id"
        case title, artist, album
        case durationSeconds = "duration_seconds"
    }
}

/// Response from GET /user/scrobble.
struct ScrobbleLinks: Decodable {
    let lastfmLinked: Bool
    let lastfmUsername: String?
    let listenbrainzLinked: Bool
    let librefmLinked: Bool
    let librefmUsername: String?
    let enabled: Bool

    enum CodingKeys: String, CodingKey {
        case lastfmLinked       = "lastfm_linked"
        case lastfmUsername     = "lastfm_username"
        case listenbrainzLinked = "listenbrainz_linked"
        case librefmLinked      = "librefm_linked"
        case librefmUsername    = "librefm_username"
        case enabled
    }
}

/// One entry from GET /user/subscriptions.
struct ArtistSubscription: Decodable, Identifiable {
    let id: String
    let channelUrl: String
    let channelName: String?
    let lastVideoId: String?
    let lastCheckedAt: String?
    let createdAt: String?
    let channelId: String?
    let channelThumbnail: String?

    enum CodingKeys: String, CodingKey {
        case id
        case channelUrl        = "channel_url"
        case channelName       = "channel_name"
        case lastVideoId       = "last_video_id"
        case lastCheckedAt     = "last_checked_at"
        case createdAt         = "created_at"
        case channelId         = "channel_id"
        case channelThumbnail  = "channel_thumbnail"
    }
}

/// Result from POST /youtube/resolve-channel — a real YouTube channel
/// resolved from a URL/@handle/search term.
struct ResolvedChannel: Decodable {
    let channelId: String
    let channelTitle: String
    let channelThumbnail: String

    enum CodingKeys: String, CodingKey {
        case channelId        = "channel_id"
        case channelTitle     = "channel_title"
        case channelThumbnail = "channel_thumbnail"
    }
}

/// Response from POST /user/subscriptions/{id}/check.
struct SubscriptionCheckResult: Decodable {
    let newTracks: [StreamTrack]

    enum CodingKeys: String, CodingKey {
        case newTracks = "new_tracks"
    }
}

/// Response from GET /user/discord-webhook.
struct DiscordWebhookStatus: Decodable {
    let configured: Bool
    let enabled: Bool
    let webhookUrl: String?

    enum CodingKeys: String, CodingKey {
        case configured, enabled
        case webhookUrl = "webhook_url"
    }
}

/// Response from GET /user/discord-rpc-config — the server-side registration
/// for the local Discord Rich Presence daemon (Application client ID +
/// optional art asset name). Lets the daemon run with just an RPC token.
struct DiscordRpcConfig: Decodable {
    let configured: Bool
    let enabled: Bool
    let discordClientId: String?
    let largeImage: String?
    let smallImage: String?
    let showButtons: Bool

    enum CodingKeys: String, CodingKey {
        case configured, enabled
        case discordClientId = "discord_client_id"
        case largeImage = "large_image"
        case smallImage = "small_image"
        case showButtons = "show_buttons"
    }
}

/// Response shape for GET /user/youtube-api-key — the user's personal YouTube
/// Data API v3 key, used by /api/resolve to enumerate full YouTube playlists
/// (bypassing yt-dlp's ~205-entry flat-playlist cap). `apiKey` is masked
/// (e.g. "AIzaSy...AbPw") since the full key is never sent back after saving.
/// Status of this account's stored yt-dlp cookies.txt upload. The cookie
/// contents themselves are never sent back from the server — only whether
/// one is configured and when it was last updated.
struct YtdlpCookiesStatus: Decodable {
    let configured: Bool
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case configured
        case updatedAt = "updated_at"
    }
}

/// Detailed result of validating this account's stored yt-dlp cookies —
/// mirrors the structural + live checks the bridge runs in
/// `_validate_user_cookies` (required sign-in cookies present/expired, plus
/// whether LOGIN_INFO is present for age-restricted content).
struct YtdlpCookiesValidation: Decodable {
    let status: String
    let detail: String
    let missing: [String]
    let ageRestrictionReady: Bool
    let cookieCount: Int

    enum CodingKeys: String, CodingKey {
        case status, detail, missing
        case ageRestrictionReady = "age_restriction_ready"
        case cookieCount = "cookie_count"
    }
}

struct YoutubeApiKeyConfig: Decodable {
    let configured: Bool
    let apiKey: String?

    enum CodingKeys: String, CodingKey {
        case configured
        case apiKey = "api_key"
    }
}

/// One entry from GET /user/notifications.
struct AppNotification: Decodable, Identifiable {
    let id: String
    let type: String
    let title: String
    let body: String?
    let createdAt: String?
    let readAt: String?

    var isUnread: Bool { readAt == nil }

    enum CodingKeys: String, CodingKey {
        case id, type, title, body
        case createdAt = "created_at"
        case readAt    = "read_at"
    }
}

/// Response from POST /user/scrobble/lastfm/request-token.
struct LastfmRequestToken: Decodable {
    let token: String
    let authUrl: String

    enum CodingKeys: String, CodingKey {
        case token
        case authUrl = "auth_url"
    }
}

/// Full playlist (with tracks) from GET /user/playlists/{id}.
struct SharedPlaylistDetail: Decodable {
    let id: String
    let name: String
    let description: String?
    let role: String
    let tracks: [SharedPlaylistTrack]
}

/// One track from GET /user/queue.
struct QueueItem: Decodable {
    let localSongId: String?
    let trackUrl: String?
    let title: String
    let artist: String?
    let album: String?
    let durationSeconds: Int?

    enum CodingKeys: String, CodingKey {
        case localSongId      = "local_song_id"
        case trackUrl         = "track_url"
        case title, artist, album
        case durationSeconds  = "duration_seconds"
    }
}

/// Listening streaks and badge unlocks from GET /user/achievements.
struct AchievementsData: Codable {
    let totalPlays: Int
    let totalListenSeconds: Int
    let currentStreakDays: Int
    let longestStreakDays: Int
    let badges: [String]

    enum CodingKeys: String, CodingKey {
        case totalPlays         = "total_plays"
        case totalListenSeconds = "total_listen_seconds"
        case currentStreakDays  = "current_streak_days"
        case longestStreakDays  = "longest_streak_days"
        case badges
    }
}

struct SyncTrack: Codable {
    let localSongId: String?
    let trackUrl: String?
    let title: String
    let artist: String?
    let album: String?
    let durationSeconds: Int?
    let position: Int?

    enum CodingKeys: String, CodingKey {
        case localSongId      = "local_song_id"
        case trackUrl         = "track_url"
        case title
        case artist
        case album
        case durationSeconds  = "duration_seconds"
        case position
    }
}

// MARK: - AccountService

@MainActor
final class AccountService: ObservableObject {

    static let tokenKey       = "ios_account_token"
    static let userKey        = "ios_account_user"
    static let lastSyncKey    = "ios_account_last_sync"

    // MARK: Published state

    @Published var isLoggedIn: Bool = false
    @Published var currentUser: AppUser? = nil
    @Published var isSyncing: Bool = false
    @Published var errorMessage: String? = nil
    @Published var lastSyncDate: Date? = nil {
        didSet {
            if let d = lastSyncDate {
                UserDefaults.standard.set(d.timeIntervalSince1970, forKey: Self.lastSyncKey)
            }
        }
    }
    @Published var avatarImage: UIImage? = nil
    @Published var backups: [SyncBackup] = []
    @Published var socialActivity: [ActivityEntry] = []
    @Published var trendingTracks: [TrendingTrack] = []
    @Published var sessions: [AccountSession] = []
    @Published var stats: AccountStats? = nil
    @Published var achievements: AchievementsData? = nil
    @Published private(set) var hasDateOfBirth: Bool = false

    // MARK: Persisted token

    var token: String? {
        get { UserDefaults.standard.string(forKey: Self.tokenKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.tokenKey) }
    }

    // MARK: Debounce state

    private var syncDebounceTask: Task<Void, Never>?

    // MARK: Auto-push timer

    private var autoPushTimer: Timer?

    func startAutoPushTimer(library: LibraryManager) {
        stopAutoPushTimer()
        autoPushTimer = Timer.scheduledTimer(withTimeInterval: 8 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isLoggedIn else { return }
                await self.pushSync(library: library)
                await self.syncLibraryInventory(library: library)
            }
        }
    }

    func stopAutoPushTimer() {
        autoPushTimer?.invalidate()
        autoPushTimer = nil
    }

    /// Schedules a push sync that fires 2 seconds after the last call.
    /// Rapid successive mutations only trigger one server write.
    func schedulePush(
        library: LibraryManager,
        audioSettings: AudioSettings? = nil,
        trackAudioSettings: [String: AudioSettings]? = nil
    ) {
        guard isLoggedIn else { return }
        syncDebounceTask?.cancel()
        syncDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            guard let self, !Task.isCancelled, self.isLoggedIn else { return }
            await self.pushSync(library: library, audioSettings: audioSettings, trackAudioSettings: trackAudioSettings)
            await self.syncLibraryInventory(library: library)
        }
    }

    /// Uploads the set of source ids currently in the on-device library
    /// (Song.sourceTrackID + download-ledger ids whose files are still present)
    /// to the bridge, so server-side dedup (playlist resolve / downloads) knows
    /// what the user already has even though yt-dlp can never see the device's
    /// folders. Replaces the stored snapshot, so deletions are reflected. Cheap
    /// and debounced via the schedulePush path that calls it.
    func syncLibraryInventory(library: LibraryManager) async {
        guard isLoggedIn else { return }
        var ids = Set(library.allSongs.compactMap { $0.sourceTrackID }.filter { !$0.isEmpty })
        let presentFilenames = Set(library.allSongs.compactMap { $0.url?.lastPathComponent })
        for id in DownloadLedgerStore.shared.presentSourceIDs(presentFilenames: presentFilenames) {
            ids.insert(id)
        }
        struct InventoryBody: Encodable { let source_ids: [String] }
        do {
            _ = try await makeRequest("/user/library/inventory", method: "POST",
                                      body: InventoryBody(source_ids: Array(ids)))
            appLog("syncLibraryInventory: uploaded \(ids.count) source id(s)", category: "account")
        } catch {
            appWarn("syncLibraryInventory failed: \(error.localizedDescription)", category: "account")
        }
    }

    // MARK: Bridge URL — defaults to public baked-in URL, overridable in Settings

    var bridgeURL: String {
        UserDefaults.standard.string(forKey: StreamingService.bridgeURLKey)
            ?? StreamingService.defaultBridgeURL
    }

    // MARK: Init / Deinit

    deinit {
        syncDebounceTask?.cancel()
        autoPushTimer?.invalidate()
    }

    /// Ambient reference to the app's single AccountService instance, so
    /// services without direct access to the SwiftUI environment (e.g.
    /// AudioPlayerManager) can push playback state. Set once at init.
    static weak var shared: AccountService?

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.userKey),
           let user = try? JSONDecoder().decode(AppUser.self, from: data) {
            currentUser = user
            isLoggedIn = token != nil
            hasDateOfBirth = user.dateOfBirth != nil
            // Show the cached avatar immediately so the launch screen never
            // flashes the placeholder initial circle for a returning user —
            // `loadAvatar(forceRefresh: true)` (called later, post-pullSync)
            // skips the cache and hits the network, which is too slow for
            // the launch screen's first frame.
            avatarImage = loadAvatarLocally()
        }
        let ts = UserDefaults.standard.double(forKey: Self.lastSyncKey)
        if ts > 0 {
            // Bypass didSet to avoid re-writing the same value on init
            _lastSyncDate = Published(initialValue: Date(timeIntervalSince1970: ts))
        }
        Self.shared = self
    }

    // MARK: - Public API

    func login(username: String, password: String, deviceName: String = UIDevice.current.name) async {
        appLog("Login attempt: \(username)", category: "account")
        errorMessage = nil
        struct Body: Encodable {
            let username: String
            let password: String
            let device_name: String
        }
        do {
            let data = try await makeRequest(
                "/auth/login",
                method: "POST",
                body: Body(username: username, password: password, device_name: deviceName)
            )
            let response = try JSONDecoder().decode(AuthResponse.self, from: data)
            token = response.token
            currentUser = response.user
            isLoggedIn = true
            hasDateOfBirth = response.user.dateOfBirth != nil
            saveUserLocally(response.user)
            appLog("Login success: \(username) (id: \(response.user.id))", category: "account")
            await loadAvatar(forceRefresh: true)
        } catch let err as AccountError {
            appError("Login failed [\(err.statusCode)]: \(err.message)", category: "account")
            errorMessage = err.message
        } catch {
            appError("Login error: \(error.localizedDescription)", category: "account")
            errorMessage = error.localizedDescription
        }
    }

    func register(
        username: String,
        password: String,
        email: String?,
        displayName: String?
    ) async {
        appLog("Register attempt: \(username)", category: "account")
        errorMessage = nil
        struct Body: Encodable {
            let username: String
            let password: String
            let email: String?
            let display_name: String?
        }
        do {
            let data = try await makeRequest(
                "/auth/register",
                method: "POST",
                body: Body(
                    username: username,
                    password: password,
                    email: email.flatMap { $0.isEmpty ? nil : $0 },
                    display_name: displayName.flatMap { $0.isEmpty ? nil : $0 }
                )
            )
            let response = try JSONDecoder().decode(AuthResponse.self, from: data)
            token = response.token
            currentUser = response.user
            isLoggedIn = true
            hasDateOfBirth = response.user.dateOfBirth != nil
            saveUserLocally(response.user)
            appLog("Register success: \(username) (id: \(response.user.id))", category: "account")
            await loadAvatar(forceRefresh: true)
        } catch let err as AccountError {
            appError("Register failed [\(err.statusCode)]: \(err.message)", category: "account")
            errorMessage = err.message
        } catch {
            appError("Register error: \(error.localizedDescription)", category: "account")
            errorMessage = error.localizedDescription
        }
    }

    func logout() async {
        appLog("Logout: \(currentUser?.username ?? "?")", category: "account")
        errorMessage = nil
        if token != nil {
            _ = try? await makeRequest("/auth/logout", method: "POST", body: EmptyBody())
        }
        clearSession()
    }

    func refreshMe() async {
        guard isLoggedIn else { return }
        do {
            let data = try await makeRequest("/auth/me")
            let user = try JSONDecoder().decode(AppUser.self, from: data)
            currentUser = user
            hasDateOfBirth = user.dateOfBirth != nil
            saveUserLocally(user)
            appLog("refreshMe: updated profile for \(user.username)", category: "account")
        } catch let err as AccountError where err.statusCode == 401 {
            appWarn("refreshMe: session expired, clearing", category: "account")
            clearSession()
        } catch {
            appWarn("refreshMe: \(error.localizedDescription) — using cached user", category: "account")
        }
    }

    /// Update the display name on the server and locally.
    func updateDisplayName(_ newName: String) async {
        guard isLoggedIn else { return }
        appLog("updateDisplayName: \"\(newName)\"", category: "account")
        errorMessage = nil
        struct Body: Encodable { let display_name: String }
        do {
            let data = try await makeRequest("/auth/me", method: "PUT", body: Body(display_name: newName))
            let user = try JSONDecoder().decode(AppUser.self, from: data)
            currentUser = user
            hasDateOfBirth = user.dateOfBirth != nil
            saveUserLocally(user)
            appLog("updateDisplayName: success", category: "account")
        } catch let err as AccountError {
            appError("updateDisplayName failed [\(err.statusCode)]: \(err.message)", category: "account")
            errorMessage = err.message
        } catch {
            appError("updateDisplayName error: \(error.localizedDescription)", category: "account")
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Sync

    /// Call schedulePush instead of this directly — it debounces rapid mutations.
    func pushSync(
        library: LibraryManager,
        audioSettings: AudioSettings? = nil,
        trackAudioSettings: [String: AudioSettings]? = nil
    ) async {
        guard isLoggedIn else { return }
        appLog("Push sync started (favorites: \(library.favoriteSongIDs.count), playlists: \(library.playlists.count))", category: "account")
        isSyncing = true
        errorMessage = nil
        defer { isSyncing = false }

        // Build favorites from library
        let favorites = library.favoriteSongs.map { song in
            SyncFavorite(
                songId: song.id,
                title: song.title,
                artist: song.artistName,
                album: song.albumName
            )
        }

        // Build playlists from library
        let playlists = library.playlists.map { playlist -> SyncPlaylist in
            let songs = playlist.songIDs.compactMap { id in
                library.allSongs.first { $0.id == id }
            }
            let tracks = songs.enumerated().map { idx, song in
                SyncTrack(
                    localSongId: song.id,
                    trackUrl: song.url?.absoluteString,
                    title: song.title,
                    artist: song.artist.isEmpty ? nil : song.artist,
                    album: song.album.isEmpty ? nil : song.album,
                    durationSeconds: Int(song.duration),
                    position: idx
                )
            }
            return SyncPlaylist(
                id: playlist.id.uuidString,
                name: playlist.name,
                description: nil,
                folder: playlist.folder,
                tags: playlist.tags,
                tracks: tracks
            )
        }

        // Serialize audio settings to JSON if provided
        let audioJSON: String? = audioSettings.flatMap { settings in
            (try? JSONEncoder().encode(settings)).flatMap { String(data: $0, encoding: .utf8) }
        }
        // Serialize per-track audio settings overrides to JSON if provided
        let trackAudioJSON: String? = trackAudioSettings.flatMap { map in
            (try? JSONEncoder().encode(map)).flatMap { String(data: $0, encoding: .utf8) }
        }
        // Read current accent colour from UserDefaults (saved by AppTheme.saveAccentColor)
        let themeHex: String? = {
            guard let data = UserDefaults.standard.data(forKey: "accent_color_data"),
                  let uiColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: UIColor.self, from: data)
            else { return nil }
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
            return String(format: "#%02X%02X%02X", Int(r*255), Int(g*255), Int(b*255))
        }()

        let defaults = UserDefaults.standard

        // Visual/layout preferences — mirrored from ios_user_settings_expanded
        // columns so they round-trip through the normal sync push/pull too.
        // "Vinyl disc enabled" maps to the legacy `nowPlaying_showVinylDisc`
        // bool if present (NowPlayingView migrates it to nowPlaying_artworkStyle
        // on first read), otherwise derive it from the current artwork style.
        let vinylDiscEnabled: Bool? = {
            if let legacy = defaults.object(forKey: "nowPlaying_showVinylDisc") as? Bool {
                return legacy
            }
            if let style = defaults.string(forKey: "nowPlaying_artworkStyle") {
                return style == "vinylDisc"
            }
            return nil
        }()
        let showQueuePreview: Bool? = defaults.object(forKey: "nowPlaying_showQueuePreview") != nil
            ? defaults.bool(forKey: "nowPlaying_showQueuePreview") : nil
        let songsPerRow: Int? = defaults.object(forKey: "library_songs_columns") != nil
            ? defaults.integer(forKey: "library_songs_columns") : nil
        let albumsPerRow: Int? = defaults.object(forKey: "library_albums_columns") != nil
            ? defaults.integer(forKey: "library_albums_columns") : nil
        let bgAnimation = defaults.string(forKey: "bgService.animation")
        let bgOpacity: Double? = defaults.object(forKey: "bgService.opacity") != nil
            ? defaults.double(forKey: "bgService.opacity") : nil
        let bgEnabled: Bool? = defaults.object(forKey: "bgService.isEnabled") != nil
            ? defaults.bool(forKey: "bgService.isEnabled") : nil
        let bgBlurRadius: Double? = defaults.object(forKey: "bgService.blurRadius") != nil
            ? defaults.double(forKey: "bgService.blurRadius") : nil
        let bgShuffleInterval: Double? = defaults.object(forKey: "bgService.shuffleInterval") != nil
            ? defaults.double(forKey: "bgService.shuffleInterval") : nil
        let preferredAudioFormat = defaults.string(forKey: StreamingService.preferredFormatKey)
        let downloadPath = defaults.string(forKey: StreamingService.downloadPathKey)

        // New sync fields
        let carModeEnabled: Bool? = defaults.object(forKey: "carModeEnabled") != nil
            ? defaults.bool(forKey: "carModeEnabled") : nil
        let libraryArtistsColumns: Int? = defaults.object(forKey: "library_artists_columns") != nil
            ? defaults.integer(forKey: "library_artists_columns") : nil
        let nowPlayingArtworkStyle = defaults.string(forKey: "nowPlaying_artworkStyle")
        let nowPlayingSeekerStyle = defaults.string(forKey: "nowPlaying_seekerStyle")
        let earnedBadgesJSON: String? = {
            guard let data = defaults.data(forKey: "earnedBadges"),
                  let decoded = try? JSONDecoder().decode(Set<String>.self, from: data),
                  !decoded.isEmpty
            else { return nil }
            return (try? JSONEncoder().encode(decoded)).flatMap { String(data: $0, encoding: .utf8) }
        }()

        let payload = SyncData(
            favorites: favorites,
            playlists: playlists,
            audioSettingsJSON: audioJSON,
            trackAudioSettingsJSON: trackAudioJSON,
            themeColor: themeHex ?? "#EC4079",
            vinylDiscEnabled: vinylDiscEnabled,
            showQueuePreview: showQueuePreview,
            songsPerRow: songsPerRow,
            albumsPerRow: albumsPerRow,
            bgAnimation: bgAnimation,
            bgOpacity: bgOpacity,
            bgEnabled: bgEnabled,
            bgBlurRadius: bgBlurRadius,
            bgShuffleInterval: bgShuffleInterval,
            preferredAudioFormat: preferredAudioFormat,
            downloadPath: downloadPath,
            carModeEnabled: carModeEnabled,
            libraryArtistsColumns: libraryArtistsColumns,
            nowPlayingArtworkStyle: nowPlayingArtworkStyle,
            nowPlayingSeekerStyle: nowPlayingSeekerStyle,
            earnedBadgesJSON: earnedBadgesJSON,
            extraSettingsJSON: Self.buildExtraSettingsJSON()
        )

        do {
            _ = try await makeRequest("/user/sync", method: "POST", body: payload)
            lastSyncDate = Date()
            appLog("Push sync complete", category: "account")
        } catch let err as AccountError {
            appError("Push sync failed [\(err.statusCode)]: \(err.message)", category: "account")
            errorMessage = err.message
        } catch {
            appError("Push sync error: \(error.localizedDescription)", category: "account")
            errorMessage = error.localizedDescription
        }
    }

    /// Additional UserDefaults-backed preference keys (and their value type)
    /// included in the per-user auto backup beyond the explicitly-modelled
    /// SyncData columns. Backed up/restored as a single JSON bag
    /// (`extra_settings_json`). Adding a new backed-up preference is a one-line
    /// addition here.
    private static let extraBackupKeys: [(key: String, kind: ExtraSettingKind)] = [
        ("library_cardStyle", .string),
        ("autoRadio_enabled", .bool),
        ("notifications_enabled", .bool),
        ("ytdlp_use_aria2", .bool),
        // Liquid Glass customization (see GlassSettings)
        ("glass_tintStrength", .double),
        ("glass_tintHue", .double),
        ("glass_useAccentTint", .bool),
        ("glass_translucency", .double),
    ]

    private enum ExtraSettingKind { case bool, double, string, int }

    /// Serializes the current values of `extraBackupKeys` (only those actually
    /// set) into a JSON object string for the backup payload.
    static func buildExtraSettingsJSON() -> String? {
        let defaults = UserDefaults.standard
        var dict: [String: Any] = [:]
        for entry in extraBackupKeys {
            guard defaults.object(forKey: entry.key) != nil else { continue }
            switch entry.kind {
            case .bool:   dict[entry.key] = defaults.bool(forKey: entry.key)
            case .double: dict[entry.key] = defaults.double(forKey: entry.key)
            case .int:    dict[entry.key] = defaults.integer(forKey: entry.key)
            case .string: dict[entry.key] = defaults.string(forKey: entry.key)
            }
        }
        guard !dict.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: dict),
              let json = String(data: data, encoding: .utf8)
        else { return nil }
        return json
    }

    /// Restores backed-up extra settings, writing each key only when it's not
    /// already set locally — first-run/new-device bootstrap only, mirroring the
    /// non-destructive restore policy used for the other synced settings (see
    /// the destructive-pull-sync fix) so a fresher local value is never
    /// clobbered by a stale server one.
    static func applyExtraSettingsJSON(_ json: String?) {
        guard let json, let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }
        let defaults = UserDefaults.standard
        for entry in extraBackupKeys {
            guard defaults.object(forKey: entry.key) == nil, let value = dict[entry.key] else { continue }
            switch entry.kind {
            case .bool:   if let b = value as? Bool   { defaults.set(b, forKey: entry.key) }
            case .double: if let d = value as? Double { defaults.set(d, forKey: entry.key) }
                          else if let n = value as? NSNumber { defaults.set(n.doubleValue, forKey: entry.key) }
            case .int:    if let i = value as? Int    { defaults.set(i, forKey: entry.key) }
                          else if let n = value as? NSNumber { defaults.set(n.intValue, forKey: entry.key) }
            case .string: if let s = value as? String { defaults.set(s, forKey: entry.key) }
            }
        }
    }

    func pullSync(library: LibraryManager, player: AudioPlayerManager? = nil) async {
        guard isLoggedIn else { return }
        appLog("Pull sync started", category: "account")
        isSyncing = true
        errorMessage = nil
        defer { isSyncing = false }

        do {
            let data = try await makeRequest("/user/sync")
            let sync = try JSONDecoder().decode(SyncData.self, from: data)

            // Apply favorites: merge remote into local — add anything missing locally.
            //
            // This used to be a destructive "toggle to match remote exactly", which
            // also *removed* any local favorite absent from the server payload. That
            // silently wiped out the user's likes whenever the remote was behind the
            // device (e.g. the previous session's pushSync hadn't completed before
            // the app was terminated, or ran against a flaky connection) — which is
            // exactly what showed up as "app data doesn't seem to hold anything
            // locally". Only ever add; the merged superset gets pushed back up by
            // the `.onChange(of: favoriteSongIDs)` → schedulePush handler, so both
            // sides converge without data loss.
            let remoteIDs = Set(sync.favorites.map { $0.songId })
            let localFavorites = library.favoriteSongIDs
            let toAdd = remoteIDs.subtracting(localFavorites)
            for id in toAdd { library.toggleFavorite(songID: id) }

            // Apply playlists: merge server playlists (add missing by name, skip existing)
            let existingNames = Set(library.playlists.map { $0.name })
            for sp in sync.playlists {
                guard !existingNames.contains(sp.name) else { continue }
                library.createPlaylist(name: sp.name)
                // Add any local song IDs that match tracks
                if let newPL = library.playlists.last(where: { $0.name == sp.name }) {
                    for track in sp.tracks {
                        if let sid = track.localSongId {
                            library.addSong(id: sid, toPlaylistID: newPL.id)
                        }
                    }
                    if sp.folder != nil { library.setFolder(sp.folder, forPlaylistID: newPL.id) }
                    if !sp.tags.isEmpty { library.setTags(sp.tags, forPlaylistID: newPL.id) }
                }
            }

            // Restore audio settings from DB — but only as a first-run/new-device
            // bootstrap (no local settings yet). Unconditionally overwriting local
            // settings with whatever the server last received clobbers more recent
            // local changes whenever a previous pushSync didn't finish before the
            // app was terminated (the debounced 2s push is easy to race on app
            // close), which presents to the user as "my settings keep resetting /
            // don't actually save". The local copy — which `onChange` keeps pushed
            // up via schedulePush — is always at least as fresh as the server's.
            if PersistenceService.shared.loadAudioSettings() == nil,
               let json = sync.audioSettingsJSON,
               let jsonData = json.data(using: .utf8),
               let restoredSettings = try? JSONDecoder().decode(AudioSettings.self, from: jsonData) {
                PersistenceService.shared.saveAudioSettings(restoredSettings)
                // Signal the player to apply them (observers in LumisoundApp reload on launch)
            }

            // Restore per-track audio settings overrides — same first-run-only
            // guard as the global audio settings above, to avoid clobbering
            // settings saved locally since the last successful push.
            if PersistenceService.shared.loadTrackAudioSettings().isEmpty,
               let json = sync.trackAudioSettingsJSON,
               let jsonData = json.data(using: .utf8),
               let restoredMap = try? JSONDecoder().decode([String: AudioSettings].self, from: jsonData),
               !restoredMap.isEmpty {
                if let player {
                    player.restorePerTrackAudioSettings(restoredMap)
                } else {
                    PersistenceService.shared.saveTrackAudioSettings(restoredMap)
                }
            }

            // Restore theme colour — same first-run-only guard as audio settings above:
            // there's no `.onChange` hook pushing accent-colour changes immediately
            // (it only rides along on the next favorites/playlist/settings push), so
            // an unconditional overwrite here would routinely revert a just-picked
            // colour back to whatever stale value the server last happened to receive.
            if UserDefaults.standard.data(forKey: "accent_color_data") == nil,
               let hex = sync.themeColor, hex.hasPrefix("#"), hex.count == 7 {
                let scanner = Scanner(string: String(hex.dropFirst()))
                var rgb: UInt64 = 0
                if scanner.scanHexInt64(&rgb) {
                    let r = CGFloat((rgb >> 16) & 0xFF) / 255
                    let g = CGFloat((rgb >> 8)  & 0xFF) / 255
                    let b = CGFloat( rgb        & 0xFF) / 255
                    AppTheme.saveAccentColor(Color(red: r, green: g, blue: b))
                }
            }

            // Restore expanded visual/layout preferences and the new sync
            // fields — same first-run-only guard as audio settings/theme above:
            // only apply when the local UserDefaults key is unset, so a fresher
            // local change is never clobbered by a stale server value.
            let defaults = UserDefaults.standard

            if defaults.object(forKey: "nowPlaying_showVinylDisc") == nil,
               defaults.string(forKey: "nowPlaying_artworkStyle") == nil,
               let vinylDiscEnabled = sync.vinylDiscEnabled {
                defaults.set(vinylDiscEnabled, forKey: "nowPlaying_showVinylDisc")
            }
            if defaults.object(forKey: "nowPlaying_showQueuePreview") == nil,
               let showQueuePreview = sync.showQueuePreview {
                defaults.set(showQueuePreview, forKey: "nowPlaying_showQueuePreview")
            }
            if defaults.object(forKey: "library_songs_columns") == nil,
               let songsPerRow = sync.songsPerRow {
                defaults.set(songsPerRow, forKey: "library_songs_columns")
            }
            if defaults.object(forKey: "library_albums_columns") == nil,
               let albumsPerRow = sync.albumsPerRow {
                defaults.set(albumsPerRow, forKey: "library_albums_columns")
            }
            if defaults.string(forKey: "bgService.animation") == nil,
               let bgAnimation = sync.bgAnimation {
                defaults.set(bgAnimation, forKey: "bgService.animation")
            }
            if defaults.object(forKey: "bgService.opacity") == nil,
               let bgOpacity = sync.bgOpacity {
                defaults.set(bgOpacity, forKey: "bgService.opacity")
            }
            if defaults.object(forKey: "bgService.isEnabled") == nil,
               let bgEnabled = sync.bgEnabled {
                defaults.set(bgEnabled, forKey: "bgService.isEnabled")
            }
            if defaults.object(forKey: "bgService.blurRadius") == nil,
               let bgBlurRadius = sync.bgBlurRadius {
                defaults.set(bgBlurRadius, forKey: "bgService.blurRadius")
            }
            if defaults.object(forKey: "bgService.shuffleInterval") == nil,
               let bgShuffleInterval = sync.bgShuffleInterval {
                defaults.set(bgShuffleInterval, forKey: "bgService.shuffleInterval")
            }
            // Re-apply the (possibly just-updated) gallery background settings to
            // the live BackgroundService instance — without this, a value written
            // to UserDefaults above sits unused until the next app launch, and the
            // very next `didSet` on the running instance (e.g. opening the
            // background settings screen) immediately pushes its still-old
            // in-memory value back to the server, overwriting what was just pulled.
            BackgroundService.shared?.loadSettings()
            if defaults.string(forKey: StreamingService.preferredFormatKey) == nil,
               let preferredAudioFormat = sync.preferredAudioFormat {
                defaults.set(preferredAudioFormat, forKey: StreamingService.preferredFormatKey)
            }
            if defaults.string(forKey: StreamingService.downloadPathKey) == nil,
               let downloadPath = sync.downloadPath {
                defaults.set(downloadPath, forKey: StreamingService.downloadPathKey)
            }
            if defaults.object(forKey: "carModeEnabled") == nil,
               let carModeEnabled = sync.carModeEnabled {
                defaults.set(carModeEnabled, forKey: "carModeEnabled")
            }
            if defaults.object(forKey: "library_artists_columns") == nil,
               let libraryArtistsColumns = sync.libraryArtistsColumns {
                defaults.set(libraryArtistsColumns, forKey: "library_artists_columns")
            }
            if defaults.string(forKey: "nowPlaying_artworkStyle") == nil,
               let nowPlayingArtworkStyle = sync.nowPlayingArtworkStyle {
                defaults.set(nowPlayingArtworkStyle, forKey: "nowPlaying_artworkStyle")
            }
            if defaults.string(forKey: "nowPlaying_seekerStyle") == nil,
               let nowPlayingSeekerStyle = sync.nowPlayingSeekerStyle {
                defaults.set(nowPlayingSeekerStyle, forKey: "nowPlaying_seekerStyle")
            }

            // Earned badges: UNION merge with local regardless of whether local
            // already has a value — badges should never be "lost" by syncing
            // from a device that hasn't unlocked them all yet.
            if let json = sync.earnedBadgesJSON,
               let jsonData = json.data(using: .utf8),
               let remoteBadges = try? JSONDecoder().decode(Set<String>.self, from: jsonData),
               !remoteBadges.isEmpty {
                var localBadges: Set<String> = []
                if let stored = defaults.data(forKey: "earnedBadges"),
                   let decoded = try? JSONDecoder().decode(Set<String>.self, from: stored) {
                    localBadges = decoded
                }
                let merged = localBadges.union(remoteBadges)
                if merged != localBadges,
                   let encoded = try? JSONEncoder().encode(merged) {
                    defaults.set(encoded, forKey: "earnedBadges")
                }
            }

            // Restore any additional backed-up preferences (card style,
            // auto-radio, notifications, Liquid Glass customization, …) — only
            // for keys not already set locally (new-device bootstrap).
            Self.applyExtraSettingsJSON(sync.extraSettingsJSON)

            lastSyncDate = Date()
            appLog("Pull sync complete (favorites: \(remoteIDs.count), playlists: \(sync.playlists.count))", category: "account")
        } catch let err as AccountError {
            appError("Pull sync failed [\(err.statusCode)]: \(err.message)", category: "account")
            errorMessage = err.message
        } catch {
            appError("Pull sync error: \(error.localizedDescription)", category: "account")
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Queue sync

    /// Replaces the server's "up next" queue with `songs`, in order, so it
    /// survives app restarts and syncs across devices (PUT /user/queue).
    /// Fire-and-forget — failures are logged but not surfaced as errors,
    /// since this runs automatically in the background whenever the queue changes.
    func pushQueue(_ songs: [Song]) async {
        guard isLoggedIn else { return }
        struct TrackBody: Encodable {
            let local_song_id: String?
            let track_url: String?
            let title: String
            let artist: String?
            let album: String?
            let duration_seconds: Int
        }
        struct Body: Encodable { let tracks: [TrackBody] }
        let tracks = songs.map { song in
            TrackBody(
                local_song_id: song.persistentID == nil ? song.id : nil,
                track_url: song.url?.absoluteString,
                title: song.title,
                artist: song.artist.isEmpty ? nil : song.artist,
                album: song.album.isEmpty ? nil : song.album,
                duration_seconds: Int(song.duration)
            )
        }
        do {
            _ = try await makeRequest("/user/queue", method: "PUT", body: Body(tracks: tracks))
        } catch {
            appLog("Queue sync push failed: \(error.localizedDescription)", category: "account")
        }
    }

    /// Fetches the server's "up next" queue (GET /user/queue), resolving each
    /// entry against the local library (by ID) or as a streaming track (by URL).
    /// Entries that can't be resolved either way are skipped.
    func fetchQueue(library: LibraryManager) async -> [Song] {
        guard isLoggedIn else { return [] }
        do {
            let data = try await makeRequest("/user/queue")
            let items = try JSONDecoder().decode([QueueItem].self, from: data)
            let songsByID = Dictionary(uniqueKeysWithValues: library.allSongs.map { ($0.id, $0) })
            return items.compactMap { item -> Song? in
                if let localID = item.localSongId, let song = songsByID[localID] {
                    return song
                }
                if let urlString = item.trackUrl, let url = URL(string: urlString) {
                    return Song(
                        title: item.title,
                        artist: item.artist ?? "",
                        album: item.album ?? "",
                        duration: TimeInterval(item.durationSeconds ?? 0),
                        url: url
                    )
                }
                return nil
            }
        } catch let err as AccountError {
            errorMessage = err.message
            return []
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

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

    // MARK: - Scrobbling

    /// Fetches whether the user has Last.fm/ListenBrainz scrobbling linked.
    func fetchScrobbleLinks() async -> ScrobbleLinks? {
        guard isLoggedIn else { return nil }
        do {
            let data = try await makeRequest("/user/scrobble")
            return try JSONDecoder().decode(ScrobbleLinks.self, from: data)
        } catch let err as AccountError {
            errorMessage = err.message
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Links (or relinks) a ListenBrainz user token.
    func linkListenBrainz(token: String) async -> Bool {
        guard isLoggedIn else { return false }
        struct Body: Encodable { let listenbrainz_token: String }
        do {
            _ = try await makeRequest("/user/scrobble", method: "PUT", body: Body(listenbrainz_token: token))
            return true
        } catch let err as AccountError {
            errorMessage = err.message
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Enables or disables scrobbling without changing linked accounts.
    func setScrobblingEnabled(_ enabled: Bool) async -> Bool {
        guard isLoggedIn else { return false }
        struct Body: Encodable { let enabled: Bool }
        do {
            _ = try await makeRequest("/user/scrobble", method: "PUT", body: Body(enabled: enabled))
            return true
        } catch let err as AccountError {
            errorMessage = err.message
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Unlinks all scrobbling accounts.
    func unlinkScrobbling() async -> Bool {
        guard isLoggedIn else { return false }
        do {
            _ = try await makeRequest("/user/scrobble", method: "DELETE")
            return true
        } catch let err as AccountError {
            errorMessage = err.message
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Step 1 of the Last.fm desktop auth flow — fetch a token and the URL to open in Safari.
    func lastfmRequestToken() async -> LastfmRequestToken? {
        guard isLoggedIn else { return nil }
        do {
            let data = try await makeRequest("/user/scrobble/lastfm/request-token", method: "POST")
            return try JSONDecoder().decode(LastfmRequestToken.self, from: data)
        } catch let err as AccountError {
            errorMessage = err.message
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Step 2 — exchange an approved token for a session key. Returns the linked username on success.
    func lastfmLinkSession(token: String) async -> String? {
        guard isLoggedIn else { return nil }
        struct Body: Encodable { let token: String }
        struct Response: Decodable { let lastfm_username: String? }
        do {
            let data = try await makeRequest("/user/scrobble/lastfm/link", method: "POST", body: Body(token: token))
            return try JSONDecoder().decode(Response.self, from: data).lastfm_username
        } catch let err as AccountError {
            errorMessage = err.message
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Step 1 of the Libre.fm desktop auth flow — same protocol as Last.fm, different host.
    func librefmRequestToken() async -> LastfmRequestToken? {
        guard isLoggedIn else { return nil }
        do {
            let data = try await makeRequest("/user/scrobble/librefm/request-token", method: "POST")
            return try JSONDecoder().decode(LastfmRequestToken.self, from: data)
        } catch let err as AccountError {
            errorMessage = err.message
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Step 2 — exchange an approved Libre.fm token for a session key. Returns the linked username on success.
    func librefmLinkSession(token: String) async -> String? {
        guard isLoggedIn else { return nil }
        struct Body: Encodable { let token: String }
        struct Response: Decodable { let librefm_username: String? }
        do {
            let data = try await makeRequest("/user/scrobble/librefm/link", method: "POST", body: Body(token: token))
            return try JSONDecoder().decode(Response.self, from: data).librefm_username
        } catch let err as AccountError {
            errorMessage = err.message
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    // MARK: - Artist/Channel Subscriptions

    /// Lists the user's subscribed channels.
    func fetchSubscriptions() async -> [ArtistSubscription] {
        guard isLoggedIn else { return [] }
        do {
            let data = try await makeRequest("/user/subscriptions")
            return try JSONDecoder().decode([ArtistSubscription].self, from: data)
        } catch let err as AccountError {
            errorMessage = err.message
            return []
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    /// Subscribes to a channel/artist URL (YouTube or SoundCloud).
    func addSubscription(channelUrl: String, channelName: String?) async -> Bool {
        guard isLoggedIn else { return false }
        struct Body: Encodable { let channel_url: String; let channel_name: String? }
        do {
            _ = try await makeRequest("/user/subscriptions", method: "POST", body: Body(channel_url: channelUrl, channel_name: channelName))
            return true
        } catch let err as AccountError {
            errorMessage = err.message
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Unsubscribes from a channel.
    func removeSubscription(id: String) async -> Bool {
        guard isLoggedIn else { return false }
        do {
            _ = try await makeRequest("/user/subscriptions/\(id)", method: "DELETE")
            return true
        } catch let err as AccountError {
            errorMessage = err.message
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Resolves a YouTube channel URL/@handle/search term to a real channel
    /// (id, title, thumbnail) via POST /youtube/resolve-channel.
    func resolveYoutubeChannel(query: String) async -> ResolvedChannel? {
        guard isLoggedIn else { return nil }
        struct Body: Encodable { let query: String }
        do {
            let data = try await makeRequest("/youtube/resolve-channel", method: "POST", body: Body(query: query))
            return try JSONDecoder().decode(ResolvedChannel.self, from: data)
        } catch let err as AccountError {
            errorMessage = err.message
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Fetches recent uploads for a resolved channel (GET /youtube/channel-uploads).
    func fetchChannelUploads(channelId: String, limit: Int = 10) async -> [StreamTrack] {
        guard isLoggedIn else { return [] }
        do {
            let data = try await makeRequest("/youtube/channel-uploads?channel_id=\(channelId)&limit=\(limit)")
            return try JSONDecoder().decode([StreamTrack].self, from: data)
        } catch let err as AccountError {
            errorMessage = err.message
            return []
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    /// Checks a channel for new uploads since the last check, returning any new tracks found.
    func checkSubscription(id: String) async -> [StreamTrack] {
        guard isLoggedIn else { return [] }
        do {
            let data = try await makeRequest("/user/subscriptions/\(id)/check", method: "POST")
            return try JSONDecoder().decode(SubscriptionCheckResult.self, from: data).newTracks
        } catch let err as AccountError {
            errorMessage = err.message
            return []
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    // MARK: - Discover Mix

    /// Fetches a "Discover Mix" of suggested tracks seeded from the user's
    /// most-played artists, excluding tracks already in their library/favorites.
    func fetchDiscoverMix(limit: Int = 20) async -> [StreamTrack] {
        guard isLoggedIn else { return [] }
        do {
            let data = try await makeRequest("/user/discover-mix?limit=\(limit)")
            return try JSONDecoder().decode([StreamTrack].self, from: data)
        } catch let err as AccountError {
            errorMessage = err.message
            return []
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

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

    // MARK: - Folder structure backup (item 3)

    /// Debounce task mirroring `schedulePush` — folder-structure pushes ride
    /// along on the same 2-second debounce window as the main sync push, since
    /// both are triggered by the same kinds of changes (library rescans/imports).
    private var folderBackupDebounceTask: Task<Void, Never>?

    /// Schedules a push of the watched-folder structure 2 seconds after the
    /// last call. Called whenever watched folders or the library's imported
    /// songs change (folder added/removed, rescan picks up new files, etc.).
    func scheduleFolderBackupPush(folderService: MusicFolderService, library: LibraryManager) {
        guard isLoggedIn else { return }
        folderBackupDebounceTask?.cancel()
        folderBackupDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard let self, !Task.isCancelled, self.isLoggedIn else { return }
            await self.pushFolderBackups(folderService: folderService, library: library)
        }
    }

    /// Pushes the current watched-folder structure (relative paths under
    /// Documents + the tracks in each) to the server, replacing any previous
    /// folder backup wholesale. Fire-and-forget — failures are logged only.
    func pushFolderBackups(folderService: MusicFolderService, library: LibraryManager) async {
        guard isLoggedIn else { return }
        let entries = folderService.folderBackupEntries(songs: library.allSongs)
        struct Body: Encodable {
            let folders: [FolderBackupEntry]
            enum CodingKeys: String, CodingKey { case folders }
        }
        do {
            _ = try await makeRequest("/user/folder-backups", method: "PUT", body: Body(folders: entries))
            appLog("pushFolderBackups: pushed \(entries.count) folder(s)", category: "account")
        } catch let err as AccountError {
            appWarn("pushFolderBackups failed [\(err.statusCode)]: \(err.message)", category: "account")
        } catch {
            appWarn("pushFolderBackups error: \(error.localizedDescription)", category: "account")
        }
    }

    /// Fetches this account's backed-up folder structure, if any. Returns an
    /// empty array if the user never pushed one (never used watched folders, or
    /// hasn't synced since this feature shipped).
    func fetchFolderBackups() async -> [FolderBackupEntry] {
        guard isLoggedIn else { return [] }
        struct Response: Decodable {
            let folders: [FolderBackupEntry]
            enum CodingKeys: String, CodingKey { case folders }
        }
        do {
            let data = try await makeRequest("/user/folder-backups")
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            return decoded.folders
        } catch let err as AccountError {
            appWarn("fetchFolderBackups failed [\(err.statusCode)]: \(err.message)", category: "account")
            return []
        } catch {
            appWarn("fetchFolderBackups error: \(error.localizedDescription)", category: "account")
            return []
        }
    }

    // MARK: - Social: listening activity & discovery

    /// Toggles whether this account's recent plays are visible to other
    /// signed-in users (title/artist only — see GET /social/activity).
    func setShareListeningActivity(_ enabled: Bool) async {
        guard isLoggedIn else { return }
        struct Body: Encodable { let share_listening_activity: Bool }
        do {
            _ = try await makeRequest("/user/privacy", method: "PUT", body: Body(share_listening_activity: enabled))
            if var user = currentUser {
                user.shareListeningActivity = enabled
                currentUser = user
                if let data = try? JSONEncoder().encode(user) {
                    UserDefaults.standard.set(data, forKey: Self.userKey)
                }
            }
        } catch let err as AccountError {
            errorMessage = err.message
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Fetches the recent "what others are listening to" feed.
    func fetchSocialActivity() async {
        guard isLoggedIn else { return }
        do {
            let data = try await makeRequest("/social/activity")
            struct Response: Decodable { let activity: [ActivityEntry] }
            socialActivity = try JSONDecoder().decode(Response.self, from: data).activity
        } catch let err as AccountError {
            errorMessage = err.message
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Fetches trending tracks aggregated across users sharing activity.
    func fetchTrendingTracks() async {
        guard isLoggedIn else { return }
        do {
            let data = try await makeRequest("/social/discover")
            struct Response: Decodable { let tracks: [TrendingTrack] }
            trendingTracks = try JSONDecoder().decode(Response.self, from: data).tracks
        } catch let err as AccountError {
            errorMessage = err.message
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Stats

    /// Fetches lifetime listening stats (total plays/time, top artists/tracks).
    func fetchStats() async {
        guard isLoggedIn else { return }
        do {
            let data = try await makeRequest("/user/stats")
            stats = try JSONDecoder().decode(AccountStats.self, from: data)
        } catch let err as AccountError {
            errorMessage = err.message
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Fetches listening streaks and badge unlocks (derived server-side from play history).
    func fetchAchievements() async {
        guard isLoggedIn else { return }
        do {
            let data = try await makeRequest("/user/achievements")
            achievements = try JSONDecoder().decode(AchievementsData.self, from: data)
        } catch let err as AccountError {
            errorMessage = err.message
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Sessions (active logins)

    /// Fetches this account's active sessions (one per signed-in device).
    func fetchSessions() async {
        guard isLoggedIn else { return }
        do {
            let data = try await makeRequest("/auth/sessions")
            struct Response: Decodable { let sessions: [AccountSession] }
            sessions = try JSONDecoder().decode(Response.self, from: data).sessions
        } catch let err as AccountError {
            errorMessage = err.message
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Revokes a session by token ID. If it's the current device's session,
    /// also clears the local session (the user is effectively signed out).
    func revokeSession(tokenId: String) async {
        guard isLoggedIn else { return }
        do {
            _ = try await makeRequest("/auth/sessions/\(tokenId)", method: "DELETE")
            if sessions.first(where: { $0.tokenId == tokenId })?.isCurrent == true {
                clearSession()
                return
            }
            await fetchSessions()
        } catch let err as AccountError {
            errorMessage = err.message
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Generates a long-lived (365-day) "RPC setup" token for local tools
    /// like the Discord Rich Presence bridge, so the user never has to put
    /// their account password in a desktop config file. The token shows up
    /// as a regular session ("Discord RPC Bridge") and can be revoked from
    /// Active Sessions.
    func generateRpcToken() async -> String? {
        guard isLoggedIn else { return nil }
        do {
            let data = try await makeRequest("/user/rpc-token", method: "POST")
            struct Response: Decodable { let token: String; let expires_at: String }
            return try JSONDecoder().decode(Response.self, from: data).token
        } catch let err as AccountError {
            errorMessage = err.message
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Fetches this account's registered Discord Rich Presence settings
    /// (Application client ID + optional art asset name). The local
    /// Rich Presence daemon reads this so users don't need to copy the
    /// client ID into a config file.
    func fetchDiscordRpcConfig() async -> DiscordRpcConfig? {
        guard isLoggedIn else { return nil }
        do {
            let data = try await makeRequest("/user/discord-rpc-config")
            return try JSONDecoder().decode(DiscordRpcConfig.self, from: data)
        } catch let err as AccountError {
            errorMessage = err.message
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Registers (or updates) the Discord Application client ID and optional
    /// art asset name used by the local Discord Rich Presence daemon.
    func setDiscordRpcConfig(clientId: String, largeImage: String?, smallImage: String?, showButtons: Bool, enabled: Bool) async -> Bool {
        guard isLoggedIn else { return false }
        struct Body: Encodable {
            let discord_client_id: String
            let large_image: String?
            let small_image: String?
            let show_buttons: Bool
            let enabled: Bool
        }
        do {
            _ = try await makeRequest("/user/discord-rpc-config", method: "PUT", body: Body(discord_client_id: clientId, large_image: largeImage, small_image: smallImage, show_buttons: showButtons, enabled: enabled))
            return true
        } catch let err as AccountError {
            errorMessage = err.message
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Removes the Discord Rich Presence registration entirely.
    func deleteDiscordRpcConfig() async -> Bool {
        guard isLoggedIn else { return false }
        do {
            _ = try await makeRequest("/user/discord-rpc-config", method: "DELETE")
            return true
        } catch let err as AccountError {
            errorMessage = err.message
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Fetches this account's personal YouTube Data API key status (masked).
    func fetchYoutubeApiKey() async -> YoutubeApiKeyConfig? {
        guard isLoggedIn else { return nil }
        do {
            let data = try await makeRequest("/user/youtube-api-key")
            return try JSONDecoder().decode(YoutubeApiKeyConfig.self, from: data)
        } catch let err as AccountError {
            errorMessage = err.message
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Saves (or replaces) this account's personal YouTube Data API key.
    /// Used by /api/resolve for full-playlist enumeration via playlistItems.list,
    /// and falls back to the server-wide key if unset.
    func setYoutubeApiKey(_ apiKey: String) async -> Bool {
        guard isLoggedIn else { return false }
        struct Body: Encodable { let api_key: String }
        do {
            _ = try await makeRequest("/user/youtube-api-key", method: "PUT", body: Body(api_key: apiKey))
            return true
        } catch let err as AccountError {
            errorMessage = err.message
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Validates this account's stored YouTube Data API key with a minimal
    /// server-side call. Returns "valid", "invalid", "quota_exceeded", or
    /// "error" (network/other failure).
    func validateYouTubeAPIKey() async -> String {
        guard isLoggedIn else { return "error" }
        struct Response: Decodable { let status: String }
        do {
            let data = try await makeRequest("/youtube/validate-key", method: "POST")
            return try JSONDecoder().decode(Response.self, from: data).status
        } catch let err as AccountError {
            errorMessage = err.message
            return "error"
        } catch {
            errorMessage = error.localizedDescription
            return "error"
        }
    }

    /// Checks whether this account's stored YouTube Data API key shows signs
    /// of having been leaked/abused (invalid, referrer-restricted, or
    /// quota-exhausted shortly after setup).
    func checkYouTubeKeyExposure() async -> (exposed: Bool, detail: String) {
        guard isLoggedIn else { return (false, "") }
        struct Response: Decodable { let exposed: Bool; let detail: String }
        do {
            let data = try await makeRequest("/youtube/key-exposure-check")
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            return (decoded.exposed, decoded.detail)
        } catch let err as AccountError {
            errorMessage = err.message
            return (false, "")
        } catch {
            errorMessage = error.localizedDescription
            return (false, "")
        }
    }

    /// Removes this account's personal YouTube Data API key.
    func deleteYoutubeApiKey() async -> Bool {
        guard isLoggedIn else { return false }
        do {
            _ = try await makeRequest("/user/youtube-api-key", method: "DELETE")
            return true
        } catch let err as AccountError {
            errorMessage = err.message
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - yt-dlp cookies (per-user, for authenticated/age-restricted downloads)

    /// Fetches whether this account has yt-dlp cookies configured (status
    /// only — contents are never returned).
    func fetchYtdlpCookiesStatus() async -> YtdlpCookiesStatus? {
        guard isLoggedIn else { return nil }
        do {
            let data = try await makeRequest("/user/ytdlp-cookies")
            return try JSONDecoder().decode(YtdlpCookiesStatus.self, from: data)
        } catch let err as AccountError {
            errorMessage = err.message
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Uploads (or replaces) this account's yt-dlp cookies.txt contents
    /// (Netscape format). Used to authenticate yt-dlp as this user's YouTube
    /// session for search/stream/resolve/download — required for
    /// age-restricted videos and to avoid YouTube's anonymous-request
    /// bot-detection blocks.
    func setYtdlpCookies(_ cookiesText: String) async -> Bool {
        guard isLoggedIn else { return false }
        struct Body: Encodable { let cookies_text: String }
        do {
            _ = try await makeRequest("/user/ytdlp-cookies", method: "PUT", body: Body(cookies_text: cookiesText))
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

    /// Removes this account's stored yt-dlp cookies.
    func deleteYtdlpCookies() async -> Bool {
        guard isLoggedIn else { return false }
        do {
            _ = try await makeRequest("/user/ytdlp-cookies", method: "DELETE")
            return true
        } catch let err as AccountError {
            errorMessage = err.message
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Runs the bridge's detailed cookie validator: structural checks (are
    /// the required sign-in cookies present and unexpired, is LOGIN_INFO
    /// present for age-restricted content) followed by a real yt-dlp call to
    /// confirm YouTube actually accepts them.
    func validateYtdlpCookies() async -> YtdlpCookiesValidation? {
        guard isLoggedIn else { return nil }
        do {
            let data = try await makeRequest("/user/ytdlp-cookies/validate", method: "POST")
            return try JSONDecoder().decode(YtdlpCookiesValidation.self, from: data)
        } catch let err as AccountError {
            errorMessage = err.message
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

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

    // MARK: - DOB

    /// Set date of birth (ISO YYYY-MM-DD). Server enforces immutability once set.
    func setDateOfBirth(_ dob: String) async {
        guard isLoggedIn else { return }
        appLog("setDateOfBirth: setting DOB", category: "account")
        errorMessage = nil
        struct Body: Encodable { let date_of_birth: String }
        do {
            _ = try await makeRequest("/auth/me", method: "PUT", body: Body(date_of_birth: dob))
            hasDateOfBirth = true
            appLog("setDateOfBirth: success", category: "account")
        } catch let err as AccountError {
            appError("setDateOfBirth failed [\(err.statusCode)]: \(err.message)", category: "account")
            errorMessage = err.message
        } catch {
            appError("setDateOfBirth error: \(error.localizedDescription)", category: "account")
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Avatar

    /// Upload a profile picture as JPEG (max 1 MB enforced server-side).
    func uploadAvatar(image: UIImage) async {
        guard isLoggedIn else { return }
        guard let jpeg = image.jpegData(compressionQuality: 0.8) else {
            appWarn("uploadAvatar: could not encode image as JPEG", category: "account")
            return
        }
        guard var req = makeBaseRequest("/user/avatar", method: "POST") else {
            appWarn("uploadAvatar: could not build request", category: "account")
            return
        }
        req.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        req.httpBody = jpeg
        appLog("uploadAvatar: uploading \(jpeg.count / 1024)KB", category: "account")
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if (200..<300).contains(status) {
                appLog("uploadAvatar: success", category: "account")
            } else {
                appWarn("uploadAvatar: HTTP \(status)", category: "account")
            }
        } catch {
            appError("uploadAvatar: \(error.localizedDescription)", category: "account")
        }
        avatarImage = image
        saveAvatarLocally(image)
    }

    /// Load avatar from local cache first, then from server. Updates `avatarImage`.
    func loadAvatar(forceRefresh: Bool = false) async {
        if !forceRefresh, let cached = loadAvatarLocally() {
            avatarImage = cached
            appLog("loadAvatar: loaded from local cache", category: "account")
            return
        }
        guard isLoggedIn, let userId = currentUser?.id else { return }
        guard let req = makeBaseRequest("/user/avatar/\(userId)", method: "GET") else { return }
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status), let img = UIImage(data: data) else {
                appWarn("loadAvatar: HTTP \(status) or invalid image data", category: "account")
                return
            }
            avatarImage = img
            saveAvatarLocally(img)
            appLog("loadAvatar: fetched from server (\(data.count / 1024)KB)", category: "account")
        } catch {
            appWarn("loadAvatar: \(error.localizedDescription)", category: "account")
        }
    }

    private func makeBaseRequest(_ path: String, method: String) -> URLRequest? {
        let base = bridgeURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + path) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = method
        if let t = token, !t.isEmpty {
            req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
        }
        return req
    }

    private func saveAvatarLocally(_ image: UIImage) {
        guard let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("user_avatar.jpg") else { return }
        image.jpegData(compressionQuality: 0.8).flatMap { try? $0.write(to: url) }
    }

    private func loadAvatarLocally() -> UIImage? {
        guard let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("user_avatar.jpg") else { return nil }
        return (try? Data(contentsOf: url)).flatMap { UIImage(data: $0) }
    }

    func logPlay(song: Song, listenSeconds: Int, bpm: Double? = nil) async {
        guard isLoggedIn else { return }
        struct Body: Encodable {
            let title: String
            let artist: String?
            let track_url: String?
            let local_song_id: String?
            let listen_seconds: Int
            let bpm: Double?
        }
        do {
            _ = try await makeRequest(
                "/user/history",
                method: "POST",
                body: Body(
                    title: song.title,
                    artist: song.artist.isEmpty ? nil : song.artist,
                    track_url: song.url?.absoluteString,
                    local_song_id: song.id,
                    listen_seconds: listenSeconds,
                    bpm: bpm
                )
            )
            appLog("logPlay: \"\(song.title)\" \(listenSeconds)s", category: "account")
        } catch {
            appWarn("logPlay: failed for \"\(song.title)\": \(error.localizedDescription)", category: "account")
        }
    }

    /// Pushes the current track/position to the bridge so other surfaces
    /// (e.g. the local Discord Rich Presence daemon) can mirror "now playing"
    /// for this account. Best-effort and silent on failure — this runs on
    /// every play/pause/track-change and periodically during playback, so it
    /// shouldn't spam logs or interrupt playback if the network is down.
    private var playbackStatePushTask: Task<Void, Never>?

    func pushPlaybackState(song: Song?, position: TimeInterval, duration: TimeInterval, isPlaying: Bool, bpm: Double? = nil) {
        guard isLoggedIn else { return }
        struct Body: Encodable {
            let song_id: String?
            let title: String?
            let artist: String?
            let track_url: String?
            let source: String?
            let position_seconds: Double
            let duration_seconds: Double
            let is_playing: Bool
            let bpm: Double?
        }
        let body = Body(
            song_id: song?.id,
            title: song?.title,
            artist: song?.artist.isEmpty == true ? nil : song?.artist,
            track_url: song?.url?.absoluteString,
            source: nil,
            position_seconds: position,
            duration_seconds: duration,
            is_playing: isPlaying,
            bpm: bpm
        )
        playbackStatePushTask?.cancel()
        playbackStatePushTask = Task { [weak self] in
            _ = try? await self?.makeRequest("/user/playback-state", method: "PUT", body: body)
        }
    }

    // MARK: - Private helpers

    private struct EmptyBody: Encodable {}

    private struct AuthResponse: Decodable {
        let user: AppUser
        let token: String
    }

    private func saveUserLocally(_ user: AppUser) {
        if let data = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(data, forKey: Self.userKey)
        }
    }

    private func handleUnauthorized() {
        appWarn("JWT expired or invalid — clearing session", category: "account")
        UserDefaults.standard.removeObject(forKey: Self.tokenKey)
        UserDefaults.standard.removeObject(forKey: Self.userKey)
        token = nil
        currentUser = nil
        isLoggedIn = false
        errorMessage = "Your session expired. Please sign in again."
    }

    private func clearSession() {
        token = nil
        currentUser = nil
        isLoggedIn = false
        hasDateOfBirth = false
        avatarImage = nil
        stopAutoPushTimer()
        UserDefaults.standard.removeObject(forKey: Self.userKey)
    }

    func makeRequest<T: Encodable>(_ path: String, method: String = "GET", body: T) async throws -> Data {
        try await _makeRequest(path, method: method, bodyData: try JSONEncoder().encode(body))
    }

    func makeRequest(_ path: String, method: String = "GET") async throws -> Data {
        try await _makeRequest(path, method: method, bodyData: nil)
    }

    private func _makeRequest(_ path: String, method: String, bodyData: Data?) async throws -> Data {
        let base = bridgeURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let normalizedPath = path.hasPrefix("/") ? path : "/\(path)"
        guard let url = URL(string: base + normalizedPath) else {
            throw AccountError(statusCode: 0, message: "Invalid bridge URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20

        if let tok = token {
            request.setValue("Bearer \(tok)", forHTTPHeaderField: "Authorization")
        }

        if let data = bodyData {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = data
        }

        // Only idempotent GETs are retried — a retried POST/PUT/DELETE could
        // double-apply a mutation if the original request actually reached the
        // server but the response was lost to a transient network blip.
        let attempts = method == "GET" ? 3 : 1

        return try await NetworkRetry.withRetry(maxAttempts: attempts) {
            let (data, response) = try await URLSession.shared.data(for: request)

            if let http = response as? HTTPURLResponse {
                if http.statusCode == 401 {
                    // Only auto-logout on 401 when the user was already logged in.
                    // A 401 on /auth/login means wrong password — not an expired token.
                    if self.isLoggedIn && path != "/auth/login" {
                        self.handleUnauthorized()
                    }
                    throw AccountError(statusCode: 401, message: "Session expired. Please sign in again.")
                }
                if !(200..<300).contains(http.statusCode) {
                    // Try to extract detail from FastAPI error body
                    if let detail = try? JSONDecoder().decode(APIErrorBody.self, from: data) {
                        throw AccountError(statusCode: http.statusCode, message: detail.detail)
                    }
                    throw AccountError(statusCode: http.statusCode, message: "Server error (HTTP \(http.statusCode))")
                }
            }

            return data
        }
    }
}

// MARK: - Error types

struct AccountError: LocalizedError {
    let statusCode: Int
    let message: String

    var errorDescription: String? { message }
}

private struct APIErrorBody: Decodable {
    let detail: String
}
