@preconcurrency import AVFoundation
import AudioToolbox
import Foundation
import MediaPlayer
import UIKit

extension AudioPlayerManager {

    // MARK: - Queue Management

    /// Drag-reorder support (e.g. List onMove).
    func moveQueueItem(from source: IndexSet, to destination: Int) {
        // Capture the current song id before mutation so we can re-anchor currentIndex.
        let currentSongID = currentSong?.id
        queue.move(fromOffsets: source, toOffset: destination)
        if let id = currentSongID,
           let newIndex = queue.firstIndex(where: { $0.id == id }) {
            currentIndex = newIndex
        }
    }

    /// Swipe-to-delete support.
    func removeFromQueue(at offsets: IndexSet) {
        let currentSongID = currentSong?.id
        queue.remove(atOffsets: offsets)
        guard !queue.isEmpty else { stop(); return }
        if let id = currentSongID,
           let newIndex = queue.firstIndex(where: { $0.id == id }) {
            currentIndex = newIndex
        } else {
            // Current song was removed; clamp index and move on.
            currentIndex = min(currentIndex, queue.count - 1)
            currentSong = queue[currentIndex]
            gaplessScheduled = false
            pendingNextIndex = nil
            playCurrent(from: 0)
        }
    }

    /// Insert a song to play immediately after the current track.
    func insertNext(song: Song) {
        let insertionIndex = currentIndex + 1
        if insertionIndex >= queue.count {
            queue.append(song)
        } else {
            queue.insert(song, at: insertionIndex)
        }
    }

    /// Append a song to the end of the queue without affecting current playback.
    func appendToQueue(song: Song) {
        queue.append(song)
    }

    /// Clears the auto-radio seed after the LumisoundApp observer has handled it.
    func clearAutoRadioSeed() {
        autoRadioSeed = nil
    }
    // MARK: - Queue Helpers

    /// Resolves which queue index plays after `currentIndex`, WITHOUT mutating any state.
    /// Shuffle reorders `queue` itself when enabled (see `shuffleQueue`), so the
    /// upcoming index is always just the next sequential slot — keeping this in sync
    /// with what the Up Next/Queue UI displays.
    func resolveNextIndex() -> Int? {
        guard !queue.isEmpty else { return nil }
        if repeatMode == .one { return currentIndex }
        let nextIndex = currentIndex + 1
        if nextIndex < queue.count { return nextIndex }
        if repeatMode == .all { return 0 }
        return nil
    }

    func peekNextSong() -> Song? {
        guard let nextIndex = resolveNextIndex() else {
            pendingNextIndex = nil
            return nil
        }
        pendingNextIndex = nextIndex
        return queue[nextIndex]
    }

    /// Best-effort background download of the *upcoming* queue item's stream
    /// into the exact temp-cache path `downloadAndSchedule` checks before
    /// downloading — so by the time playback reaches it, the file is already
    /// local and starts instantly instead of opening with a fresh multi-second
    /// network download (the audible "gap" streamed YouTube/SoundCloud tracks
    /// have that local files don't, and the dominant remaining playback-feel
    /// issue once gapless/crossfade are handled for local files).
    ///
    /// Deliberately a self-contained duplicate of `downloadAndSchedule`'s
    /// cache-key/extension logic rather than a refactor of it: this is purely
    /// additive and best-effort (wrapped in `try?`, every failure silently
    /// no-ops), so it can never regress the existing, carefully-tuned download
    /// path — at worst a mismatch just means the upcoming track downloads
    /// normally when its turn comes, exactly as it does today.
    func prefetchUpcomingStreamIfNeeded() {
        guard let nextIndex = resolveNextIndex(), queue.indices.contains(nextIndex) else { return }
        let nextSong = queue[nextIndex]
        guard nextSong.id != currentSong?.id,
              let url = nextSong.url,
              ["http", "https"].contains(url.scheme?.lowercased() ?? "")
        else { return }

        let headers = nextSong.httpHeaders
        Task.detached(priority: .utility) {
            let cacheKey: String = url.absoluteString.data(using: .utf8).map { bytes in
                var hash: UInt64 = 5381
                for byte in bytes { hash = hash &* 31 &+ UInt64(byte) }
                return String(hash, radix: 16)
            } ?? UUID().uuidString

            let urlPath = url.path.lowercased()
            var ext: String
            if urlPath.contains("audio/webm") || urlPath.hasSuffix(".webm") || urlPath.contains("mime=audio%2fwebm") {
                ext = "webm"
            } else if urlPath.hasSuffix(".opus") || urlPath.contains("mime=audio%2fogg") {
                ext = "opus"
            } else if urlPath.hasSuffix(".mp3") {
                ext = "mp3"
            } else {
                ext = "m4a"
            }

            let tempDir = FileManager.default.temporaryDirectory
            var tempURL = tempDir.appendingPathComponent("stream_\(cacheKey).\(ext)")
            guard !FileManager.default.fileExists(atPath: tempURL.path) else { return }

            var req = URLRequest(url: url)
            req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148", forHTTPHeaderField: "User-Agent")
            req.timeoutInterval = 60
            if let headers {
                for (field, value) in headers { req.setValue(value, forHTTPHeaderField: field) }
            }

            guard let (downloaded, response) = try? await URLSession.shared.download(for: req) else { return }

            if ext == "m4a", let ct = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") {
                if ct.contains("webm") { ext = "webm" }
                else if ct.contains("ogg") || ct.contains("opus") { ext = "opus" }
                else if ct.contains("mpeg") { ext = "mp3" }
                tempURL = tempDir.appendingPathComponent("stream_\(cacheKey).\(ext)")
            }

            guard !FileManager.default.fileExists(atPath: tempURL.path) else {
                try? FileManager.default.removeItem(at: downloaded)
                return
            }
            try? FileManager.default.moveItem(at: downloaded, to: tempURL)
        }
    }

    func advanceIndex() {
        guard !queue.isEmpty else { return }
        if repeatMode == .one { return }
        // Prefer the index that was actually resolved (and scheduled/crossfaded to)
        // by the most recent `peekNextSong()` — re-resolving here would let shuffle
        // mode land on a different song than the audio that's already playing.
        let nextIndex: Int
        if let pending = pendingNextIndex, queue.indices.contains(pending) {
            nextIndex = pending
        } else if let resolved = resolveNextIndex() {
            nextIndex = resolved
        } else {
            return
        }
        currentIndex = nextIndex
        currentSong = queue[currentIndex]
        pendingNextIndex = nil
    }
}
