@preconcurrency import AVFoundation
import AudioToolbox
import Foundation
import MediaPlayer
import UIKit

extension AudioPlayerManager {

    // MARK: - Gapless Playback

    /// Pre-schedules the next track on primaryNode immediately after the current segment,
    /// so AVAudioEngine delivers audio without any gap.
    func scheduleGaplessNext() {
        // Never schedule gapless while crossfade is enabled — the two transition
        // strategies would both fire and play two tracks at once.
        guard audioSettings.gaplessEnabled, !audioSettings.crossfadeActive else { return }
        guard let nextSong = peekNextSong(), let nextURL = nextSong.url else { return }
        guard let nextFile = try? AVAudioFile(forReading: nextURL) else { return }

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
