import Foundation
import UIKit

extension StreamingService {

    // MARK: - Auto-Backup Sync (catches songs that were imported/scanned, not just downloaded)

    /// Uploads any locally-stored songs that aren't yet in the user's cloud
    /// library — covers files added via import/scan/folder-watch, not just the
    /// "download from search" path that originally drove auto-backup. Apple
    /// Music library items (no readable file URL) are skipped; they can't be
    /// read off disk directly.
    ///
    /// Runs at low priority and pauses between uploads so a large library catch-up
    /// doesn't compete with foreground playback, streaming, or UI responsiveness —
    /// callers should fire-and-forget this from a scan/import completion handler
    /// when Auto-Backup is enabled.
    func backUpLibraryIfNeeded(songs: [Song], token: String) {
        guard !isSyncingLibraryBackup else { return }
        let localSongs = songs.filter { $0.url?.isFileURL == true }
        guard !localSongs.isEmpty else { return }

        isSyncingLibraryBackup = true
        Task(priority: .background) { [weak self] in
            guard let self else { return }
            defer { self.isSyncingLibraryBackup = false }

            // Compare against what the server already has so re-runs (e.g. after
            // every scan) only ever upload genuinely new files.
            guard let existing = try? await self.fetchUserMusicMetadata(token: token) else { return }
            let alreadyBackedUp = Set(existing.compactMap { $0.originalFilename })

            let pending = localSongs.filter { song in
                guard let name = song.url?.lastPathComponent else { return false }
                return !alreadyBackedUp.contains(name)
            }
            guard !pending.isEmpty else { return }
            appLog("backUpLibraryIfNeeded: backing up \(pending.count) local song(s)", category: "network")

            for song in pending {
                guard !Task.isCancelled, let url = song.url else { return }
                let metadata = TrackMetadata(
                    title: song.title.isEmpty ? nil : song.title,
                    artist: song.artist.isEmpty ? nil : song.artist,
                    album: song.album.isEmpty ? nil : song.album,
                    genre: song.genre.isEmpty ? nil : song.genre,
                    year: song.year.isEmpty ? nil : song.year,
                    durationSeconds: song.duration > 0 ? song.duration : nil,
                    bitrate: song.bitrate > 0 ? song.bitrate : nil,
                    sampleRate: song.sampleRate > 0 ? song.sampleRate : nil
                )
                _ = try? await self.uploadTrack(fileURL: url, token: token, metadata: metadata)
                // Throttle — keeps this from saturating the network/CPU during a
                // big catch-up so foreground playback and streaming stay smooth.
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
            appLog("backUpLibraryIfNeeded: finished", category: "network")
        }
    }
}
