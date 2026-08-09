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

    /// Reads the last-persisted library state so `allSongs` (and the derived
    /// facet lists) are populated moments after `LibraryManager` is
    /// constructed — before any scan has run. For a 1,100-song library the
    /// real scan can take many seconds; without this, the launch/library
    /// screens sit empty that whole time even though the user had a perfectly
    /// good library a moment ago. `scanMediaLibrary`/`scanLocalDocuments`/etc.
    /// always run after `init` and silently replace these values with fresh
    /// results once they complete (see `persistSnapshotIfSettled`).
    ///
    /// The file read + JSON decode — real work for a several-thousand-song
    /// library — run off the main actor in a `Task.detached`; only the final
    /// `@Published` assignment touches the main actor. This USED to run
    /// fully synchronously and get called directly from `init()`, which
    /// SwiftUI invokes (via `@StateObject`) before the very first frame can
    /// render — for a big library, that synchronous decode was slow enough
    /// to visibly freeze the launch screen's supposedly-continuous
    /// animations for its duration, the opposite of the "instant" library
    /// this feature exists to provide. Callers should fire this from a
    /// `Task`, not await it inline where a blocked launch screen would
    /// matter.
    func loadPersistedSnapshot() async {
        let url = Self.snapshotURL
        let snapshot: LibrarySnapshot? = await Task.detached(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: url),
                  let snapshot = try? JSONDecoder().decode(LibrarySnapshot.self, from: data),
                  !snapshot.songs.isEmpty
            else { return nil }
            return snapshot
        }.value
        guard let snapshot else { return }
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
    ///
    /// Debounced ~2s (separate from `rebuildAllSongs()`'s own 100ms debounce):
    /// `rebuildAllSongs()` runs once per single-song mutation too (e.g. one
    /// BPM analysis completing at a time, or a metadata correction), and each
    /// call used to trigger its own full snapshot re-encode+write. A run of
    /// several such mutations a few seconds apart — common while background
    /// BPM analysis works through a large library — now collapses into one
    /// disk write instead of one per mutation.
    func persistSnapshotIfSettled() {
        guard !isScanning else { return }
        pendingSnapshotPersistTask?.cancel()
        pendingSnapshotPersistTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            guard let self, !Task.isCancelled, !self.isScanning else { return }
            let snapshot = LibrarySnapshot(songs: self.allSongs, artists: self.artists, albums: self.albums, genres: self.genres)
            let destination = Self.snapshotURL
            await Task.detached(priority: .utility) {
                guard let data = try? JSONEncoder().encode(snapshot) else { return }
                try? data.write(to: destination, options: .atomic)
            }.value
        }
    }
}
