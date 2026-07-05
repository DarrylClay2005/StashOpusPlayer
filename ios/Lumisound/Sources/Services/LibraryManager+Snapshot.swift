import Foundation
import MediaPlayer
import UIKit

extension LibraryManager {

    // MARK: - Library Snapshot (instant-on-launch cache)

    private struct LibrarySnapshot: Codable {
        let songs: [Song]
        let artists: [String]
        let albums: [String]
        let genres: [String]
    }

    private static let snapshotURL: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return caches.appendingPathComponent("library_snapshot_v1.json")
    }()

    /// Reads the last-persisted library state synchronously so `allSongs` (and
    /// the derived facet lists) are populated the instant `LibraryManager` is
    /// constructed — before any scan has run. For a 1,100-song library the
    /// real scan can take many seconds; without this, the launch/library
    /// screens sit empty that whole time even though the user had a perfectly
    /// good library a moment ago. `scanMediaLibrary`/`scanLocalDocuments`/etc.
    /// always run after `init` and silently replace these values with fresh
    /// results once they complete (see `persistSnapshotIfSettled`).
    func loadPersistedSnapshot() {
        guard let data = try? Data(contentsOf: Self.snapshotURL),
              let snapshot = try? JSONDecoder().decode(LibrarySnapshot.self, from: data),
              !snapshot.songs.isEmpty
        else { return }
        allSongs = snapshot.songs
        artists = snapshot.artists
        albums = snapshot.albums
        genres = snapshot.genres
        appLog("Loaded cached library snapshot: \(snapshot.songs.count) song(s)", category: "library")
    }

    /// Writes the current library state to disk so the next launch can show it
    /// instantly via `loadPersistedSnapshot`. Only called once a scan has
    /// fully settled (`!isScanning`) so we never persist a half-populated
    /// mid-scan state as if it were the real library. Encoding/writing
    /// thousands of `Song` structs is real work — offloaded to a background
    /// task exactly like `ScanCacheService.persist()`.
    func persistSnapshotIfSettled() {
        guard !isScanning else { return }
        let snapshot = LibrarySnapshot(songs: allSongs, artists: artists, albums: albums, genres: genres)
        let destination = Self.snapshotURL
        Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: destination, options: .atomic)
        }
    }
}
