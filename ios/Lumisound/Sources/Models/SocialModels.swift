import Foundation

// MARK: - Social Ecosystem models
//
// Backs the new /api/social/* endpoints on the bridge (see the "SOCIAL
// ECOSYSTEM" section at the end of ios-bridge/main.py). Deliberately kept
// separate from AccountModels.swift's pre-existing `ActivityEntry` /
// `TrendingTrack` (the global, non-friend-scoped /social/activity+discover
// feed) — these types are all friend/profile/presence-scoped.

/// One pinned "favorite song" on a profile (up to 5, ordered).
struct PinnedTrack: Codable, Identifiable, Equatable {
    var id: String { sourceTrackID ?? trackURL ?? "\(title)-\(artist ?? "")" }
    var sourceTrackID: String?
    var trackURL: String?
    var title: String
    var artist: String?
    var album: String?

    enum CodingKeys: String, CodingKey {
        case sourceTrackID = "source_track_id"
        case trackURL      = "track_url"
        case title, artist, album
    }
}

/// The signed-in user's own profile — GET /api/social/profile/me.
struct MySocialProfile: Decodable {
    let userId: String
    let bio: String?
    let mainAccentHex: String?
    let subAccentHex: String?
    let shareNowPlaying: Bool
    let pronouns: String?
    let statusEmoji: String?
    let statusText: String?
    let avatarFrame: String
    let showTopGenres: Bool
    let showGuestbook: Bool
    /// Feature: profile-customization-3 — opt-out toggle for the visitor
    /// stats card (default true) and opt-in toggle for the listening
    /// streak card (default false), mirroring `showTopGenres`'s precedent.
    let showVisitorStats: Bool
    let showListeningStats: Bool
    let memberSince: String?
    let pinnedTracks: [PinnedTrack]
    /// Own taste snapshot, always populated regardless of `showTopGenres` —
    /// see the bridge's `get_my_social_profile` doc comment: it's your own
    /// data, so the editor can preview the showcase card before turning it on.
    let topGenres: [String]
    let topArtists: [String]
    /// Always populated for /me regardless of `showListeningStats` — same
    /// "preview before you publish" reasoning as `topGenres`/`topArtists`.
    let listeningStreak: ListeningStreak
    /// Milestone achievement chips — always populated, no privacy toggle.
    let badges: [ProfileBadge]
    /// Always populated for /me regardless of `showVisitorStats`.
    let visitorCount: Int
    let recentVisitors: [ProfileVisitor]
    let featuredPlaylist: FeaturedPlaylist?

    enum CodingKeys: String, CodingKey {
        case userId          = "user_id"
        case bio
        case mainAccentHex   = "main_accent_hex"
        case subAccentHex    = "sub_accent_hex"
        case shareNowPlaying = "share_now_playing"
        case pronouns
        case statusEmoji     = "status_emoji"
        case statusText      = "status_text"
        case avatarFrame     = "avatar_frame"
        case showTopGenres   = "show_top_genres"
        case showGuestbook   = "show_guestbook"
        case showVisitorStats   = "show_visitor_stats"
        case showListeningStats = "show_listening_stats"
        case memberSince     = "member_since"
        case pinnedTracks    = "pinned_tracks"
        case topGenres       = "top_genres"
        case topArtists      = "top_artists"
        case listeningStreak = "listening_streak"
        case badges
        case visitorCount    = "visitor_count"
        case recentVisitors  = "recent_visitors"
        case featuredPlaylist = "featured_playlist"
    }
}

/// Another user's public profile — GET /api/social/profile/{user_id}.
struct PublicSocialProfile: Decodable, Identifiable {
    let userId: String
    let username: String
    let displayName: String?
    let avatarURL: String?
    let bio: String?
    let mainAccentHex: String?
    let subAccentHex: String?
    let pronouns: String?
    let statusEmoji: String?
    let statusText: String?
    let avatarFrame: String
    let showGuestbook: Bool
    let isFriend: Bool
    let memberSince: String?
    let pinnedTracks: [PinnedTrack]
    /// Empty unless the profile owner opted in via `show_top_genres` — the
    /// bridge withholds these entirely rather than sending real data the
    /// client is just expected not to display.
    let topGenres: [String]
    let topArtists: [String]
    /// Milestone achievement chips — always populated, no privacy toggle.
    let badges: [ProfileBadge]
    /// `nil` unless the profile owner opted in via `show_listening_stats`.
    let listeningStreak: ListeningStreak?
    /// `nil` unless the profile owner opted in via `show_visitor_stats`
    /// (the bridge withholds it entirely, same convention as `topGenres`).
    let visitorCount: Int?
    /// Only non-empty when the caller is actually a friend of the profile
    /// owner — see the bridge's `_profile_visitor_stats` doc comment.
    let recentVisitors: [ProfileVisitor]
    let featuredPlaylist: FeaturedPlaylist?

    var id: String { userId }

    enum CodingKeys: String, CodingKey {
        case userId        = "user_id"
        case username
        case displayName   = "display_name"
        case avatarURL     = "avatar_url"
        case bio
        case mainAccentHex = "main_accent_hex"
        case subAccentHex  = "sub_accent_hex"
        case pronouns
        case statusEmoji   = "status_emoji"
        case statusText    = "status_text"
        case avatarFrame   = "avatar_frame"
        case showGuestbook = "show_guestbook"
        case isFriend      = "is_friend"
        case memberSince   = "member_since"
        case pinnedTracks  = "pinned_tracks"
        case topGenres     = "top_genres"
        case topArtists    = "top_artists"
        case badges
        case listeningStreak = "listening_streak"
        case visitorCount    = "visitor_count"
        case recentVisitors  = "recent_visitors"
        case featuredPlaylist = "featured_playlist"
    }
}

/// Shared "public user" shape reused across search/friends/requests/blocks/
/// suggestions responses.
struct SocialUserRef: Codable, Identifiable, Equatable, Hashable {
    let userId: String
    let username: String
    let displayName: String?
    let avatarURL: String?

    var id: String { userId }

    enum CodingKeys: String, CodingKey {
        case userId      = "user_id"
        case username
        case displayName = "display_name"
        case avatarURL   = "avatar_url"
    }
}

/// One entry from GET /api/social/friends.
struct SocialFriend: Decodable, Identifiable {
    let userId: String
    let username: String
    let displayName: String?
    let avatarURL: String?
    let friendsSince: String?

    var id: String { userId }

    enum CodingKeys: String, CodingKey {
        case userId       = "user_id"
        case username
        case displayName  = "display_name"
        case avatarURL    = "avatar_url"
        case friendsSince = "friends_since"
    }
}

/// One entry from GET /api/social/friends/requests (incoming or outgoing).
struct SocialFriendRequest: Decodable, Identifiable {
    let requestId: String
    let userId: String
    let username: String
    let displayName: String?
    let avatarURL: String?
    let createdAt: String?

    var id: String { requestId }

    enum CodingKeys: String, CodingKey {
        case requestId  = "request_id"
        case userId     = "user_id"
        case username
        case displayName = "display_name"
        case avatarURL  = "avatar_url"
        case createdAt  = "created_at"
    }
}

/// Response from GET /api/social/friends/requests.
struct SocialFriendRequestsResponse: Decodable {
    let incoming: [SocialFriendRequest]
    let outgoing: [SocialFriendRequest]
}

/// One entry from GET /api/social/friends/suggestions.
struct SocialFriendSuggestion: Decodable, Identifiable {
    let userId: String
    let username: String
    let displayName: String?
    let avatarURL: String?
    let mutualFriendCount: Int

    var id: String { userId }

    enum CodingKeys: String, CodingKey {
        case userId            = "user_id"
        case username
        case displayName       = "display_name"
        case avatarURL         = "avatar_url"
        case mutualFriendCount = "mutual_friend_count"
    }
}

/// Presence for one user — GET /api/social/presence/{user_id} or one entry
/// of the batched GET /api/social/presence/friends response.
struct SocialPresence: Decodable, Identifiable, Equatable {
    let userId: String
    let online: Bool
    let isPlaying: Bool
    let nowPlayingTitle: String?
    let nowPlayingArtist: String?
    let lastSeenAt: String?

    var id: String { userId }

    enum CodingKeys: String, CodingKey {
        case userId           = "user_id"
        case online
        case isPlaying        = "is_playing"
        case nowPlayingTitle  = "now_playing_title"
        case nowPlayingArtist = "now_playing_artist"
        case lastSeenAt       = "last_seen_at"
    }
}

/// Response from GET /api/social/presence/friends.
struct SocialFriendsPresenceResponse: Decodable {
    let presence: [SocialPresence]
}

/// One entry from GET /api/social/activity/friends — extra feature #1,
/// a friends-only feed of recent plays/favorites.
struct SocialActivityEntry: Decodable, Identifiable {
    let userId: String
    let username: String
    let displayName: String?
    let avatarURL: String?
    let kind: String   // "played" or "favorited"
    let title: String?
    let artist: String?
    let at: String?

    var id: String { "\(userId)-\(kind)-\(at ?? "")-\(title ?? "")" }

    var isPlayed: Bool { kind == "played" }

    var date: Date? {
        guard let at else { return nil }
        return parseServerDate(at)
    }

    enum CodingKeys: String, CodingKey {
        case userId      = "user_id"
        case username
        case displayName = "display_name"
        case avatarURL   = "avatar_url"
        case kind, title, artist, at
    }
}

/// One entry from GET /api/social/profile/{user_id}/comments — a short
/// guestbook-style message a friend left on a profile.
struct ProfileComment: Decodable, Identifiable, Equatable {
    let id: String
    let authorUserId: String
    let authorUsername: String
    let authorDisplayName: String?
    let authorAvatarURL: String?
    let body: String
    let createdAt: String?

    var date: Date? {
        guard let createdAt else { return nil }
        return parseServerDate(createdAt)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case authorUserId      = "author_user_id"
        case authorUsername    = "author_username"
        case authorDisplayName = "author_display_name"
        case authorAvatarURL   = "author_avatar_url"
        case body
        case createdAt         = "created_at"
    }
}

/// Response from GET /api/social/profile/{user_id}/comments.
struct ProfileCommentsResponse: Decodable {
    let comments: [ProfileComment]
}

/// Response from GET /api/social/compatibility/{user_id} — a "Music Match"
/// score between the caller and a friend, derived from shared top/favorited
/// artists and library genre overlap (see the bridge's
/// `_taste_display_map_and_keys`/`_jaccard`; artists weighted 70%, genres 30%).
struct MusicCompatibility: Decodable, Equatable {
    let score: Int
    let insufficientData: Bool
    let sharedArtists: [String]
    let sharedGenres: [String]

    enum CodingKeys: String, CodingKey {
        case score
        case insufficientData = "insufficient_data"
        case sharedArtists     = "shared_artists"
        case sharedGenres      = "shared_genres"
    }
}

// MARK: - Feature: profile-customization-3 (2026-07-21)
//
// Five more profile/social-profile features on top of everything above:
// profile visitor stats, a listening streak stat, milestone badges, a
// featured/spotlight playlist, and a friends-only "recently played
// together" overlap card. All wire into the existing MySocialProfile /
// PublicSocialProfile payloads above except the last two, which are their
// own small request/response types below.

/// Current/longest consecutive-day listening streaks — GET
/// /api/social/profile/me's `listening_streak` (always present) or
/// /api/social/profile/{user_id}'s (present only when the owner opted in
/// via `show_listening_stats`).
struct ListeningStreak: Decodable, Equatable {
    let currentStreakDays: Int
    let longestStreakDays: Int

    enum CodingKeys: String, CodingKey {
        case currentStreakDays = "current_streak_days"
        case longestStreakDays = "longest_streak_days"
    }
}

/// One milestone achievement chip (e.g. "1 Year+", "500 Plays") — always
/// present on both /me and public profiles, no privacy toggle; see the
/// bridge's `_compute_profile_badges`. `icon` is an SF Symbol name; `tier`
/// is one of "bronze"/"silver"/"gold".
struct ProfileBadge: Decodable, Identifiable, Equatable, Hashable {
    let id: String
    let label: String
    let icon: String
    let tier: String
}

/// One friend who's recently visited a profile — only ever populated when
/// the viewer is a friend of the profile owner (see `_profile_visitor_stats`).
struct ProfileVisitor: Decodable, Identifiable, Equatable {
    let userId: String
    let username: String
    let displayName: String?
    let avatarURL: String?
    let lastViewedAt: String?

    var id: String { userId }

    enum CodingKeys: String, CodingKey {
        case userId       = "user_id"
        case username
        case displayName  = "display_name"
        case avatarURL    = "avatar_url"
        case lastViewedAt = "last_viewed_at"
    }
}

/// One track preview line inside a `FeaturedPlaylist`.
struct FeaturedPlaylistTrackPreview: Decodable, Equatable {
    let title: String
    let artist: String?
}

/// An owner-chosen spotlight playlist shown on their profile — `nil` on
/// both MySocialProfile/PublicSocialProfile when nothing is featured (or,
/// for a public profile, when the featured playlist has since been
/// deleted — see the bridge's `_featured_playlist_payload`).
struct FeaturedPlaylist: Decodable, Equatable, Identifiable {
    let id: String
    let name: String
    let description: String?
    let trackCount: Int
    let previewTracks: [FeaturedPlaylistTrackPreview]

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case trackCount    = "track_count"
        case previewTracks = "preview_tracks"
    }
}

/// A minimal summary of one of the caller's own server-stored playlists —
/// GET /user/playlists returns full per-playlist track lists (needed
/// elsewhere for collaborative-playlist sync), but the Featured Playlist
/// picker only needs id/name/track count, so this intentionally never
/// decodes the "tracks" array's individual track fields, just its length.
struct RemotePlaylistSummary: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let trackCount: Int

    private enum CodingKeys: String, CodingKey { case id, name, tracks }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        trackCount = (try container.decodeIfPresent([_EmptyDecodableStub].self, forKey: .tracks) ?? []).count
    }
}

/// A `Decodable` with no stored properties — decoding an array of these
/// against an array of real track JSON objects still succeeds (extra keys
/// are simply ignored), so this is a zero-allocation-of-fields way to learn
/// just an array's *length* without paying to decode every track's fields.
private struct _EmptyDecodableStub: Decodable {}

/// One track from GET /api/social/profile/{user_id}/recently-played-together
/// — extra feature #5: tracks both the caller and a friend have played in
/// the last 30 days, newest shared listen first.
struct SharedRecentTrack: Decodable, Identifiable, Equatable {
    let title: String
    let artist: String?
    let yourLastPlayedAt: String?
    let theirLastPlayedAt: String?

    var id: String { "\(title)-\(artist ?? "")" }

    var mostRecentDate: Date? {
        let candidates = [yourLastPlayedAt, theirLastPlayedAt].compactMap { $0 }.compactMap(parseServerDate)
        return candidates.max()
    }

    enum CodingKeys: String, CodingKey {
        case title, artist
        case yourLastPlayedAt  = "your_last_played_at"
        case theirLastPlayedAt = "their_last_played_at"
    }
}

/// Response from GET /api/social/profile/{user_id}/recently-played-together.
struct SharedRecentTracksResponse: Decodable {
    let tracks: [SharedRecentTrack]
}
