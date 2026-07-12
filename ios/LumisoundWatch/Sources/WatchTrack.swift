import Foundation

// MARK: - WatchTrack
//
// Mirrors the bridge's `/user/music` per-track JSON shape (see
// ios-bridge/main.py's `get_user_music`). This target does not compile
// `Lumisound/Sources/Services/StreamingModels.swift` (LumisoundWatch's
// `sources:` in project.yml is `LumisoundWatch/Sources` only), so this is an
// intentional, minimal, hand-kept-in-sync duplicate of the fields the watch
// actually needs — not the full `UserMusicTrack`/`UserMusicMetadataTrack` set.

struct WatchTrack: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let artist: String
    let album: String
    let duration: Double
    /// File extension (e.g. "mp3", "m4a") — used to name the on-disk cache file.
    let ext: String
    /// Relative path within the user's bridge music dir. Pass as the `path`
    /// query param to `/user/music/stream` to fetch this track's audio.
    let serverPath: String
    let hasArtwork: Bool

    enum CodingKeys: String, CodingKey {
        case id, title, artist, album, duration, ext
        case serverPath = "server_path"
        case hasArtwork = "has_artwork"
    }
}

/// Matches `GET /user/music`'s top-level response shape:
/// `{"tracks": [...], "total": int, "configured": bool}`.
struct WatchTrackListResponse: Codable {
    let tracks: [WatchTrack]
    let total: Int
    let configured: Bool
}
