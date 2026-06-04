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
    @Published private(set) var isPlaying = false
    @Published var position: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var repeatMode: RepeatMode = .off
    @Published var shuffleEnabled = false
    @Published var audioSettings = AudioSettings() {
        didSet { applyAudioSettings() }
    }
    @Published var errorMessage: String?

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
    private var rotationHz: Double = 0.18
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

    // The node playing (or scheduled for) the current song.
    private var activeNode: AVAudioPlayerNode {
        if isCrossfading {
            // During a crossfade the *incoming* node (opposite side) has the new track.
            return usingPrimaryNode ? secondaryNode : primaryNode
        }
        return usingPrimaryNode ? primaryNode : secondaryNode
    }

    // MARK: Private — Playback Bookkeeping

    private var audioFile: AVAudioFile?
    private var fileStartFrame: AVAudioFramePosition = 0
    private var timer: Timer?
    private var isEngineConfigured = false

    // Crossfade state
    private var isCrossfading = false
    private var crossfadeTimer: Timer?

    // Gapless: the next file pre-loaded and scheduled on the active node.
    private var gaplessScheduled = false

    // Set to true while an async HTTP download + schedule is in progress.
    // Prevents updatePositionFromPlayer() from overwriting `position` with a
    // stale value from the AVAudioPlayerNode before it has actually started.
    private var isSchedulingAsync = false

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
    }

    deinit {
        timer?.invalidate()
        crossfadeTimer?.invalidate()
        rotationLink?.invalidate()
        tremoloLink?.invalidate()
        vibratoLink?.invalidate()
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
        if autoplay {
            playCurrent(from: 0)
        } else {
            prepareCurrent()
        }
    }

    func play(song: Song, in songs: [Song]) {
        let source = songs.isEmpty ? [song] : songs
        let index = source.firstIndex(where: { $0.id == song.id }) ?? 0
        setQueue(source, startIndex: index, autoplay: true)
    }

    func togglePlayPause() {
        if isPlaying { pause() } else { resume() }
    }

    func pause() {
        updatePositionFromPlayer()
        primaryNode.pause()
        secondaryNode.pause()
        isPlaying = false
        stopTimer()
        updateNowPlaying()
        savePlaybackState()
    }

    func resume() {
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
        }
    }

    func stop() {
        primaryNode.stop()
        secondaryNode.stop()
        isCrossfading = false
        crossfadeTimer?.invalidate()
        crossfadeTimer = nil
        gaplessScheduled = false
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
        gaplessScheduled = false
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
            playCurrent(from: 0)
            savePlaybackState()
        } else if repeatMode == .all {
            currentIndex = 0
            currentSong = queue[currentIndex]
            gaplessScheduled = false
            playCurrent(from: 0)
            savePlaybackState()
        } else {
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

        // Sanitise URLs before restoring.
        // ipod-library:// asset URLs are session-scoped and expire across app launches.
        // Clear them so scheduleCurrent() fails gracefully instead of crashing on a
        // stale MPMediaItem URL. Song metadata (title/artist) is preserved for display.
        let sanitisedQueue = snapshot.queue.map { song -> Song in
            if let url = song.url, url.scheme == "ipod-library" {
                var cleaned = song
                cleaned.url = nil
                return cleaned
            }
            return song
        }

        queue = sanitisedQueue
        currentIndex = min(max(snapshot.currentIndex, 0), sanitisedQueue.count - 1)
        currentSong = queue[currentIndex]
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
        cancelCrossfade()

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
        startEngineIfNeeded()
        activeNode.play()
        isPlaying = true
        startTimer()
        updateNowPlaying()
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

        // Local file — schedule directly.
        do {
            let node = activeNode
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

            node.scheduleSegment(file, startingFrame: startFrame, frameCount: framesLeft, at: nil) { [weak self] in
                Task { @MainActor in self?.handleTrackEnded() }
            }
        } catch {
            errorMessage = error.localizedDescription
            isPlaying = false
        }
    }

    /// Downloads an HTTP/HTTPS audio URL to a named temp file (using a simple hash as the cache
    /// key), then schedules it for playback via the existing AVAudioFile pipeline.
    ///
    /// Called from `scheduleCurrent` when the song URL has an http/https scheme.
    /// This method is responsible for starting the engine and calling `node.play()` because
    /// `playCurrent` returns early before doing so when it detects an HTTP URL.
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

            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("stream_\(cacheKey).m4a")

            if !FileManager.default.fileExists(atPath: tempURL.path) {
                let (downloaded, _) = try await URLSession.shared.download(from: url)
                // Move from the system-assigned temp location to our named cache file.
                try? FileManager.default.removeItem(at: tempURL)
                try FileManager.default.moveItem(at: downloaded, to: tempURL)
            }

            // From here on this is identical to the local-file path in scheduleCurrent.
            let node = activeNode
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

            node.scheduleSegment(file, startingFrame: startFrame, frameCount: framesLeft, at: nil) { [weak self] in
                Task { @MainActor in self?.handleTrackEnded() }
            }

            // Start playback — playCurrent already set isPlaying = true before the download.
            if isPlaying {
                startEngineIfNeeded()
                node.play()
                startTimer()
            }
            updateNowPlaying()

        } catch {
            errorMessage = "Could not load audio: \(error.localizedDescription)"
            isPlaying = false
        }
    }

    /// Called by the AVAudioPlayerNode completion block when the current segment finishes.
    private func handleTrackEnded() {
        guard isPlaying else { return }

        // If gapless already scheduled the next file on this node, advance the index and update UI.
        if gaplessScheduled {
            advanceIndex()
            gaplessScheduled = false
            updateNowPlaying()
            // Schedule completion for the newly playing segment.
            scheduleGaplessNext()
            return
        }

        if audioSettings.crossfadeEnabled {
            beginCrossfade()
        } else {
            skipToNext()
        }
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
        let outgoing = usingPrimaryNode ? primaryNode : secondaryNode
        let incoming = usingPrimaryNode ? secondaryNode : primaryNode

        incoming.volume = 0
        incoming.scheduleFile(nextFile, at: nil) { [weak self] in
            Task { @MainActor in
                // Incoming finished its full file — crossfade is complete; swap active node.
                self?.isCrossfading = false
                self?.usingPrimaryNode.toggle()
                self?.handleTrackEnded()
            }
        }
        startEngineIfNeeded()
        incoming.play()

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
                    self.finishCrossfade(nextSong: nextSong, nextFile: nextFile)
                }
            }
        }
    }

    /// Called when the volume-ramp timer completes.
    /// The incoming node is still mid-playback — only stop the outgoing one.
    private func finishCrossfade(nextSong: Song, nextFile: AVAudioFile) {
        let outgoing = usingPrimaryNode ? primaryNode : secondaryNode
        outgoing.stop()
        outgoing.volume = audioSettings.volume
        // Incoming keeps playing; isCrossfading stays true so activeNode and
        // updatePositionFromPlayer keep using the incoming node until it finishes.
        advanceIndex()
        currentSong = nextSong
        audioFile = nextFile
        fileStartFrame = 0
        duration = nextFile.duration
        position = 0
        gaplessScheduled = false
        updateNowPlaying()
    }

    private func cancelCrossfade() {
        crossfadeTimer?.invalidate()
        crossfadeTimer = nil
        if isCrossfading {
            // Stop the incoming node and restore both volumes.
            let incoming = usingPrimaryNode ? secondaryNode : primaryNode
            incoming.stop()
            incoming.volume = audioSettings.volume
            let outgoing = usingPrimaryNode ? primaryNode : secondaryNode
            outgoing.volume = audioSettings.volume
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
        activeNode.scheduleFile(nextFile, at: nil) { [weak self] in
            Task { @MainActor in self?.handleTrackEnded() }
        }
    }

    // MARK: - Queue Helpers

    private func peekNextSong() -> Song? {
        guard !queue.isEmpty else { return nil }
        if repeatMode == .one { return currentSong }
        let nextIndex: Int
        if shuffleEnabled && queue.count > 1 {
            let pool = queue.indices.filter { $0 != currentIndex }
            nextIndex = pool.randomElement() ?? currentIndex
        } else {
            nextIndex = currentIndex + 1
        }
        if nextIndex < queue.count { return queue[nextIndex] }
        if repeatMode == .all { return queue[0] }
        return nil
    }

    private func advanceIndex() {
        guard !queue.isEmpty else { return }
        if repeatMode == .one { return }
        let nextIndex: Int
        if shuffleEnabled && queue.count > 1 {
            let pool = queue.indices.filter { $0 != currentIndex }
            nextIndex = pool.randomElement() ?? currentIndex
        } else {
            nextIndex = currentIndex + 1
        }
        if nextIndex < queue.count {
            currentIndex = nextIndex
        } else if repeatMode == .all {
            currentIndex = 0
        }
        currentSong = queue[currentIndex]
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
            if isPlaying {
                pause()
                wasInterrupted = true
            }
        case .ended:
            wasInterrupted = false
            guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) {
                // Re-activate the audio session before restarting the engine; the
                // system deactivates it when an interruption begins.
                try? AVAudioSession.sharedInstance().setActive(true)
                resume()
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
            band.bandwidth  = 0.5   // ~half-octave Q; tighter bands for more precise control
            band.gain       = 0
            band.bypass     = true
        }
    }

    private func startEngineIfNeeded() {
        guard !engine.isRunning else { return }
        do {
            try engine.start()
        } catch {
            // After an audio-session interruption the engine may need a full reset.
            // Tear down the graph, rebuild it, and retry once.
            isEngineConfigured = false
            configureEngine()
            configureEqualizer()
            do {
                try engine.start()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - 8D Rotation

    func start8DRotation(hz: Double = 0.18) {
        stop8DRotation()
        guard engine.isRunning else { return }  // engine must be running for spatial audio
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
        // Reset listener to neutral orientation so no spatial coloration remains.
        environmentNode.listenerAngularOrientation = AVAudio3DAngularOrientation(
            yaw: 0, pitch: 0, roll: 0
        )
    }

    @objc private func update8DRotation() {
        guard is8DActive else { return }
        // Advance angle by one display-link frame (assume 60 fps; CADisplayLink duration
        // could be used for accuracy but 60 fps is the common case on iOS devices).
        rotationAngle += 2 * .pi * rotationHz / 60.0
        // Wrap to keep angle in [0, 2π) to avoid floating-point drift.
        if rotationAngle >= 2 * .pi { rotationAngle -= 2 * .pi }
        // Rotate the listener's yaw. The spatial source is fixed to the right (x=2),
        // so rotating the listener's facing direction makes the source appear to orbit.
        let yawDegrees = Float(rotationAngle * 180.0 / .pi)
        environmentNode.listenerAngularOrientation = AVAudio3DAngularOrientation(
            yaw: yawDegrees, pitch: 0, roll: 0
        )
    }

    // MARK: - Tremolo

    func startTremolo(frequency: Double = 4.0, depth: Float = 0.45) {
        stopTremolo()
        guard engine.isRunning else { return }  // engine must be running for tremolo to be heard
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
        guard engine.isRunning else { return }  // engine must be running for vibrato to be heard
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

    /// Fetches artwork asynchronously and injects it into the Now Playing info center.
    private func updateNowPlayingArtwork(for song: Song?) async {
        guard let song else { return }
        guard let image = await ArtworkService.shared.loadArtwork(for: song) else { return }
        let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyArtwork] = artwork
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
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
