import Foundation
import UIKit

extension StreamingService {

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
}
