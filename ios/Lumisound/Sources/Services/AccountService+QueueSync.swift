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
            /// Forward-compatible only: the `/user/queue` bridge endpoint's
            /// schema (`QueueTrackRequest` / `ios_user_queue` table in
            /// ios-bridge's main.py) has no column for this yet, so FastAPI's
            /// default `extra="ignore"` request-model behavior silently drops
            /// it on write, and GET /user/queue never returns it — meaning a
            /// queue restored via `fetchQueue` below always comes back with
            /// `queueSource == nil` (read as `.autoContinuation`) regardless
            /// of what was pushed. Sending it now costs nothing and means a
            /// future backend migration to persist it doesn't require another
            /// app release. See QueueSource for the manual/auto-continuation
            /// distinction this mirrors.
            let queue_source: String
        }
        struct Body: Encodable { let tracks: [TrackBody] }
        let tracks = songs.map { song in
            TrackBody(
                local_song_id: song.persistentID == nil ? song.id : nil,
                track_url: song.url?.absoluteString,
                title: song.title,
                artist: song.artist.isEmpty ? nil : song.artist,
                album: song.album.isEmpty ? nil : song.album,
                duration_seconds: Int(song.duration),
                queue_source: song.resolvedQueueSource.rawValue
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
    /// Entries that can't be resolved either way are skipped. Every resolved
    /// `Song` comes back with `queueSource == nil` (i.e. `.autoContinuation`) —
    /// the bridge doesn't persist that distinction yet (see the comment on
    /// `queue_source` in `pushQueue` above), so a queue restored from another
    /// device currently loses the manual/auto-continuation split even though
    /// track identity and order survive intact.
    func fetchQueue(library: LibraryManager) async -> [Song] {
        guard isLoggedIn else { return [] }
        do {
            let data = try await makeRequest("/user/queue")
            let items = try JSONDecoder().decode([QueueItem].self, from: data)
            // uniquingKeysWith:, not uniqueKeysWithValues: — the latter traps
            // (crashes) on any duplicate id, which `library.allSongs` isn't
            // guaranteed to be free of (see the matching fix/comment in
            // LibraryManager+SongRemoval.swift's rebuildAllSongs).
            let songsByID = Dictionary(library.allSongs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
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
