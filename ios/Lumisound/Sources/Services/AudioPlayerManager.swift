@preconcurrency import AVFoundation
import AudioToolbox
import Foundation
import MediaPlayer
import UIKit

// MARK: - PlaybackProgress

/// Holds just the high-frequency playback position/duration values, observed
/// separately from the rest of `AudioPlayerManager`'s `@Published` state. Any
/// `@Published` change on an `ObservableObject` fires `objectWillChange` for the
/// WHOLE object, forcing every view holding it (e.g. via `@EnvironmentObject`) to
/// re-evaluate its `body` — regardless of which property that view actually reads.
/// Position/duration tick every 0.25–0.5s while playing, and `MiniPlayerBar` (which
/// only needs `currentSong`/`isPlaying`) is mounted on most screens simultaneously,
/// so publishing them directly on `AudioPlayerManager` was cascading re-renders
/// app-wide. Views that need live progress (the mini-player's progress bar, the
/// Now Playing scrubbers, the lyrics sync editor) observe this lightweight object
/// instead, so the high-frequency updates stay scoped to just those views.
@MainActor
final class PlaybackProgress: ObservableObject {
    @Published var position: TimeInterval = 0
    @Published var duration: TimeInterval = 0
}

// MARK: - AudioPlayerManager

@MainActor
final class AudioPlayerManager: ObservableObject {

    // MARK: Published State

    @Published private(set) var currentSong: Song? {
        didSet {
            if currentSong?.id != oldValue?.id {
                Task { await updateNowPlayingArtwork(for: currentSong) }
                applyTrackAudioSettings(previousID: oldValue?.id)
                pushPlaybackStateToBridge()
                scheduleHistoryLog()
            }
        }
    }
    @Published private(set) var queue: [Song] = [] {
        didSet {
            pushQueueToBridge()
        }
    }
    @Published private(set) var currentIndex = 0
    @Published private(set) var isPlaying = false {
        didSet {
            guard isPlaying != oldValue else { return }
            WidgetDataService.shared.updatePlayState(isPlaying: isPlaying, position: position, duration: duration)
            pushPlaybackStateToBridge()
        }
    }
    /// Backing store for `position`/`duration` — see `PlaybackProgress` for why
    /// these are split out instead of `@Published` directly on this object. Every
    /// internal read/write site (`position = 0`, `duration > 0`, etc.) keeps
    /// working unchanged since these remain plain gettable/settable properties.
    let progress = PlaybackProgress()

    var position: TimeInterval {
        get { progress.position }
        set { progress.position = newValue }
    }
    var duration: TimeInterval {
        get { progress.duration }
        set { progress.duration = newValue }
    }
    @Published var repeatMode: RepeatMode = .off
    @Published var shuffleEnabled = false
    /// Queue order captured before shuffle was enabled, so it can be restored
    /// when shuffle is turned off again.
    private var preShuffleQueue: [Song]?
    @Published var audioSettings = AudioSettings() {
        didSet {
            applyAudioSettings()
            guard !isSwitchingTrack else { return }
            if isUsingTrackAudioSettings, let id = currentSong?.id {
                perTrackAudioSettings[id] = audioSettings
                PersistenceService.shared.saveTrackAudioSettings(perTrackAudioSettings)
                onTrackAudioSettingsChanged?()
            } else {
                defaultAudioSettings = audioSettings
            }
        }
    }

    /// The user's global/default audio settings — applied to any track that
    /// doesn't have its own saved per-track override. Mirrors `audioSettings`
    /// except while a per-track override (or a programmatic track switch) is active.
    private(set) var defaultAudioSettings = AudioSettings()

    /// Per-track audio settings overrides, keyed by `Song.id`. Loaded from disk
    /// at init and kept in sync with `PersistenceService` on every change.
    @Published private(set) var perTrackAudioSettings: [String: AudioSettings] = PersistenceService.shared.loadTrackAudioSettings()

    /// Whether the currently playing track has a saved per-track override active
    /// (i.e. `audioSettings` reflects that track's own settings, not the global default).
    @Published private(set) var isUsingTrackAudioSettings = false

    /// Suppresses the `audioSettings` didSet's save-as-default/save-per-track logic
    /// while `applyTrackAudioSettings` is itself assigning `audioSettings` during a
    /// track switch — that assignment reflects a *recall* of previously saved
    /// settings, not a new user edit, and must not overwrite the saved values.
    private var isSwitchingTrack = false

    /// Notifies observers (used by `LumisoundApp` to push to the backend)
    /// whenever the per-track settings map changes.
    var onTrackAudioSettingsChanged: (() -> Void)?

    /// Wired up by `LumisoundApp` at launch so the player can resolve BPM for
    /// the current/next track (via `LibraryManager.bpm(for:)`) to drive
    /// beat-aware crossfades. `weak` since `LibraryManager` owns the player's
    /// environment lifetime, not the other way around.
    weak var libraryManager: LibraryManager?

    @Published var errorMessage: String?

    // Auto-Radio
    @Published var autoRadioEnabled: Bool = UserDefaults.standard.bool(forKey: "autoRadio_enabled") {
        didSet { UserDefaults.standard.set(autoRadioEnabled, forKey: "autoRadio_enabled") }
    }
    @Published private(set) var autoRadioSeed: Song? = nil

    // AB Repeat
    @Published var abRepeatEnabled: Bool = false
    @Published var abRepeatStart: TimeInterval? = nil
    @Published var abRepeatEnd: TimeInterval? = nil

    // MARK: Private — Engine

    private let engine = AVAudioEngine()

    private let primaryNode = AVAudioPlayerNode()
    private let secondaryNode = AVAudioPlayerNode()
    // Per-node pitch-preserving time stretchers, sitting between each player
    // node and `crossfadeMixer`. `.rate` is 1.0 (transparent passthrough)
    // outside of crossfades; `beginCrossfade` nudges these toward each
    // other's tempo for "beatmatched" overlaps. Separate from the shared
    // `timePitch` below, which applies the user's global speed/pitch settings
    // to the final mixed output.
    private let primaryBeatMatch = AVAudioUnitTimePitch()
    private let secondaryBeatMatch = AVAudioUnitTimePitch()
    // Dedicated mixer so both player nodes can connect to a single effects chain.
    private let crossfadeMixer = AVAudioMixerNode()

    private let timePitch = AVAudioUnitTimePitch()
    private let equalizer = AVAudioUnitEQ(numberOfBands: 10)
    // Real-room reverb — sits after the EQ, before the limiter, so any wet
    // signal it adds still gets caught by the limiter instead of clipping.
    private let reverb = AVAudioUnitReverb()
    // Tracks which factory preset is currently loaded on `reverb` so
    // `applyAudioSettings` only calls `loadFactoryPreset` (a relatively heavy
    // call) when the user's chosen preset actually changes.
    private var loadedReverbPreset: ReverbRoomPreset?
    // Brick-wall peak limiter placed at the very end of the chain. Lets
    // `audioSettings.volume` boost gain above 100% (up to `maxVolume`) without
    // the boosted signal clipping — the limiter clamps transient peaks instead
    // of letting them hard-clip in `mainMixerNode`.
    private let limiter: AVAudioUnitEffect = {
        var description = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_DynamicsProcessor,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        return AVAudioUnitEffect(audioComponentDescription: description)
    }()

    // MARK: Private — Spatial / Special-Effect Nodes

    private var rotationAngle: Double = 0
    /// The 8D rotation speed in Hz. Persisted across sessions. Published so EffectsView can bind to it.
    @Published var rotationHz: Double = UserDefaults.standard.double(forKey: "8d_rotation_hz") > 0
        ? UserDefaults.standard.double(forKey: "8d_rotation_hz") : 0.18
    private var rotationLink: CADisplayLink?
    private var is8DActive = false

    // Tremolo
    private var tremoloLink: CADisplayLink?
    private var tremoloPhase: Double = 0
    private var tremoloFrequency: Double = 4.0
    private var tremoloDepth: Float = 0.45
    private var isTremoloActive = false

    // Vibrato
    private var vibratoLink: CADisplayLink?
    private var vibratoPhase: Double = 0
    private var vibratoFrequency: Double = 4.5
    private var vibratoDepth: Double = 0.35  // semitones
    private var isVibratoActive = false
    private var vibratoBasePitch: Float = 0  // captures audioSettings.pitchSemitones at start

    // Karaoke
    private var isKaraokeActive = false

    // Tracks which player node currently owns the active song.
    // Flips after each crossfade so the two nodes alternate roles.
    private var usingPrimaryNode = true

    // The node playing (or scheduled for) the current song. `usingPrimaryNode` flips
    // to the incoming node the instant a crossfade begins (see beginCrossfade) — at
    // the same moment currentSong/duration/audioFile switch — so this can resolve
    // the same way regardless of crossfade state and never disagrees with "now playing".
    private var activeNode: AVAudioPlayerNode {
        usingPrimaryNode ? primaryNode : secondaryNode
    }

    // MARK: Private — Playback Bookkeeping

    private var audioFile: AVAudioFile?
    private var fileStartFrame: AVAudioFramePosition = 0
    private var timer: Timer?
    private var isEngineConfigured = false

    /// The AVAudioFile pre-scheduled by `scheduleGaplessNext` for the next
    /// gapless hand-off, stashed so `handleTrackEnded` can adopt it as the new
    /// `audioFile` the instant that track starts playing (otherwise position/
    /// duration would keep reflecting the track that just ended).
    private var pendingGaplessFile: AVAudioFile?

    /// The active node's render-clock sample time at the moment the current
    /// gapless segment began. A gapless hand-off appends the next file to the
    /// SAME continuously-playing node, so `playerTime.sampleTime` keeps
    /// accumulating across tracks instead of resetting to 0 — without
    /// subtracting this baseline, `updatePositionFromPlayer` would compute the
    /// new track's position from the cumulative frame count (clamped to the new
    /// duration), freezing the Now Playing scrubber/MiniPlayer progress. Reset
    /// to 0 on every fresh (stop()+play()) schedule, where the node's clock
    /// really does restart at 0.
    private var gaplessBaseFrame: Double = 0

    // ReplayGain: linear gain factor derived from the current track's metadata/RMS analysis
    // (see the `replayGainEnabled` block in scheduleCurrent/transcodeAndSchedule). Reset to
    // neutral (1.0) whenever a new track is scheduled, then refined once analysis completes.
    // `applyAudioSettings` reads this — rather than applying its own separate formula — so a
    // mid-track volume/EQ/speed tweak (which re-invokes applyAudioSettings via the
    // `audioSettings` didSet) recombines the SAME per-track gain with the new volume instead
    // of clobbering it with an unrelated flat value, which previously made ReplayGain's
    // effective loudness depend on the race between the analysis Task and settings changes.
    private var replayGainLinearGain: Float = 1.0

    // Crossfade state
    private var isCrossfading = false
    private var crossfadeTimer: Timer?
    // Fires crossfadeDuration seconds before a track ends so we begin fading early.
    private var crossfadeStartTimer: Timer?

    /// BPM lookups resolved via `libraryManager?.bpm(for:)`, keyed by song ID.
    /// Populated ahead of time by `prewarmBPM` so `beginCrossfade` can read a
    /// tempo synchronously without blocking the fade on analysis.
    private var bpmCache: [String: Double] = [:]

    // Gapless: the next file pre-loaded and scheduled on the active node.
    private var gaplessScheduled = false

    // The queue index resolved by `peekNextSong()` at the moment a gapless file
    // was scheduled or a crossfade began — captured so `advanceIndex()` lands on
    // the SAME song that's actually already playing. Without this, shuffle mode
    // would independently re-roll a random index when the track transition
    // completes, landing on a different song than the one that was scheduled —
    // which is exactly what showed up as "Now Playing doesn't correctly switch
    // to the next song" / "Next Up doesn't update properly" (currentIndex and
    // currentSong would point at two different songs).
    private var pendingNextIndex: Int?

    // Set to true while an async HTTP download + schedule is in progress.
    // Prevents updatePositionFromPlayer() from overwriting `position` with a
    // stale value from the AVAudioPlayerNode before it has actually started.
    private var isSchedulingAsync = false

    // Circuit breaker for AVPlayer load/playback failures. Without this, a track
    // with a stale/expired stream URL fails near-instantly, skipToNext() is
    // called, repeatMode == .one replays the SAME track (or .all/.off cycles
    // through an entire queue of equally-stale URLs), and the failure repeats
    // in a tight loop — observed as ~3,000 "AVPlayer failed to load" errors/minute.
    // If failures happen too fast for too long, stop playback instead of retrying.
    private var recentLoadFailureTimestamps: [Date] = []

    // AVPlayer fallback for containers (e.g. .opus) that AVAssetReader cannot decode.
    // When active, this player owns audio output instead of the AVAudioEngine nodes.
    private var opusPlayer: AVPlayer?
    private var opusTimeObserver: Any?
    private var opusStatusObserver: NSKeyValueObservation?
    private var opusEndObserver: NSObjectProtocol?
    private var opusFailObserver: NSObjectProtocol?

    // Closure-based `addObserver(forName:object:queue:using:)` registers an internal
    // proxy as "the observer" — `removeObserver(self, name:object:)` in `deinit`
    // never matches it (see the `tearDownOpusPlayer` comment for the full
    // explanation). These three must be removed by their captured tokens too.
    private var backgroundObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?
    private var engineConfigChangeObserver: NSObjectProtocol?
    private var isUsingOpusPlayer: Bool { opusPlayer != nil }

    // Schedule generation counter — incremented before every node stop/reschedule.
    // Completion blocks capture the generation at registration time and bail out if it
    // has changed, preventing ghost completions from firing after a seek or skip.
    private var scheduleGeneration: UInt64 = 0

    // Audio interruption / route change
    private var wasInterrupted = false
    // True when playback was auto-paused because the active output route
    // disappeared (e.g. Bluetooth disconnect) — used to auto-resume when a
    // route becomes available again.
    private var pausedByRouteChange = false

    // MARK: Init / Deinit

    init() {
        configureAudioSession()
        configureEngine()
        configureEqualizer()
        configureRemoteCommands()
        restorePlaybackState()

        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.savePlaybackState() }
        }

        // Receive playback control commands posted from the WidgetKit extension.
        DarwinWidgetBridge.shared.addObserver(name: DarwinWidgetBridge.togglePlayback) { [weak self] in
            Task { @MainActor [weak self] in self?.togglePlayPause() }
        }
        DarwinWidgetBridge.shared.addObserver(name: DarwinWidgetBridge.skipNext) { [weak self] in
            Task { @MainActor [weak self] in self?.skipToNext() }
        }
        DarwinWidgetBridge.shared.addObserver(name: DarwinWidgetBridge.skipPrevious) { [weak self] in
            Task { @MainActor [weak self] in self?.skipToPrevious() }
        }
    }

    deinit {
        timer?.invalidate()
        crossfadeTimer?.invalidate()
        crossfadeStartTimer?.invalidate()
        rotationLink?.invalidate()
        tremoloLink?.invalidate()
        vibratoLink?.invalidate()
        // `removeObserver(self)` is a no-op for closure-based registrations below
        // (they're keyed on an internal proxy, not `self`) — must remove by token.
        for token in [backgroundObserver, interruptionObserver, routeChangeObserver, engineConfigChangeObserver, opusEndObserver, opusFailObserver] {
            if let token { NotificationCenter.default.removeObserver(token) }
        }
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.removeTarget(nil)
        center.pauseCommand.removeTarget(nil)
        center.togglePlayPauseCommand.removeTarget(nil)
        center.nextTrackCommand.removeTarget(nil)
        center.previousTrackCommand.removeTarget(nil)
        center.changePlaybackPositionCommand.removeTarget(nil)
    }

    // MARK: - Per-Track Audio Settings

    /// Called whenever `currentSong` changes to a different track. Saves the
    /// outgoing track's settings (if it had a custom override active) and loads
    /// the incoming track's saved override, falling back to the global default.
    private func applyTrackAudioSettings(previousID: String?) {
        if let previousID, isUsingTrackAudioSettings {
            perTrackAudioSettings[previousID] = audioSettings
            PersistenceService.shared.saveTrackAudioSettings(perTrackAudioSettings)
        }

        isSwitchingTrack = true
        if let id = currentSong?.id, let saved = perTrackAudioSettings[id] {
            isUsingTrackAudioSettings = true
            audioSettings = saved
        } else {
            isUsingTrackAudioSettings = false
            audioSettings = defaultAudioSettings
        }
        isSwitchingTrack = false
    }

    /// Saves the current `audioSettings` (EQ, effects, volume, etc.) as a
    /// per-track override for the currently playing song, so they're recalled
    /// automatically the next time this track plays.
    func saveAudioSettingsForCurrentTrack() {
        guard let id = currentSong?.id else { return }
        isUsingTrackAudioSettings = true
        perTrackAudioSettings[id] = audioSettings
        PersistenceService.shared.saveTrackAudioSettings(perTrackAudioSettings)
        onTrackAudioSettingsChanged?()
    }

    /// Removes the saved per-track override for the currently playing song and
    /// reverts playback to the global default settings.
    func clearAudioSettingsForCurrentTrack() {
        guard let id = currentSong?.id, perTrackAudioSettings[id] != nil else { return }
        perTrackAudioSettings.removeValue(forKey: id)
        PersistenceService.shared.saveTrackAudioSettings(perTrackAudioSettings)
        isUsingTrackAudioSettings = false
        isSwitchingTrack = true
        audioSettings = defaultAudioSettings
        isSwitchingTrack = false
        onTrackAudioSettingsChanged?()
    }

    /// Called once at launch to restore the user's global default audio settings
    /// from disk. `restorePlaybackState()` (called earlier, during `init()`) may
    /// already have switched `audioSettings` to a per-track override for the
    /// restored `currentSong` — in that case only `defaultAudioSettings` is
    /// updated here, leaving the active per-track settings in place.
    func restoreDefaultAudioSettings(_ settings: AudioSettings) {
        defaultAudioSettings = settings
        guard !isUsingTrackAudioSettings else { return }
        isSwitchingTrack = true
        audioSettings = settings
        isSwitchingTrack = false
    }

    /// Replaces the entire per-track settings map (used when restoring from a
    /// server sync). If the currently playing track has an override in the new
    /// map, it's applied immediately.
    func restorePerTrackAudioSettings(_ map: [String: AudioSettings]) {
        perTrackAudioSettings = map
        PersistenceService.shared.saveTrackAudioSettings(map)
        if let id = currentSong?.id, let saved = map[id] {
            isUsingTrackAudioSettings = true
            isSwitchingTrack = true
            audioSettings = saved
            isSwitchingTrack = false
        }
    }

    // MARK: - Public Playback Controls

    func setQueue(_ songs: [Song], startIndex: Int = 0, autoplay: Bool = true) {
        guard !songs.isEmpty else { return }
        queue = songs
        currentIndex = min(max(startIndex, 0), songs.count - 1)
        currentSong = queue[currentIndex]
        position = 0
        gaplessScheduled = false
        pendingNextIndex = nil
        // A new queue invalidates any stashed pre-shuffle order from the previous one.
        preShuffleQueue = nil
        if shuffleEnabled {
            shuffleQueue()
        }
        if autoplay {
            playCurrent(from: 0)
        } else {
            prepareCurrent()
        }
        applyAutoEQIfNeeded(bpm: currentSong?.bpm ?? bpmCache[currentSong?.id ?? ""])
    }

    func play(song: Song, in songs: [Song]) {
        let source = songs.isEmpty ? [song] : songs
        let index = source.firstIndex(where: { $0.id == song.id }) ?? 0
        appLog("Play: \"\(song.displayName)\" by \(song.artistName) (\(source.count) in queue)", category: "audio")
        appBreadcrumb("Playing \"\(song.displayName)\"")
        setQueue(source, startIndex: index, autoplay: true)
    }

    func togglePlayPause() {
        if isPlaying { pause() } else { resume() }
    }

    func pause() {
        if isUsingOpusPlayer {
            opusPlayer?.pause()
            isPlaying = false
            updateNowPlaying()
            savePlaybackState()
            return
        }
        updatePositionFromPlayer()
        primaryNode.pause()
        secondaryNode.pause()
        isPlaying = false
        stopTimer()
        updateNowPlaying()
        savePlaybackState()
        appLog("Paused at \(String(format: "%.1f", position))s — \(currentSong?.displayName ?? "?")", category: "audio")
    }

    func resume() {
        if isUsingOpusPlayer {
            // `.play()` always resumes at 1.0× — set `.rate` directly so the
            // user's chosen Speed setting is honored on resume too.
            opusPlayer?.rate = Float(audioSettings.speed)
            isPlaying = true
            updateNowPlaying()
            return
        }
        guard currentSong != nil else {
            if !queue.isEmpty { playCurrent(from: position) }
            return
        }
        if !activeNode.isPlaying {
            startEngineIfNeeded()
            activeNode.play()
            isPlaying = true
            startTimer()
            updateNowPlaying()
            reapplyActiveEffect()
            appLog("Resumed — \(currentSong?.displayName ?? "?")", category: "audio")
        }
    }

    func stop() {
        tearDownOpusPlayer()
        appLog("Stopped — \(currentSong?.displayName ?? "nothing playing")", category: "audio")
        primaryNode.stop()
        secondaryNode.stop()
        isCrossfading = false
        crossfadeTimer?.invalidate()
        crossfadeTimer = nil
        crossfadeStartTimer?.invalidate()
        crossfadeStartTimer = nil
        gaplessScheduled = false
        pendingNextIndex = nil
        position = 0
        isPlaying = false
        stopTimer()
        // Stop any active special effects so their CADisplayLinks don't keep firing.
        stop8DRotation()
        stopTremolo()
        stopVibrato()
        disableKaraoke()
        // Fully release the audio system when stopped — without this the engine
        // kept running and the audio session stayed active with nothing playing
        // (the "ghost audio engine" / app stays an active audio app). The next
        // play() restarts the engine + reactivates the session via
        // `startEngineIfNeeded`. `.notifyOthersOnDeactivation` lets other apps
        // (paused music, etc.) resume.
        if engine.isRunning {
            engine.stop()
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        updateNowPlaying()
    }

    func seek(to newPosition: TimeInterval) {
        let target = max(0, min(newPosition, duration))
        position = target
        if isUsingOpusPlayer {
            opusPlayer?.seek(to: CMTime(seconds: target, preferredTimescale: 600))
            updateNowPlaying()
            return
        }
        gaplessScheduled = false
        pendingNextIndex = nil
        crossfadeStartTimer?.invalidate()
        crossfadeStartTimer = nil
        if isPlaying {
            playCurrent(from: target)
        } else {
            scheduleCurrent(from: target)
        }
        updateNowPlaying()
        pushPlaybackStateToBridge()
    }

    func skipToNext() {
        guard !queue.isEmpty else { return }
        if repeatMode == .one {
            playCurrent(from: 0)
            return
        }

        // Shuffle mode reorders `queue` itself (see toggleShuffle/shuffleQueue) so the
        // Up Next/Queue UI always matches what plays — just advance sequentially here too.
        let nextIndex = currentIndex + 1

        if nextIndex < queue.count {
            currentIndex = nextIndex
            currentSong = queue[currentIndex]
            gaplessScheduled = false
            pendingNextIndex = nil
            appLog("Skip next → \"\(currentSong?.displayName ?? "?")\"", category: "audio")
            playCurrent(from: 0)
            savePlaybackState()
        } else if repeatMode == .all {
            currentIndex = 0
            currentSong = queue[currentIndex]
            gaplessScheduled = false
            pendingNextIndex = nil
            appLog("Skip next (loop) → \"\(currentSong?.displayName ?? "?")\"", category: "audio")
            playCurrent(from: 0)
            savePlaybackState()
        } else {
            if autoRadioEnabled {
                autoRadioSeed = currentSong
            }
            stop()
        }
    }

    func skipToPrevious() {
        guard !queue.isEmpty else { return }
        if position > 4 {
            seek(to: 0)
            return
        }
        currentIndex = max(currentIndex - 1, 0)
        currentSong = queue[currentIndex]
        gaplessScheduled = false
        pendingNextIndex = nil
        playCurrent(from: 0)
        savePlaybackState()
    }

    func cycleRepeatMode() {
        switch repeatMode {
        case .off:  repeatMode = .all
        case .all:  repeatMode = .one
        case .one:  repeatMode = .off
        }
        updateNowPlaying()
    }

    func toggleShuffle() {
        shuffleEnabled.toggle()
        if shuffleEnabled {
            shuffleQueue()
        } else {
            restoreUnshuffledQueue()
        }
        updateNowPlaying()
    }

    /// Reorders `queue` so everything after the currently-playing track is shuffled —
    /// this keeps the Up Next/Queue UI in sync with what `skipToNext()` will actually
    /// play next, and produces a fresh order every time shuffle is turned on (the
    /// previous unshuffled order is stashed so toggling shuffle off can restore it).
    private func shuffleQueue() {
        guard queue.count > 1 else { return }
        if preShuffleQueue == nil {
            preShuffleQueue = queue
        }
        let currentSongID = currentSong?.id
        var rest = queue
        let current = rest.remove(at: currentIndex)
        rest.shuffle()
        let anchorBPM = current.bpm ?? bpmCache[current.id]
        queue = [current] + smartTempoOrder(rest, anchorBPM: anchorBPM)
        currentIndex = queue.firstIndex(where: { $0.id == currentSongID }) ?? 0
        gaplessScheduled = false
        pendingNextIndex = nil
    }

    /// Reorders an already-randomly-shuffled list so tracks with a known BPM
    /// form smoother tempo transitions: each step greedily picks the remaining
    /// known-BPM track closest to the previous track's tempo, avoiding jarring
    /// energetic→sleep whiplash between consecutive songs. Tracks with no
    /// known BPM (not yet analyzed) keep their shuffled relative order and are
    /// interleaved back in at roughly their original positions, so the queue
    /// doesn't degrade into two separate "known" / "unknown" blocks.
    private func smartTempoOrder(_ songs: [Song], anchorBPM: Double?) -> [Song] {
        guard songs.count > 2 else { return songs }

        var withBPM: [(offset: Int, song: Song, bpm: Double)] = []
        var withoutBPM: [(offset: Int, song: Song)] = []
        for (offset, song) in songs.enumerated() {
            if let bpm = song.bpm ?? bpmCache[song.id] {
                withBPM.append((offset, song, bpm))
            } else {
                withoutBPM.append((offset, song))
            }
        }
        guard withBPM.count > 1 else { return songs }

        var remaining = withBPM
        var ordered: [Song] = []
        var lastBPM = anchorBPM ?? remaining[0].bpm

        while !remaining.isEmpty {
            let reference = lastBPM ?? remaining[0].bpm
            let nearestIndex = remaining.indices.min(by: {
                abs(remaining[$0].bpm - reference) < abs(remaining[$1].bpm - reference)
            })!
            let chosen = remaining.remove(at: nearestIndex)
            ordered.append(chosen.song)
            lastBPM = chosen.bpm
        }

        guard !withoutBPM.isEmpty else { return ordered }
        var result = ordered
        for entry in withoutBPM {
            let fraction = Double(entry.offset) / Double(max(songs.count - 1, 1))
            let insertIndex = min(Int((fraction * Double(result.count)).rounded()), result.count)
            result.insert(entry.song, at: insertIndex)
        }
        return result
    }

    /// Restores the queue order captured before shuffle was turned on.
    private func restoreUnshuffledQueue() {
        guard let original = preShuffleQueue else { return }
        let currentSongID = currentSong?.id
        queue = original
        preShuffleQueue = nil
        if let id = currentSongID, let idx = queue.firstIndex(where: { $0.id == id }) {
            currentIndex = idx
        }
        gaplessScheduled = false
        pendingNextIndex = nil
    }

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

    // MARK: - AB Repeat

    func setABStart() {
        abRepeatStart = position
        // If a full region was previously set, disable until user sets a new end.
        if abRepeatEnd != nil { abRepeatEnabled = false }
    }

    func setABEnd() {
        guard let start = abRepeatStart else { return }
        let end = position
        guard end > start else { return }
        abRepeatEnd = end
        abRepeatEnabled = true
    }

    func clearABRepeat() {
        abRepeatEnabled = false
        abRepeatStart = nil
        abRepeatEnd = nil
    }

    // MARK: - Audio Effects

    func applyEffect(_ effect: AudioEffect) {
        appLog("Effect applied: \(effect.name) (id: \(effect.id))", category: "audio")
        // Stop all running special effects before switching to a new one.
        stop8DRotation()
        stopTremolo()
        stopVibrato()
        disableKaraoke()

        // Apply static EQ / speed / pitch settings.
        var s = AudioEffectsService.apply(effect: effect, to: audioSettings)
        s.activeEffectID = effect.id
        audioSettings = s   // triggers didSet → applyAudioSettings()

        // Start the special mode for this effect.
        switch effect.specialMode.type {
        case .rotation:
            start8DRotation(hz: effect.specialMode.hz)
        case .tremolo:
            startTremolo(frequency: effect.specialMode.freq, depth: effect.specialMode.depth)
        case .vibrato:
            startVibrato(frequency: effect.specialMode.freq, depth: effect.specialMode.pitchDepth)
        case .karaoke:
            enableKaraoke(level: effect.specialMode.level)
        case .none:
            break
        }
    }

    /// Re-starts any dynamic effect (8D, tremolo, vibrato, karaoke) that was active before
    /// playback began. Called after the engine starts so CADisplayLink effects actually run.
    private func reapplyActiveEffect() {
        let effectID = audioSettings.activeEffectID
        guard !effectID.isEmpty, effectID != "none",
              let effect = AudioEffectsService.allEffects.first(where: { $0.id == effectID })
        else { return }
        switch effect.specialMode.type {
        case .rotation:
            if !is8DActive { start8DRotation(hz: effect.specialMode.hz) }
        case .tremolo:
            if !isTremoloActive { startTremolo(frequency: effect.specialMode.freq, depth: effect.specialMode.depth) }
        case .vibrato:
            if !isVibratoActive { startVibrato(frequency: effect.specialMode.freq, depth: effect.specialMode.pitchDepth) }
        case .karaoke:
            if !isKaraokeActive { enableKaraoke(level: effect.specialMode.level) }
        case .none:
            break
        }
    }

    // MARK: - EQ Presets

    func applyEQPreset(_ preset: EQPreset) {
        var settings = audioSettings
        settings.eqPreset = preset
        if preset != .custom {
            settings.eqBands = preset.bands
        }
        settings.equalizerEnabled = preset != .flat
        audioSettings = settings   // triggers didSet → applyAudioSettings()
    }

    // MARK: - Persistence

    private let playbackStateKey = "playback_state_v1"

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

    // MARK: - Private Helpers

    private func prepareCurrent() {
        scheduleCurrent(from: position)
        updateNowPlaying()
    }

    private func playCurrent(from startTime: TimeInterval) {
        // Invalidate any pending completion callbacks BEFORE cancelCrossfade() or node.stop()
        // so that the stopped node's completion block never fires handleTrackEnded().
        scheduleGeneration &+= 1
        crossfadeStartTimer?.invalidate()
        crossfadeStartTimer = nil
        cancelCrossfade()
        // Clear before scheduling so failure can be detected below.
        errorMessage = nil

        // Best-effort: get the upcoming streamed track's audio onto disk while
        // this one plays, so its turn doesn't open with a multi-second download
        // stall (the audible "gap" streamed sources have that local files don't).
        prefetchUpcomingStreamIfNeeded()

        // For HTTP/HTTPS URLs the download is async — scheduleCurrent handles the full play
        // flow internally (including calling node.play() after the download completes).
        if let url = currentSong?.url,
           ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            isPlaying = true  // optimistically set — confirmed once download finishes
            startTimer()
            updateNowPlaying()
            scheduleCurrent(from: startTime)  // kicks off async download path
            return
        }

        // Local file — synchronous path.
        scheduleCurrent(from: startTime)
        // scheduleCurrent sets errorMessage on failure; bail out here to avoid a zombie
        // state where isPlaying=true but no audio segment is scheduled on the node.
        guard errorMessage == nil else { return }
        startEngineIfNeeded()
        activeNode.play()
        isPlaying = true
        startTimer()
        updateNowPlaying()
        reapplyActiveEffect()
    }

    /// Resets ReplayGain to neutral at the start of a new track — before that track's own
    /// analysis (the `replayGainEnabled` block further down each scheduling path) computes
    /// its per-track gain — so the previous track's gain can't briefly bleed into this one.
    /// Called only once a file/stream has loaded successfully, so this also doubles as the
    /// reset point for the AVPlayer load-failure circuit breaker (see `handleLoadFailure`).
    private func resetReplayGainForNewTrack() {
        recentLoadFailureTimestamps.removeAll()
        replayGainLinearGain = 1.0
        // Every fresh (stop()+play()) schedule restarts the node's sample clock
        // at 0, so the gapless position baseline must reset too. The gapless
        // hand-off path also calls this, then immediately re-captures the
        // node's cumulative sample time (see `handleTrackEnded`).
        gaplessBaseFrame = 0
        // Re-apply the master volume/boost (and reset ReplayGain's contribution
        // to neutral) so a track change can't leave the previous track's
        // analysed ReplayGain — or a stale boost level — applied to the new one.
        applyOutputGain()
    }

    /// Core scheduler — loads the audio file, seeks to `startTime`, and arms the completion handler
    /// that drives crossfade / gapless / normal track-end logic.
    ///
    /// `fileStartFrame` is always set to the absolute frame corresponding to `startTime`.
    /// When `startTime == 0` this is explicitly 0, which keeps `updatePositionFromPlayer()`
    /// accurate from the very first rendered frame of a new track.
    ///
    /// For HTTP/HTTPS URLs this method returns early after launching an async Task;
    /// `downloadAndSchedule` completes the setup and starts the node once the file is cached.
    private func scheduleCurrent(from startTime: TimeInterval) {
        guard let song = currentSong else { return }
        guard let url = song.url else {
            // URL was cleared (e.g. stale ipod-library:// after app restore) — skip silently.
            // Do not set errorMessage; the user sees the track title with no playback.
            return
        }

        // HTTP URLs must be downloaded to a temp file before AVAudioFile can read them.
        // AVAudioFile only reads local filesystem paths, not HTTP streams.
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == "http" || scheme == "https" {
            Task {
                await downloadAndSchedule(url: url, startTime: startTime)
            }
            return
        }

        // Opus/WebM/OGG containers may not be natively supported by AVAudioFile.
        // Route through AudioEncoderService which tries native open first, then exports to M4A.
        let fileExt = url.pathExtension.lowercased()
        if ["opus", "webm", "ogg"].contains(fileExt) {
            Task { await transcodeAndSchedule(url: url, startTime: startTime) }
            return
        }

        // Local file — schedule directly (native format, no transcoding needed).
        tearDownOpusPlayer()
        do {
            let node = activeNode
            // Increment generation before stopping so the old completion is invalidated.
            let gen = scheduleGeneration &+ 1
            scheduleGeneration = gen
            node.stop()
            let file = try AVAudioFile(forReading: url)
            audioFile = file
            duration = file.duration
            let sampleRate = file.processingFormat.sampleRate
            let startFrame = max(0, AVAudioFramePosition(startTime * sampleRate))
            let framesLeft = max(0, AVAudioFrameCount(file.length - startFrame))
            // Explicitly reset to 0 for new-track starts so the position formula is exact.
            fileStartFrame = startFrame
            position = startTime
            gaplessScheduled = false
            pendingNextIndex = nil
            resetReplayGainForNewTrack()

            node.scheduleSegment(file, startingFrame: startFrame, frameCount: framesLeft, at: nil) { [weak self] in
                Task { @MainActor in
                    guard let self, self.scheduleGeneration == gen else { return }
                    self.handleTrackEnded()
                }
            }

            // Warm the BPM cache for this track and the one queued after it so
            // `beginCrossfade` can read a tempo synchronously once it fires.
            prewarmBPM(for: currentSong)
            prewarmBPM(for: peekNextSong())

            // Schedule crossfade to begin crossfadeDuration seconds before the track ends,
            // so the incoming track fades in while the current track is still playing.
            if audioSettings.crossfadeEnabled && audioSettings.crossfadeDuration > 0 {
                let trackLength = Double(framesLeft) / file.processingFormat.sampleRate
                let crossfadeOffset = max(0, trackLength - audioSettings.crossfadeDuration)
                if crossfadeOffset > 0 {
                    crossfadeStartTimer?.invalidate()
                    crossfadeStartTimer = Timer.scheduledTimer(
                        withTimeInterval: crossfadeOffset, repeats: false
                    ) { [weak self] _ in
                        Task { @MainActor in
                            guard let self, self.isPlaying, !self.isCrossfading else { return }
                            self.beginCrossfade()
                        }
                    }
                }
            }

            // Pre-schedule the next track for gapless playback 0.1 s after this segment
            // starts, giving the engine enough time to buffer it seamlessly.
            //
            // Gapless and crossfade are mutually-exclusive transition strategies:
            // crossfade starts the incoming track on the OTHER node a few seconds
            // early, while gapless queues it on THIS node to start the instant
            // this one ends. With both enabled, the crossfade fires AND the
            // gapless-queued segment also plays — two tracks at once (the
            // "current + next play together" bug). So only arm gapless when
            // crossfade is off.
            if audioSettings.gaplessEnabled && !audioSettings.crossfadeEnabled {
                Task { [weak self] in
                    guard let self else { return }
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    await MainActor.run {
                        guard self.isPlaying,
                              self.audioSettings.gaplessEnabled,
                              !self.audioSettings.crossfadeEnabled,
                              !self.gaplessScheduled else { return }
                        self.scheduleGaplessNext()
                    }
                }
            }

            // ReplayGain: read embedded REPLAYGAIN_TRACK_GAIN tag; fall back to RMS analysis
            // for files without a tag. Runs off the main thread to avoid blocking playback.
            if audioSettings.replayGainEnabled {
                let asset = AVURLAsset(url: url)
                let capturedURL = url
                Task.detached(priority: .utility) { [weak self] in
                    let metadata = (try? await asset.load(.metadata)) ?? []
                    var gainDB: Float? = nil
                    for item in metadata {
                        let id = item.identifier?.rawValue.lowercased() ?? ""
                        if id.contains("replaygain_track_gain") || id.contains("replaygain") {
                            if let str = item.stringValue {
                                // Tag format: "+1.23 dB" or "-1.23 dB"
                                let numeric = str.components(
                                    separatedBy: CharacterSet(
                                        charactersIn: "-+0123456789."
                                    ).inverted
                                ).joined()
                                gainDB = Float(numeric)
                            }
                        }
                    }
                    // No embedded tag: compute RMS gain (returns 0 for unsupported formats).
                    if gainDB == nil {
                        let rms = await NormalizationService.shared.gain(for: capturedURL)
                        if rms != 0 { gainDB = rms }
                    }
                    if let gain = gainDB {
                        await MainActor.run { [weak self] in
                            guard let self else { return }
                            let linear = pow(10.0, gain / 20.0)
                            self.replayGainLinearGain = linear
                            // Re-derive the output gain split (mixer attenuation +
                            // EQ globalGain boost) now that ReplayGain's contribution
                            // is known.
                            self.applyOutputGain()
                        }
                    }
                }
            }
        } catch {
            // AVAudioFile couldn't open this "native format" file — most often a
            // corrupted/truncated download (e.g. a track saved despite a failed
            // yt-dlp run) that AVAssetReader chokes on with a cryptic coreaudio
            // error. AVPlayer's codec pipeline is more tolerant and can often play
            // (or at least cleanly fail) these files, so fall back to it instead of
            // leaving playback stalled on a silent "errorMessage only" dead end.
            appWarn("AVAudioFile open failed for \"\(currentSong?.displayName ?? "?")\": \(error.localizedDescription) — falling back to AVPlayer", category: "audio")
            scheduleWithOpusPlayer(url: url, startTime: startTime)
        }
    }

    /// Converts an Opus/WebM/OGG file to a playable format via AudioEncoderService,
    /// then schedules the result for playback using the standard AVAudioFile pipeline.
    /// Called from `scheduleCurrent` when it detects an unsupported container extension.
    @MainActor
    private func transcodeAndSchedule(url: URL, startTime: TimeInterval) async {
        isSchedulingAsync = true
        defer { isSchedulingAsync = false }
        errorMessage = nil

        guard let transcodedURL = await AudioEncoderService.shared.transcodeForPlayback(url) else {
            // AVAssetReader/AVAssetExportSession cannot decode this container (e.g. Ogg/Opus).
            // Fall back to AVPlayer which has access to iOS's full codec pipeline.
            appLog("Transcoding unavailable for .\(url.pathExtension), falling back to AVPlayer — \"\(currentSong?.displayName ?? "?")\"", category: "audio")
            scheduleWithOpusPlayer(url: url, startTime: startTime)
            return
        }

        do {
            let node = activeNode
            let gen  = scheduleGeneration &+ 1
            scheduleGeneration = gen
            node.stop()

            let file        = try AVAudioFile(forReading: transcodedURL)
            audioFile       = file
            duration        = file.duration
            let sampleRate  = file.processingFormat.sampleRate
            let startFrame  = max(0, AVAudioFramePosition(startTime * sampleRate))
            let framesLeft  = max(0, AVAudioFrameCount(file.length - startFrame))
            fileStartFrame  = startFrame
            position        = startTime
            gaplessScheduled = false
            pendingNextIndex = nil
            resetReplayGainForNewTrack()

            node.scheduleSegment(file, startingFrame: startFrame, frameCount: framesLeft, at: nil) { [weak self] in
                Task { @MainActor in
                    guard let self, self.scheduleGeneration == gen else { return }
                    self.handleTrackEnded()
                }
            }

            // Warm the BPM cache for this track and the one queued after it so
            // `beginCrossfade` can read a tempo synchronously once it fires.
            prewarmBPM(for: currentSong)
            prewarmBPM(for: peekNextSong())

            // Crossfade timer — same logic as scheduleCurrent.
            if audioSettings.crossfadeEnabled && audioSettings.crossfadeDuration > 0 {
                let trackLength     = Double(framesLeft) / sampleRate
                let crossfadeOffset = max(0, trackLength - audioSettings.crossfadeDuration)
                if crossfadeOffset > 0 {
                    crossfadeStartTimer?.invalidate()
                    crossfadeStartTimer = Timer.scheduledTimer(
                        withTimeInterval: crossfadeOffset, repeats: false
                    ) { [weak self] _ in
                        Task { @MainActor in
                            guard let self, self.isPlaying, !self.isCrossfading else { return }
                            self.beginCrossfade()
                        }
                    }
                }
            }

            if isPlaying {
                startEngineIfNeeded()
                node.play()
                startTimer()
                reapplyActiveEffect()
            }
            updateNowPlaying()

            // ReplayGain from original file's metadata.
            if audioSettings.replayGainEnabled {
                let asset       = AVURLAsset(url: url)
                let capturedURL = url
                Task.detached(priority: .utility) { [weak self] in
                    let metadata = (try? await asset.load(.metadata)) ?? []
                    var gainDB: Float?
                    for item in metadata {
                        let id = item.identifier?.rawValue.lowercased() ?? ""
                        if id.contains("replaygain_track_gain") || id.contains("replaygain") {
                            if let str = item.stringValue {
                                let numeric = str.components(
                                    separatedBy: CharacterSet(charactersIn: "-+0123456789.").inverted
                                ).joined()
                                gainDB = Float(numeric)
                            }
                        }
                    }
                    if gainDB == nil {
                        let rms = await NormalizationService.shared.gain(for: capturedURL)
                        if rms != 0 { gainDB = rms }
                    }
                    if let gain = gainDB {
                        await MainActor.run { [weak self] in
                            guard let self else { return }
                            let linear = pow(10.0, gain / 20.0)
                            self.replayGainLinearGain = linear
                            // Re-derive the output gain split (mixer attenuation +
                            // EQ globalGain boost) now that ReplayGain's contribution
                            // is known.
                            self.applyOutputGain()
                        }
                    }
                }
            }

        } catch {
            errorMessage = "Playback error: \(error.localizedDescription)"
            isPlaying = false
            appError("Transcoded-file scheduling failed for \"\(currentSong?.displayName ?? "?")\": \(error.localizedDescription)", category: "audio")
        }
    }

    /// Removes stream cache temp files older than 1 hour to prevent unbounded disk growth.
    private func cleanOldStreamCache() {
        let tempDir = FileManager.default.temporaryDirectory
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: [.creationDateKey]) else { return }
        let cutoff = Date().addingTimeInterval(-3600)  // 1 hour
        for file in files where file.lastPathComponent.hasPrefix("stream_") {
            if let created = try? file.resourceValues(forKeys: [.creationDateKey]).creationDate,
               created < cutoff {
                try? fm.removeItem(at: file)
            }
        }
    }

    @MainActor
    private func downloadAndSchedule(url: URL, startTime: TimeInterval) async {
        tearDownOpusPlayer()
        cleanOldStreamCache()
        isSchedulingAsync = true
        defer { isSchedulingAsync = false }

        errorMessage = nil

        do {
            // Derive a stable cache filename from the URL string.
            let cacheKey: String = url.absoluteString.data(using: .utf8).map { bytes in
                var hash: UInt64 = 5381
                for byte in bytes { hash = hash &* 31 &+ UInt64(byte) }
                return String(hash, radix: 16)
            } ?? UUID().uuidString

            // Detect the actual audio container from the URL path before choosing an extension.
            // YouTube CDN URLs often include the itag/mime in the path or may serve webm/opus
            // even when we requested m4a. AVAudioFile reads magic bytes but uses the file
            // extension for format hints — a mismatch causes silent failure.
            let urlPath = url.path.lowercased()
            let ext: String
            if urlPath.contains("audio/webm") || urlPath.hasSuffix(".webm") || urlPath.contains("mime=audio%2fwebm") {
                ext = "webm"
            } else if urlPath.hasSuffix(".opus") || urlPath.contains("mime=audio%2fogg") {
                ext = "opus"
            } else if urlPath.hasSuffix(".mp3") {
                ext = "mp3"
            } else {
                ext = "m4a"    // default; covers m4a, aac, mp4 audio
            }

            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("stream_\(cacheKey).\(ext)")

            if !FileManager.default.fileExists(atPath: tempURL.path) {
                // Build a request with a realistic browser UA so CDN servers don't reject it.
                var req = URLRequest(url: url)
                req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148", forHTTPHeaderField: "User-Agent")
                req.timeoutInterval = 60
                // Apply any per-song headers (e.g. Authorization for user music / server tracks).
                if let headers = currentSong?.httpHeaders {
                    for (field, value) in headers { req.setValue(value, forHTTPHeaderField: field) }
                }
                let (downloaded, response) = try await URLSession.shared.download(for: req)
                // Detect extension from Content-Type if URL path was inconclusive
                if ext == "m4a", let ct = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") {
                    let refinedExt: String
                    if ct.contains("webm") { refinedExt = "webm" }
                    else if ct.contains("ogg") || ct.contains("opus") { refinedExt = "opus" }
                    else if ct.contains("mpeg") { refinedExt = "mp3" }
                    else { refinedExt = "m4a" }
                    let refinedURL = tempURL.deletingPathExtension().appendingPathExtension(refinedExt)
                    try? FileManager.default.removeItem(at: refinedURL)
                    try FileManager.default.moveItem(at: downloaded, to: refinedURL)
                    // Re-enter with the corrected URL
                    let file2 = try AVAudioFile(forReading: refinedURL)
                    audioFile = file2
                    duration = file2.duration
                    let node = activeNode
                    let gen = scheduleGeneration &+ 1
                    scheduleGeneration = gen
                    node.stop()
                    let sr = file2.processingFormat.sampleRate
                    let sf = max(0, AVAudioFramePosition(startTime * sr))
                    let fl = max(0, AVAudioFrameCount(file2.length - sf))
                    fileStartFrame = sf; position = startTime; gaplessScheduled = false; pendingNextIndex = nil
                    resetReplayGainForNewTrack()
                    node.scheduleSegment(file2, startingFrame: sf, frameCount: fl, at: nil) { [weak self] in
                        Task { @MainActor in guard let self, self.scheduleGeneration == gen else { return }; self.handleTrackEnded() }
                    }
                    if isPlaying { startEngineIfNeeded(); node.play(); startTimer(); reapplyActiveEffect() }
                    updateNowPlaying()
                    return
                }
                try? FileManager.default.removeItem(at: tempURL)
                try FileManager.default.moveItem(at: downloaded, to: tempURL)
            }

            // From here on this is identical to the local-file path in scheduleCurrent.
            let node = activeNode
            // Increment generation before stopping so the old completion is invalidated.
            let gen = scheduleGeneration &+ 1
            scheduleGeneration = gen
            node.stop()
            let file = try AVAudioFile(forReading: tempURL)
            audioFile = file
            duration = file.duration
            let sampleRate = file.processingFormat.sampleRate
            let startFrame = max(0, AVAudioFramePosition(startTime * sampleRate))
            let framesLeft = max(0, AVAudioFrameCount(file.length - startFrame))
            fileStartFrame = startFrame
            position = startTime
            gaplessScheduled = false
            pendingNextIndex = nil
            resetReplayGainForNewTrack()

            node.scheduleSegment(file, startingFrame: startFrame, frameCount: framesLeft, at: nil) { [weak self] in
                Task { @MainActor in
                    guard let self, self.scheduleGeneration == gen else { return }
                    self.handleTrackEnded()
                }
            }

            // Start playback — playCurrent already set isPlaying = true before the download.
            if isPlaying {
                startEngineIfNeeded()
                node.play()
                startTimer()
                reapplyActiveEffect()
            }
            updateNowPlaying()

        } catch {
            errorMessage = "Could not load audio: \(error.localizedDescription)"
            isPlaying = false
            appError("Stream load failed for \"\(currentSong?.displayName ?? "?")\": \(error.localizedDescription)", category: "audio")
        }
    }

    /// Called by the AVAudioPlayerNode completion block when the current segment finishes.
    private func handleTrackEnded() {
        guard isPlaying else { return }

        // If gapless already scheduled the next file on this node, advance the index and update UI.
        if gaplessScheduled {
            advanceIndex()
            gaplessScheduled = false
            pendingNextIndex = nil
            // Adopt the file that just began playing gaplessly so position,
            // duration, and the scrubber track the NEW track. Without this the
            // Now Playing UI/MiniPlayer keep showing the previous track's
            // duration and a frozen (clamped) progress bar — the "won't update
            // when crossfade is off" bug, since gapless is the default
            // crossfade-off transition path.
            if let nextFile = pendingGaplessFile {
                audioFile = nextFile
                duration = nextFile.duration
            }
            fileStartFrame = 0
            pendingGaplessFile = nil
            // Fresh track — reset ReplayGain to neutral (its own analysis, if
            // enabled, runs per-track in the scheduling paths). This also zeroes
            // `gaplessBaseFrame`, so capture the node's CURRENT cumulative sample
            // time as this segment's baseline immediately afterward.
            resetReplayGainForNewTrack()
            if let nodeTime = activeNode.lastRenderTime,
               let playerTime = activeNode.playerTime(forNodeTime: nodeTime) {
                gaplessBaseFrame = Double(playerTime.sampleTime)
            }
            position = 0
            reapplyActiveEffect()
            updateNowPlaying()
            // Schedule completion for the newly playing segment.
            scheduleGaplessNext()
            return
        }

        if audioSettings.crossfadeEnabled {
            // The crossfadeStartTimer may have already started the crossfade;
            // don't trigger a second crossfade if we're already mid-fade.
            guard !isCrossfading else { return }
            beginCrossfade()
        } else {
            skipToNext()
        }
    }

    // MARK: - AVPlayer fallback (Opus / WebM / OGG)

    /// Records an AVPlayer load/playback failure and either advances to the next track or, if
    /// failures are arriving in a tight loop (4+ within 5 seconds — e.g. a stale stream URL that
    /// fails instantly and `repeatMode == .one`/`.all` keeps re-triggering the same failure),
    /// stops playback entirely instead of spinning forever.
    private func handleLoadFailure(message: String, userFacingMessage: String) {
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

    /// Used when AVAssetReader/AVAssetExportSession cannot decode the file (e.g. Ogg/Opus container).
    /// AVPlayer has access to iOS's full codec pipeline and can always play .opus files.
    /// Basic play/pause/seek/volume/speed work (speed via `.rate` + `.spectral`
    /// pitch algorithm — see `applyAudioSettings`). EQ, pitch shift, ReplayGain,
    /// 8D, crossfade, gapless, and reverb need the AVAudioEngine graph and do not apply.
    private func scheduleWithOpusPlayer(url: URL, startTime: TimeInterval) {
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
                    let detail = item.error?.localizedDescription ?? "unknown error"
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
                    message: "AVPlayer playback failed — skipping. \(err?.localizedDescription ?? "unknown")",
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

    private func tearDownOpusPlayer() {
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

    // MARK: - Crossfade

    private func beginCrossfade() {
        guard let nextSong = peekNextSong(), let nextURL = nextSong.url else {
            skipToNext(); return
        }
        guard let nextFile = try? AVAudioFile(forReading: nextURL) else {
            skipToNext(); return
        }

        isCrossfading = true
        // Smart Auto Crossfade (when enabled): snap the fade to the outgoing
        // track's beat grid (if its tempo is known) so it starts and ends on a
        // downbeat instead of an arbitrary fraction of a second. With Smart
        // Crossfade off, use the fixed user-set duration verbatim.
        let smartCrossfade = audioSettings.smartCrossfadeEnabled
        let fadeDuration = smartCrossfade
            ? smartFadeDuration(base: audioSettings.crossfadeDuration, bpm: currentSong.flatMap { bpmCache[$0.id] })
            : audioSettings.crossfadeDuration

        // The outgoing node is the one currently playing; incoming is the opposite.
        // Captured as `let` — the upcoming `usingPrimaryNode` flip changes what
        // `activeNode` resolves to, but these bindings keep pointing at the
        // correct physical nodes for the rest of this function and the timer below.
        let outgoing = usingPrimaryNode ? primaryNode : secondaryNode
        let incoming = usingPrimaryNode ? secondaryNode : primaryNode
        let outgoingBeatMatch = usingPrimaryNode ? primaryBeatMatch : secondaryBeatMatch
        let incomingBeatMatch = usingPrimaryNode ? secondaryBeatMatch : primaryBeatMatch

        // True beatmatching (Smart Auto Crossfade only): nudge both tracks'
        // tempos toward their midpoint for the duration of the overlap, then
        // ease the incoming track back to its native tempo as the fade
        // completes. Only attempted when Smart Crossfade is on, both BPMs are
        // known, and the required adjustment is modest (±8%) — outside that
        // range (or with Smart Crossfade off) both rates stay at 1.0 for a
        // plain volume crossfade.
        let outgoingBPM = currentSong.flatMap { bpmCache[$0.id] }
        let incomingBPM = bpmCache[nextSong.id]
        var incomingRate: Float = 1.0
        if smartCrossfade, let oBPM = outgoingBPM, let iBPM = incomingBPM, oBPM > 0, iBPM > 0 {
            let target = (oBPM + iBPM) / 2
            let oRatio = target / oBPM
            let iRatio = target / iBPM
            if (0.92...1.08).contains(oRatio), (0.92...1.08).contains(iRatio) {
                outgoingBeatMatch.rate = Float(oRatio)
                incomingRate = Float(iRatio)
            } else {
                outgoingBeatMatch.rate = 1.0
            }
        } else {
            outgoingBeatMatch.rate = 1.0
        }
        incomingBeatMatch.rate = incomingRate

        incoming.volume = 0
        let gen = scheduleGeneration &+ 1
        scheduleGeneration = gen
        incoming.scheduleFile(nextFile, at: nil) { [weak self] in
            Task { @MainActor in
                // Incoming finished its full file — drive normal track-end logic.
                guard let self, self.scheduleGeneration == gen else { return }
                self.handleTrackEnded()
            }
        }
        startEngineIfNeeded()
        incoming.play()

        // Switch every "what's playing" property to the incoming track THE INSTANT
        // it starts audibly — not after the multi-second fade finishes. `activeNode`
        // is a plain `usingPrimaryNode` lookup that we flip right here, so position
        // tracking immediately reads frames from `incoming`. Previously these stayed
        // pointed at the outgoing track for the whole fade: `updatePositionFromPlayer`
        // combined the OLD track's fileStartFrame/duration with the NEW node's
        // elapsed time (the position briefly snapping toward zero against the old
        // track's duration), while Now Playing, the miniplayer, and "Up Next" kept
        // showing the outgoing track's title/artwork/queue position until the fade
        // ended — exactly the "miniplayer freaks out, Now Playing/Up Next don't
        // live-update" glitch reported during crossfades. Flipping here keeps every
        // published property in lockstep with the audio from the first frame.
        usingPrimaryNode.toggle()
        advanceIndex()
        currentSong = nextSong
        audioFile = nextFile
        fileStartFrame = 0
        position = 0
        duration = nextFile.duration
        gaplessScheduled = false
        pendingNextIndex = nil
        // Crossfade schedules `nextFile` directly rather than through scheduleCurrent,
        // so no fresh ReplayGain analysis runs for it — fall back to neutral rather than
        // carrying over the outgoing track's (likely mismatched) computed gain.
        resetReplayGainForNewTrack()
        updateNowPlaying()
        applyAutoEQIfNeeded(bpm: incomingBPM ?? nextSong.bpm)

        // The track that just became current was prewarmed before this fade
        // started; warm the one after it now so its tempo is ready for the
        // next crossfade.
        prewarmBPM(for: peekNextSong())

        // Arm the crossfade-start timer for the track that just became current —
        // mirroring the setup `scheduleCurrent` does for the very first track.
        // Without this, `handleTrackEnded` only ever calls `beginCrossfade` again
        // at the natural end of `nextFile`'s full playback (zero seconds of
        // overlap), so every transition after the first one in a session degrades
        // from an actual crossfade into the new track simply fading in from
        // silence once the old one has already finished. Re-arming here keeps
        // the whole queue crossfading with consistent overlap.
        let nextTrackLength = nextFile.duration
        let nextCrossfadeOffset = max(0, nextTrackLength - fadeDuration)
        crossfadeStartTimer?.invalidate()
        crossfadeStartTimer = nil
        if fadeDuration > 0 && nextCrossfadeOffset > 0 {
            crossfadeStartTimer = Timer.scheduledTimer(
                withTimeInterval: nextCrossfadeOffset, repeats: false
            ) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.isPlaying, !self.isCrossfading else { return }
                    self.beginCrossfade()
                }
            }
        }

        // When crossfadeDuration == 0, steps clamps to 1 (instantaneous swap). Intentional.
        let steps = max(1, Int(fadeDuration * 30))
        let interval = fadeDuration / Double(steps)
        var step = 0

        crossfadeTimer?.invalidate()
        crossfadeTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] t in
            Task { @MainActor [weak self] in
                guard let self else { t.invalidate(); return }
                step += 1
                let progress = Float(step) / Float(steps)
                let clipped = min(max(progress, 0), 1)
                outgoing.volume = (1 - clipped) * self.audioSettings.volume
                incoming.volume = clipped * self.audioSettings.volume
                // Ease the incoming track from its beatmatched rate back to its
                // native tempo (1.0) over the course of the fade, so by the time
                // the outgoing track is fully silent, the new track is playing
                // at its own correct speed.
                incomingBeatMatch.rate = incomingRate + (1.0 - incomingRate) * clipped
                if step >= steps {
                    t.invalidate()
                    self.crossfadeTimer = nil
                    self.finishCrossfade(outgoing: outgoing)
                }
            }
        }
    }

    /// Called when the volume-ramp timer completes. All "now playing" state already
    /// switched to the incoming track at the moment the fade began (see
    /// beginCrossfade) — this just silences and stops the now-abandoned outgoing node.
    private func finishCrossfade(outgoing: AVAudioPlayerNode) {
        outgoing.stop()
        outgoing.volume = audioSettings.volume
        // Reset the abandoned node's beatmatch rate to neutral so it's ready
        // for reuse on the next crossfade.
        (outgoing === primaryNode ? primaryBeatMatch : secondaryBeatMatch).rate = 1.0
        isCrossfading = false
    }

    private func cancelCrossfade() {
        crossfadeTimer?.invalidate()
        crossfadeTimer = nil
        crossfadeStartTimer?.invalidate()
        crossfadeStartTimer = nil
        if isCrossfading {
            // `usingPrimaryNode`/`activeNode` already point at the track that's
            // becoming current (flipped at the start of the fade — see
            // beginCrossfade) — that node keeps playing and gets reused/
            // rescheduled by the caller. The other node is the abandoned
            // fade-out track: silence and stop it so it doesn't keep sounding.
            let abandoned = usingPrimaryNode ? secondaryNode : primaryNode
            abandoned.stop()
            abandoned.volume = audioSettings.volume
            (abandoned === primaryNode ? primaryBeatMatch : secondaryBeatMatch).rate = 1.0
            (activeNode === primaryNode ? primaryBeatMatch : secondaryBeatMatch).rate = 1.0
            activeNode.volume = audioSettings.volume
            isCrossfading = false
        }
    }

    /// Adjusts `base` (the user's configured crossfade duration) to the nearest
    /// whole number of beats at `bpm`, so the fade starts and ends on a
    /// downbeat instead of an arbitrary fraction of a second. Falls back to
    /// `base` unchanged if `bpm` isn't known yet, and clamps the result to
    /// within ±50% of `base` so a very slow track doesn't balloon a short
    /// crossfade into a multi-second one (or vice versa for a fast track).
    private func smartFadeDuration(base: TimeInterval, bpm: Double?) -> TimeInterval {
        guard base > 0, let bpm, bpm > 0 else { return base }
        let beatLength = 60.0 / bpm
        let beats = max(1, (base / beatLength).rounded())
        let snapped = beats * beatLength
        return min(max(snapped, base * 0.5), base * 1.5)
    }

    /// Kicks off (cached) BPM analysis for `song` so its tempo is available by
    /// the time `beginCrossfade` needs it. Fire-and-forget — `bpmCache` is
    /// populated asynchronously and read synchronously from `beginCrossfade`.
    private func prewarmBPM(for song: Song?) {
        guard let song, bpmCache[song.id] == nil, song.url != nil else { return }
        Task { [weak self] in
            guard let self, let library = self.libraryManager,
                  let bpm = await library.bpm(for: song)
            else { return }
            await MainActor.run {
                self.bpmCache[song.id] = bpm
                // Surface the result on `currentSong` too, so the Now Playing
                // UI can display tempo once it's known.
                if self.currentSong?.id == song.id {
                    self.currentSong?.bpm = bpm
                    self.applyAutoEQIfNeeded(bpm: bpm)
                }
            }
        }
    }

    /// If "Auto EQ" is enabled, switches the EQ preset to match the current
    /// track's genre (preferred) or tempo (fallback) — see
    /// `EQPreset.auto(forBPM:genre:)`. No-op if Auto EQ is off, neither signal
    /// is usable, or the suggested preset is already active.
    private func applyAutoEQIfNeeded(bpm: Double?) {
        guard audioSettings.autoEQEnabled else { return }
        let genre = currentSong?.genre
        guard let preset = EQPreset.auto(forBPM: bpm, genre: genre),
              audioSettings.eqPreset != preset else { return }
        applyEQPreset(preset)
    }

    // MARK: - Gapless Playback

    /// Pre-schedules the next track on primaryNode immediately after the current segment,
    /// so AVAudioEngine delivers audio without any gap.
    private func scheduleGaplessNext() {
        // Never schedule gapless while crossfade is enabled — the two transition
        // strategies would both fire and play two tracks at once.
        guard audioSettings.gaplessEnabled, !audioSettings.crossfadeEnabled else { return }
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

    // MARK: - Queue Helpers

    /// Resolves which queue index plays after `currentIndex`, WITHOUT mutating any state.
    /// Shuffle reorders `queue` itself when enabled (see `shuffleQueue`), so the
    /// upcoming index is always just the next sequential slot — keeping this in sync
    /// with what the Up Next/Queue UI displays.
    private func resolveNextIndex() -> Int? {
        guard !queue.isEmpty else { return nil }
        if repeatMode == .one { return currentIndex }
        let nextIndex = currentIndex + 1
        if nextIndex < queue.count { return nextIndex }
        if repeatMode == .all { return 0 }
        return nil
    }

    private func peekNextSong() -> Song? {
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
    private func prefetchUpcomingStreamIfNeeded() {
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

    private func advanceIndex() {
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

    // MARK: - Audio Engine Configuration

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        // Try with full options first; fall back gracefully if Bluetooth A2DP
        // is unavailable (causes -20 error on some devices/simulators).
        let fullOptions: AVAudioSession.CategoryOptions = [.allowAirPlay, .allowBluetoothA2DP]
        let fallbackOptions: AVAudioSession.CategoryOptions = [.allowAirPlay]
        if (try? session.setCategory(.playback, mode: .default, options: fullOptions)) == nil {
            try? session.setCategory(.playback, mode: .default, options: fallbackOptions)
        }
        // Request 48 kHz — the native rate for Opus and most modern audio.
        // iOS honours this when hardware supports it; silently ignores it otherwise.
        try? session.setPreferredSampleRate(48000)
        // NOTE: deliberately do NOT activate the session here. Activating at
        // launch (before anything plays) made the app grab the audio system
        // immediately — ducking other apps, holding the route, and acting like
        // a running ("ghost") audio app with nothing playing. The session is
        // now activated only when playback actually starts (see
        // `startEngineIfNeeded`) and released on `stop()`.

        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in self?.handleAudioInterruption(notification) }
        }

        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in self?.handleRouteChange(notification) }
        }

        // The hardware can change sample rate / channel layout (e.g. switching to/from
        // AirPlay or certain Bluetooth devices) without firing an interruption or route
        // change with `.oldDeviceUnavailable` — `AVAudioEngine` just stops itself. Left
        // unhandled, `isPlaying` stays true but the engine is silent and never recovers,
        // which is exactly the "music randomly stops" symptom users hit.
        engineConfigChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleEngineConfigurationChange() }
        }
    }

    private func handleEngineConfigurationChange() {
        guard !isUsingOpusPlayer, isPlaying else { return }
        appWarn("Audio engine configuration changed — restarting engine to resume playback", category: "audio")
        guard !engine.isRunning else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        startEngineIfNeeded()
        if !activeNode.isPlaying {
            activeNode.play()
        }
    }

    private func handleAudioInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return }

        switch type {
        case .began:
            appLog("Audio session interrupted", category: "audio")
            if isPlaying {
                pause()
                wasInterrupted = true
            }
        case .ended:
            wasInterrupted = false
            guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) {
                appLog("Audio session interruption ended — resuming", category: "audio")
                // Re-activate the audio session before restarting the engine; the
                // system deactivates it when an interruption begins.
                try? AVAudioSession.sharedInstance().setActive(true)
                resume()
            } else {
                appLog("Audio session interruption ended — not resuming", category: "audio")
            }
        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue)
        else { return }

        switch reason {
        case .oldDeviceUnavailable:
            appLog("Audio route changed — output device removed, pausing", category: "audio")
            pause()
            pausedByRouteChange = true
        case .newDeviceAvailable:
            // A Bluetooth device (or other output) just connected. If playback was
            // paused because the previous route disappeared (headphones unplugged,
            // Bluetooth dropped), resume now that audio has somewhere to go again —
            // otherwise the user has to manually hit play every time their
            // Bluetooth device reconnects.
            if pausedByRouteChange {
                pausedByRouteChange = false
                appLog("Audio route changed — output device available, resuming", category: "audio")
                try? AVAudioSession.sharedInstance().setActive(true)
                resume()
            }
        default:
            break
        }
    }

    private func configureEngine() {
        guard !isEngineConfigured else { return }
        engine.attach(primaryNode)
        engine.attach(secondaryNode)
        engine.attach(primaryBeatMatch)
        engine.attach(secondaryBeatMatch)
        engine.attach(crossfadeMixer)
        engine.attach(timePitch)
        engine.attach(equalizer)
        engine.attach(reverb)
        engine.attach(limiter)
        configureLimiter()
        configureReverb()

        // Both player nodes connect to separate mixer inputs (via their own
        // beatmatch time-stretch units) so their volumes can be ramped
        // independently during a crossfade, and their tempos can be nudged
        // toward each other for a "beatmatched" overlap.
        engine.connect(primaryNode, to: primaryBeatMatch, format: nil)
        engine.connect(primaryBeatMatch, to: crossfadeMixer, fromBus: 0, toBus: 0, format: nil)
        engine.connect(secondaryNode, to: secondaryBeatMatch, format: nil)
        engine.connect(secondaryBeatMatch, to: crossfadeMixer, fromBus: 0, toBus: 1, format: nil)
        engine.connect(crossfadeMixer, to: timePitch, format: nil)
        engine.connect(timePitch, to: equalizer, format: nil)
        engine.connect(equalizer, to: reverb, format: nil)
        engine.connect(reverb, to: limiter, format: nil)
        engine.connect(limiter, to: engine.mainMixerNode, format: nil)

        isEngineConfigured = true
    }

    /// Loads the default factory preset and zeroes the wet/dry mix — the real
    /// mix level/preset is then applied immediately by `applyAudioSettings()`,
    /// which runs as soon as the engine starts (or `audioSettings` is restored
    /// from disk) so reverb never plays at a stale level after a rebuild.
    private func configureReverb() {
        reverb.loadFactoryPreset(.mediumRoom)
        reverb.wetDryMix = 0
        loadedReverbPreset = .mediumRoom
    }

    /// Maps our Codable `ReverbRoomPreset` (Models layer, no AVFoundation
    /// dependency) onto the real `AVAudioUnitReverbPreset`.
    private func avReverbPreset(for preset: ReverbRoomPreset) -> AVAudioUnitReverbPreset {
        switch preset {
        case .smallRoom: return .smallRoom
        case .mediumRoom: return .mediumRoom
        case .largeRoom: return .largeRoom
        case .mediumHall: return .mediumHall
        case .largeHall: return .largeHall
        case .plate: return .plate
        case .cathedral: return .cathedral
        }
    }

    /// Configures `limiter` as a fast brick-wall peak limiter: threshold just
    /// under 0 dBFS with a very high ratio, near-instant attack, and a short
    /// release. With this in place, raising `crossfadeMixer.outputVolume`
    /// above 1.0 (via `audioSettings.volume`, up to `AudioSettings.maxVolume`)
    /// makes playback louder without the output signal hard-clipping.
    private func configureLimiter() {
        let unit = limiter.audioUnit
        AudioUnitSetParameter(unit, kDynamicsProcessorParam_Threshold, kAudioUnitScope_Global, 0, -1.0, 0)    // dB — start limiting just below full scale
        AudioUnitSetParameter(unit, kDynamicsProcessorParam_HeadRoom, kAudioUnitScope_Global, 0, 1.0, 0)      // dB of headroom above the threshold
        AudioUnitSetParameter(unit, kDynamicsProcessorParam_AttackTime, kAudioUnitScope_Global, 0, 0.001, 0)  // seconds — fast enough to catch transients
        AudioUnitSetParameter(unit, kDynamicsProcessorParam_ReleaseTime, kAudioUnitScope_Global, 0, 0.05, 0)  // seconds — short so it doesn't pump audibly
        AudioUnitSetParameter(unit, kDynamicsProcessorParam_OverallGain, kAudioUnitScope_Global, 0, 0, 0)
        limiter.bypass = false
    }

    private func configureEqualizer() {
        let frequencies: [Float] = [32, 64, 125, 250, 500, 1_000, 2_000, 4_000, 8_000, 16_000]
        // Use shelf filters for the frequency extremes so gain is applied to everything
        // below 32 Hz or above 16 kHz, not just a narrow peak at those frequencies.
        // All mid bands use parametric (bell/peak) filters.
        let filterTypes: [AVAudioUnitEQFilterType] = [
            .lowShelf,   // 32 Hz  — boosts/cuts all sub-bass below shelf point
            .parametric, // 64 Hz
            .parametric, // 125 Hz
            .parametric, // 250 Hz
            .parametric, // 500 Hz
            .parametric, // 1 kHz
            .parametric, // 2 kHz
            .parametric, // 4 kHz
            .parametric, // 8 kHz
            .highShelf   // 16 kHz — boosts/cuts all air-band above shelf point
        ]
        for (index, band) in equalizer.bands.enumerated() {
            band.filterType = filterTypes[index]
            band.frequency  = frequencies[index]
            band.bandwidth  = 1.0   // 1-octave bandwidth — musical, smooth boost/cut response
            band.gain       = 0
            band.bypass     = true
        }
    }

    private func startEngineIfNeeded() {
        guard !engine.isRunning else { return }
        // Activate the audio session lazily, right before the engine starts —
        // not at launch — so the app only holds the audio system while actually
        // playing (see `configureAudioSession`).
        try? AVAudioSession.sharedInstance().setActive(true)
        do {
            try engine.start()
            errorMessage = nil
        } catch {
            // Full teardown + rebuild, then reactivate the audio session before retry.
            // engine.reset() detaches all nodes and clears connections, so configureEngine()
            // can re-attach them cleanly without duplicates.
            appWarn("Audio engine start failed — rebuilding: \(error.localizedDescription)", category: "audio")
            engine.reset()
            isEngineConfigured = false
            configureEngine()
            configureEqualizer()
            try? AVAudioSession.sharedInstance().setActive(true)
            do {
                try engine.start()
                appLog("Audio engine recovered after rebuild", category: "audio")
                errorMessage = nil
                // `configureEqualizer()` resets every band to gain=0/bypass=true —
                // without reapplying the user's EQ/effects settings here, an engine
                // rebuild (triggered by an interruption, route change, or hardware
                // config change) silently wipes the EQ until the user next touches
                // a slider. Reapply so it picks up exactly where it left off.
                applyAudioSettings()
            } catch {
                errorMessage = error.localizedDescription
                appError("Audio engine failed to recover: \(error.localizedDescription)", category: "audio")
            }
        }
    }

    // MARK: - 8D Rotation

    func start8DRotation(hz: Double = 0.18) {
        stop8DRotation()
        rotationHz = hz
        rotationAngle = 0
        is8DActive = true
        let link = CADisplayLink(target: self, selector: #selector(update8DRotation))
        // update8DRotation advances its phase assuming a 60Hz callback. On
        // ProMotion devices CADisplayLink fires up to 120Hz by default, which
        // would both double the audible rotation speed and double the
        // per-effect CPU/battery cost for no benefit (this drives an audio
        // parameter, not a visual). Pin it to 60 so the math stays correct.
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        rotationLink = link
    }

    func stop8DRotation() {
        rotationLink?.invalidate()
        rotationLink = nil
        is8DActive = false
        // Reset pan to center so no stereo imbalance remains after 8D effect stops.
        crossfadeMixer.pan = 0.0
    }

    /// Updates the 8D rotation speed while the effect is running. Persists to UserDefaults.
    func set8DSpeed(hz: Double) {
        let clamped = min(max(hz, 0.02), 2.0)
        rotationHz = clamped
        UserDefaults.standard.set(clamped, forKey: "8d_rotation_hz")
        if is8DActive {
            start8DRotation(hz: clamped)
        }
    }

    @objc private func update8DRotation() {
        guard is8DActive else { return }
        // Advance angle by one display-link frame. preferredFrameRateRange in
        // start8DRotation pins the link to 60Hz, so this fixed-step math stays
        // correct even on 120Hz ProMotion displays (which would otherwise call
        // back twice as often and double the audible rotation speed).
        rotationAngle += 2 * .pi * rotationHz / 60.0
        // Wrap to keep angle in [0, 2π) to avoid floating-point drift.
        if rotationAngle >= 2 * .pi { rotationAngle -= 2 * .pi }
        // Pan oscillates at the rotation frequency. Scaled to ±0.5 — enough for a clear
        // spatial effect while keeping both channels audible (~-6 dB on the receding side).
        let pan = Float(sin(rotationAngle)) * 0.5
        crossfadeMixer.pan = pan
    }

    // MARK: - Tremolo

    func startTremolo(frequency: Double = 4.0, depth: Float = 0.45) {
        stopTremolo()
        tremoloFrequency = frequency
        tremoloDepth = depth
        tremoloPhase = 0
        isTremoloActive = true
        let link = CADisplayLink(target: self, selector: #selector(updateTremolo))
        // Same 60Hz assumption as update8DRotation — pin the rate so the LFO
        // speed stays correct (and the callback doesn't run twice as often)
        // on 120Hz ProMotion displays.
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        tremoloLink = link
    }

    func stopTremolo() {
        tremoloLink?.invalidate()
        tremoloLink = nil
        isTremoloActive = false
        // Restore both nodes to their normal volume.
        primaryNode.volume = audioSettings.volume
        secondaryNode.volume = audioSettings.volume
    }

    @objc private func updateTremolo() {
        guard isTremoloActive, isPlaying else { return }
        tremoloPhase += 2 * .pi * tremoloFrequency / 60.0
        // LFO: volume = baseVolume × (1 − depth/2 + depth/2 × sin(phase))
        // Centres around baseVolume with ±depth/2 swing, never exceeds baseVolume.
        let baseVol = Double(audioSettings.volume)
        let lfo = 1.0 - Double(tremoloDepth) / 2.0 + Double(tremoloDepth) / 2.0 * sin(tremoloPhase)
        let vol = Float(max(0, min(baseVol, baseVol * lfo)))
        if isCrossfading {
            // During crossfade both nodes are audible — apply to the active one only.
            activeNode.volume = vol
        } else {
            primaryNode.volume  = usingPrimaryNode ? vol : audioSettings.volume
            secondaryNode.volume = usingPrimaryNode ? audioSettings.volume : vol
        }
    }

    // MARK: - Vibrato

    func startVibrato(frequency: Double = 4.5, depth: Double = 0.35) {
        stopVibrato()
        vibratoFrequency = frequency
        vibratoDepth = depth
        vibratoPhase = 0
        vibratoBasePitch = audioSettings.pitchSemitones
        isVibratoActive = true
        let link = CADisplayLink(target: self, selector: #selector(updateVibrato))
        // Same 60Hz assumption as update8DRotation — pin the rate so the
        // pitch-modulation speed stays correct (and the callback doesn't run
        // twice as often) on 120Hz ProMotion displays.
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        vibratoLink = link
    }

    func stopVibrato() {
        vibratoLink?.invalidate()
        vibratoLink = nil
        isVibratoActive = false
        // Restore pitch to the value captured when vibrato started (or current setting).
        timePitch.pitch = vibratoBasePitch * 100
    }

    @objc private func updateVibrato() {
        guard isVibratoActive else { return }
        vibratoPhase += 2 * .pi * vibratoFrequency / 60.0
        let deviation = vibratoDepth * sin(vibratoPhase)
        let totalSemitones = Double(vibratoBasePitch) + deviation
        timePitch.pitch = Float(totalSemitones * 100)  // AVAudioUnitTimePitch.pitch is in cents
    }

    // MARK: - Karaoke (center-channel cancellation)

    func enableKaraoke(level: Float = 1.0) {
        guard !isKaraokeActive else { return }
        isKaraokeActive = true
        installKaraokeTap(level: level)
    }

    func disableKaraoke() {
        guard isKaraokeActive else { return }
        isKaraokeActive = false
        removeKaraokeTap()
    }

    /// Installs a tap on the engine's output node that rewrites the stereo PCM frames
    /// in-place with L-R center-cancellation, avoiding any graph topology changes at runtime.
    private func installKaraokeTap(level: Float) {
        let outputNode = engine.outputNode
        outputNode.installTap(onBus: 0, bufferSize: 4096, format: nil) { [weak self] buffer, _ in
            guard let self, self.isKaraokeActive else { return }
            self.applyCenterCancellation(to: buffer, level: level)
        }
    }

    private func removeKaraokeTap() {
        engine.outputNode.removeTap(onBus: 0)
    }

    /// Applies stereo center-channel cancellation in-place to a PCM buffer.
    /// For each stereo pair: out_L = (L − R) × 0.5 × level; out_R = (R − L) × 0.5 × level.
    private func applyCenterCancellation(to buffer: AVAudioPCMBuffer, level: Float) {
        guard buffer.format.channelCount == 2,
              let data = buffer.floatChannelData else { return }
        let frameCount = Int(buffer.frameLength)
        let left  = data[0]
        let right = data[1]
        let scale = 0.5 * level
        for i in 0 ..< frameCount {
            let l = left[i]
            let r = right[i]
            left[i]  = (l - r) * scale
            right[i] = (r - l) * scale
        }
    }

    // MARK: - Apply Audio Settings

    private func applyAudioSettings() {
        // AVPlayer fallback path (opus/webm/ogg streams) — only Speed can be
        // mapped onto AVPlayer's API (EQ/pitch/crossfade/gapless/ReplayGain need
        // the AVAudioEngine graph below, which this path bypasses entirely).
        // Re-apply `.rate` directly so dragging the Speed slider mid-playback
        // takes effect immediately instead of silently doing nothing.
        if isUsingOpusPlayer {
            // AVPlayer.volume is hard-clamped to 0...1 by AVFoundation and this
            // path bypasses the AVAudioEngine graph entirely (no `equalizer`/
            // `limiter` available here to realise a boost above unity). Clamp
            // explicitly so values above 1.0 don't silently no-op — boost beyond
            // 100% simply isn't available for opus/webm/ogg streams played via
            // this fallback.
            opusPlayer?.volume = min(audioSettings.volume, 1.0)
            if isPlaying { opusPlayer?.rate = Float(audioSettings.speed) }
            return
        }

        // Volume — apply to both nodes (secondary will be 0 unless crossfading).
        primaryNode.volume = isCrossfading ? primaryNode.volume : audioSettings.volume
        if !isCrossfading { secondaryNode.volume = audioSettings.volume }

        // Speed / pitch
        timePitch.rate = audioSettings.speed
        timePitch.pitch = audioSettings.pitchSemitones * 100

        // EQ bands
        let eqEnabled = audioSettings.equalizerEnabled
        for (index, band) in equalizer.bands.enumerated() {
            band.bypass = !eqEnabled
            if audioSettings.eqBands.indices.contains(index) {
                var gain = eqEnabled ? audioSettings.eqBands[index] : 0
                // Apply bass boost on top of EQ gains for bands 0 (32Hz) and 1 (64Hz).
                if audioSettings.bassBoostEnabled && eqEnabled {
                    if index == 0 || index == 1 {
                        let boost = min(max(audioSettings.bassBoostGain, 0), 15)
                        gain += boost
                    }
                }
                // AVAudioUnitEQ clamps band gain to -96...24 dB internally — combining a
                // +12 dB EQ slider with a +15 dB bass boost (27 dB) silently hit that
                // ceiling, so the boost had less audible effect than its displayed value
                // implied. Clamp explicitly so the applied gain matches what's shown.
                band.gain = min(max(gain, -96), 24)
            }
        }

        // If bass boost is enabled but EQ is disabled, enable EQ bands 0 & 1 for bass
        // boost only. This block is mutually exclusive with the EQ block above (which
        // already adds boost to bands 0/1 when both EQ and bass boost are on), so there
        // is no double-application.
        if audioSettings.bassBoostEnabled && !audioSettings.equalizerEnabled {
            for (index, band) in equalizer.bands.enumerated() {
                band.bypass = false
                if index == 0 || index == 1 {
                    band.gain = min(max(audioSettings.bassBoostGain, 0), 15)
                } else {
                    band.gain = 0
                }
            }
        }

        // Reverb — live wet/dry mix and room preset. Only reload the factory
        // preset when it actually changed (loadFactoryPreset is the heavy
        // call); wetDryMix itself is cheap and safe to set on every pass so
        // toggling the setting or dragging the mix slider applies instantly,
        // including to whatever is playing right now.
        if loadedReverbPreset != audioSettings.reverbPreset {
            reverb.loadFactoryPreset(avReverbPreset(for: audioSettings.reverbPreset))
            loadedReverbPreset = audioSettings.reverbPreset
        }
        reverb.wetDryMix = audioSettings.reverbEnabled ? min(max(audioSettings.reverbWetDryMix, 0), 100) : 0

        // ReplayGain + master volume/boost: re-combine the current track's analysed
        // gain (replayGainLinearGain, computed asynchronously in scheduleCurrent/
        // transcodeAndSchedule from embedded REPLAYGAIN_TRACK_GAIN metadata or RMS
        // analysis) with the live volume. Using the SAME formula here as the analysis
        // callback — rather than a separate flat-cap value — means a mid-track
        // volume/EQ/speed tweak (which re-invokes this via the `audioSettings` didSet)
        // refreshes the output level without clobbering the per-track gain the
        // analysis already computed.
        applyOutputGain()

        // Do NOT call updateNowPlaying() here — this runs on every EQ slider drag.
    }

    /// Applies the ReplayGain correction (if enabled) and any volume boost above
    /// 100% to the output stage. The 0...100% portion of `audioSettings.volume`
    /// is applied separately, directly to the player node(s) — see
    /// `applyAudioSettings()` and the crossfade/tremolo helpers — since
    /// `AVAudioPlayerNode.volume` already handles that range correctly.
    ///
    /// `AVAudioMixerNode.outputVolume` is hard-clamped by AVFoundation to `0...1`,
    /// so it (and the player nodes) can only ever *attenuate* — neither can express
    /// the boost above unity that `audioSettings.volume` allows (up to
    /// `AudioSettings.maxVolume`, i.e. up to +12 dB), nor a ReplayGain correction
    /// greater than 1.0x for a quiet track. To realise gain beyond what those
    /// attenuation-only stages contribute, the *remaining* portion of the desired
    /// total gain is applied as positive dB on `equalizer.globalGain`, which is NOT
    /// clamped to unity. The brick-wall `limiter` further down the chain (see
    /// `configureLimiter`) catches any peaks this boost would otherwise clip.
    private func applyOutputGain() {
        let rgGain: Float = audioSettings.replayGainEnabled ? replayGainLinearGain : 1.0
        let userVol = audioSettings.volume

        // Desired total linear gain across the whole chain.
        let totalLinear = max(0, rgGain * userVol)

        // What the player-node volume (set in applyAudioSettings/crossfade/tremolo
        // to `min(userVol, 1.0)`) and the mixer's outputVolume can each contribute
        // on their own, attenuation-only (0...1).
        let nodeContribution = min(max(userVol, 0), 1.0)
        let mixerContribution = min(max(rgGain, 0), 1.0)
        crossfadeMixer.outputVolume = mixerContribution

        // Whatever's left over — i.e. gain the node+mixer pair can't express
        // because both are capped at 1.0x — is made up as positive dB via the
        // EQ's global gain.
        let attenuationApplied = nodeContribution * mixerContribution
        if totalLinear > attenuationApplied, attenuationApplied > 0 {
            let boostLinear = totalLinear / attenuationApplied
            let boostDB = 20 * log10(boostLinear)
            equalizer.globalGain = min(max(boostDB, 0), AudioSettings.maxBoostDB)
        } else {
            equalizer.globalGain = 0
        }
    }

    // MARK: - Position Tracking

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.timerTick()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    /// Counts 0.5s timer ticks so `pushPlaybackStateToBridge()` runs roughly
    /// every 5s during playback, instead of on every tick.
    private var bridgePushTickCounter = 0

    private func timerTick() {
        updatePositionFromPlayer()

        bridgePushTickCounter += 1
        if bridgePushTickCounter >= 10 {
            bridgePushTickCounter = 0
            pushPlaybackStateToBridge()
        }

        // Belt-and-braces recovery: if we think we're playing but the engine has
        // silently stopped (and no interruption/route/config-change notification
        // fired to tell us), restart it here. Without this, `isPlaying` stays true
        // forever with no audio and no track advance — the "music randomly stops"
        // bug — until the user manually pauses/resumes.
        if isPlaying, !isUsingOpusPlayer, !engine.isRunning {
            handleEngineConfigurationChange()
        }

        // AB Repeat enforcement
        if abRepeatEnabled,
           let start = abRepeatStart,
           let end = abRepeatEnd,
           position >= end {
            seek(to: start)
        }

        // Keep the lock screen / Apple Watch / CarPlay "Now Playing" elapsed time and
        // playback-rate in sync with actual position — without this, those surfaces
        // only refresh on play/pause/track-change events and can visibly drift from
        // (or briefly disagree with) the in-app scrubber.
        updateNowPlaying()
    }

    /// Mirrors the current track/position to the bridge (`/user/playback-state`)
    /// so other surfaces — e.g. the local Discord Rich Presence daemon — can
    /// show what this account is currently playing. Fires on play/pause/track
    /// changes and roughly every 5s during playback; no-ops if not logged in.
    private func pushPlaybackStateToBridge() {
        AccountService.shared?.pushPlaybackState(
            song: currentSong,
            position: position,
            duration: duration,
            isPlaying: isPlaying,
            bpm: currentSong.flatMap { $0.bpm ?? bpmCache[$0.id] }
        )
    }

    /// Cancelled/rescheduled on every track change; the in-flight task for the
    /// previous track.
    private var historyLogTask: Task<Void, Never>?

    /// Logs the current track to `/user/history` (`AccountService.logPlay`)
    /// ~5s after it starts playing — long enough to filter out rapid skips,
    /// but soon enough that a linked Discord "Now Playing" webhook and any
    /// Last.fm/ListenBrainz scrobble reflect the track the user is actually
    /// listening to. Without this, play history was never recorded and those
    /// integrations silently never fired.
    private func scheduleHistoryLog() {
        historyLogTask?.cancel()
        guard let song = currentSong else { return }
        historyLogTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled, let self else { return }
            guard self.currentSong?.id == song.id else { return }
            await AccountService.shared?.logPlay(
                song: song,
                listenSeconds: Int(self.position),
                bpm: song.bpm ?? self.bpmCache[song.id]
            )
        }
    }

    private var queuePushTask: Task<Void, Never>?

    /// Mirrors the "up next" queue to the bridge (`/user/queue`), debounced so
    /// rapid changes (drag-reorder, batch removals) don't fire a request per
    /// edit. No-ops if not logged in.
    private func pushQueueToBridge() {
        queuePushTask?.cancel()
        let snapshot = queue
        queuePushTask = Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            await AccountService.shared?.pushQueue(snapshot)
        }
    }

    private func updatePositionFromPlayer() {
        guard !isUsingOpusPlayer else { return }
        // Do not overwrite `position` while an async download is in progress.
        // The position was already set to the seek target in seek()/downloadAndSchedule();
        // letting the timer fire here would clobber it with a stale node time.
        guard !isSchedulingAsync else { return }

        let node = activeNode
        guard let nodeTime = node.lastRenderTime,
              let playerTime = node.playerTime(forNodeTime: nodeTime),
              let file = audioFile
        else { return }

        // Subtract `gaplessBaseFrame` so elapsed time is measured from the start
        // of the CURRENT segment, not the cumulative frame count of every
        // gapless segment played on this node since the last fresh schedule.
        let elapsedFrames = Double(playerTime.sampleTime) - gaplessBaseFrame
        let computed = Double(fileStartFrame) / file.processingFormat.sampleRate
            + elapsedFrames / playerTime.sampleRate
        position = min(duration, max(0, computed))
    }

    // MARK: - Now Playing / Remote Commands

    private func updateNowPlaying() {
        guard let song = currentSong else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: song.displayName,
            MPMediaItemPropertyArtist: song.artistName,
            MPMediaItemPropertyAlbumTitle: song.albumName,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(audioSettings.speed) : 0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: Double(audioSettings.speed)
        ]

        // Preserve existing artwork if already set (avoid flickering during position updates).
        if let existing = MPNowPlayingInfoCenter.default().nowPlayingInfo,
           let existingArtwork = existing[MPMediaItemPropertyArtwork] {
            info[MPMediaItemPropertyArtwork] = existingArtwork
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// Fetches artwork asynchronously and injects it into the Now Playing info center
    /// and the WidgetKit shared container.
    private func updateNowPlayingArtwork(for song: Song?) async {
        guard let song else {
            WidgetDataService.shared.update(song: nil, isPlaying: false, artwork: nil)
            return
        }
        let image = await ArtworkService.shared.loadArtwork(for: song)
        if let image {
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
            info[MPMediaItemPropertyArtwork] = artwork
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        }
        WidgetDataService.shared.update(song: song, isPlaying: isPlaying, artwork: image, position: position, duration: duration)
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.nextTrackCommand.isEnabled = true
        center.previousTrackCommand.isEnabled = true
        center.changePlaybackPositionCommand.isEnabled = true

        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.skipToNext() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.skipToPrevious() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            if let e = event as? MPChangePlaybackPositionCommandEvent {
                Task { @MainActor in self?.seek(to: e.positionTime) }
            }
            return .success
        }
    }
}

// MARK: - AVAudioFile Convenience

private extension AVAudioFile {
    var duration: TimeInterval {
        Double(length) / processingFormat.sampleRate
    }
}
