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

    /// Public URL baked into the app — routed via SwarmPanel ngrok proxy so
    /// it works anywhere without home WiFi. Users can override in Settings.
    static let defaultBridgeURL = "https://germinate-props-motive.ngrok-free.dev"

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

    // MARK: User Music Library state (personal per-user storage)

    @Published var userMusicTracks: [UserMusicTrack] = []
    @Published var isLoadingUserMusic = false
    @Published var isUploadingUserMusic = false
    @Published var uploadProgress: Double = 0

    // MARK: User Music Metadata state (rich metadata from /user/music/metadata)

    @Published var userMusicMetadata: [UserMusicMetadataTrack] = []
    @Published var isLoadingUserMusicMetadata = false

    // MARK: Gallery state

    @Published var galleryImages: [GalleryImageInfo] = []
    @Published var isLoadingGallery = false
    @Published var isUploadingGalleryImage = false

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
            errorMessage = "Bridge server URL not configured."
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

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               !(200..<300).contains(httpResponse.statusCode) {
                errorMessage = "Bridge server offline. Make sure the server and ngrok tunnel are running, then retry."
                searchResults = []
                return
            }
            let tracks = try JSONDecoder().decode([StreamTrack].self, from: data)
            searchResults = tracks
            appLog("Search returned \(tracks.count) result(s) for \"\(query)\"", category: "network")
        } catch {
            appError("Search failed: \(error.localizedDescription)", category: "network")
            errorMessage = "Bridge server offline. Make sure the server and ngrok tunnel are running, then retry."
            searchResults = []
        }
    }

    // MARK: - Playlist resolution

    /// Resolves a YouTube (or SoundCloud) playlist URL to a list of tracks via
    /// the bridge's `/api/resolve` endpoint. Results are published on `searchResults`
    /// and `isPlaylistResult` is set to `true` so the UI can show the playlist banner.
    func resolvePlaylist(url: String) async {
        guard isConfigured else {
            errorMessage = "Bridge server URL not configured."
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
            URLQueryItem(name: "limit", value: "100"),
        ]

        guard var request = makeRequest(components.string ?? "/api/resolve") else {
            errorMessage = "Invalid bridge URL."
            return
        }
        request.timeoutInterval = 130  // slightly over server timeout

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
            searchResults = tracks
            isPlaylistResult = true
            appLog("Resolved playlist: \(tracks.count) track(s)", category: "network")
        } catch {
            appError("Playlist resolve failed: \(error.localizedDescription)", category: "network")
            errorMessage = "Failed to resolve playlist: \(error.localizedDescription)"
            searchResults = []
        }
    }

    // MARK: - Stream URL

    func streamURL(for track: StreamTrack) async throws -> URL {
        guard isConfigured else {
            throw StreamingError.notConfigured
        }

        let cacheKey = "\(track.id)_\(preferredFormat)_\(track.source)"
        if let hit = streamURLCache[cacheKey], hit.expiry > Date() {
            appLog("streamURL: cache hit for \"\(track.title)\"", category: "network")
            return hit.url
        }

        appLog("streamURL: \"\(track.title)\" [src: \(track.source), fmt: \(preferredFormat)]", category: "network")
        isLoadingStream = true
        defer { isLoadingStream = false }

        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "id",     value: track.id),
            URLQueryItem(name: "source", value: track.source),
            URLQueryItem(name: "format", value: preferredFormat),
        ]
        if track.source == "soundcloud" {
            queryItems.append(URLQueryItem(name: "url", value: track.youtubeURL))
        }

        var components = URLComponents()
        components.path = "/api/stream"
        components.queryItems = queryItems

        guard var request = makeRequest(components.string ?? "/api/stream") else {
            throw StreamingError.invalidURL
        }
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse {
            switch httpResponse.statusCode {
            case 200..<300:
                break
            case 408:
                appWarn("streamURL: timeout for \"\(track.title)\"", category: "network")
                throw StreamingError.timeout
            case 404:
                appWarn("streamURL: not found for \"\(track.title)\"", category: "network")
                throw StreamingError.notFound(track.title)
            default:
                appError("streamURL: HTTP \(httpResponse.statusCode) for \"\(track.title)\"", category: "network")
                throw StreamingError.httpError(httpResponse.statusCode)
            }
        }

        let decoded = try JSONDecoder().decode(StreamResponse.self, from: data)
        guard let url = URL(string: decoded.url) else {
            appError("streamURL: invalid URL in response for \"\(track.title)\"", category: "network")
            throw StreamingError.invalidURL
        }
        streamURLCache[cacheKey] = (url: url, expiry: Date().addingTimeInterval(Self.streamURLCacheTTL))
        appLog("streamURL: got URL for \"\(track.title)\" (expires \(decoded.expiresIn)s)", category: "network")
        return url
    }

    // MARK: - Convert to Song

    func toSong(track: StreamTrack, streamURL: URL) -> Song {
        Song(
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
            sampleRate: 0
        )
    }

    // MARK: - Server Library Search

    /// Searches the server's local music library via `GET /api/library/server`.
    /// Results are published on `serverTracks`. On error the `errorMessage` is set.
    func searchServerLibrary(query: String) async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            serverTracks = []
            return
        }
        appLog("searchServerLibrary: \"\(query)\"", category: "network")
        isSearchingServer = true
        errorMessage = nil
        defer { isSearchingServer = false }

        var components = URLComponents()
        components.path = "/api/library/server"
        components.queryItems = [
            URLQueryItem(name: "search", value: query),
            URLQueryItem(name: "limit",  value: "100"),
        ]

        guard var request = makeRequest(components.string ?? "/api/library/server") else {
            errorMessage = "Invalid bridge URL."
            return
        }
        request.timeoutInterval = 20

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               !(200..<300).contains(httpResponse.statusCode) {
                appWarn("searchServerLibrary: HTTP \(httpResponse.statusCode) for \"\(query)\"", category: "network")
                errorMessage = "Bridge server offline. Make sure the server and ngrok tunnel are running, then retry."
                serverTracks = []
                return
            }
            struct ServerLibraryResponse: Decodable {
                let tracks: [ServerTrack]
                let total: Int
                let dir: String?
                let configured: Bool?
            }
            let decoded = try JSONDecoder().decode(ServerLibraryResponse.self, from: data)
            serverTracks = decoded.tracks
            appLog("searchServerLibrary: \(serverTracks.count) result(s) for \"\(query)\"", category: "network")
        } catch {
            appError("searchServerLibrary: \(error.localizedDescription)", category: "network")
            errorMessage = "Bridge server offline. Make sure the server and ngrok tunnel are running, then retry."
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

    /// Downloads a stream track's audio permanently to `downloadDirectory` using the
    /// `/api/download` endpoint (which embeds metadata and thumbnail into the file).
    /// If the file already exists it is returned immediately without re-downloading.
    func downloadToLibrary(track: StreamTrack) async throws -> URL {
        appLog("Download started: \"\(track.title)\" [fmt: \(preferredFormat)]", category: "network")
        let fmt = preferredFormat
        let ext = fileExtension(for: fmt)

        let importDir = downloadDirectory
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
        let destURL = importDir.appendingPathComponent("\(safeName).\(ext)")

        if FileManager.default.fileExists(atPath: destURL.path) {
            appLog("downloadToLibrary: already exists, skipping \(destURL.lastPathComponent)", category: "network")
            return destURL
        }

        // Hit the /api/download endpoint which runs yt-dlp with metadata embedding.
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "id",     value: track.id),
            URLQueryItem(name: "source", value: track.source),
            URLQueryItem(name: "format", value: fmt),
            URLQueryItem(name: "title",  value: safeName),
        ]
        if track.source == "soundcloud" {
            queryItems.append(URLQueryItem(name: "url", value: track.youtubeURL))
        }

        var components = URLComponents()
        components.path = "/api/download"
        components.queryItems = queryItems

        guard var request = makeRequest(components.string ?? "/api/download") else {
            throw StreamingError.invalidURL
        }
        // Downloads can take longer than stream URL fetches.
        request.timeoutInterval = 120

        let (downloadedURL, response) = try await BackgroundDownloadManager.run(
            named: "lumisound.download.\(safeName)"
        ) {
            try await URLSession.shared.download(for: request)
        }
        if let httpResponse = response as? HTTPURLResponse {
            switch httpResponse.statusCode {
            case 200..<300:
                break
            case 408:
                appWarn("downloadToLibrary: timeout for \"\(track.title)\"", category: "network")
                throw StreamingError.timeout
            case 404:
                appWarn("downloadToLibrary: not found for \"\(track.title)\"", category: "network")
                throw StreamingError.notFound(track.title)
            default:
                appError("downloadToLibrary: HTTP \(httpResponse.statusCode) for \"\(track.title)\"", category: "network")
                throw StreamingError.httpError(httpResponse.statusCode)
            }
        }

        try? FileManager.default.removeItem(at: destURL)
        do {
            try FileManager.default.moveItem(at: downloadedURL, to: destURL)
        } catch {
            appError("downloadToLibrary: move failed for \"\(track.title)\": \(error)", category: "network")
            throw error
        }
        appLog("Download complete: \(destURL.lastPathComponent)", category: "network")

        // Pre-seed the artwork cache with the track's thumbnail so it's immediately
        // available when scanLocalDocuments() creates the Song for this file.
        if !track.thumbnailURL.isEmpty, let thumbURL = URL(string: track.thumbnailURL) {
            await ArtworkService.shared.prefetchRemoteImage(url: thumbURL, forKey: destURL.lastPathComponent)
        }

        return destURL
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
            URLQueryItem(name: "limit", value: "200"),
        ]
        if !search.isEmpty {
            components.queryItems?.append(URLQueryItem(name: "search", value: search))
        }

        guard var request = makeRequest(components.string ?? "/user/music") else {
            errorMessage = "Invalid bridge URL."
            return
        }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 20

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
                appWarn("fetchUserMusic: HTTP \(httpResponse.statusCode)", category: "network")
                errorMessage = "Bridge server offline. Make sure the server and ngrok tunnel are running, then retry."
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

        guard var request = makeRequest("/user/music/metadata?limit=500") else {
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

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Bridge server URL is not configured. Go to Settings → Streaming."
        case .invalidURL:
            return "The bridge returned an invalid stream URL."
        case .timeout:
            return "Stream URL fetch timed out. Try again."
        case .notFound(let title):
            return "Could not find a stream URL for \"\(title)\"."
        case .httpError:
            return "Bridge server offline. Make sure the server and ngrok tunnel are running, then retry."
        }
    }
}
