import Foundation

/// Shared ISO8601 parser. Creating an `ISO8601DateFormatter` is expensive, and
/// the model `date` computed properties below are read once per row on every
/// SwiftUI redraw — a fresh formatter each time caused visible lag on lists with
/// many items (e.g. Backup History). One shared instance removes that cost.
let sharedISO8601Formatter = ISO8601DateFormatter()

// MARK: - Models

struct AppUser: Codable, Equatable {
    let id: String
    let username: String
    let displayName: String?
    let email: String?
    let avatarURL: String?
    let dateOfBirth: String?   // ISO YYYY-MM-DD, nil if not set
    var shareListeningActivity: Bool = false
    /// Opt-in for AI-assisted suggestions (metadata/EQ/duplicate/mix). Off by
    /// default — when enabled, track titles/artists/genres may be sent to
    /// Anthropic's API. See PUT /user/privacy and AccountService+Intelligence.
    var aiAssistedSuggestions: Bool = false

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case displayName  = "display_name"
        case email
        case avatarURL    = "avatar_url"
        case dateOfBirth  = "date_of_birth"
        case shareListeningActivity = "share_listening_activity"
        case aiAssistedSuggestions  = "ai_assisted_suggestions"
    }

    // Hand-written so a boolean flag added in a later app version (like
    // aiAssistedSuggestions) never breaks decoding of an AppUser cached in
    // UserDefaults by an OLDER app version that predates the field — the
    // synthesized Decodable init does NOT fall back to a property's default
    // value when a key is missing, it throws. That bug shipped in 1.4.62/63
    // and logged everyone out on update (old cached user JSON had no
    // "ai_assisted_suggestions" key -> decode failed -> currentUser reset to
    // nil). decodeIfPresent + ?? false makes every Bool flag here tolerant
    // of being absent, from either a stale local cache or an older/newer
    // server response, going forward.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        username = try container.decode(String.self, forKey: .username)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        avatarURL = try container.decodeIfPresent(String.self, forKey: .avatarURL)
        dateOfBirth = try container.decodeIfPresent(String.self, forKey: .dateOfBirth)
        shareListeningActivity = try container.decodeIfPresent(Bool.self, forKey: .shareListeningActivity) ?? false
        aiAssistedSuggestions = try container.decodeIfPresent(Bool.self, forKey: .aiAssistedSuggestions) ?? false
    }

    init(
        id: String, username: String, displayName: String?, email: String?,
        avatarURL: String?, dateOfBirth: String?,
        shareListeningActivity: Bool = false, aiAssistedSuggestions: Bool = false
    ) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.email = email
        self.avatarURL = avatarURL
        self.dateOfBirth = dateOfBirth
        self.shareListeningActivity = shareListeningActivity
        self.aiAssistedSuggestions = aiAssistedSuggestions
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
        sharedISO8601Formatter.date(from: createdAt)
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
        return sharedISO8601Formatter.date(from: playedAt)
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
        sharedISO8601Formatter.date(from: createdAt)
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

/// Response shape for GET /user/acoustid-api-key — the user's personal
/// AcoustID API key (free registration at acoustid.org), used by
/// AcoustIDService to identify tracks with wrong/missing tags via audio
/// fingerprint. `apiKey` is masked, same convention as `YoutubeApiKeyConfig`.
struct AcoustIDApiKeyConfig: Decodable {
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

/// One candidate metadata result (from iTunes/MusicBrainz/Deezer) sent to
/// POST /user/intelligence/metadata-resolve for AI-assisted disambiguation.
/// Mirrors the backend's `MetadataCandidate` Pydantic model field-for-field.
struct MetadataCandidate: Codable {
    let title: String
    let artist: String
    let album: String?
    let year: String?
    let source: String
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

