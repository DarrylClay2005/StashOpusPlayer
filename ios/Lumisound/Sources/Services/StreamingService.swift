import Foundation
import UIKit

// MARK: - StreamTrack

struct StreamTrack: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let artist: String
    let durationSeconds: Int
    let thumbnailURL: String
    let source: String       // "youtube" or "soundcloud"
    let youtubeURL: String   // canonical URL for sharing

    var duration: TimeInterval { TimeInterval(durationSeconds) }

    /// The `LUMISOUND_ID`-style identifier embedded in downloaded files'
    /// metadata (see `_estimate_bpm`/download tagging in the bridge), used to
    /// match this search result against an already-downloaded `Song` by
    /// `Song.sourceTrackID` regardless of filename/title differences.
    var sourceTrackID: String { "\(source):\(id)" }

    var durationText: String {
        let m = durationSeconds / 60
        let s = durationSeconds % 60
        return "\(m):\(String(format: "%02d", s))"
    }

    // MARK: Codable keys (bridge returns snake_case)

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case artist
        case durationSeconds = "duration_seconds"
        case thumbnailURL    = "thumbnail_url"
        case source
        case youtubeURL      = "youtube_url"
    }
}

// MARK: - UserMusicTrack  (personal server library, per-user)

struct UserMusicTrack: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let artist: String
    let album: String
    let duration: Double
    let genre: String
    let trackNumber: String
    let hasArtwork: Bool
    let serverPath: String   // relative to the user's personal music dir
    let filename: String
    let ext: String

    var durationText: String {
        let s = Int(duration)
        return "\(s / 60):\(String(format: "%02d", s % 60))"
    }

    enum CodingKeys: String, CodingKey {
        case id, title, artist, album, duration, genre
        case trackNumber = "track_number"
        case hasArtwork  = "has_artwork"
        case serverPath  = "server_path"
        case filename, ext
    }
}

// MARK: - DownloadHistoryTrack  (server-side record of past /api/download calls)

/// A track this account has downloaded before, as recorded server-side by
/// `/api/download` and returned by `/user/download-history`. Used to surface
/// "My Library" search results for tracks the user has ever downloaded (even
/// if no longer present on this device) and to power a "previously
/// downloaded" restore list.
struct DownloadHistoryTrack: Identifiable, Codable, Hashable {
    let source: String
    let id: String
    let title: String
    let artist: String
    let thumbnailURL: String
    let durationSeconds: Int
    let format: String
    let downloadCount: Int
    let lastDownloadedAt: String?

    var sourceTrackID: String { "\(source):\(id)" }

    /// Converts to a `StreamTrack` so it can be downloaded/played via the
    /// same pipeline as search results.
    var asStreamTrack: StreamTrack {
        let youtubeURL = source == "youtube" ? "https://youtube.com/watch?v=\(id)" : ""
        return StreamTrack(
            id: id,
            title: title,
            artist: artist,
            durationSeconds: durationSeconds,
            thumbnailURL: thumbnailURL,
            source: source,
            youtubeURL: youtubeURL
        )
    }

    enum CodingKeys: String, CodingKey {
        case source, id, title, artist
        case thumbnailURL = "thumbnail_url"
        case durationSeconds = "duration_seconds"
        case format
        case downloadCount = "download_count"
        case lastDownloadedAt = "last_downloaded_at"
    }
}

// MARK: - TrackMetadata  (client-provided metadata for upload)

struct TrackMetadata {
    var title: String?
    var artist: String?
    var album: String?
    var genre: String?
    var year: String?
    var durationSeconds: Double?
    var bitrate: Int?
    var sampleRate: Int?
}

// MARK: - UserMusicMetadataTrack  (rich metadata from /user/music/metadata)

struct UserMusicMetadataTrack: Identifiable, Codable, Hashable {
    let id: String                     // SHA-256 of file content
    let filename: String
    let originalFilename: String?
    let title: String?
    let artist: String?
    let album: String?
    let genre: String?
    let year: String?
    let durationSeconds: Double?
    let fileSizeBytes: Int?
    let bitrate: Int?
    let sampleRate: Int?
    let mimeType: String?
    let hasArtwork: Bool
    let uploadedAt: String?
    let artworkURL: String?

    enum CodingKeys: String, CodingKey {
        case id, filename, title, artist, album, genre, year
        case originalFilename = "original_filename"
        case durationSeconds  = "duration_seconds"
        case fileSizeBytes    = "file_size_bytes"
        case bitrate
        case sampleRate       = "sample_rate"
        case mimeType         = "mime_type"
        case hasArtwork       = "has_artwork"
        case uploadedAt       = "uploaded_at"
        case artworkURL       = "artwork_url"
    }

    var durationText: String {
        guard let d = durationSeconds else { return "--:--" }
        let s = Int(d)
        return "\(s / 60):\(String(format: "%02d", s % 60))"
    }

    var fileSizeText: String {
        guard let bytes = fileSizeBytes else { return "" }
        let mb = Double(bytes) / 1_048_576
        return String(format: "%.1f MB", mb)
    }
}

// MARK: - GalleryImageInfo  (cloud-synced gallery image)

struct GalleryImageInfo: Identifiable, Codable, Hashable {
    let id: String
    let filename: String
    let displayOrder: Int
    let uploadedAt: String?
    let url: String         // relative path on bridge, e.g. /user/gallery/images/{id}

    enum CodingKeys: String, CodingKey {
        case id, filename, url
        case displayOrder = "display_order"
        case uploadedAt   = "uploaded_at"
    }
}

// MARK: - ServerTrack

struct ServerTrack: Identifiable, Codable, Hashable {
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
        case id, title, artist, album, duration, genre
        case trackNumber = "track_number"
        case hasArtwork  = "has_artwork"
        case serverPath  = "server_path"
        case filename, ext
    }
}

// MARK: - StreamResponse helpers

/// One entry from GET /api/search/suggestions or /api/search/trending.
struct SearchQueryCount: Identifiable, Codable, Hashable {
    let query: String
    let count: Int
    var id: String { query }
}

private struct StreamResponse: Decodable {
    let url: String
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case url
        case expiresIn = "expires_in"
    }
}

// MARK: - StreamingService

@MainActor
final class StreamingService: ObservableObject {

    // MARK: UserDefaults keys

    static let bridgeURLKey      = "ios_bridge_url"
    static let apiKeyKey         = "ios_bridge_api_key"
    static let preferredFormatKey = "streaming_preferred_format"
    static let downloadPathKey    = "download_path_key"

    /// Public URL baked into the app — routed via a Cloudflare Tunnel so
    /// it works anywhere without home WiFi. Users can override in Settings.
    static let defaultBridgeURL = "https://lumisound-bridge.xenusanimations.studio"

    // MARK: Available formats

    static let availableFormats: [(label: String, value: String)] = [
        ("M4A (Default)", "m4a"),
        ("MP3",           "mp3"),
        ("FLAC",          "flac"),
        ("Opus",          "opus"),
        ("Best Quality",  "best"),
    ]

    // MARK: Private — Stream URL Cache

    private var streamURLCache: [String: (url: URL, expiry: Date)] = [:]
    private static let streamURLCacheTTL: TimeInterval = 5 * 60 * 60  // 5 hours

    // MARK: Published state

    @Published var searchResults: [StreamTrack] = []
    @Published var isSearching       = false
    @Published var isLoadingStream   = false
    @Published var isResolvingPlaylist = false
    @Published var isPlaylistResult  = false
    @Published var errorMessage: String?

    // MARK: Server Library state

    @Published var serverTracks: [ServerTrack] = []
    @Published var isSearchingServer = false
    /// nil until the first server-library load; then true/false per the bridge's
    /// `configured` flag (whether SERVER_MUSIC_DIR is set). Lets the UI show a
    /// clear "not set up" message instead of an indefinitely-empty list.
    @Published var serverLibraryConfigured: Bool? = nil

    // MARK: User Music Library state (personal per-user storage)

    @Published var userMusicTracks: [UserMusicTrack] = []
    @Published var isLoadingUserMusic = false
    @Published var downloadHistory: [DownloadHistoryTrack] = []
    @Published var isLoadingDownloadHistory = false
    @Published var isUploadingUserMusic = false
    @Published var uploadProgress: Double = 0

    // MARK: User Music Metadata state (rich metadata from /user/music/metadata)

    @Published var userMusicMetadata: [UserMusicMetadataTrack] = []
    @Published var isLoadingUserMusicMetadata = false
    @Published private(set) var isSyncingLibraryBackup = false

    // MARK: Gallery state

    @Published var galleryImages: [GalleryImageInfo] = []
    @Published var isLoadingGallery = false
    @Published var isUploadingGalleryImage = false

    // MARK: Ambient shared reference
    //
    // Mirrors `AccountService.shared` — gives `BackgroundService` (which has no
    // direct SwiftUI environment access to this type at the point gallery images
    // are mutated) a way to trigger cloud gallery upload/restore automatically,
    // for all logged-in users, with no opt-in UI.
    static weak var shared: StreamingService?

    init() {
        Self.shared = self
    }

    // MARK: Persisted settings

    var bridgeURL: String {
        get { UserDefaults.standard.string(forKey: Self.bridgeURLKey) ?? Self.defaultBridgeURL }
        set { UserDefaults.standard.set(newValue, forKey: Self.bridgeURLKey) }
    }

    var apiKey: String {
        get { UserDefaults.standard.string(forKey: Self.apiKeyKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Self.apiKeyKey) }
    }

    var preferredFormat: String {
        get { UserDefaults.standard.string(forKey: Self.preferredFormatKey) ?? "m4a" }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.preferredFormatKey)
            objectWillChange.send()
        }
    }

    var downloadDirectory: URL {
        get {
            if let savedPath = UserDefaults.standard.string(forKey: Self.downloadPathKey),
               let url = URL(string: savedPath) {
                return url
            }
            guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                fatalError("Document directory unavailable")
            }
            return docs.appendingPathComponent("Imported Music")
        }
        set {
            UserDefaults.standard.set(newValue.absoluteString, forKey: Self.downloadPathKey)
        }
    }

    var isConfigured: Bool { true } // always configured via default URL

    // MARK: - Playlist URL detection

    static func isPlaylistURL(_ text: String) -> Bool {
        let t = text.lowercased()
        guard t.hasPrefix("http") else { return false }
        let isYouTube = t.contains("youtube.com") || t.contains("youtu.be")
        return isYouTube && (t.contains("list=") || t.contains("/playlist"))
    }

    // MARK: - Search

    func search(query: String, source: String = "youtube") async {
        guard isConfigured else {
            errorMessage = "Streaming service is unavailable right now."
            return
        }
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchResults = []
            return
        }
        appLog("Search: \"\(query)\" [source: \(source)]", category: "network")
        isSearching = true
        isPlaylistResult = false
        errorMessage = nil
        defer { isSearching = false }

        var components = URLComponents()
        components.path = "/api/search"
        components.queryItems = [
            URLQueryItem(name: "q",      value: query),
            URLQueryItem(name: "limit",  value: "20"),
            URLQueryItem(name: "source", value: source),
        ]

        guard var request = makeRequest(components.string ?? "/api/search") else {
            errorMessage = "Invalid bridge URL."
            return
        }
        request.timeoutInterval = 20
        // Lets the bridge use this account's personally-uploaded yt-dlp
        // cookies (Settings -> YouTube Cookies) so search results include
        // age-restricted videos and aren't blocked by YouTube's
        // anonymous-request bot detection.
        if let accountToken = AccountService.shared?.token {
            request.setValue(accountToken, forHTTPHeaderField: "X-Account-Token")
        }

        do {
            let tracks = try await NetworkRetry.withRetry {
                let (data, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse,
                   !(200..<300).contains(httpResponse.statusCode) {
                    throw StreamingError.httpError(httpResponse.statusCode)
                }
                return try JSONDecoder().decode([StreamTrack].self, from: data)
            }
            searchResults = tracks
            appLog("Search returned \(tracks.count) result(s) for \"\(query)\"", category: "network")
        } catch {
            appError("Search failed: \(error.localizedDescription)", category: "network")
            errorMessage = "Streaming service is unavailable right now. Please try again later."
            searchResults = []
        }
    }

    /// Autocomplete suggestions for `q` — past queries from any user, starting
    /// with `q`, most popular first. Returns `[]` on no match or any failure.
    func searchSuggestions(query: String, limit: Int = 8) async -> [SearchQueryCount] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }

        var components = URLComponents()
        components.path = "/api/search/suggestions"
        components.queryItems = [
            URLQueryItem(name: "q",     value: trimmed),
            URLQueryItem(name: "limit", value: "\(limit)"),
        ]
        guard var request = makeRequest(components.string ?? "/api/search/suggestions") else { return [] }
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               !(200..<300).contains(httpResponse.statusCode) {
                return []
            }
            return try JSONDecoder().decode([SearchQueryCount].self, from: data)
        } catch {
            return []
        }
    }

    /// Most popular search queries across all users in the last `days` days.
    /// Returns `[]` on no match or any failure.
    func searchTrending(limit: Int = 10, days: Int = 7) async -> [SearchQueryCount] {
        var components = URLComponents()
        components.path = "/api/search/trending"
        components.queryItems = [
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "days",  value: "\(days)"),
        ]
        guard var request = makeRequest(components.string ?? "/api/search/trending") else { return [] }
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               !(200..<300).contains(httpResponse.statusCode) {
                return []
            }
            return try JSONDecoder().decode([SearchQueryCount].self, from: data)
        } catch {
            return []
        }
    }

    /// One-off lookup that finds the best streamable match for a title/artist pair
    /// without touching the published `searchResults`/`isSearching` state (which the
    /// Search tab UI is bound to). Used to resolve playable sources for tracks that
    /// arrived as metadata-only snapshots — e.g. shared/collaborative playlist tracks,
    /// which carry no stream URL by design. Returns `nil` on no match or any failure;
    /// callers should treat that as "skip this track" rather than a fatal error.
    func bestMatch(forTitle title: String, artist: String, source: String = "youtube") async -> StreamTrack? {
        guard isConfigured else { return nil }
        let query = "\(title) \(artist)".trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return nil }

        var components = URLComponents()
        components.path = "/api/search"
        components.queryItems = [
            URLQueryItem(name: "q",      value: query),
            URLQueryItem(name: "limit",  value: "1"),
            URLQueryItem(name: "source", value: source),
        ]
        guard var request = makeRequest(components.string ?? "/api/search") else { return nil }
        request.timeoutInterval = 20

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               !(200..<300).contains(httpResponse.statusCode) {
                return nil
            }
            let tracks = try JSONDecoder().decode([StreamTrack].self, from: data)
            return tracks.first
        } catch {
            return nil
        }
    }

    /// Fetches up to `limit` tracks for a raw query without touching the published
    /// `searchResults`/`isSearching`/`errorMessage` state — see `bestMatch` above for
    /// why that matters. Used by Auto-Radio to seed several related tracks from one
    /// query without clobbering whatever the user has up in the Search tab. Returns
    /// `[]` on no results or any failure.
    func relatedTracks(query: String, source: String = "youtube", limit: Int = 5) async -> [StreamTrack] {
        guard isConfigured else { return [] }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }

        var components = URLComponents()
        components.path = "/api/search"
        components.queryItems = [
            URLQueryItem(name: "q",      value: trimmed),
            URLQueryItem(name: "limit",  value: String(limit)),
            URLQueryItem(name: "source", value: source),
        ]
        guard var request = makeRequest(components.string ?? "/api/search") else { return [] }
        request.timeoutInterval = 20

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               !(200..<300).contains(httpResponse.statusCode) {
                return []
            }
            return try JSONDecoder().decode([StreamTrack].self, from: data)
        } catch {
            return []
        }
    }

    // MARK: - Playlist resolution

    /// Builds the comma-separated "source:id" manifest of tracks the user
    /// already has, from `songs` (typically `LibraryManager.allSongs`). Sent
    /// to `/api/resolve` and `/api/download` so the bridge can skip
    /// re-downloading/re-listing tracks the client already has. Only songs
    /// with a non-empty `sourceTrackID` (the `LUMISOUND_ID`-tagged downloads)
    /// can be matched this way — local-only imports have no such ID and are
    /// simply omitted from the manifest.
    func existingTrackManifest(songs: [Song]) -> String {
        var ids = Set(songs.compactMap { song -> String? in
            guard let id = song.sourceTrackID, !id.isEmpty else { return nil }
            return id
        })
        // Also include ids from the download ledger whose files are still present.
        // This covers tracks whose embedded LUMISOUND_ID didn't round-trip (e.g.
        // older m4a downloads), so the server's playlist-resolve dedup filter
        // doesn't hand them back as "missing" and trigger duplicate downloads.
        let presentFilenames = Set(songs.compactMap { $0.url?.lastPathComponent })
        for id in DownloadLedgerStore.shared.presentSourceIDs(presentFilenames: presentFilenames) {
            ids.insert(id)
        }
        return ids.joined(separator: ",")
    }

    /// Resolves a YouTube (or SoundCloud) playlist URL to a list of tracks via
    /// the bridge's `/api/resolve` endpoint. Results are published on `searchResults`
    /// and `isPlaylistResult` is set to `true` so the UI can show the playlist banner.
    /// `existingSongs` (typically `LibraryManager.allSongs`) is sent as a dedupe
    /// manifest so tracks the user already has are excluded from the result —
    /// pass `[]` to disable this (e.g. callers without library access).
    func resolvePlaylist(url: String, existingSongs: [Song] = []) async {
        guard isConfigured else {
            errorMessage = "Streaming service is unavailable right now."
            return
        }
        appLog("Resolving playlist: \(url)", category: "network")
        isResolvingPlaylist = true
        isPlaylistResult = false
        errorMessage = nil
        defer { isResolvingPlaylist = false }

        var components = URLComponents()
        components.path = "/api/resolve"
        components.queryItems = [
            URLQueryItem(name: "url",   value: url),
            URLQueryItem(name: "limit", value: "1000"),
        ]
        let manifest = existingTrackManifest(songs: existingSongs)
        if !manifest.isEmpty {
            components.queryItems?.append(URLQueryItem(name: "existing_ids", value: manifest))
        }

        guard var request = makeRequest(components.string ?? "/api/resolve") else {
            errorMessage = "Invalid bridge URL."
            return
        }
        request.timeoutInterval = 130  // slightly over server timeout
        // Lets the bridge use this account's personal YouTube Data API key
        // (Account -> ... ) for full playlist enumeration, if one is set.
        if let accountToken = AccountService.shared?.token {
            request.setValue(accountToken, forHTTPHeaderField: "X-Account-Token")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse {
                switch http.statusCode {
                case 200..<300: break
                case 408:
                    errorMessage = "Playlist resolve timed out. Try again."
                    searchResults = []
                    return
                default:
                    errorMessage = "Could not resolve playlist (HTTP \(http.statusCode))."
                    searchResults = []
                    return
                }
            }
            let tracks = try JSONDecoder().decode([StreamTrack].self, from: data)
            if tracks.isEmpty {
                // Primary resolve returned nothing — fall back to the
                // playlist-to-individual-URLs expander (the export-style
                // workaround), which can succeed where full playlist resolution
                // doesn't for large/partially-unavailable playlists.
                let expanded = await expandPlaylistTracks(url: url, existingSongs: existingSongs)
                searchResults = expanded
                isPlaylistResult = !expanded.isEmpty
                appLog("Resolved playlist via expand fallback: \(expanded.count) track(s)", category: "network")
            } else {
                searchResults = tracks
                isPlaylistResult = true
                appLog("Resolved playlist: \(tracks.count) track(s)", category: "network")
            }
        } catch {
            appError("Playlist resolve failed: \(error.localizedDescription)", category: "network")
            // Last resort before giving up: try the individual-URL expander.
            let expanded = await expandPlaylistTracks(url: url, existingSongs: existingSongs)
            if !expanded.isEmpty {
                searchResults = expanded
                isPlaylistResult = true
                errorMessage = nil
                appLog("Playlist resolve recovered via expand fallback: \(expanded.count) track(s)", category: "network")
            } else {
                errorMessage = "Failed to resolve playlist: \(error.localizedDescription)"
                searchResults = []
            }
        }
    }

    /// Resolves a playlist URL to its tracks and RETURNS them, without touching
    /// the published `searchResults`/`isPlaylistResult` state. Used by the
    /// tracked-playlist screen so opening a tracked playlist doesn't clobber the
    /// user's current Stream-search results. Pass `existingSongs: []` to keep
    /// already-owned tracks in the result (the tracked-playlist UI wants to show
    /// them with an "In Library" badge rather than hide them). Returns `[]` on
    /// failure; `errorMessage` is left untouched.
    func fetchPlaylistTracks(url: String, existingSongs: [Song] = []) async -> [StreamTrack] {
        guard isConfigured else { return [] }
        var components = URLComponents()
        components.path = "/api/resolve"
        components.queryItems = [
            URLQueryItem(name: "url",   value: url),
            URLQueryItem(name: "limit", value: "1000"),
        ]
        let manifest = existingTrackManifest(songs: existingSongs)
        if !manifest.isEmpty {
            components.queryItems?.append(URLQueryItem(name: "existing_ids", value: manifest))
        }
        guard var request = makeRequest(components.string ?? "/api/resolve") else { return [] }
        request.timeoutInterval = 130
        if let accountToken = AccountService.shared?.token {
            request.setValue(accountToken, forHTTPHeaderField: "X-Account-Token")
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                // Fall back to the individual-URL expander on any non-2xx.
                return await expandPlaylistTracks(url: url, existingSongs: existingSongs)
            }
            let tracks = try JSONDecoder().decode([StreamTrack].self, from: data)
            if tracks.isEmpty {
                return await expandPlaylistTracks(url: url, existingSongs: existingSongs)
            }
            return tracks
        } catch {
            appWarn("fetchPlaylistTracks failed: \(error.localizedDescription)", category: "network")
            return await expandPlaylistTracks(url: url, existingSongs: existingSongs)
        }
    }

    /// Expands a playlist URL into individual track entries via the bridge's
    /// `/api/playlist/expand` endpoint (the export-youtube-playlist-style
    /// extraction). Used as a robustness fallback by `resolvePlaylist`. Returns
    /// an empty array on any failure. Already-imported tracks (by sourceTrackID)
    /// are filtered out using `existingSongs`.
    private func expandPlaylistTracks(url: String, existingSongs: [Song]) async -> [StreamTrack] {
        var components = URLComponents()
        components.path = "/api/playlist/expand"
        components.queryItems = [
            URLQueryItem(name: "url", value: url),
            URLQueryItem(name: "limit", value: "1000"),
        ]
        guard var request = makeRequest(components.string ?? "/api/playlist/expand") else { return [] }
        request.timeoutInterval = 130
        if let accountToken = AccountService.shared?.token {
            request.setValue(accountToken, forHTTPHeaderField: "X-Account-Token")
        }

        struct ExpandItem: Decodable { let id: String?; let title: String?; let url: String? }
        struct ExpandResponse: Decodable { let source: String; let count: Int; let items: [ExpandItem] }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return [] }
            let decoded = try JSONDecoder().decode(ExpandResponse.self, from: data)
            let haveIDs = Set(existingSongs.compactMap { $0.sourceTrackID })
            return decoded.items.compactMap { item -> StreamTrack? in
                guard let id = item.id, !id.isEmpty else { return nil }
                if haveIDs.contains("\(decoded.source):\(id)") { return nil }
                return StreamTrack(
                    id: id,
                    title: item.title ?? "Unknown Title",
                    artist: "",
                    durationSeconds: 0,
                    thumbnailURL: "",
                    source: decoded.source,
                    youtubeURL: item.url ?? ""
                )
            }
        } catch {
            appWarn("expandPlaylistTracks failed: \(error.localizedDescription)", category: "network")
            return []
        }
    }

    // MARK: - Stream URL

    /// Decodes FastAPI's standard `{"detail": "..."}` error body, if present.
    private static func decodeErrorDetail(_ data: Data) -> String? {
        struct ErrorBody: Decodable { let detail: String }
        return try? JSONDecoder().decode(ErrorBody.self, from: data).detail
    }

    func streamURL(for track: StreamTrack) async throws -> URL {
        guard isConfigured else {
            throw StreamingError.notConfigured
        }

        // Return the bridge's stream PROXY URL rather than the raw CDN URL.
        // YouTube's googlevideo URLs are bound to the IP that extracted them, so
        // the old flow (bridge extracts → app fetches the raw URL from a
        // different IP) returned 403 and never produced a temp file to play. The
        // proxy re-streams the audio from the bridge's IP, so playback works; it
        // also extracts lazily (when the app fetches it), so Play is instant and
        // the URL is deterministic/cacheable. Auth/cookie headers travel on the
        // Song (see `toSong`) since the player fetches this URL directly.
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "id",     value: track.id),
            URLQueryItem(name: "source", value: track.source),
            URLQueryItem(name: "format", value: preferredFormat),
        ]
        if track.source == "soundcloud" {
            queryItems.append(URLQueryItem(name: "url", value: track.youtubeURL))
        }

        var components = URLComponents()
        components.path = "/api/stream/proxy"
        components.queryItems = queryItems

        guard let request = makeRequest(components.string ?? "/api/stream/proxy"),
              let url = request.url else {
            throw StreamingError.invalidURL
        }
        appLog("streamURL: proxy URL for \"\(track.title)\" [src: \(track.source), fmt: \(preferredFormat)]", category: "network")
        return url
    }

    // MARK: - Convert to Song

    func toSong(track: StreamTrack, streamURL: URL) -> Song {
        // The player fetches `streamURL` (the bridge proxy) directly, so carry
        // any auth the bridge needs on the Song: the shared API key (if set) and
        // the account token (lets the proxy use this user's YouTube cookies for
        // age-restricted/bot-gated videos).
        var headers: [String: String] = [:]
        if !apiKey.isEmpty { headers["Authorization"] = "Bearer \(apiKey)" }
        if let token = AccountService.shared?.token, !token.isEmpty {
            headers["X-Account-Token"] = token
        }
        return Song(
            id: track.id,
            title: track.title,
            artist: track.artist,
            album: "",
            duration: track.duration,
            url: streamURL,
            persistentID: nil,
            artworkCacheKey: track.thumbnailURL.isEmpty ? nil : track.thumbnailURL,
            trackNumber: 0,
            year: "",
            genre: "",
            bitrate: 0,
            sampleRate: 0,
            httpHeaders: headers.isEmpty ? nil : headers
        )
    }

    // MARK: - Server Library Search

    /// Searches the server's local music library via `GET /api/library/server`.
    /// Results are published on `serverTracks`. An empty `query` browses the
    /// whole server library (the bridge lists everything when no search filter
    /// is given) so the Server tab actually loads content on open instead of
    /// sitting empty until the user types. On error the `errorMessage` is set.
    func searchServerLibrary(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        appLog("searchServerLibrary: \"\(trimmed)\" (browse-all: \(trimmed.isEmpty))", category: "network")
        isSearchingServer = true
        errorMessage = nil
        defer { isSearchingServer = false }

        var components = URLComponents()
        components.path = "/api/library/server"
        components.queryItems = [
            URLQueryItem(name: "search", value: trimmed),
            URLQueryItem(name: "limit",  value: "200"),
        ]

        guard var request = makeRequest(components.string ?? "/api/library/server") else {
            errorMessage = "Invalid bridge URL."
            return
        }
        request.timeoutInterval = 20

        struct ServerLibraryResponse: Decodable {
            let tracks: [ServerTrack]
            let total: Int
            let dir: String?
            let configured: Bool?
        }

        do {
            let decoded = try await NetworkRetry.withRetry {
                let (data, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse,
                   !(200..<300).contains(httpResponse.statusCode) {
                    throw StreamingError.httpError(httpResponse.statusCode)
                }
                return try JSONDecoder().decode(ServerLibraryResponse.self, from: data)
            }
            serverTracks = decoded.tracks
            serverLibraryConfigured = decoded.configured ?? true
            appLog("searchServerLibrary: \(serverTracks.count) result(s) for \"\(trimmed)\" (configured: \(serverLibraryConfigured == true))", category: "network")
        } catch {
            appError("searchServerLibrary: \(error.localizedDescription)", category: "network")
            errorMessage = "Streaming service is unavailable right now. Please try again later."
            serverTracks = []
        }
    }

    // MARK: - Server Library URLs

    /// Returns the direct stream URL for a server library track.
    func serverStreamURL(for track: ServerTrack) -> URL? {
        guard let encoded = track.serverPath.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        let base = bridgeURL.trimmingCharacters(in: .init(charactersIn: "/"))
        return URL(string: "\(base)/api/library/server/stream?path=\(encoded)")
    }

    /// Returns the artwork URL for a server library track.
    func serverArtworkURL(for track: ServerTrack) -> URL? {
        guard track.hasArtwork,
              let encoded = track.serverPath.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        let base = bridgeURL.trimmingCharacters(in: .init(charactersIn: "/"))
        return URL(string: "\(base)/api/library/server/artwork?path=\(encoded)")
    }

    // MARK: - Convert ServerTrack to Song

    /// Wraps a `ServerTrack` in a `Song` so it can be handed to `AudioPlayerManager`.
    /// The stream URL is baked in; artwork is loaded lazily via `ArtworkService` using
    /// the server artwork URL as the cache key.
    func toSong(serverTrack: ServerTrack) -> Song {
        let artworkKey = serverArtworkURL(for: serverTrack)?.absoluteString
        let headers: [String: String]? = apiKey.isEmpty ? nil : ["Authorization": "Bearer \(apiKey)"]
        return Song(
            id: serverTrack.id,
            title: serverTrack.title,
            artist: serverTrack.artist,
            album: serverTrack.album,
            duration: serverTrack.duration,
            url: serverStreamURL(for: serverTrack),
            persistentID: nil,
            artworkCacheKey: artworkKey,
            trackNumber: Int(serverTrack.trackNumber) ?? 0,
            year: "",
            genre: serverTrack.genre,
            bitrate: 0,
            sampleRate: 0,
            httpHeaders: headers
        )
    }

    // MARK: - Download to Library

    /// Downloads a stream track's audio permanently to `downloadDirectory` (or
    /// `destinationDir` if provided — used by folder-structure restore to place
    /// redownloaded tracks back into their original watched-folder path) using
    /// the `/api/download` endpoint (which embeds metadata and thumbnail into
    /// the file). If the file already exists it is returned immediately without
    /// re-downloading.
    ///
    /// `existingSongs` (typically `LibraryManager.allSongs`) enables pre-download
    /// dedupe: if a song in `existingSongs` shares this track's `sourceTrackID`
    /// ("\(track.source):\(track.id)") and its local file passes
    /// `CorruptFileFinderService.isValidAudioFile(at:)`, the download is skipped
    /// entirely and that song's existing file URL is returned. If the matching
    /// local file is missing or corrupt, the download proceeds normally to
    /// replace it. Pass `[]` (the default) to disable this check.
    func downloadToLibrary(track: StreamTrack, destinationDir: URL? = nil, existingSongs: [Song] = []) async throws -> URL {
        let sourceTrackID = "\(track.source):\(track.id)"

        // Pre-download dedupe — skip entirely if we already have a valid copy
        // of this exact source track (matched by sourceTrackID/LUMISOUND_ID).
        if let match = existingSongs.first(where: { $0.sourceTrackID == sourceTrackID }),
           let existingURL = match.url,
           FileManager.default.fileExists(atPath: existingURL.path) {
            if CorruptFileFinderService.isValidAudioFile(at: existingURL) {
                appLog("downloadToLibrary: skipping \"\(track.title)\" — valid existing copy at \(existingURL.lastPathComponent)", category: "network")
                DownloadLedgerStore.shared.record(sourceTrackID: sourceTrackID, filename: existingURL.lastPathComponent)
                return existingURL
            } else {
                appWarn("downloadToLibrary: existing copy of \"\(track.title)\" is corrupt — redownloading to replace it", category: "network")
            }
        }

        appLog("Download started: \"\(track.title)\" [fmt: \(preferredFormat)]", category: "network")
        let fmt = preferredFormat
        let requestedExt = fileExtension(for: fmt)

        let importDir = destinationDir ?? downloadDirectory
        do {
            try FileManager.default.createDirectory(at: importDir, withIntermediateDirectories: true)
        } catch {
            appWarn("downloadToLibrary: could not create download dir: \(error)", category: "network")
        }

        // Build a filesystem-safe filename from the track title (max 100 chars).
        let safeName = String(
            track.title
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")
                .prefix(100)
        )

        // Check for an existing download under the requested extension before hitting
        // the network — the actual extension is only known after the response arrives
        // (see below), so this is just the common-case fast path.
        let provisionalDestURL = importDir.appendingPathComponent("\(safeName).\(requestedExt)")
        if FileManager.default.fileExists(atPath: provisionalDestURL.path) {
            appLog("downloadToLibrary: already exists, skipping \(provisionalDestURL.lastPathComponent)", category: "network")
            DownloadLedgerStore.shared.record(sourceTrackID: sourceTrackID, filename: provisionalDestURL.lastPathComponent)
            return provisionalDestURL
        }

        // Hit the /api/download endpoint which runs yt-dlp with metadata embedding.
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "id",       value: track.id),
            URLQueryItem(name: "source",   value: track.source),
            URLQueryItem(name: "format",   value: fmt),
            URLQueryItem(name: "title",    value: safeName),
            URLQueryItem(name: "artist",   value: track.artist),
            URLQueryItem(name: "thumbnail", value: track.thumbnailURL),
            URLQueryItem(name: "duration", value: String(track.durationSeconds)),
        ]
        if track.source == "soundcloud" {
            queryItems.append(URLQueryItem(name: "url", value: track.youtubeURL))
        }
        // Per-user aria2 preference (Settings → yt-dlp). Off by default — the
        // bridge uses its native downloader unless this is true. Only send when
        // enabled to keep the default request unchanged.
        if UserDefaults.standard.bool(forKey: "ytdlp_use_aria2") {
            queryItems.append(URLQueryItem(name: "use_aria2", value: "true"))
        }
        // Defense-in-depth: also tell the bridge what the client already has, so
        // a stale/incomplete `existingSongs` snapshot still gets server-side dedupe.
        // Exclude this track's own ID — if we got this far the pre-download check
        // above either found no local copy or found a corrupt one that needs
        // replacing, so the server must not skip *this* download.
        let manifest = existingTrackManifest(songs: existingSongs.filter { $0.sourceTrackID != sourceTrackID })
        if !manifest.isEmpty {
            queryItems.append(URLQueryItem(name: "existing_ids", value: manifest))
        }

        var components = URLComponents()
        components.path = "/api/download"
        components.queryItems = queryItems

        guard var request = makeRequest(components.string ?? "/api/download") else {
            throw StreamingError.invalidURL
        }
        // Lets the bridge record this download in the account's server-side
        // download history (My Library search, previously-downloaded restore).
        if let accountToken = AccountService.shared?.token {
            request.setValue(accountToken, forHTTPHeaderField: "X-Account-Token")
        }

        // Big playlists hammer the bridge's yt-dlp pipeline hard enough that some
        // tracks come back truncated or with invalid audio data even though the
        // HTTP transfer "succeeds". Retry the whole download a few times — with a
        // fresh temp file and a full integrity check each time — before giving up,
        // so a single flaky fetch doesn't leave a corrupt file in the library.
        let maxAttempts = 3
        var lastError: Error = StreamingError.corruptDownload

        for attempt in 1...maxAttempts {
            do {
                let destURL = try await attemptDownload(
                    track: track,
                    request: request,
                    safeName: safeName,
                    requestedExt: requestedExt,
                    importDir: importDir
                )
                if attempt != 1 {
                    appLog("downloadToLibrary: succeeded for \"\(track.title)\" on attempt \(attempt)/\(maxAttempts)", category: "network")
                }
                DownloadLedgerStore.shared.record(sourceTrackID: sourceTrackID, filename: destURL.lastPathComponent)
                return destURL
            } catch let error as StreamingError {
                switch error {
                case .incompleteDownload, .corruptDownload:
                    lastError = error
                    appWarn("downloadToLibrary: attempt \(attempt)/\(maxAttempts) failed for \"\(track.title)\": \(error.localizedDescription)", category: "network")
                    continue
                default:
                    // Not-found / timeout / HTTP errors are unlikely to be fixed by retrying.
                    throw error
                }
            }
        }

        throw lastError
    }

    /// Performs a single download attempt for `downloadToLibrary`, including the
    /// HTTP request, completeness check, move-into-place, and an `AVAudioFile`
    /// integrity check on the final file. Throws `.incompleteDownload` or
    /// `.corruptDownload` on failure so the caller can retry.
    private func attemptDownload(
        track: StreamTrack,
        request: URLRequest,
        safeName: String,
        requestedExt: String,
        importDir: URL
    ) async throws -> URL {
        // /api/download is async: it returns a job_id immediately (status 202)
        // instead of holding the connection open for the whole yt-dlp run. A
        // synchronous design here routinely exceeded the Cloudflare Tunnel's
        // ~100s edge timeout for normal-length tracks, causing 524s followed by
        // from-scratch retries that piled onto the bridge and made every
        // subsequent request slower (a runaway retry storm).
        var startRequest = request
        startRequest.timeoutInterval = 30

        let startData: Data
        let startResponse: URLResponse
        do {
            (startData, startResponse) = try await URLSession.shared.data(for: startRequest)
        } catch {
            // A raw URLError (e.g. .timedOut) here isn't a StreamingError, so the
            // outer retry loop's `catch let error as StreamingError` wouldn't see
            // it — the whole downloadToLibrary call would abort with no retry at
            // all. Map it to .incompleteDownload so a flaky/slow start request
            // (the bridge under load) gets retried like any other transient failure.
            appWarn("downloadToLibrary: network error starting job for \"\(track.title)\": \(error.localizedDescription) — will retry", category: "network")
            throw StreamingError.incompleteDownload
        }
        guard let startHTTP = startResponse as? HTTPURLResponse else {
            throw StreamingError.invalidURL
        }

        switch startHTTP.statusCode {
        case 202:
            break
        case 408:
            appWarn("downloadToLibrary: timeout for \"\(track.title)\"", category: "network")
            throw StreamingError.timeout
        case 404:
            appWarn("downloadToLibrary: not found for \"\(track.title)\"", category: "network")
            throw StreamingError.notFound(track.title)
        case 502, 503, 504, 524:
            appWarn("downloadToLibrary: gateway error \(startHTTP.statusCode) for \"\(track.title)\" — will retry", category: "network")
            throw StreamingError.incompleteDownload
        default:
            // Includes 204 ("client already has this track" per existing_ids) —
            // this track's own id is excluded from that manifest, so 204 here
            // would be unexpected; treat it like an incomplete result so the
            // retry loop re-fetches rather than adopting an empty file.
            appWarn("downloadToLibrary: unexpected start status \(startHTTP.statusCode) for \"\(track.title)\"", category: "network")
            throw StreamingError.incompleteDownload
        }

        struct StartPayload: Decodable { let job_id: String }
        guard let start = try? JSONDecoder().decode(StartPayload.self, from: startData) else {
            throw StreamingError.incompleteDownload
        }

        guard let statusURL = jobPollURL(from: startRequest, path: "/api/download/status", jobID: start.job_id),
              let resultURL = jobPollURL(from: startRequest, path: "/api/download/result", jobID: start.job_id) else {
            throw StreamingError.invalidURL
        }

        var statusRequest = startRequest
        statusRequest.url = statusURL

        struct StatusPayload: Decodable { let status: String; let code: Int?; let detail: String? }

        // Poll every 3s for up to 5 minutes — matches the previous client-side
        // timeout, but each poll is a trivial dict lookup (<1s), so this never
        // approaches the tunnel's ~100s edge timeout regardless of how long
        // yt-dlp itself takes on the bridge.
        let deadline = Date().addingTimeInterval(300)
        pollLoop: while true {
            if Date() > deadline {
                appWarn("downloadToLibrary: job poll timed out for \"\(track.title)\"", category: "network")
                throw StreamingError.incompleteDownload
            }
            let data: Data
            let resp: URLResponse
            do {
                (data, resp) = try await URLSession.shared.data(for: statusRequest)
            } catch {
                // A single slow/timed-out status poll (the bridge can be briefly
                // CPU-busy under load) shouldn't abort the whole job — wait and
                // poll again rather than letting a raw URLError escape uncaught.
                appWarn("downloadToLibrary: network error polling status for \"\(track.title)\": \(error.localizedDescription) — retrying poll", category: "network")
                try await Task.sleep(nanoseconds: 3_000_000_000)
                continue pollLoop
            }
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200,
                  let status = try? JSONDecoder().decode(StatusPayload.self, from: data) else {
                throw StreamingError.incompleteDownload
            }
            switch status.status {
            case "pending":
                try await Task.sleep(nanoseconds: 3_000_000_000)
                continue pollLoop
            case "done":
                break pollLoop
            case "error":
                switch status.code {
                case 408:
                    appWarn("downloadToLibrary: timeout for \"\(track.title)\"", category: "network")
                    throw StreamingError.timeout
                case 404:
                    appWarn("downloadToLibrary: not found for \"\(track.title)\"", category: "network")
                    throw StreamingError.notFound(track.title)
                case 502, 503, 504, 524:
                    appWarn("downloadToLibrary: job failed with gateway error \(status.code ?? 0) for \"\(track.title)\" — will retry", category: "network")
                    throw StreamingError.incompleteDownload
                default:
                    appError("downloadToLibrary: job failed (\(status.code ?? 0)) for \"\(track.title)\": \(status.detail ?? "")", category: "network")
                    throw StreamingError.httpError(status.code ?? 500)
                }
            default:
                throw StreamingError.incompleteDownload
            }
        }

        var resultRequest = startRequest
        resultRequest.url = resultURL
        resultRequest.timeoutInterval = 120

        let downloadedURL: URL
        let response: URLResponse
        do {
            (downloadedURL, response) = try await BackgroundDownloadManager.run(
                named: "lumisound.download.\(safeName)"
            ) {
                try await URLSession.shared.download(for: resultRequest)
            }
        } catch {
            // Same as the start/poll requests: a raw URLError here would otherwise
            // escape uncaught and abort the whole pipeline instead of retrying.
            appWarn("downloadToLibrary: network error fetching result for \"\(track.title)\": \(error.localizedDescription) — will retry", category: "network")
            throw StreamingError.incompleteDownload
        }
        if let httpResponse = response as? HTTPURLResponse {
            switch httpResponse.statusCode {
            case 200..<300:
                break
            default:
                appError("downloadToLibrary: HTTP \(httpResponse.statusCode) fetching result for \"\(track.title)\"", category: "network")
                throw StreamingError.incompleteDownload
            }
        }

        // Verify the downloaded file is complete before adopting it into the library.
        // A truncated download (dropped connection, app suspended mid-transfer, etc.)
        // would otherwise sit in the library as a track that shows "0:00" forever.
        let downloadedSize = (try? FileManager.default.attributesOfItem(atPath: downloadedURL.path))?[.size] as? Int64 ?? 0
        let expectedSize = (response as? HTTPURLResponse)?.expectedContentLength ?? -1
        if downloadedSize <= 0 || (expectedSize > 0 && downloadedSize != expectedSize) {
            try? FileManager.default.removeItem(at: downloadedURL)
            appWarn("downloadToLibrary: incomplete download for \"\(track.title)\" (\(downloadedSize)/\(expectedSize) bytes)", category: "network")
            throw StreamingError.incompleteDownload
        }

        // The bridge can fall back to a different container than requested (e.g. yt-dlp
        // has no native m4a stream for this video and serves webm/opus instead while
        // `format=m4a` was requested) — `_download_format_args` on the bridge already
        // reflects this in the `Content-Type` header. Saving such a file with a `.m4a`
        // extension makes AVAudioFile misparse it (it picks a decoder based on the file
        // extension): playback's timer keeps advancing from the engine's render clock
        // while no audio is actually decoded, which is the "silently lands ~1 minute in"
        // bug. Trust the response's actual content type over the requested format.
        let actualExt = extensionForContentType(
            (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type")
        ) ?? requestedExt
        let destURL = importDir.appendingPathComponent("\(safeName).\(actualExt)")

        if FileManager.default.fileExists(atPath: destURL.path) {
            try? FileManager.default.removeItem(at: downloadedURL)
            appLog("downloadToLibrary: already exists, skipping \(destURL.lastPathComponent)", category: "network")
            return destURL
        }

        try? FileManager.default.removeItem(at: destURL)
        do {
            try FileManager.default.moveItem(at: downloadedURL, to: destURL)
        } catch {
            appError("downloadToLibrary: move failed for \"\(track.title)\": \(error)", category: "network")
            throw error
        }
        if actualExt != requestedExt {
            appLog("downloadToLibrary: bridge returned .\(actualExt) instead of requested .\(requestedExt) for \"\(track.title)\" — saved with correct extension", category: "network")
        }

        // Final integrity check: the byte count matched what the server promised, but
        // yt-dlp can still emit a file AVAudioFile can't decode (corrupt remux, dropped
        // moov atom, etc.) — exactly what CorruptFileFinderService flags later. Catch it
        // immediately so the retry loop can re-fetch instead of leaving a dead file behind.
        guard CorruptFileFinderService.isValidAudioFile(at: destURL) else {
            try? FileManager.default.removeItem(at: destURL)
            appWarn("downloadToLibrary: corrupt/unreadable file for \"\(track.title)\" — discarding", category: "network")
            throw StreamingError.corruptDownload
        }

        appLog("Download complete: \(destURL.lastPathComponent)", category: "network")

        // Pre-seed the artwork cache with the track's thumbnail so it's immediately
        // available when scanLocalDocuments() creates the Song for this file.
        if !track.thumbnailURL.isEmpty, let thumbURL = URL(string: track.thumbnailURL) {
            await ArtworkService.shared.prefetchRemoteImage(url: thumbURL, forKey: destURL.lastPathComponent)
        }

        return destURL
    }

    /// Builds the `/api/download/status` or `/api/download/result` URL for a given
    /// job, reusing the scheme/host/port/auth of the original `/api/download`
    /// request but replacing the path and query with `job_id=`.
    private func jobPollURL(from request: URLRequest, path: String, jobID: String) -> URL? {
        guard let url = request.url,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.path = path
        components.queryItems = [URLQueryItem(name: "job_id", value: jobID)]
        return components.url
    }

    /// Maps a format value to the appropriate file extension.
    private func fileExtension(for format: String) -> String {
        switch format {
        case "mp3":  return "mp3"
        case "flac": return "flac"
        case "opus": return "opus"
        case "wav":  return "wav"
        default:     return "m4a"   // m4a and best both produce m4a
        }
    }

    /// Maps the `/api/download` response's `Content-Type` (set by the bridge's
    /// `content_type_map` from yt-dlp's *actual* output container, which can differ
    /// from the requested `format` when that container isn't available for a given
    /// video) back to a file extension. Returns `nil` for missing/unrecognized
    /// content types so the caller can fall back to the requested format's extension.
    private func extensionForContentType(_ contentType: String?) -> String? {
        guard let contentType else { return nil }
        // Strip any "; charset=..." parameters before matching.
        let base = contentType.split(separator: ";").first.map(String.init)?
            .trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        switch base {
        case "audio/mpeg":      return "mp3"
        case "audio/mp4":       return "m4a"
        case "audio/flac":      return "flac"
        case "audio/ogg":       return "opus"
        case "audio/wav", "audio/x-wav", "audio/wave": return "wav"
        case "audio/webm":      return "webm"
        default:                return nil
        }
    }

    // MARK: - User Music Library (personal per-user server storage)

    /// Returns the stream URL for a user music track (requires JWT token).
    func userMusicStreamURL(for track: UserMusicTrack, token: String) -> URL? {
        guard let encoded = track.serverPath.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        let base = bridgeURL.trimmingCharacters(in: .init(charactersIn: "/"))
        return URL(string: "\(base)/user/music/stream?path=\(encoded)")
    }

    /// Returns the artwork URL for a user music track (requires JWT token).
    func userMusicArtworkURL(for track: UserMusicTrack) -> URL? {
        guard track.hasArtwork,
              let encoded = track.serverPath.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        let base = bridgeURL.trimmingCharacters(in: .init(charactersIn: "/"))
        return URL(string: "\(base)/user/music/artwork?path=\(encoded)")
    }

    /// Wraps a `UserMusicTrack` in a `Song` for playback.
    func toSong(userMusicTrack: UserMusicTrack, token: String) -> Song {
        let streamURL = userMusicStreamURL(for: userMusicTrack, token: token)
        let artworkKey = userMusicArtworkURL(for: userMusicTrack)?.absoluteString
        return Song(
            id: userMusicTrack.id,
            title: userMusicTrack.title,
            artist: userMusicTrack.artist,
            album: userMusicTrack.album,
            duration: userMusicTrack.duration,
            url: streamURL,
            persistentID: nil,
            artworkCacheKey: artworkKey,
            trackNumber: Int(userMusicTrack.trackNumber) ?? 0,
            year: "",
            genre: userMusicTrack.genre,
            bitrate: 0,
            sampleRate: 0,
            httpHeaders: ["Authorization": "Bearer \(token)"]
        )
    }

    /// Fetches the user's personal music library from the server.
    func fetchUserMusic(token: String, search: String = "") async {
        appLog("fetchUserMusic: search=\"\(search)\"", category: "network")
        isLoadingUserMusic = true
        errorMessage = nil
        defer { isLoadingUserMusic = false }

        var components = URLComponents()
        components.path = "/user/music"
        components.queryItems = [
            // No 500-item cap on the user's cloud library (server allows up to 100k).
            URLQueryItem(name: "limit", value: "100000"),
        ]
        if !search.isEmpty {
            components.queryItems?.append(URLQueryItem(name: "search", value: search))
        }

        guard var request = makeRequest(components.string ?? "/user/music") else {
            errorMessage = "Invalid bridge URL."
            return
        }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        // The first request after a library change has to ffprobe every
        // uncached file server-side before it can respond — with a large
        // personal library this routinely took longer than the old 20s
        // timeout, which made "My Library" appear to hang/fail forever even
        // though the server was still working (and would have served a fast,
        // cached response on the next try). 90s gives that cold pass room to
        // finish; subsequent calls hit the server's ffprobe cache and return
        // quickly regardless.
        request.timeoutInterval = 90

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
                appWarn("fetchUserMusic: HTTP \(httpResponse.statusCode)", category: "network")
                if httpResponse.statusCode == 401 {
                    errorMessage = "Your session has expired. Please log in again."
                } else {
                    errorMessage = "Streaming service error (HTTP \(httpResponse.statusCode)). Please try again later."
                }
                return
            }

            struct Response: Decodable {
                let tracks: [UserMusicTrack]
                let total: Int
                let configured: Bool
            }
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            if !decoded.configured {
                errorMessage = "User music storage is not configured on the server."
                userMusicTracks = []
            } else {
                userMusicTracks = decoded.tracks
                appLog("fetchUserMusic: \(decoded.tracks.count) tracks", category: "network")
            }
        } catch {
            appError("fetchUserMusic: \(error.localizedDescription)", category: "network")
            errorMessage = "Failed to load your library: \(error.localizedDescription)"
        }
    }

    /// Fetches the tracks this account has downloaded before (server-side
    /// history), optionally filtered by `search`. Used by "My Library" search
    /// to surface tracks the user has ever had — even ones no longer present
    /// on this device — and by the "previously downloaded" restore list.
    func fetchDownloadHistory(token: String, search: String = "") async {
        appLog("fetchDownloadHistory: search=\"\(search)\"", category: "network")
        isLoadingDownloadHistory = true
        defer { isLoadingDownloadHistory = false }

        var components = URLComponents()
        components.path = "/user/download-history"
        components.queryItems = [URLQueryItem(name: "limit", value: "200")]
        if !search.isEmpty {
            components.queryItems?.append(URLQueryItem(name: "search", value: search))
        }

        guard var request = makeRequest(components.string ?? "/user/download-history") else {
            return
        }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
                appWarn("fetchDownloadHistory: HTTP \(httpResponse.statusCode)", category: "network")
                return
            }
            struct Response: Decodable {
                let tracks: [DownloadHistoryTrack]
                let total: Int
            }
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            downloadHistory = decoded.tracks
            appLog("fetchDownloadHistory: \(decoded.tracks.count) tracks", category: "network")
        } catch {
            appError("fetchDownloadHistory: \(error.localizedDescription)", category: "network")
        }
    }

    /// Uploads a local audio file to the user's personal music library on the server.
    func uploadToUserLibrary(fileURL: URL, token: String, folder: String = "") async throws {
        appLog("uploadToUserLibrary: \(fileURL.lastPathComponent)", category: "network")
        isUploadingUserMusic = true
        uploadProgress = 0
        defer { isUploadingUserMusic = false; uploadProgress = 0 }

        let filename = fileURL.lastPathComponent
        var components = URLComponents()
        components.path = "/user/music/upload"
        components.queryItems = [
            URLQueryItem(name: "filename", value: filename),
        ]
        if !folder.isEmpty {
            components.queryItems?.append(URLQueryItem(name: "folder", value: folder))
        }

        guard var request = makeRequest(components.string ?? "/user/music/upload") else {
            throw StreamingError.invalidURL
        }
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 300   // 5 min for large files

        // Use URLSession.upload(for:fromFile:) instead of loading the whole file into memory.
        // This streams the file directly from disk, critical for large audio files.
        let (_, response) = try await URLSession.shared.upload(for: request, fromFile: fileURL)
        if let http = response as? HTTPURLResponse {
            switch http.statusCode {
            case 200..<300: break
            case 413: throw StreamingError.httpError(413)
            default: throw StreamingError.httpError(http.statusCode)
            }
        }
        appLog("uploadToUserLibrary: uploaded \(filename)", category: "network")
    }

    /// Deletes a file from the user's personal music library on the server.
    func deleteUserMusic(path: String, token: String) async throws {
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        guard var request = makeRequest("/user/music/\(encoded)") else {
            throw StreamingError.invalidURL
        }
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 20

        let (_, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw StreamingError.httpError(http.statusCode)
        }
        appLog("deleteUserMusic: deleted \(path)", category: "network")
    }

    // MARK: - Upload Track with Metadata

    /// Uploads a local audio file to the user's personal music library, passing
    /// client-supplied metadata as query parameters so the server can populate
    /// `ios_user_music_metadata` immediately without an ffprobe pass.
    /// Returns the `UserMusicMetadataTrack` row created on the server.
    func uploadTrack(fileURL: URL, token: String, metadata: TrackMetadata, folder: String = "") async throws -> UserMusicMetadataTrack {
        appLog("uploadTrack: \(fileURL.lastPathComponent)", category: "network")
        isUploadingUserMusic = true
        uploadProgress = 0
        defer { isUploadingUserMusic = false; uploadProgress = 0 }

        let filename = fileURL.lastPathComponent
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "filename", value: filename),
        ]
        if !folder.isEmpty {
            queryItems.append(URLQueryItem(name: "folder", value: folder))
        }
        if let v = metadata.title,          !v.isEmpty { queryItems.append(URLQueryItem(name: "title",       value: v)) }
        if let v = metadata.artist,         !v.isEmpty { queryItems.append(URLQueryItem(name: "artist",      value: v)) }
        if let v = metadata.album,          !v.isEmpty { queryItems.append(URLQueryItem(name: "album",       value: v)) }
        if let v = metadata.genre,          !v.isEmpty { queryItems.append(URLQueryItem(name: "genre",       value: v)) }
        if let v = metadata.year,           !v.isEmpty { queryItems.append(URLQueryItem(name: "year",        value: v)) }
        if let v = metadata.durationSeconds               { queryItems.append(URLQueryItem(name: "duration",    value: String(v))) }
        if let v = metadata.bitrate                       { queryItems.append(URLQueryItem(name: "bitrate",     value: String(v))) }
        if let v = metadata.sampleRate                    { queryItems.append(URLQueryItem(name: "sample_rate", value: String(v))) }

        var components = URLComponents()
        components.path = "/user/music/upload"
        components.queryItems = queryItems

        guard var request = makeRequest(components.string ?? "/user/music/upload") else {
            throw StreamingError.invalidURL
        }
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 300

        let (_, response) = try await URLSession.shared.upload(for: request, fromFile: fileURL)
        if let http = response as? HTTPURLResponse {
            switch http.statusCode {
            case 200..<300: break
            case 413: throw StreamingError.httpError(413)
            default:  throw StreamingError.httpError(http.statusCode)
            }
        }

        uploadProgress = 1.0
        appLog("uploadTrack: uploaded \(filename)", category: "network")

        // Re-fetch metadata so the caller gets a fully populated object
        let tracks = try await fetchUserMusicMetadata(token: token)
        if let match = tracks.first(where: { $0.filename == filename }) {
            return match
        }
        // Fallback: synthesise a minimal response from the query params
        return UserMusicMetadataTrack(
            id: "",
            filename: filename,
            originalFilename: filename,
            title: metadata.title,
            artist: metadata.artist,
            album: metadata.album,
            genre: metadata.genre,
            year: metadata.year,
            durationSeconds: metadata.durationSeconds,
            fileSizeBytes: nil,
            bitrate: metadata.bitrate,
            sampleRate: metadata.sampleRate,
            mimeType: nil,
            hasArtwork: false,
            uploadedAt: nil,
            artworkURL: nil
        )
    }

    // MARK: - Fetch User Music Metadata

    /// Fetches rich metadata for all uploaded tracks from `/user/music/metadata`.
    @discardableResult
    func fetchUserMusicMetadata(token: String) async throws -> [UserMusicMetadataTrack] {
        appLog("fetchUserMusicMetadata", category: "network")
        isLoadingUserMusicMetadata = true
        defer { isLoadingUserMusicMetadata = false }

        // No artificial 500-item cap on a user's cloud-backed library — request
        // the full set (server allows up to 100k).
        guard var request = makeRequest("/user/music/metadata?limit=100000") else {
            throw StreamingError.invalidURL
        }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw StreamingError.httpError(http.statusCode)
        }

        struct MetadataResponse: Decodable {
            let tracks: [UserMusicMetadataTrack]
            let total: Int
        }
        let decoded = try JSONDecoder().decode(MetadataResponse.self, from: data)
        userMusicMetadata = decoded.tracks
        appLog("fetchUserMusicMetadata: \(decoded.tracks.count) tracks", category: "network")
        return decoded.tracks
    }

    // MARK: - Auto-Backup Sync (catches songs that were imported/scanned, not just downloaded)

    /// Uploads any locally-stored songs that aren't yet in the user's cloud
    /// library — covers files added via import/scan/folder-watch, not just the
    /// "download from search" path that originally drove auto-backup. Apple
    /// Music library items (no readable file URL) are skipped; they can't be
    /// read off disk directly.
    ///
    /// Runs at low priority and pauses between uploads so a large library catch-up
    /// doesn't compete with foreground playback, streaming, or UI responsiveness —
    /// callers should fire-and-forget this from a scan/import completion handler
    /// when Auto-Backup is enabled.
    func backUpLibraryIfNeeded(songs: [Song], token: String) {
        guard !isSyncingLibraryBackup else { return }
        let localSongs = songs.filter { $0.url?.isFileURL == true }
        guard !localSongs.isEmpty else { return }

        isSyncingLibraryBackup = true
        Task(priority: .background) { [weak self] in
            guard let self else { return }
            defer { self.isSyncingLibraryBackup = false }

            // Compare against what the server already has so re-runs (e.g. after
            // every scan) only ever upload genuinely new files.
            guard let existing = try? await self.fetchUserMusicMetadata(token: token) else { return }
            let alreadyBackedUp = Set(existing.compactMap { $0.originalFilename })

            let pending = localSongs.filter { song in
                guard let name = song.url?.lastPathComponent else { return false }
                return !alreadyBackedUp.contains(name)
            }
            guard !pending.isEmpty else { return }
            appLog("backUpLibraryIfNeeded: backing up \(pending.count) local song(s)", category: "network")

            for song in pending {
                guard !Task.isCancelled, let url = song.url else { return }
                let metadata = TrackMetadata(
                    title: song.title.isEmpty ? nil : song.title,
                    artist: song.artist.isEmpty ? nil : song.artist,
                    album: song.album.isEmpty ? nil : song.album,
                    genre: song.genre.isEmpty ? nil : song.genre,
                    year: song.year.isEmpty ? nil : song.year,
                    durationSeconds: song.duration > 0 ? song.duration : nil,
                    bitrate: song.bitrate > 0 ? song.bitrate : nil,
                    sampleRate: song.sampleRate > 0 ? song.sampleRate : nil
                )
                _ = try? await self.uploadTrack(fileURL: url, token: token, metadata: metadata)
                // Throttle — keeps this from saturating the network/CPU during a
                // big catch-up so foreground playback and streaming stay smooth.
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
            appLog("backUpLibraryIfNeeded: finished", category: "network")
        }
    }

    // MARK: - Gallery

    /// Returns the absolute URL for a gallery image given its relative path.
    func galleryImageURL(_ relativePath: String, token: String) -> URL? {
        let base = bridgeURL.trimmingCharacters(in: .init(charactersIn: "/"))
        guard let url = URL(string: base + relativePath) else { return nil }
        return url
    }

    /// Fetches the list of cloud-synced gallery images.
    @discardableResult
    func fetchGalleryImages(token: String) async throws -> [GalleryImageInfo] {
        appLog("fetchGalleryImages", category: "network")
        isLoadingGallery = true
        defer { isLoadingGallery = false }

        guard var request = makeRequest("/user/gallery/images") else {
            throw StreamingError.invalidURL
        }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw StreamingError.httpError(http.statusCode)
        }

        let images = try JSONDecoder().decode([GalleryImageInfo].self, from: data)
        galleryImages = images
        appLog("fetchGalleryImages: \(images.count) images", category: "network")
        return images
    }

    /// Uploads a UIImage as JPEG to the user's cloud gallery.
    /// Returns the image ID assigned by the server.
    func uploadGalleryImage(_ image: UIImage, token: String, displayOrder: Int = 0) async throws -> String {
        appLog("uploadGalleryImage", category: "network")
        isUploadingGalleryImage = true
        defer { isUploadingGalleryImage = false }

        guard let jpeg = image.jpegData(compressionQuality: 0.85) else {
            throw StreamingError.invalidURL   // reuse invalidURL for encode failure
        }

        let base = bridgeURL.trimmingCharacters(in: .init(charactersIn: "/"))
        guard let url = URL(string: "\(base)/user/gallery/images?display_order=\(displayOrder)") else {
            throw StreamingError.invalidURL
        }

        // Build multipart/form-data body
        let boundary = UUID().uuidString
        var body = Data()
        let crlf = "\r\n"
        body.append("--\(boundary)\(crlf)".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"gallery.jpg\"\(crlf)".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\(crlf)\(crlf)".data(using: .utf8)!)
        body.append(jpeg)
        body.append("\(crlf)--\(boundary)--\(crlf)".data(using: .utf8)!)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 120

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw StreamingError.httpError(http.statusCode)
        }

        struct UploadResponse: Decodable { let id: String }
        let decoded = try JSONDecoder().decode(UploadResponse.self, from: data)
        appLog("uploadGalleryImage: uploaded, id=\(decoded.id)", category: "network")

        // Refresh the gallery list
        _ = try? await fetchGalleryImages(token: token)
        return decoded.id
    }

    /// Deletes a gallery image by ID.
    func deleteGalleryImage(id: String, token: String) async throws {
        guard var request = makeRequest("/user/gallery/images/\(id)") else {
            throw StreamingError.invalidURL
        }
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 20

        let (_, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw StreamingError.httpError(http.statusCode)
        }
        galleryImages.removeAll { $0.id == id }
        appLog("deleteGalleryImage: deleted \(id)", category: "network")
    }

    /// Downloads the actual bytes for a cloud gallery entry. The file-serving endpoint
    /// requires the same per-user bearer token as the listing/upload/delete calls
    /// (it's not a public URL), so this can't be loaded via a plain AsyncImage.
    func fetchGalleryImageData(_ image: GalleryImageInfo, token: String) async -> UIImage? {
        guard var request = makeRequest(image.url) else { return nil }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        return UIImage(data: data)
    }

    // MARK: - Health Check

    func checkHealth() async -> Bool {
        guard isConfigured, let request = makeRequest("/health") else { return false }
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                return (200..<300).contains(httpResponse.statusCode)
            }
            return false
        } catch {
            return false
        }
    }

    // MARK: - Public request builder

    /// Public wrapper so external services (e.g. BridgeHealthService) can build
    /// authenticated requests without duplicating URL construction logic.
    func makePublicRequest(_ path: String) -> URLRequest? {
        makeRequest(path)
    }

    // MARK: - Private helpers

    private func makeRequest(_ path: String) -> URLRequest? {
        // Strip trailing slash from bridgeURL, ensure path starts with /
        let base = bridgeURL.trimmingCharacters(in: .init(charactersIn: "/"))
        let normalizedPath = path.hasPrefix("/") ? path : "/\(path)"
        guard let url = URL(string: base + normalizedPath) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        return request
    }
}

// MARK: - StreamingError

enum StreamingError: LocalizedError {
    case notConfigured
    case invalidURL
    case timeout
    case notFound(String)
    case httpError(Int)
    case incompleteDownload
    case corruptDownload
    /// Carries a specific, already-user-facing reason string straight from
    /// the bridge's error `detail` field (e.g. "upload your YouTube cookies
    /// to play age-restricted videos") instead of a generic message.
    case serverDetail(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Streaming service is unavailable right now."
        case .invalidURL:
            return "The bridge returned an invalid stream URL."
        case .timeout:
            return "Stream URL fetch timed out. Try again."
        case .notFound(let title):
            return "Could not find a stream URL for \"\(title)\"."
        case .serverDetail(let detail):
            return detail
        case .httpError(let code):
            switch code {
            case 401, 403:
                return "You're not signed in or don't have permission for this. Try signing in again."
            case 404:
                return "Not found on the server — it may have already been removed."
            case 413:
                return "File is too large for the server to accept."
            case 500...599:
                return "Server error (HTTP \(code)). Please try again later."
            default:
                return "Request failed (HTTP \(code)). Please try again later."
            }
        case .incompleteDownload:
            return "Download was incomplete. Please try again."
        case .corruptDownload:
            return "Downloaded file failed an integrity check. Please try again."
        }
    }
}
