import Foundation

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

    // MARK: Published state

    @Published var searchResults: [StreamTrack] = []
    @Published var isSearching      = false
    @Published var isLoadingStream  = false
    @Published var errorMessage: String?

    // MARK: Server Library state

    @Published var serverTracks: [ServerTrack] = []
    @Published var isSearchingServer = false

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
                errorMessage = "Unable to reach streaming server. Check your connection."
                searchResults = []
                return
            }
            let tracks = try JSONDecoder().decode([StreamTrack].self, from: data)
            searchResults = tracks
            appLog("Search returned \(tracks.count) result(s) for \"\(query)\"", category: "network")
        } catch {
            appError("Search failed: \(error.localizedDescription)", category: "network")
            errorMessage = "Unable to reach streaming server. Check your connection."
            searchResults = []
        }
    }

    // MARK: - Stream URL

    func streamURL(for track: StreamTrack) async throws -> URL {
        guard isConfigured else {
            throw StreamingError.notConfigured
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
                errorMessage = "Unable to reach streaming server. Check your connection."
                serverTracks = []
                return
            }
            serverTracks = try JSONDecoder().decode([ServerTrack].self, from: data)
            appLog("searchServerLibrary: \(serverTracks.count) result(s) for \"\(query)\"", category: "network")
        } catch {
            appError("searchServerLibrary: \(error.localizedDescription)", category: "network")
            errorMessage = "Unable to reach streaming server. Check your connection."
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
            sampleRate: 0
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

        let (downloadedURL, response) = try await URLSession.shared.download(for: request)
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
            return "Unable to reach streaming server. Check your connection."
        }
    }
}
