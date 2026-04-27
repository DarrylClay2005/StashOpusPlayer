import AVFoundation
import Foundation
import MediaPlayer

@MainActor
final class AudioPlayerManager: ObservableObject {
    @Published private(set) var currentSong: Song?
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

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let timePitch = AVAudioUnitTimePitch()
    private let equalizer = AVAudioUnitEQ(numberOfBands: 10)
    private var audioFile: AVAudioFile?
    private var fileStartFrame: AVAudioFramePosition = 0
    private var playbackStartedAt: Date?
    private var timer: Timer?
    private var isEngineConfigured = false

    init() {
        configureAudioSession()
        configureEngine()
        configureEqualizer()
        configureRemoteCommands()
    }

    deinit {
        timer?.invalidate()
        MPRemoteCommandCenter.shared().playCommand.removeTarget(nil)
        MPRemoteCommandCenter.shared().pauseCommand.removeTarget(nil)
        MPRemoteCommandCenter.shared().togglePlayPauseCommand.removeTarget(nil)
        MPRemoteCommandCenter.shared().nextTrackCommand.removeTarget(nil)
        MPRemoteCommandCenter.shared().previousTrackCommand.removeTarget(nil)
    }

    func setQueue(_ songs: [Song], startIndex: Int = 0, autoplay: Bool = true) {
        guard !songs.isEmpty else { return }
        queue = songs
        currentIndex = min(max(startIndex, 0), songs.count - 1)
        currentSong = queue[currentIndex]
        position = 0
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
        if isPlaying {
            pause()
        } else {
            resume()
        }
    }

    func pause() {
        updatePositionFromPlayer()
        playerNode.pause()
        isPlaying = false
        playbackStartedAt = nil
        stopTimer()
        updateNowPlaying()
    }

    func resume() {
        guard currentSong != nil else {
            if !queue.isEmpty { playCurrent(from: position) }
            return
        }

        if !playerNode.isPlaying {
            startEngineIfNeeded()
            playerNode.play()
            playbackStartedAt = Date()
            isPlaying = true
            startTimer()
            updateNowPlaying()
        }
    }

    func stop() {
        playerNode.stop()
        position = 0
        isPlaying = false
        playbackStartedAt = nil
        stopTimer()
        updateNowPlaying()
    }

    func seek(to newPosition: TimeInterval) {
        let target = max(0, min(newPosition, duration))
        position = target
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

        let nextIndex = shuffleEnabled
            ? Int.random(in: queue.indices)
            : currentIndex + 1

        if nextIndex < queue.count {
            currentIndex = nextIndex
            currentSong = queue[currentIndex]
            playCurrent(from: 0)
        } else if repeatMode == .all {
            currentIndex = 0
            currentSong = queue[currentIndex]
            playCurrent(from: 0)
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
        playCurrent(from: 0)
    }

    func cycleRepeatMode() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
        updateNowPlaying()
    }

    func toggleShuffle() {
        shuffleEnabled.toggle()
        updateNowPlaying()
    }

    private func prepareCurrent() {
        scheduleCurrent(from: position)
        updateNowPlaying()
    }

    private func playCurrent(from startTime: TimeInterval) {
        scheduleCurrent(from: startTime)
        startEngineIfNeeded()
        playerNode.play()
        playbackStartedAt = Date()
        isPlaying = true
        startTimer()
        updateNowPlaying()
    }

    private func scheduleCurrent(from startTime: TimeInterval) {
        guard let song = currentSong, let url = song.url else {
            errorMessage = "This song does not have a local playable URL."
            return
        }

        do {
            playerNode.stop()
            let file = try AVAudioFile(forReading: url)
            audioFile = file
            duration = file.duration
            let sampleRate = file.processingFormat.sampleRate
            let startFrame = max(0, AVAudioFramePosition(startTime * sampleRate))
            let framesLeft = max(0, AVAudioFrameCount(file.length - startFrame))
            fileStartFrame = startFrame
            position = startTime

            playerNode.scheduleSegment(file, startingFrame: startFrame, frameCount: framesLeft, at: nil) { [weak self] in
                Task { @MainActor in
                    self?.handleTrackEnded()
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            isPlaying = false
        }
    }

    private func handleTrackEnded() {
        guard isPlaying else { return }
        skipToNext()
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.allowAirPlay, .allowBluetoothA2DP])
            try session.setActive(true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func configureEngine() {
        guard !isEngineConfigured else { return }
        engine.attach(playerNode)
        engine.attach(timePitch)
        engine.attach(equalizer)
        engine.connect(playerNode, to: timePitch, format: nil)
        engine.connect(timePitch, to: equalizer, format: nil)
        engine.connect(equalizer, to: engine.mainMixerNode, format: nil)
        isEngineConfigured = true
    }

    private func configureEqualizer() {
        let frequencies: [Float] = [32, 64, 125, 250, 500, 1_000, 2_000, 4_000, 8_000, 16_000]
        for (index, band) in equalizer.bands.enumerated() {
            band.filterType = .parametric
            band.frequency = frequencies[index]
            band.bandwidth = 0.8
            band.gain = 0
            band.bypass = true
        }
    }

    private func startEngineIfNeeded() {
        do {
            if !engine.isRunning {
                try engine.start()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applyAudioSettings() {
        playerNode.volume = audioSettings.volume
        timePitch.rate = audioSettings.speed
        timePitch.pitch = audioSettings.pitchSemitones * 100

        for (index, band) in equalizer.bands.enumerated() {
            band.bypass = !audioSettings.equalizerEnabled
            if audioSettings.eqBands.indices.contains(index) {
                band.gain = audioSettings.eqBands[index]
            }
        }
        updateNowPlaying()
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updatePositionFromPlayer()
                self?.updateNowPlaying()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func updatePositionFromPlayer() {
        guard let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime),
              let file = audioFile
        else { return }

        let elapsedFrames = Double(playerTime.sampleTime)
        position = min(duration, Double(fileStartFrame) / file.processingFormat.sampleRate + elapsedFrames / playerTime.sampleRate)
    }

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
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? audioSettings.speed : 0
        ]

        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = audioSettings.speed
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.nextTrackCommand.isEnabled = true
        center.previousTrackCommand.isEnabled = true

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
    }
}

private extension AVAudioFile {
    var duration: TimeInterval {
        Double(length) / processingFormat.sampleRate
    }
}
