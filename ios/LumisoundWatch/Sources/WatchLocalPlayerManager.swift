import Foundation
import AVFoundation
import WatchKit

// MARK: - WatchLocalPlayerManager
//
// The watch's own, independent playback engine for the standalone "Watch
// Library" flow — deliberately simple (play/pause/seek/skip/queue only, no
// EQ/effects/crossfade) rather than porting the phone's full
// `AudioPlayerManager`. Tracks must already be downloaded to Documents (see
// `download(_:client:)`) before they can be played; standalone playback never
// streams live, which keeps this whole path small and offline-friendly.

@MainActor
final class WatchLocalPlayerManager: NSObject, ObservableObject {
    static let shared = WatchLocalPlayerManager()

    @Published private(set) var queue: [WatchTrack] = []
    @Published private(set) var currentIndex: Int?
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var position: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var downloadedTrackIDs: Set<String> = []
    @Published private(set) var downloadingTrackIDs: Set<String> = []
    @Published var errorMessage: String?

    /// True once a track has been started from the Watch Library this app
    /// session — the view layer (WatchNowPlayingView) uses this to decide
    /// whether it's driving this local player or mirroring the phone.
    var hasActiveTrack: Bool { currentIndex != nil }

    var currentTrack: WatchTrack? {
        guard let currentIndex, queue.indices.contains(currentIndex) else { return nil }
        return queue[currentIndex]
    }

    private var player: AVAudioPlayer?
    private var progressTimer: Timer?
    private var extendedSession: WKExtendedRuntimeSession?

    private override init() {
        super.init()
        configureAudioSession()
        refreshDownloadedTrackIDs()
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            errorMessage = "Audio session error: \(error.localizedDescription)"
        }
    }

    // MARK: - Local storage

    private var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private func localFileURL(for track: WatchTrack) -> URL {
        documentsDirectory.appendingPathComponent("track_\(track.id).\(track.ext)")
    }

    func isDownloaded(_ track: WatchTrack) -> Bool {
        downloadedTrackIDs.contains(track.id)
    }

    /// Re-scans Documents for previously-downloaded tracks (e.g. after relaunch).
    func refreshDownloadedTrackIDs() {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: documentsDirectory.path) else { return }
        let ids = files.compactMap { name -> String? in
            guard name.hasPrefix("track_") else { return nil }
            let stem = (name as NSString).deletingPathExtension
            return String(stem.dropFirst("track_".count))
        }
        downloadedTrackIDs = Set(ids)
    }

    func download(_ track: WatchTrack, client: WatchBridgeClient) async {
        guard !isDownloaded(track) else { return }
        downloadingTrackIDs.insert(track.id)
        defer { downloadingTrackIDs.remove(track.id) }
        do {
            let data = try await client.downloadData(for: track)
            try data.write(to: localFileURL(for: track), options: .atomic)
            downloadedTrackIDs.insert(track.id)
        } catch {
            errorMessage = (error as? WatchBridgeError)?.message ?? error.localizedDescription
        }
    }

    func deleteDownload(_ track: WatchTrack) {
        try? FileManager.default.removeItem(at: localFileURL(for: track))
        downloadedTrackIDs.remove(track.id)
        if currentTrack?.id == track.id { stop() }
    }

    // MARK: - Playback

    /// Starts playing `tracks[startAt]` — that track must already be
    /// downloaded (see `download(_:client:)`); the caller (WatchLibraryView)
    /// downloads on demand before calling this.
    func play(queue tracks: [WatchTrack], startAt index: Int) {
        queue = tracks
        currentIndex = index
        playCurrentTrack()
    }

    private func playCurrentTrack() {
        guard let track = currentTrack, isDownloaded(track) else {
            errorMessage = "Track isn't downloaded yet"
            return
        }
        do {
            let newPlayer = try AVAudioPlayer(contentsOf: localFileURL(for: track))
            newPlayer.delegate = self
            newPlayer.prepareToPlay()
            newPlayer.play()
            player = newPlayer
            isPlaying = true
            duration = newPlayer.duration
            position = 0
            beginExtendedSessionIfNeeded()
            startProgressTimer()
            pushNowPlayingToWidget()
        } catch {
            errorMessage = "Playback failed: \(error.localizedDescription)"
        }
    }

    func togglePlayPause() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
        pushNowPlayingToWidget()
    }

    func skipNext() {
        guard let currentIndex, currentIndex + 1 < queue.count else { return }
        let nextIndex = currentIndex + 1
        guard isDownloaded(queue[nextIndex]) else {
            errorMessage = "Next track isn't downloaded yet"
            return
        }
        self.currentIndex = nextIndex
        playCurrentTrack()
    }

    func skipPrevious() {
        guard let currentIndex else { return }
        // Standard transport convention: restart the current track if more
        // than a few seconds in, otherwise go to the previous track.
        if position > 3 {
            seek(to: 0)
            return
        }
        let prevIndex = currentIndex - 1
        guard prevIndex >= 0, isDownloaded(queue[prevIndex]) else { return }
        self.currentIndex = prevIndex
        playCurrentTrack()
    }

    func seek(to time: TimeInterval) {
        player?.currentTime = time
        position = time
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        progressTimer?.invalidate()
        progressTimer = nil
        endExtendedSession()
    }

    private func startProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let player = self.player else { return }
                self.position = player.currentTime
            }
        }
    }

    private func pushNowPlayingToWidget() {
        guard let track = currentTrack else {
            WatchWidgetDataService.clear()
            return
        }
        WatchWidgetDataService.update(title: track.title, artist: track.artist, isPlaying: isPlaying)
    }

    // MARK: - WKExtendedRuntimeSession (background audio)
    //
    // NEEDS ON-DEVICE XCODE VERIFICATION: the primary, well-established
    // mechanism for background audio on watchOS is the same as iOS —
    // `WKBackgroundModes` containing `"audio"` in Info.plist (not added here;
    // see the task report) plus an active `AVAudioSession` in the `.playback`
    // category (configured in `configureAudioSession()` above), which lets
    // the system treat this app as a backgroundable Now Playing audio app.
    // `WKExtendedRuntimeSession`'s documented session types
    // (`.mindfulness`/`.physicalTherapy`/`.carPlay`/generic) don't include an
    // explicit "audio" case on every SDK version — this is used here as a
    // best-effort supplementary keep-alive only. If Xcode flags this
    // constructor/session type as unavailable or unnecessary, it's safe to
    // delete this block entirely and rely on the AVAudioSession + Info.plist
    // background mode alone.
    private func beginExtendedSessionIfNeeded() {
        guard extendedSession == nil else { return }
        let session = WKExtendedRuntimeSession()
        session.delegate = self
        session.start()
        extendedSession = session
    }

    private func endExtendedSession() {
        extendedSession?.invalidate()
        extendedSession = nil
    }
}

// MARK: - AVAudioPlayerDelegate

extension WatchLocalPlayerManager: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            guard let currentIndex = self.currentIndex,
                  currentIndex + 1 < self.queue.count,
                  self.isDownloaded(self.queue[currentIndex + 1]) else {
                self.stop()
                return
            }
            self.skipNext()
        }
    }
}

// MARK: - WKExtendedRuntimeSessionDelegate

extension WatchLocalPlayerManager: WKExtendedRuntimeSessionDelegate {
    nonisolated func extendedRuntimeSession(
        _ extendedRuntimeSession: WKExtendedRuntimeSession,
        didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
        error: Error?
    ) {}

    nonisolated func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {}

    nonisolated func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {}
}
