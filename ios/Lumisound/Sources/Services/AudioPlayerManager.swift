@preconcurrency import AVFoundation
import Foundation
import MediaPlayer
import UIKit

// MARK: - AudioPlayerManager

@MainActor
final class AudioPlayerManager: ObservableObject {

    // MARK: Published State

    @Published private(set) var currentSong: Song? {
        didSet {
            if currentSong?.id != oldValue?.id {
                Task { await updateNowPlayingArtwork(for: currentSong) }
            }
        }
    }
    @Published private(set) var queue: [Song] = []
    @Published private(set) var currentIndex = 0
    @Published private(set) var isPlaying = false {
        didSet {
            guard isPlaying != oldValue else { return }
            WidgetDataService.shared.updatePlayState(isPlaying: isPlaying)
        }
    }
    @Published var position: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var repeatMode: RepeatMode = .off
    @Published var shuffleEnabled = false
    @Published var audioSettings = AudioSettings() {
        didSet { applyAudioSettings() }
    }
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
    // Dedicated mixer so both player nodes can connect to a single effects chain.
    private let crossfadeMixer = AVAudioMixerNode()

    private let timePitch = AVAudioUnitTimePitch()
    private let equalizer = AVAudioUnitEQ(numberOfBands: 10)

    // MARK: Private — Spatial / Special-Effect Nodes

    // 8D: environment + a spatial source mixer
    private let environmentNode = AVAudioEnvironmentNode()
    private let spatialSourceMixer = AVAudioMixerNode()
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

    // Crossfade state
    private var isCrossfading = false
    private var crossfadeTimer: Timer?
    // Fires crossfadeDuration seconds before a track ends so we begin fading early.
    private var crossfadeStartTimer: Timer?

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

    // AVPlayer fallback for containers (e.g. .opus) that AVAssetReader cannot decode.
    // When active, this player owns audio output instead of the AVAudioEngine nodes.
    private var opusPlayer: AVPlayer?
    private var opusTimeObserver: Any?
    private var opusStatusObserver: NSKeyValueObservation?
    private var isUsingOpusPlayer: Bool { opusPlayer != nil }

    // Schedule generation counter — incremented before every node stop/reschedule.
    // Completion blocks capture the generation at registration time and bail out if it
    // has changed, preventing ghost completions from firing after a seek or skip.
    private var scheduleGeneration: UInt64 = 0

    // Audio interruption / route change
    private var wasInterrupted = false

    // MARK: Init / Deinit

    init() {
        configureAudioSession()
        configureEngine()
        configureEqualizer()
        configureRemoteCommands()
        restorePlaybackState()

        NotificationCenter.default.addObserver(
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
    }

    deinit {
        timer?.invalidate()
        crossfadeTimer?.invalidate()
        crossfadeStartTimer?.invalidate()
        rotationLink?.invalidate()
        tremoloLink?.invalidate()
        vibratoLink?.invalidate()
        NotificationCenter.default.removeObserver(self)
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.removeTarget(nil)
        center.pauseCommand.removeTarget(nil)
        center.togglePlayPauseCommand.removeTarget(nil)
        center.nextTrackCommand.removeTarget(nil)
        center.previousTrackCommand.removeTarget(nil)
        center.changePlaybackPositionCommand.removeTarget(nil)
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
        if autoplay {
            playCurrent(from: 0)
        } else {
            prepareCurrent()
        }
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
    }

    func skipToNext() {
        guard !queue.isEmpty else { return }
        if repeatMode == .one {
            playCurrent(from: 0)
            return
        }

        let nextIndex: Int
        if shuffleEnabled && queue.count > 1 {
            // Exclude currentIndex so the same track is never picked twice in a row.
            let pool = queue.indices.filter { $0 != currentIndex }
            nextIndex = pool.randomElement() ?? currentIndex
        } else {
            nextIndex = currentIndex + 1
        }

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
        updateNowPlaying()
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
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: playbackStateKey)
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

            node.scheduleSegment(file, startingFrame: startFrame, frameCount: framesLeft, at: nil) { [weak self] in
                Task { @MainActor in
                    guard let self, self.scheduleGeneration == gen else { return }
                    self.handleTrackEnded()
                }
            }

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
            if audioSettings.gaplessEnabled {
                Task { [weak self] in
                    guard let self else { return }
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    await MainActor.run {
                        guard self.isPlaying, self.audioSettings.gaplessEnabled,
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
                            // Allow a modest boost above 1.0 when normalising a quiet track.
                            self.crossfadeMixer.outputVolume = min(linear * self.audioSettings.volume, 1.5)
                        }
                    }
                }
            }
        } catch {
            isPlaying = false
            errorMessage = error.localizedDescription
            appError("Playback error for \"\(currentSong?.displayName ?? "?")\": \(error.localizedDescription)", category: "audio")
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

            node.scheduleSegment(file, startingFrame: startFrame, frameCount: framesLeft, at: nil) { [weak self] in
                Task { @MainActor in
                    guard let self, self.scheduleGeneration == gen else { return }
                    self.handleTrackEnded()
                }
            }

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
                            self.crossfadeMixer.outputVolume = min(linear * self.audioSettings.volume, 1.5)
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

    /// Used when AVAssetReader/AVAssetExportSession cannot decode the file (e.g. Ogg/Opus container).
    /// AVPlayer has access to iOS's full codec pipeline and can always play .opus files.
    /// Basic play/pause/seek/volume/speed work (speed via `.rate` + `.spectral`
    /// pitch algorithm — see `applyAudioSettings`). EQ, pitch shift, ReplayGain,
    /// 8D, crossfade, and gapless need the AVAudioEngine graph and do not apply.
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
        }

        // Track completion → advances to next song normally.
        NotificationCenter.default.addObserver(
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
                    appError("AVPlayer failed to load track — skipping. \(detail)", category: "audio")
                    self.tearDownOpusPlayer()
                    self.isPlaying = false
                    self.errorMessage = "Could not play this track."
                    self.skipToNext()
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let err = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            appError("AVPlayer playback failed — skipping. \(err?.localizedDescription ?? "unknown")", category: "audio")
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.tearDownOpusPlayer()
                self.isPlaying = false
                self.errorMessage = "Playback error."
                self.skipToNext()
            }
        }

        // Setting `.rate` directly (rather than `.play()`, which always resumes at
        // 1.0×) both starts playback AND applies the user's chosen Speed setting.
        if isPlaying { player.rate = Float(audioSettings.speed) }

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
        if let item = opusPlayer?.currentItem {
            NotificationCenter.default.removeObserver(self, name: .AVPlayerItemFailedToPlayToEndTime, object: item)
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
        let fadeDuration = audioSettings.crossfadeDuration

        // The outgoing node is the one currently playing; incoming is the opposite.
        // Captured as `let` — the upcoming `usingPrimaryNode` flip changes what
        // `activeNode` resolves to, but these bindings keep pointing at the
        // correct physical nodes for the rest of this function and the timer below.
        let outgoing = usingPrimaryNode ? primaryNode : secondaryNode
        let incoming = usingPrimaryNode ? secondaryNode : primaryNode

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
        updateNowPlaying()

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
            activeNode.volume = audioSettings.volume
            isCrossfading = false
        }
    }

    // MARK: - Gapless Playback

    /// Pre-schedules the next track on primaryNode immediately after the current segment,
    /// so AVAudioEngine delivers audio without any gap.
    private func scheduleGaplessNext() {
        guard audioSettings.gaplessEnabled else { return }
        guard let nextSong = peekNextSong(), let nextURL = nextSong.url else { return }
        guard let nextFile = try? AVAudioFile(forReading: nextURL) else { return }

        gaplessScheduled = true
        let gen = scheduleGeneration &+ 1
        scheduleGeneration = gen
        activeNode.scheduleFile(nextFile, at: nil) { [weak self] in
            Task { @MainActor in
                guard let self, self.scheduleGeneration == gen else { return }
                self.handleTrackEnded()
            }
        }
    }

    // MARK: - Queue Helpers

    /// Resolves which queue index plays after `currentIndex`, WITHOUT mutating any state.
    /// Shuffle picks a random index — callers that schedule audio based on this result
    /// (`peekNextSong`) cache it in `pendingNextIndex` so `advanceIndex()` can later
    /// commit to that exact same index rather than rolling a fresh (and likely
    /// different) random pick.
    private func resolveNextIndex() -> Int? {
        guard !queue.isEmpty else { return nil }
        if repeatMode == .one { return currentIndex }
        let nextIndex: Int
        if shuffleEnabled && queue.count > 1 {
            let pool = queue.indices.filter { $0 != currentIndex }
            nextIndex = pool.randomElement() ?? currentIndex
        } else {
            nextIndex = currentIndex + 1
        }
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
        try? session.setActive(true)

        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in self?.handleAudioInterruption(notification) }
        }

        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in self?.handleRouteChange(notification) }
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

        if reason == .oldDeviceUnavailable {
            appLog("Audio route changed — output device removed, pausing", category: "audio")
            pause()
        }
    }

    private func configureEngine() {
        guard !isEngineConfigured else { return }
        engine.attach(primaryNode)
        engine.attach(secondaryNode)
        engine.attach(crossfadeMixer)
        engine.attach(timePitch)
        engine.attach(equalizer)

        // Spatial chain: spatialSourceMixer feeds into environmentNode which
        // enables HRTF-based 3D spatialisation for the 8D-rotation effect.
        engine.attach(spatialSourceMixer)
        engine.attach(environmentNode)

        // Both player nodes connect to separate mixer inputs so their volumes
        // can be ramped independently during a crossfade.
        engine.connect(primaryNode,   to: crossfadeMixer, fromBus: 0, toBus: 0, format: nil)
        engine.connect(secondaryNode, to: crossfadeMixer, fromBus: 0, toBus: 1, format: nil)
        engine.connect(crossfadeMixer, to: timePitch, format: nil)
        engine.connect(timePitch, to: equalizer, format: nil)

        // equalizer → spatialSourceMixer → environmentNode → mainMixerNode
        // The environmentNode is always in the chain; when 8D is inactive the
        // listener orientation is neutral, so it acts as a transparent passthrough.
        engine.connect(equalizer, to: spatialSourceMixer, format: nil)
        engine.connect(spatialSourceMixer, to: environmentNode, format: nil)
        engine.connect(environmentNode, to: engine.mainMixerNode, format: nil)

        configureEnvironmentNode()
        isEngineConfigured = true
    }

    private func configureEnvironmentNode() {
        // Place the listener at the origin looking forward along -Z.
        environmentNode.listenerPosition = AVAudio3DPoint(x: 0, y: 0, z: 0)
        environmentNode.listenerVectorOrientation = AVAudio3DVectorOrientation(
            forward: AVAudio3DVector(x: 0, y: 0, z: -1),
            up: AVAudio3DVector(x: 0, y: 1, z: 0)
        )
        // Use the platform's best HRTF algorithm.
        environmentNode.renderingAlgorithm = .auto

        // Park the spatial source at a fixed position to the right of the listener (radius 2 m).
        // The 8D effect rotates the listener's yaw so this fixed source appears to orbit.
        // When 8D is off the orientation is reset to neutral (yaw=0) so no coloration occurs.
        spatialSourceMixer.position = AVAudio3DPoint(x: 2, y: 0, z: 0)
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
        link.add(to: .main, forMode: .common)
        rotationLink = link
    }

    func stop8DRotation() {
        rotationLink?.invalidate()
        rotationLink = nil
        is8DActive = false
        // Reset pan to center so no stereo imbalance remains after 8D effect stops.
        crossfadeMixer.pan = 0.0
        // Also reset environment node orientation to neutral.
        environmentNode.listenerAngularOrientation = AVAudio3DAngularOrientation(
            yaw: 0, pitch: 0, roll: 0
        )
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
        // Advance angle by one display-link frame (assume 60 fps; CADisplayLink duration
        // could be used for accuracy but 60 fps is the common case on iOS devices).
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
            opusPlayer?.volume = audioSettings.volume
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
                band.gain = gain
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

        // ReplayGain: apply a gain offset via the crossfade mixer's output volume.
        // When enabled, output is limited to 75 % of the user-chosen volume to guard against
        // clipping on loud masters (equivalent to a -2.5 dB protective ceiling).
        // A full implementation would read REPLAYGAIN_TRACK_GAIN from file metadata and
        // compute a per-track linear gain; see scheduleCurrent for the metadata path.
        if audioSettings.replayGainEnabled {
            crossfadeMixer.outputVolume = min(audioSettings.volume, 0.75)
        } else {
            crossfadeMixer.outputVolume = 1.0
        }

        // Do NOT call updateNowPlaying() here — this runs on every EQ slider drag.
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

    private func timerTick() {
        updatePositionFromPlayer()

        // AB Repeat enforcement
        if abRepeatEnabled,
           let start = abRepeatStart,
           let end = abRepeatEnd,
           position >= end {
            seek(to: start)
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

        let elapsedFrames = Double(playerTime.sampleTime)
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
        WidgetDataService.shared.update(song: song, isPlaying: isPlaying, artwork: image)
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
