import Foundation
import SwiftUI
import UIKit

extension AccountService {

    // MARK: - Queue sync

    /// Replaces the server's "up next" queue with `songs`, in order, so it
    /// survives app restarts and syncs across devices (PUT /user/queue).
    /// Fire-and-forget — failures are logged but not surfaced as errors,
    /// since this runs automatically in the background whenever the queue changes.
    func pushQueue(_ songs: [Song]) async {
        guard isLoggedIn else { return }
        struct TrackBody: Encodable {
            let local_song_id: String?
            let track_url: String?
            let title: String
            let artist: String?
            let album: String?
            let duration_seconds: Int
        }
        struct Body: Encodable { let tracks: [TrackBody] }
        let tracks = songs.map { song in
            TrackBody(
                local_song_id: song.persistentID == nil ? song.id : nil,
                track_url: song.url?.absoluteString,
                title: song.title,
                artist: song.artist.isEmpty ? nil : song.artist,
                album: song.album.isEmpty ? nil : song.album,
                duration_seconds: Int(song.duration)
            )
        }
        do {
            _ = try await makeRequest("/user/queue", method: "PUT", body: Body(tracks: tracks))
        } catch {
            appLog("Queue sync push failed: \(error.localizedDescription)", category: "account")
        }
    }

    /// Fetches the server's "up next" queue (GET /user/queue), resolving each
    /// entry against the local library (by ID) or as a streaming track (by URL).
    /// Entries that can't be resolved either way are skipped.
    func fetchQueue(library: LibraryManager) async -> [Song] {
        guard isLoggedIn else { return [] }
        do {
            let data = try await makeRequest("/user/queue")
            let items = try JSONDecoder().decode([QueueItem].self, from: data)
            let songsByID = Dictionary(uniqueKeysWithValues: library.allSongs.map { ($0.id, $0) })
            return items.compactMap { item -> Song? in
                if let localID = item.localSongId, let song = songsByID[localID] {
                    return song
                }
                if let urlString = item.trackUrl, let url = URL(string: urlString) {
                    return Song(
                        title: item.title,
                        artist: item.artist ?? "",
                        album: item.album ?? "",
                        duration: TimeInterval(item.durationSeconds ?? 0),
                        url: url
                    )
                }
                return nil
            }
        } catch let err as AccountError {
            errorMessage = err.message
            return []
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }
}
