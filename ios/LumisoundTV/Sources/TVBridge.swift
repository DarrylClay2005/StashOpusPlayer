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
    let hasArtwork: Bool
    let serverPath: String
    let filename: String
    let ext: String

    enum CodingKeys: String, CodingKey {
        case id, title, artist, album, duration, filename, ext
        case hasArtwork = "has_artwork"
        case serverPath = "server_path"
    }
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
            authToken: token
        )
    }
}
