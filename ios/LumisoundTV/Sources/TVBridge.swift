import Foundation

// MARK: - TVTrack (search result)

struct TVTrack: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let artist: String
    let durationSeconds: Int
    let thumbnailURL: String
    let source: String
    let youtubeURL: String

    enum CodingKeys: String, CodingKey {
        case id, title, artist, source
        case durationSeconds = "duration_seconds"
        case thumbnailURL    = "thumbnail_url"
        case youtubeURL      = "youtube_url"
    }
}

// MARK: - UserMusicTrack (per-user cloud library)

struct UserMusicTrack: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let artist: String
    let album: String
    let duration: Double
    let genre: String
    let trackNumber: String
    let hasArtwork: Bool
    let serverPath: String
    let filename: String
    let ext: String

    var durationText: String {
        let s = Int(duration)
        return "\(s / 60):\(String(format: "%02d", s % 60))"
    }

    enum CodingKeys: String, CodingKey {
        case id, title, artist, album, duration, genre, filename, ext
        case trackNumber = "track_number"
        case hasArtwork  = "has_artwork"
        case serverPath  = "server_path"
    }
}

// MARK: - TVFavorite (GET /user/favorites row)
//
// Favoriting on tvOS is scoped to Personal Cloud Library tracks only — a
// UserMusicTrack.id is a stable hash of its server path (see `_stable_id` in
// ios-bridge/main.py), so it round-trips as the same `song_id` iOS uses when
// favoriting the same cloud track. Search results and playlist entries don't
// have a similarly stable, source-independent id, so they aren't favoritable
// here (mirrors why they aren't included in `TVPlayable.favoriteSongID`).

struct TVFavorite: Codable, Hashable {
    let songID: String
    let title: String?
    let artist: String?
    let album: String?

    enum CodingKeys: String, CodingKey {
        case songID = "song_id"
        case title, artist, album
    }
}

// MARK: - TVPlaylist / TVPlaylistTrack (cross-device synced playlists)
//
// Mirrors GET /user/playlists (see AccountModels.swift's `SharedPlaylistTrack`
// / `SharedPlaylistDetail` on iOS for the reference shape). Playlists on the
// bridge are a generic list of tracks, each backed by either a `local_song_id`
// (an on-device library item — meaningless off the phone that added it, since
// tvOS has no local file/media library access at all) or a `track_url` (the
// URL the adding device played that track from — for a Personal Cloud Library
// song this is the bridge's own `/user/music/stream` URL, which *is* playable
// here). Only tracks with an http(s) `track_url` are playable on tvOS.

struct TVPlaylistTrack: Codable, Hashable, Identifiable {
    let id: String
    let trackURL: String?
    let localSongID: String?
    let title: String
    let artist: String?
    let album: String?
    let durationSeconds: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case trackURL       = "track_url"
        case localSongID    = "local_song_id"
        case title, artist, album
        case durationSeconds = "duration_seconds"
    }

    /// True when this entry has a remote stream URL rather than only a
    /// `file://` path from the device that added it.
    var isRemotelyPlayable: Bool {
        guard let trackURL else { return false }
        return trackURL.hasPrefix("http://") || trackURL.hasPrefix("https://")
    }
}

struct TVPlaylist: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let description: String?
    let folder: String?
    var tracks: [TVPlaylistTrack]
}

// MARK: - TVPlayable (unified playback item)
//
// Both search results and per-user library tracks reduce to this so the player
// handles them uniformly. `authToken`, when set, is sent as a Bearer header for
// the stream + artwork (per-user library requires auth; search streams don't).

struct TVPlayable: Identifiable, Hashable {
    let id: String
    let title: String
    let artist: String
    let streamURL: URL
    let artworkURL: URL?
    let authToken: String?
    /// Set only when this item came from the Personal Cloud Library, where
    /// `id` is already the stable favoritable song id — see `TVFavorite`.
    var favoriteSongID: String?
}

// MARK: - TVSyncTrackBody (POST /user/playlists/{id}/tracks request body —
// mirrors the bridge's `SyncTrack` Pydantic model)

struct TVSyncTrackBody: Encodable {
    let localSongID: String? = nil
    let trackURL: String?
    let title: String
    let artist: String?
    let album: String?
    let durationSeconds: Int?

    enum CodingKeys: String, CodingKey {
        case localSongID = "local_song_id"
        case trackURL = "track_url"
        case title, artist, album
        case durationSeconds = "duration_seconds"
    }
}

// MARK: - TVBridgeClient

@MainActor
final class TVBridgeClient: ObservableObject {
    static let shared = TVBridgeClient()

    /// The same public bridge the iOS app uses by default.
    let baseURL = "https://lumisound-bridge.xenusanimations.studio"

    // Search
    @Published var results: [TVTrack] = []
    @Published var isSearching = false
    @Published var searchError: String?

    // Per-user library
    @Published var library: [UserMusicTrack] = []
    @Published var isLoadingLibrary = false
    @Published var libraryError: String?
    @Published var libraryConfigured = true

    // Synced playlists
    @Published var playlists: [TVPlaylist] = []
    @Published var isLoadingPlaylists = false
    @Published var playlistsError: String?
    @Published var playlistMutationError: String?

    // Favorites (Personal Cloud Library tracks only — see `TVFavorite`)
    @Published var favoriteSongIDs: Set<String> = []
    @Published var isLoadingFavorites = false

    /// In-flight search query, so a stale/slower response can't overwrite a newer one.
    private var activeSearch = ""

    // MARK: Networking

    /// Performs a request, retrying once on a transient failure (timeout / 5xx
    /// such as a gateway 502). The first call to a slow endpoint (YouTube search,
    /// or the library's cold ffprobe pass) often times out at the gateway; the
    /// retry hits the server's warm cache and usually returns quickly.
    private func dataWithRetry(_ request: URLRequest, retries: Int = 1) async throws -> (Data, URLResponse) {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode >= 500, retries > 0 {
                return try await dataWithRetry(request, retries: retries - 1)
            }
            return (data, response)
        } catch {
            if retries > 0 { return try await dataWithRetry(request, retries: retries - 1) }
            throw error
        }
    }

    // MARK: Search

    func search(_ query: String) async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        activeSearch = q
        isSearching = true
        searchError = nil
        defer { if activeSearch == q { isSearching = false } }

        guard var comps = URLComponents(string: baseURL + "/api/search") else { return }
        comps.queryItems = [
            URLQueryItem(name: "q", value: q),
            URLQueryItem(name: "source", value: "youtube"),
            URLQueryItem(name: "limit", value: "25"),
        ]
        guard let url = comps.url else { return }
        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 60  // YouTube extraction routinely takes 20-35s
            // Lets the bridge search with this account's YouTube Data API key
            // (near-instant) instead of the slow yt-dlp scrape.
            if let accountToken = TVAccount.shared.token {
                req.setValue(accountToken, forHTTPHeaderField: "X-Account-Token")
            }
            let (data, response) = try await dataWithRetry(req)
            guard activeSearch == q else { return }  // a newer search superseded this one
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                searchError = "Search failed. Try again."
                results = []
                return
            }
            results = try JSONDecoder().decode([TVTrack].self, from: data)
            searchError = results.isEmpty ? "No results for \"\(q)\"." : nil
        } catch {
            guard activeSearch == q else { return }
            searchError = "Couldn’t reach the music service. Try again."
            results = []
        }
    }

    // MARK: Per-user library

    func fetchLibrary(token: String, search: String = "") async {
        isLoadingLibrary = true
        libraryError = nil
        defer { isLoadingLibrary = false }

        guard var comps = URLComponents(string: baseURL + "/user/music") else { return }
        comps.queryItems = [URLQueryItem(name: "limit", value: "100000")]
        let s = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.isEmpty { comps.queryItems?.append(URLQueryItem(name: "search", value: s)) }
        guard let url = comps.url else { return }

        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 120  // cold ffprobe pass on the server can be slow

        struct Response: Decodable {
            let tracks: [UserMusicTrack]
            let total: Int
            let configured: Bool
        }
        do {
            let (data, response) = try await dataWithRetry(req)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                libraryError = http.statusCode == 401
                    ? "Your session expired. Please log in again."
                    : "Library is taking a while to load. Tap Retry."
                return
            }
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            libraryConfigured = decoded.configured
            if !decoded.configured {
                libraryError = "User music storage is not configured on the server."
                library = []
                return
            }
            library = decoded.tracks
        } catch {
            libraryError = "Couldn’t load your library. Tap Retry."
            library = []
        }
    }

    // MARK: Playlists

    func fetchPlaylists(token: String) async {
        isLoadingPlaylists = true
        playlistsError = nil
        defer { isLoadingPlaylists = false }

        guard let url = URL(string: baseURL + "/user/playlists") else { return }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 30

        do {
            let (data, response) = try await dataWithRetry(req)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                playlistsError = http.statusCode == 401
                    ? "Your session expired. Please log in again."
                    : "Couldn’t load your playlists. Tap Retry."
                return
            }
            playlists = try JSONDecoder().decode([TVPlaylist].self, from: data)
        } catch {
            playlistsError = "Couldn’t load your playlists. Tap Retry."
            playlists = []
        }
    }

    /// Bare mutation request — used for create/rename/delete/add-track/
    /// remove-track. Deliberately doesn't use `dataWithRetry`: those retry a
    /// transient 5xx, which is safe for idempotent GETs but could double a
    /// non-idempotent create/add on a slow success that looked like a
    /// failure at the gateway.
    @discardableResult
    private func mutate(_ path: String, method: String, token: String, jsonBody: Data? = nil) async -> Bool {
        guard let url = URL(string: baseURL + path) else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 30
        if let jsonBody {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = jsonBody
        }
        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200..<300).contains(http.statusCode)
        } catch {
            return false
        }
    }

    // MARK: Playlist mutations

    func createPlaylist(name: String, token: String) async -> Bool {
        playlistMutationError = nil
        guard let body = try? JSONEncoder().encode(["name": name]) else { return false }
        let ok = await mutate("/user/playlists", method: "POST", token: token, jsonBody: body)
        if ok {
            await fetchPlaylists(token: token)
        } else {
            playlistMutationError = "Couldn’t create the playlist. Try again."
        }
        return ok
    }

    func renamePlaylist(id: String, name: String, token: String) async -> Bool {
        playlistMutationError = nil
        guard let body = try? JSONEncoder().encode(["name": name]) else { return false }
        let ok = await mutate("/user/playlists/\(id)", method: "PUT", token: token, jsonBody: body)
        if ok {
            await fetchPlaylists(token: token)
        } else {
            playlistMutationError = "Couldn’t rename the playlist. Try again."
        }
        return ok
    }

    func deletePlaylist(id: String, token: String) async -> Bool {
        playlistMutationError = nil
        let ok = await mutate("/user/playlists/\(id)", method: "DELETE", token: token)
        if ok {
            playlists.removeAll { $0.id == id }
        } else {
            playlistMutationError = "Couldn’t delete the playlist. Try again."
        }
        return ok
    }

    /// Adds a track to a playlist, then refreshes so the detail view reflects
    /// the server-assigned position/id immediately.
    func addTrack(_ body: TVSyncTrackBody, toPlaylist playlistID: String, token: String) async -> Bool {
        playlistMutationError = nil
        guard let json = try? JSONEncoder().encode(body) else { return false }
        let ok = await mutate("/user/playlists/\(playlistID)/tracks", method: "POST", token: token, jsonBody: json)
        if ok {
            await fetchPlaylists(token: token)
        } else {
            playlistMutationError = "Couldn’t add that track. Try again."
        }
        return ok
    }

    func removeTrack(_ trackID: String, fromPlaylist playlistID: String, token: String) async -> Bool {
        playlistMutationError = nil
        let ok = await mutate("/user/playlists/\(playlistID)/tracks/\(trackID)", method: "DELETE", token: token)
        if ok {
            if let idx = playlists.firstIndex(where: { $0.id == playlistID }) {
                playlists[idx].tracks.removeAll { $0.id == trackID }
            }
        } else {
            playlistMutationError = "Couldn’t remove that track. Try again."
        }
        return ok
    }

    // MARK: Favorites

    func fetchFavorites(token: String) async {
        isLoadingFavorites = true
        defer { isLoadingFavorites = false }
        guard let url = URL(string: baseURL + "/user/favorites") else { return }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 30
        guard let (data, response) = try? await dataWithRetry(req),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let favorites = try? JSONDecoder().decode([TVFavorite].self, from: data)
        else { return }
        favoriteSongIDs = Set(favorites.map { $0.songID })
    }

    func isFavorite(_ songID: String) -> Bool { favoriteSongIDs.contains(songID) }

    /// Optimistically flips local state, then reconciles with the server —
    /// keeps the star responsive to remote-click without waiting on a
    /// round-trip, but self-heals if the request actually failed.
    func toggleFavorite(track: UserMusicTrack, token: String) async {
        let songID = track.id
        let wasFavorite = favoriteSongIDs.contains(songID)
        if wasFavorite {
            favoriteSongIDs.remove(songID)
        } else {
            favoriteSongIDs.insert(songID)
        }

        let ok: Bool
        if wasFavorite {
            ok = await mutate("/user/favorites/\(songID)", method: "DELETE", token: token)
        } else {
            let payload: [String: String] = [
                "song_id": songID, "title": track.title, "artist": track.artist, "album": track.album,
            ]
            guard let body = try? JSONEncoder().encode(payload) else { return }
            ok = await mutate("/user/favorites", method: "POST", token: token, jsonBody: body)
        }
        if !ok {
            // Revert the optimistic flip.
            if wasFavorite { favoriteSongIDs.insert(songID) } else { favoriteSongIDs.remove(songID) }
        }
    }

    // MARK: URL builders

    /// Bridge proxy stream URL for a search result — AVPlayer streams this directly.
    func streamURL(for track: TVTrack) -> URL? {
        guard var comps = URLComponents(string: baseURL + "/api/stream/proxy") else { return nil }
        comps.queryItems = [
            URLQueryItem(name: "id", value: track.id),
            URLQueryItem(name: "source", value: track.source),
            URLQueryItem(name: "format", value: "m4a"),
        ]
        if track.source == "soundcloud" {
            comps.queryItems?.append(URLQueryItem(name: "url", value: track.youtubeURL))
        }
        return comps.url
    }

    private func encodedPath(_ path: String) -> String? {
        path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
    }

    func userMusicStreamURL(for track: UserMusicTrack) -> URL? {
        guard let p = encodedPath(track.serverPath) else { return nil }
        return URL(string: "\(baseURL)/user/music/stream?path=\(p)")
    }

    func userMusicArtworkURL(for track: UserMusicTrack) -> URL? {
        guard track.hasArtwork, let p = encodedPath(track.serverPath) else { return nil }
        return URL(string: "\(baseURL)/user/music/artwork?path=\(p)")
    }

    // MARK: Playable mappers

    func playable(from track: TVTrack) -> TVPlayable? {
        guard let url = streamURL(for: track) else { return nil }
        return TVPlayable(
            id: track.id, title: track.title, artist: track.artist,
            streamURL: url,
            artworkURL: URL(string: track.thumbnailURL),
            authToken: nil
        )
    }

    func playable(from track: UserMusicTrack, token: String) -> TVPlayable? {
        guard let url = userMusicStreamURL(for: track) else { return nil }
        return TVPlayable(
            id: track.id,
            title: track.title.isEmpty ? track.filename : track.title,
            artist: track.artist,
            streamURL: url,
            artworkURL: userMusicArtworkURL(for: track),
            authToken: token,
            favoriteSongID: track.id
        )
    }

    /// Only produces a playable for tracks with a remote stream URL — see
    /// `TVPlaylistTrack.isRemotelyPlayable`. Playlist tracks backed only by a
    /// `local_song_id` (an on-device library item on whichever iPhone/iPad
    /// added them) have no artwork endpoint tvOS can key against, so no
    /// artwork is attached; the player falls back to its placeholder art.
    func playable(from track: TVPlaylistTrack, token: String) -> TVPlayable? {
        guard track.isRemotelyPlayable, let urlString = track.trackURL, let url = URL(string: urlString) else {
            return nil
        }
        return TVPlayable(
            id: track.id,
            title: track.title,
            artist: track.artist ?? "",
            streamURL: url,
            artworkURL: nil,
            authToken: token
        )
    }

    // MARK: Add-to-playlist payload mappers
    //
    // A playlist track is stored server-side as a denormalized snapshot
    // (title/artist/album/url), not a reference back to the library — so
    // these just carry the streamable URL forward as `track_url`, the same
    // shape a playlist entry created on iOS would have for a cloud-library
    // or streamed track.

    func syncTrackBody(from track: UserMusicTrack) -> TVSyncTrackBody? {
        guard let url = userMusicStreamURL(for: track) else { return nil }
        return TVSyncTrackBody(
            trackURL: url.absoluteString,
            title: track.title.isEmpty ? track.filename : track.title,
            artist: track.artist.isEmpty ? nil : track.artist,
            album: track.album.isEmpty ? nil : track.album,
            durationSeconds: Int(track.duration)
        )
    }

    func syncTrackBody(from track: TVTrack) -> TVSyncTrackBody? {
        guard let url = streamURL(for: track) else { return nil }
        return TVSyncTrackBody(
            trackURL: url.absoluteString,
            title: track.title,
            artist: track.artist.isEmpty ? nil : track.artist,
            album: nil,
            durationSeconds: track.durationSeconds
        )
    }
}
