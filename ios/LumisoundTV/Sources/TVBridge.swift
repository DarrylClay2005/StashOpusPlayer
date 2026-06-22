import Foundation

// MARK: - TVTrack

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

// MARK: - TVBridgeClient

@MainActor
final class TVBridgeClient: ObservableObject {
    static let shared = TVBridgeClient()

    /// The same public bridge the iOS app uses by default.
    let baseURL = "https://lumisound-bridge.xenusanimations.studio"

    @Published var results: [TVTrack] = []
    @Published var isSearching = false
    @Published var errorText: String?

    func search(_ query: String) async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        isSearching = true
        errorText = nil
        defer { isSearching = false }

        guard var comps = URLComponents(string: baseURL + "/api/search") else { return }
        comps.queryItems = [
            URLQueryItem(name: "q", value: q),
            URLQueryItem(name: "source", value: "youtube"),
            URLQueryItem(name: "limit", value: "30"),
        ]
        guard let url = comps.url else { return }
        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 30
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                errorText = "Search failed. Try again."
                results = []
                return
            }
            results = try JSONDecoder().decode([TVTrack].self, from: data)
        } catch {
            errorText = error.localizedDescription
            results = []
        }
    }

    /// The bridge proxy stream URL for a track — AVPlayer streams this directly.
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
}
