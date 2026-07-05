import Foundation
import UIKit

extension StreamingService {

    // MARK: - Playlist URL detection

    static func isPlaylistURL(_ text: String) -> Bool {
        let t = text.lowercased()
        guard t.hasPrefix("http") else { return false }
        let isYouTube = t.contains("youtube.com") || t.contains("youtu.be")
        if isYouTube {
            return t.contains("list=") || t.contains("/playlist")
        }
        // Bandcamp has no search extractor (unlike YouTube/SoundCloud), so a
        // pasted track/album/artist URL is the only way to pull in a Bandcamp
        // track — route it straight to resolvePlaylist instead of treating it
        // as a (futile) search query.
        return t.contains("bandcamp.com")
    }
}
