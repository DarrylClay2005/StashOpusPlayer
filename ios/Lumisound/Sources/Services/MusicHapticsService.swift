import CoreHaptics
import Foundation

/// Provides an audio-reactive haptic accompaniment for local/engine playback.
///
/// Apple Music's Music Haptics patterns are not a public third-party API. This
/// service uses the same public Core Haptics framework available to apps.
/// Its PRIMARY signal is `BeatGridAnalyzerService`'s full-track offline onset
/// analysis — the same "analyze the whole track up front" approach Apple
/// Music's own Music Haptics uses — so playback fires a transient at every
/// beat the analysis actually found, not just whatever a live 60Hz
/// rise-over-threshold check happens to notice in the moment (which misses
/// hits under a sustained pad/bassline, or ones below a fixed global
/// threshold during a quiet passage). The live analyzer's energy is still
/// used to shape each transient's intensity/sharpness, so it stays
/// audio-reactive in feel, not a canned pattern.
///
/// The beat grid is only ready once its (short but non-zero) full-track
/// analysis finishes, and a small number of tracks won't decode/analyze at
/// all — for both cases this falls back to the original live-energy
/// heuristic as a last resort, never silently doing nothing.
///
/// Deliberately does not run for the AVPlayer compatibility path: that path
/// bypasses the AVAudioEngine tap, so there is no reliable audio signal to
/// synchronize against.
@MainActor
final class MusicHapticsService {
    static let shared = MusicHapticsService()

    private var engine: CHHapticEngine?
    private var timer: Timer?
    private var previousEnergy: Float = 0
    private var lastTransientDate: Date = .distantPast
    private var isRunning = false

    // MARK: Beat grid state

    private var beatGridTrackURL: URL?
    private var beatGrid: [Double]?
    private var nextBeatIndex = 0
    private var lastSampledPosition: TimeInterval = 0
    private var beatGridLookupTask: Task<Void, Never>?

    var isAvailable: Bool {
        CHHapticEngine.capabilitiesForHardware().supportsHaptics
    }

    private init() {}

    func updatePlayback(enabled: Bool, isPlaying: Bool, engineAvailable: Bool) {
        let shouldRun = enabled && isPlaying && engineAvailable && isAvailable
        if shouldRun {
            startIfNeeded()
        } else {
            stop()
        }
    }

    private func startIfNeeded() {
        guard !isRunning else { return }
        guard let player = AudioPlayerManager.shared,
              player.isPlaying,
              !player.isUsingOpusPlayer else { return }

        guard let hapticEngine = try? CHHapticEngine() else {
            appWarn("Music Haptics unavailable: Core Haptics engine could not be created", category: "audio")
            return
        }

        engine = hapticEngine
        hapticEngine.resetHandler = { [weak self] in
            Task { @MainActor in
                self?.restartAfterEngineReset()
            }
        }
        hapticEngine.stoppedHandler = { [weak self] reason in
            appLog("Music Haptics engine stopped: \(reason)", category: "audio")
            Task { @MainActor in
                self?.isRunning = false
            }
        }
        do {
            try hapticEngine.start()
        } catch {
            appWarn("Music Haptics unavailable: Core Haptics engine failed to start (\(error.localizedDescription))", category: "audio")
            engine = nil
            return
        }

        previousEnergy = 0
        lastTransientDate = .distantPast
        isRunning = true
        AudioVisualizerService.shared.start(for: .musicHaptics)
        timer = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { [weak self] _ in
            self?.sampleAudioEnergy()
        }
        loadBeatGrid(for: player.currentSong)
        appLog("Music Haptics enabled for engine playback", category: "audio")
    }

    /// Kicks off (or reuses the cached result of) full-track beat analysis
    /// for whatever's currently playing. Never blocks playback/haptics
    /// start — `sampleAudioEnergy` uses the live-energy fallback until this
    /// resolves, then hands off to the precise beat grid mid-track.
    private func loadBeatGrid(for song: Song?) {
        guard let url = song?.url else {
            beatGridTrackURL = nil
            beatGrid = nil
            return
        }
        guard beatGridTrackURL != url else { return }
        beatGridTrackURL = url
        beatGrid = nil
        nextBeatIndex = 0
        lastSampledPosition = 0

        beatGridLookupTask?.cancel()
        beatGridLookupTask = Task { [weak self] in
            let grid = await BeatGridAnalyzerService.shared.beatGrid(for: url)
            guard let self, !Task.isCancelled, self.beatGridTrackURL == url else { return }
            self.beatGrid = grid
            self.resyncBeatIndex(to: AudioPlayerManager.shared?.position ?? 0)
            if let grid {
                appLog("Music Haptics: beat grid ready for \"\(url.lastPathComponent)\" — \(grid.count) onset(s)", category: "audio")
            } else {
                appLog("Music Haptics: no beat grid for \"\(url.lastPathComponent)\" — staying on live-energy fallback", category: "audio")
            }
        }
    }

    /// Advances/rewinds `nextBeatIndex` to match `position` — needed after a
    /// seek/scrub/skip, or once the beat grid first becomes available
    /// partway through a track that's already playing.
    private func resyncBeatIndex(to position: TimeInterval) {
        guard let beatGrid else { return }
        nextBeatIndex = beatGrid.firstIndex(where: { $0 >= position }) ?? beatGrid.count
    }

    private func restartAfterEngineReset() {
        guard isRunning else { return }
        try? engine?.start()
    }

    private func stop() {
        guard isRunning || timer != nil else { return }
        timer?.invalidate()
        timer = nil
        AudioVisualizerService.shared.stop(for: .musicHaptics)
        engine?.stop()
        engine = nil
        isRunning = false
        previousEnergy = 0
        beatGridLookupTask?.cancel()
        beatGridLookupTask = nil
        beatGridTrackURL = nil
        beatGrid = nil
        nextBeatIndex = 0
        lastSampledPosition = 0
    }

    private func sampleAudioEnergy() {
        guard let player = AudioPlayerManager.shared,
              player.isPlaying,
              !player.isUsingOpusPlayer else {
            stop()
            return
        }

        if player.currentSong?.url != beatGridTrackURL {
            loadBeatGrid(for: player.currentSong)
        }

        let analyzer = AudioVisualizerService.shared
        // Bass is weighted slightly higher because it produces the most
        // intelligible tactile pulse while keeping vocals and cymbals present.
        let energy = min(
            1,
            max(0, analyzer.bassLevel * 0.45 + analyzer.midLevel * 0.35 + analyzer.trebleLevel * 0.20)
        )

        if let beatGrid, !beatGrid.isEmpty {
            fireBeatGridTransients(position: player.position, beatGrid: beatGrid, energy: energy, analyzer: analyzer)
        } else {
            fireLiveEnergyTransient(energy: energy, analyzer: analyzer)
        }
    }

    /// Primary path: fires exactly at each precomputed onset the full-track
    /// analysis found, as playback position crosses it — not a live guess.
    /// Handles seeks/scrubs (including looping back to an earlier point)
    /// by detecting a position jump that doesn't match ordinary forward
    /// playback and resyncing the index rather than firing every beat
    /// between the old and new position all at once.
    private func fireBeatGridTransients(position: TimeInterval, beatGrid: [Double], energy: Float, analyzer: AudioVisualizerService) {
        defer { lastSampledPosition = position }

        let forwardDelta = position - lastSampledPosition
        // A jump bigger than a couple of poll intervals, or moving backward,
        // means a seek/loop/track-relative scrub happened — resync instead
        // of treating every intervening beat timestamp as "just crossed".
        if forwardDelta < 0 || forwardDelta > 0.5 {
            resyncBeatIndex(to: position)
        }

        while nextBeatIndex < beatGrid.count, beatGrid[nextBeatIndex] <= position {
            emitTransient(energy: energy, analyzer: analyzer)
            nextBeatIndex += 1
        }
    }

    /// Fallback path — the original real-time rise-over-threshold heuristic,
    /// used only until the beat grid is ready or for the rare track that
    /// couldn't be analyzed at all (never silently produces nothing).
    private func fireLiveEnergyTransient(energy: Float, analyzer: AudioVisualizerService) {
        let rise = energy - previousEnergy
        previousEnergy = previousEnergy * 0.82 + energy * 0.18

        // A transient is emitted only for a meaningful onset and is rate
        // limited so sustained bass does not become an unpleasant buzz.
        let now = Date()
        guard energy > 0.10,
              rise > 0.035,
              now.timeIntervalSince(lastTransientDate) >= 0.11 else { return }
        lastTransientDate = now
        emitTransient(energy: energy, analyzer: analyzer)
    }

    private func emitTransient(energy: Float, analyzer: AudioVisualizerService) {
        let intensity = min(1, max(0.15, 0.22 + energy * 0.78))
        let sharpness = min(1, max(0, 0.18 + analyzer.trebleLevel * 0.55))
        let parameters = [
            CHHapticEventParameter(
                parameterID: .hapticIntensity,
                value: intensity
            ),
            CHHapticEventParameter(
                parameterID: .hapticSharpness,
                value: sharpness
            )
        ]
        let event = CHHapticEvent(eventType: .hapticTransient, parameters: parameters, relativeTime: 0)
        guard let pattern = try? CHHapticPattern(events: [event], parameters: []),
              let hapticEngine = engine,
              let hapticPlayer = try? hapticEngine.makePlayer(with: pattern) else { return }
        try? hapticPlayer.start(atTime: CHHapticTimeImmediate)
    }
}
