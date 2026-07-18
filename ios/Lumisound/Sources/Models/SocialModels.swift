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
    let pinnedTracks: [PinnedTrack]

    enum CodingKeys: String, CodingKey {
        case userId          = "user_id"
        case bio
        case mainAccentHex   = "main_accent_hex"
        case subAccentHex    = "sub_accent_hex"
        case shareNowPlaying = "share_now_playing"
        case pinnedTracks    = "pinned_tracks"
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
    let isFriend: Bool
    let pinnedTracks: [PinnedTrack]

    var id: String { userId }

    enum CodingKeys: String, CodingKey {
        case userId        = "user_id"
        case username
        case displayName   = "display_name"
        case avatarURL     = "avatar_url"
        case bio
        case mainAccentHex = "main_accent_hex"
        case subAccentHex  = "sub_accent_hex"
        case isFriend      = "is_friend"
        case pinnedTracks  = "pinned_tracks"
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
        return sharedISO8601Formatter.date(from: at)
    }

    enum CodingKeys: String, CodingKey {
        case userId      = "user_id"
        case username
        case displayName = "display_name"
        case avatarURL   = "avatar_url"
        case kind, title, artist, at
    }
}
