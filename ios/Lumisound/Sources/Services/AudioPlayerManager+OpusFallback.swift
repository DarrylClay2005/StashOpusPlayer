@preconcurrency import AVFoundation
import AudioToolbox
import Foundation
import MediaPlayer
import UIKit

extension AudioPlayerManager {

    // MARK: - AVPlayer fallback (Opus / WebM / OGG)

    /// Records an AVPlayer load/playback failure and either advances to the next track or, if
    /// failures are arriving in a tight loop (4+ within 5 seconds — e.g. a stale stream URL that
    /// fails instantly and `repeatMode == .one`/`.all` keeps re-triggering the same failure),
    /// stops playback entirely instead of spinning forever.
    func handleLoadFailure(message: String, userFacingMessage: String) {
        appError(message, category: "audio")
        tearDownOpusPlayer()
        isPlaying = false
        errorMessage = userFacingMessage

        let now = Date()
        recentLoadFailureTimestamps.append(now)
        recentLoadFailureTimestamps.removeAll { now.timeIntervalSince($0) > 5 }

        if recentLoadFailureTimestamps.count >= 4 {
            recentLoadFailureTimestamps.removeAll()
            appError("Stopping playback after repeated track-load failures in a short window", category: "audio")
            errorMessage = "Playback stopped after repeated errors."
            stop()
            return
        }

        skipToNext()
    }

    /// `error?.localizedDescription` alone is frequently a useless generic
    /// string ("The operation could not be completed") that doesn't say
    /// *why* — the actually-informative reason usually sits one level down
    /// in `NSUnderlyingErrorKey` (e.g. a specific `NSURLErrorDomain` code
    /// like -1100 "resource unavailable" for an expired stream URL, or
    /// -1009 "offline"). Walking that chain is what made this class of
    /// failure undiagnosable from the DB event log alone up to now — every
    /// occurrence just said the same unhelpful generic sentence.
    static func describeLoadError(_ error: Error?) -> String {
        guard let error else { return "unknown error" }
        let nsError = error as NSError
        var parts = ["\(nsError.domain) \(nsError.code): \(nsError.localizedDescription)"]
        var underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
        while let inner = underlying {
            parts.append("\(inner.domain) \(inner.code): \(inner.localizedDescription)")
            underlying = inner.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return parts.joined(separator: " ← ")
    }

    /// Used when AVAssetReader/AVAssetExportSession cannot decode the file (e.g. Ogg/Opus container).
    /// AVPlayer has access to iOS's full codec pipeline and can always play .opus files.
    /// Basic play/pause/seek/volume/speed work (speed via `.rate` + `.spectral`
    /// pitch algorithm — see `applyAudioSettings`). EQ, pitch shift, ReplayGain,
    /// 8D, crossfade, gapless, and reverb need the AVAudioEngine graph and do not apply.
    func scheduleWithOpusPlayer(url: URL, startTime: TimeInterval) {
        tearDownOpusPlayer()

        // Stop any engine nodes that were started optimistically in playCurrent().
        primaryNode.stop()
        secondaryNode.stop()

        let item   = AVPlayerItem(url: url)
        // Pitch-preserving time stretch — without this, AVPlayer's default
        // `.varispeed` algorithm ties pitch to rate (chipmunk/slow-mo effect),
        // which made the Speed slider feel "broken" for streamed/opus tracks.
        item.audioTimePitchAlgorithm = .spectral
        let player = AVPlayer(playerItem: item)
        player.volume = audioSettings.volume
        opusPlayer = player

        // Load duration asynchronously (AVPlayerItem duration may be unknown at creation).
        Task { [weak self] in
            guard let self else { return }
            let asset = item.asset
            if let dur = try? await asset.load(.duration), !dur.seconds.isNaN, dur.seconds > 0 {
                self.duration = dur.seconds
                self.updateNowPlaying()
            }
        }

        // Position tracking — replaces the AVAudioEngine timer path.
        opusTimeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            self.position = time.seconds
            // AB Repeat
            if self.abRepeatEnabled,
               let start = self.abRepeatStart,
               let end   = self.abRepeatEnd,
               time.seconds >= end {
                self.opusPlayer?.seek(to: CMTime(seconds: start, preferredTimescale: 600))
                self.position = start
            }
            // Keep lock screen / Apple Watch elapsed time in sync (see timerTick).
            self.updateNowPlaying()
        }

        // Track completion → advances to next song normally.
        opusEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleTrackEnded() }
        }

        if startTime > 0 {
            player.seek(to: CMTime(seconds: startTime, preferredTimescale: 600))
        }

        // Detect AVPlayer item failures (e.g. expired stream URL, unsupported format).
        opusStatusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard let self else { return }
            if item.status == .failed {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let detail = Self.describeLoadError(item.error)
                    self.handleLoadFailure(
                        message: "AVPlayer failed to load track — skipping. \(detail)",
                        userFacingMessage: "Could not play this track."
                    )
                }
            } else if item.status == .readyToPlay {
                Task { @MainActor [weak self] in
                    self?.recentLoadFailureTimestamps.removeAll()
                }
            }
        }

        opusFailObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let err = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.handleLoadFailure(
                    message: "AVPlayer playback failed — skipping. \(Self.describeLoadError(err))",
                    userFacingMessage: "Playback error."
                )
            }
        }

        // Setting `.rate` directly (rather than `.play()`, which always resumes at
        // 1.0×) both starts playback AND applies the user's chosen Speed setting.
        // Activate the session first — the AVPlayer path bypasses the engine (so
        // `startEngineIfNeeded`'s activation), and the session is no longer
        // activated at launch.
        if isPlaying {
            try? AVAudioSession.sharedInstance().setActive(true)
            player.rate = Float(audioSettings.speed)
        }

        updateNowPlaying()
        appLog("Playing via AVPlayer: \(url.lastPathComponent)", category: "audio")
    }

    func tearDownOpusPlayer() {
        opusStatusObserver?.invalidate()
        opusStatusObserver = nil
        if let obs = opusTimeObserver {
            opusPlayer?.removeTimeObserver(obs)
            opusTimeObserver = nil
        }
        // `addObserver(forName:object:queue:using:)` registers an internal proxy as the
        // observer (not `self`), so `removeObserver(self, name:object:)` never matched
        // anything — both block-based observers below were silently leaking on every
        // track switch. Removing by the captured tokens is the only way to unregister them.
        if let obs = opusEndObserver {
            NotificationCenter.default.removeObserver(obs)
            opusEndObserver = nil
        }
        if let obs = opusFailObserver {
            NotificationCenter.default.removeObserver(obs)
            opusFailObserver = nil
        }
        opusPlayer?.pause()
        opusPlayer = nil
    }
}
