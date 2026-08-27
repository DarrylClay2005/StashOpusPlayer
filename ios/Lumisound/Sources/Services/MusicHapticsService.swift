import CoreHaptics
import Foundation

/// Provides an audio-reactive haptic accompaniment for local/engine playback.
///
/// Apple Music's Music Haptics patterns are not a public third-party API. This
/// service uses the same public Core Haptics framework available to apps,
/// driving short low-frequency transients from the live analyzer's energy
/// changes. It deliberately does not run for the AVPlayer compatibility path:
/// that path bypasses the AVAudioEngine tap, so there is no reliable audio
/// signal to synchronize against.
@MainActor
final class MusicHapticsService {
    static let shared = MusicHapticsService()

    private var engine: CHHapticEngine?
    private var timer: Timer?
    private var previousEnergy: Float = 0
    private var lastTransientDate: Date = .distantPast
    private var isRunning = false

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
        appLog("Music Haptics enabled for engine playback", category: "audio")
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
    }

    private func sampleAudioEnergy() {
        guard let player = AudioPlayerManager.shared,
              player.isPlaying,
              !player.isUsingOpusPlayer else {
            stop()
            return
        }

        let analyzer = AudioVisualizerService.shared
        // Bass is weighted slightly higher because it produces the most
        // intelligible tactile pulse while keeping vocals and cymbals present.
        let energy = min(
            1,
            max(0, analyzer.bassLevel * 0.45 + analyzer.midLevel * 0.35 + analyzer.trebleLevel * 0.20)
        )
        let rise = energy - previousEnergy
        previousEnergy = previousEnergy * 0.82 + energy * 0.18

        // A transient is emitted only for a meaningful onset and is rate
        // limited so sustained bass does not become an unpleasant buzz.
        let now = Date()
        guard energy > 0.10,
              rise > 0.035,
              now.timeIntervalSince(lastTransientDate) >= 0.11 else { return }
        lastTransientDate = now

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
              let player = try? hapticEngine.makePlayer(with: pattern) else { return }
        try? player.start(atTime: CHHapticTimeImmediate)
    }
}
