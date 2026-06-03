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

    static let bridgeURLKey = "ios_bridge_url"
    static let apiKeyKey    = "ios_bridge_api_key"

    // MARK: Published state

    @Published var searchResults: [StreamTrack] = []
    @Published var isSearching      = false
    @Published var isLoadingStream  = false
    @Published var errorMessage: String?

    // MARK: Persisted settings

    var bridgeURL: String {
        get { UserDefaults.standard.string(forKey: Self.bridgeURLKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Self.bridgeURLKey) }
    }

    var apiKey: String {
        get { UserDefaults.standard.string(forKey: Self.apiKeyKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Self.apiKeyKey) }
    }

    var isConfigured: Bool { !bridgeURL.isEmpty }

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
                errorMessage = "Search failed: HTTP \(httpResponse.statusCode)"
                searchResults = []
                return
            }
            let tracks = try JSONDecoder().decode([StreamTrack].self, from: data)
            searchResults = tracks
        } catch {
            errorMessage = "Search error: \(error.localizedDescription)"
            searchResults = []
        }
    }

    // MARK: - Stream URL

    func streamURL(for track: StreamTrack) async throws -> URL {
        guard isConfigured else {
            throw StreamingError.notConfigured
        }

        isLoadingStream = true
        defer { isLoadingStream = false }

        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "id",     value: track.id),
            URLQueryItem(name: "source", value: track.source),
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
                throw StreamingError.timeout
            case 404:
                throw StreamingError.notFound(track.title)
            default:
                throw StreamingError.httpError(httpResponse.statusCode)
            }
        }

        let decoded = try JSONDecoder().decode(StreamResponse.self, from: data)
        guard let url = URL(string: decoded.url) else {
            throw StreamingError.invalidURL
        }
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
        case .httpError(let code):
            return "Bridge server error (HTTP \(code))."
        }
    }
}
