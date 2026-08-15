@preconcurrency import AVFoundation
import AudioToolbox
import Foundation
import MediaPlayer
import UIKit

extension AudioPlayerManager {

    // MARK: - Gapless Playback

    /// Deterministic local cache path(s) for a streamed (http/https) track URL,
    /// matching the naming `downloadAndSchedule`/`prefetchUpcomingStreamIfNeeded`
    /// use — checked across every extension either of those could have landed
    /// on, since the final extension is only "refined" from a default m4a
    /// guess to the real container once a download's Content-Type response is
    /// known. Returns `nil` if nothing's been downloaded/prefetched yet.
    static func cachedStreamFileURL(for url: URL) -> URL? {
        let cacheKey: String = url.absoluteString.data(using: .utf8).map { bytes in
            var hash: UInt64 = 5381
            for byte in bytes { hash = hash &* 31 &+ UInt64(byte) }
            return String(hash, radix: 16)
        } ?? UUID().uuidString
        let tempDir = FileManager.default.temporaryDirectory
        for ext in ["m4a", "webm", "opus", "mp3"] {
            let candidate = tempDir.appendingPathComponent("stream_\(cacheKey).\(ext)")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    /// Pre-schedules the next track on primaryNode immediately after the current segment,
    /// so AVAudioEngine delivers audio without any gap.
    func scheduleGaplessNext() {
        // Never schedule gapless while crossfade is enabled — the two transition
        // strategies would both fire and play two tracks at once.
        guard audioSettings.gaplessEnabled, !audioSettings.crossfadeActive else { return }
        guard let nextSong = peekNextSong(), let nextURL = nextSong.url else { return }

        // Streamed tracks (http/https) can't be read directly by AVAudioFile,
        // which only opens local file paths — resolve to the local cache file
        // `prefetchUpcomingStreamIfNeeded()` downloads ahead of time instead.
        // Previously this called AVAudioFile(forReading:) on the raw remote
        // URL, which silently failed for every http(s) track: gapless never
        // actually armed for a streamed queue (the common case for anyone
        // playing from search/streaming rather than only downloaded/imported
        // files) and playback always fell back to the normal, audibly-gapped
        // transition — reported as "gapless doesn't work".
        let resolvedURL: URL
        if ["http", "https"].contains(nextURL.scheme?.lowercased() ?? "") {
            guard let cached = Self.cachedStreamFileURL(for: nextURL) else {
                // Prefetch hasn't finished yet (or never started) — nothing to
                // schedule gaplessly this pass. The normal (non-gapless) path
                // still plays it correctly, just with the usual transition
                // gap; this gets retried on the next segment-start call.
                return
            }
            resolvedURL = cached
        } else {
            resolvedURL = nextURL
        }

        // See LumisoundExclusiveExtensionService.playableURL's doc comment —
        // a no-op for the cached-stream-download branch above (never
        // `.lms`-marked), but needed for a `.lms`-converted local file.
        guard let nextFile = try? AVAudioFile(forReading: LumisoundExclusiveExtensionService.playableURL(for: resolvedURL)) else { return }

        gaplessScheduled = true
        // Stashed so `handleTrackEnded` can adopt it as the live `audioFile`
        // when this segment actually starts playing.
        pendingGaplessFile = nextFile
        // Reuse the current generation rather than bumping it: this segment is
        // appended to the SAME engine session as the currently-playing segment,
        // whose completion handler captured this same `scheduleGeneration` value
        // and hasn't fired yet. Bumping here would make that still-pending
        // completion's generation check fail when the current track ends,
        // silently dropping `handleTrackEnded()` for that transition — the
        // audio keeps playing gaplessly into this track, but `currentSong`/
        // `currentIndex`/Now Playing/widgets never advance, and the *next*
        // gapless segment never gets scheduled (since that scheduling only
        // happens inside `handleTrackEnded`). The queue then appears "stuck"
        // one track behind what's audibly playing. Only an explicit
        // stop()/reschedule (skip, seek, new track) should invalidate
        // in-flight completions, and those call sites already bump
        // `scheduleGeneration` themselves.
        let gen = scheduleGeneration
        activeNode.scheduleFile(nextFile, at: nil) { [weak self] in
            Task { @MainActor in
                guard let self, self.scheduleGeneration == gen else { return }
                self.handleTrackEnded()
            }
        }
    }
}
