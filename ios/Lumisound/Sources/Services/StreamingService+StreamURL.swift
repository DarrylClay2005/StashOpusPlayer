import Foundation
import UIKit

extension StreamingService {

    // MARK: - Stream URL

    /// Decodes FastAPI's standard `{"detail": "..."}` error body, if present.
    static func decodeErrorDetail(_ data: Data) -> String? {
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
        if track.source == "soundcloud" || track.source == "bandcamp" {
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
}
