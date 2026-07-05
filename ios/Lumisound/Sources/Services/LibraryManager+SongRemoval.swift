import Foundation
import MediaPlayer
import UIKit

extension LibraryManager {

    /// Permanently removes a locally-imported/downloaded song: deletes its
    /// backing file, drops it from `importedSongs`/`allSongs`, and removes any
    /// references to it from playlists and favorites. Used by the duplicate
    /// finder to delete redundant copies. Only works for imported songs (those
    /// with a file `url` and no `persistentID`) — songs from the Apple Music
    /// library can't be deleted from within the app sandbox, so callers should
    /// filter those out before offering deletion.
    func removeImportedSong(id songID: String) {
        guard let song = importedSongs.first(where: { $0.id == songID }) else { return }
        if let url = song.url {
            // Songs from user-watched folders (MusicFolderService) live outside the
            // app sandbox and are only reachable via a security-scoped bookmark —
            // without this, `removeItem` silently fails (the `try?` swallows an
            // error), the song disappears from the library list, but the file
            // stays on disk. This call is a harmless no-op for files already
            // inside the app's own Documents directory (e.g. "Imported Music"
            // and its subfolders).
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                appWarn("removeImportedSong: failed to delete file at \(url.path): \(error.localizedDescription)", category: "library")
                ToastCenter.shared.show("Couldn't delete \"\(song.displayName)\" from disk", category: .error)
                return
            }
        }
        importedSongs.removeAll { $0.id == songID }
        favoriteSongIDs.remove(songID)
        persistence.saveFavorites(favoriteSongIDs)
        for index in playlists.indices {
            playlists[index].songIDs.removeAll { $0 == songID }
        }
        persistence.savePlaylists(playlists)
        rebuildAllSongs()
        ToastCenter.shared.show("Deleted \"\(song.displayName)\"", category: .info, icon: "trash")
    }

    /// Bulk version of `removeImportedSong` for Library's multi-select "Delete"
    /// action — one rebuild/toast instead of one per song. IDs that aren't in
    /// `importedSongs` (e.g. Apple Music library tracks, which this can't
    /// delete) are silently skipped rather than failing the whole batch.
    func removeImportedSongs(ids songIDs: Set<String>) {
        let toDelete = importedSongs.filter { songIDs.contains($0.id) }
        guard !toDelete.isEmpty else { return }

        for song in toDelete {
            guard let url = song.url else { continue }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                appWarn("removeImportedSongs: failed to delete file at \(url.path): \(error.localizedDescription)", category: "library")
            }
        }

        let deletedIDs = Set(toDelete.map(\.id))
        importedSongs.removeAll { deletedIDs.contains($0.id) }
        favoriteSongIDs.subtract(deletedIDs)
        persistence.saveFavorites(favoriteSongIDs)
        for index in playlists.indices {
            playlists[index].songIDs.removeAll { deletedIDs.contains($0) }
        }
        persistence.savePlaylists(playlists)
        rebuildAllSongs()
        ToastCenter.shared.show(
            "Deleted \(deletedIDs.count) song\(deletedIDs.count == 1 ? "" : "s")",
            category: .info, icon: "trash"
        )
    }

    /// Applies a user-confirmed metadata correction (e.g. from AcoustIDService
    /// identification) to a single imported song. Unlike the periodic
    /// re-enrichment in `reenrichSongsMissingMetadata` — which only fills
    /// *empty* fields — this overwrites existing title/artist/album, since
    /// the user has explicitly reviewed and confirmed the match. Only affects
    /// the app's own record for the file (`ScanCacheService`'s cached Song),
    /// not the file's embedded tags.
    func applyMetadataCorrection(songID: String, title: String?, artist: String?, album: String?) {
        guard let index = importedSongs.firstIndex(where: { $0.id == songID }) else { return }
        var song = importedSongs[index]
        if let title, !title.isEmpty { song.title = title }
        if let artist, !artist.isEmpty { song.artist = artist }
        if let album, !album.isEmpty { song.album = album }
        importedSongs[index] = song

        if let url = song.url, let stamp = ScanCacheService.fileStamp(for: url) {
            ScanCacheService.shared.store(song: song, for: url, stamp: stamp)
            ScanCacheService.shared.persist()
        }
        rebuildAllSongs()
        ToastCenter.shared.show("Updated \"\(song.displayName)\"", category: .success, icon: "checkmark.circle")
    }

    /// Re-encodes an imported song stuck on a compatibility-fallback format
    /// (opus/webm/ogg — see `Song.usesCompatibilityFallbackFormat`) to AAC
    /// `.m4a` in place, so it plays through the full AVAudioEngine graph
    /// (EQ/pitch/crossfade/gapless/effects) instead of the reduced AVPlayer
    /// fallback. The old file is only deleted after the new one is written
    /// and confirmed playable.
    func convertImportedSongFormat(songID: String) async {
        guard let index = importedSongs.firstIndex(where: { $0.id == songID }),
              let oldURL = importedSongs[index].url,
              oldURL.isFileURL
        else { return }
        let songName = importedSongs[index].displayName

        let newURL = oldURL.deletingPathExtension().appendingPathExtension("m4a")
        guard await AudioEncoderService.shared.convertPermanently(oldURL, to: newURL) else {
            ToastCenter.shared.show("Couldn't convert \"\(songName)\"", category: .error, icon: "exclamationmark.triangle")
            return
        }

        // Re-resolve the index — this is async, and the library could have
        // mutated (e.g. the song was removed) while the conversion ran.
        guard let freshIndex = importedSongs.firstIndex(where: { $0.id == songID }) else {
            try? FileManager.default.removeItem(at: newURL)
            return
        }
        var song = importedSongs[freshIndex]
        song.url = newURL
        importedSongs[freshIndex] = song
        try? FileManager.default.removeItem(at: oldURL)

        if let stamp = ScanCacheService.fileStamp(for: newURL) {
            ScanCacheService.shared.store(song: song, for: newURL, stamp: stamp)
            ScanCacheService.shared.persist()
        }
        rebuildAllSongs()
        ToastCenter.shared.show("Converted \"\(songName)\" for compatibility", category: .success, icon: "checkmark.circle")
    }

    /// Debounced rebuild — cancels any pending task and schedules a new one after 0.1 s.
    /// This prevents runaway work when rapid successive mutations occur (e.g. bulk imports).
    ///
    /// The locale-aware sort plus the three set/sort passes for filter facets are
    /// O(n log n) over the *entire* library on every mutation. For large libraries
    /// (thousands of tracks) that's enough synchronous work to visibly stall the UI
    /// if run on the main actor, so it's computed off-actor and only the final
    /// `@Published` assignment happens on the main actor.
    func rebuildAllSongs() {
        pendingRebuildTask?.cancel()
        pendingRebuildTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 s
            guard let self, !Task.isCancelled else { return }
            let media = self.mediaSongs
            let imported = self.importedSongs

            let (combined, artists, albums, genres) = await Task.detached(priority: .userInitiated) {
                let combined = (media + imported).sorted {
                    $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                }
                let artists = Array(Set(combined.map(\.artistName))).sorted()
                let albums  = Array(Set(combined.map(\.albumName))).sorted()
                let genres  = Array(Set(combined.compactMap { $0.genre.isEmpty ? nil : $0.genre })).sorted()
                return (combined, artists, albums, genres)
            }.value

            guard !Task.isCancelled else { return }
            self.allSongs = combined
            self.artists = artists
            self.albums  = albums
            self.genres  = genres
            self.persistSnapshotIfSettled()
        }
    }
}
