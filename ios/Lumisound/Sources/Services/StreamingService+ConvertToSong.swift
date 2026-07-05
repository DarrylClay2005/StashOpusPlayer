import Foundation
import UIKit

extension StreamingService {

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
}
