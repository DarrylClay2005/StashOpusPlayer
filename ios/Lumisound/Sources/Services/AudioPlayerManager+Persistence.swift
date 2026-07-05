@preconcurrency import AVFoundation
import AudioToolbox
import Foundation
import MediaPlayer
import UIKit

extension AudioPlayerManager {

    // MARK: - Persistence

    func savePlaybackState() {
        let snapshot = PlaybackSnapshot(
            version: PlaybackSnapshot.currentVersion,
            currentSongID: currentSong?.id,
            queue: queue,
            currentIndex: currentIndex,
            position: position,
            repeatMode: repeatMode,
            shuffleEnabled: shuffleEnabled
        )
        // Called on every pause/skip/seek — encoding the full queue (which can be the
        // entire library, hundreds/thousands of Song structs) synchronously on the main
        // thread made every playback action feel laggy. Encode + write off-main, wrapped
        // in a background task so it still finishes if this races app suspension
        // (e.g. the didEnterBackground save).
        let key = playbackStateKey
        Task.detached(priority: .utility) {
            try? await BackgroundDownloadManager.run(named: "SavePlaybackState") {
                guard let data = try? JSONEncoder().encode(snapshot) else { return }
                UserDefaults.standard.set(data, forKey: key)
            }
        }
    }

    func restorePlaybackState() {
        guard
            let data = UserDefaults.standard.data(forKey: playbackStateKey),
            let snapshot = try? JSONDecoder().decode(PlaybackSnapshot.self, from: data),
            !snapshot.queue.isEmpty
        else { return }

        // Discard snapshots written by an older schema version to prevent crashes or
        // unexpected state from stale / incompatible data.
        if snapshot.version != PlaybackSnapshot.currentVersion {
            UserDefaults.standard.removeObject(forKey: playbackStateKey)
            appLog("PlaybackSnapshot version mismatch (\(snapshot.version) vs \(PlaybackSnapshot.currentVersion)) — cleared stale snapshot", category: "general")
            return
        }

        // Sanitise URLs before restoring.
        // ipod-library:// asset URLs are session-scoped and expire across app launches.
        // Clear them so scheduleCurrent() fails gracefully instead of crashing on a
        // stale MPMediaItem URL. Song metadata (title/artist) is preserved for display.
        //
        // Local file:// URLs are absolute paths through the sandbox container, e.g.
        // .../Containers/Data/Application/<UUID>/Documents/Imported Music/song.mp3 —
        // and sideloaded installs (AltStore) get a brand-new <UUID> on every update,
        // so every entry in a restored queue pointed at a path that no longer
        // existed (silently failing to schedule, or throwing "file not found").
        // Re-anchor the Documents-relative portion of the path onto the *current*
        // sandbox's Documents directory so playback resumes correctly post-update.
        let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        let sanitisedQueue = snapshot.queue.map { song -> Song in
            guard let url = song.url else { return song }
            var cleaned = song
            if url.scheme == "ipod-library" {
                cleaned.url = nil
            } else if url.isFileURL, let docsDir,
                      let relative = ScanCacheService.documentsRelativePath(for: url) {
                cleaned.url = docsDir.appendingPathComponent(relative)
            }
            return cleaned
        }

        queue = sanitisedQueue
        currentIndex = min(max(snapshot.currentIndex, 0), sanitisedQueue.count - 1)
        currentSong = queue[currentIndex]
        // Force widget refresh on launch even if the song id hasn't changed since last run.
        Task { await updateNowPlayingArtwork(for: currentSong) }
        position = snapshot.position
        repeatMode = snapshot.repeatMode
        shuffleEnabled = snapshot.shuffleEnabled
        // Do not autoplay on restore; just prepare the node so a resume() works.
        prepareCurrent()
    }
}
