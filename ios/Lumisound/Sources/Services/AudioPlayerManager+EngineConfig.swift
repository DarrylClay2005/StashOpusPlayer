@preconcurrency import AVFoundation
import AudioToolbox
import Foundation
import MediaPlayer
import UIKit

extension AudioPlayerManager {

    // MARK: - Audio Engine Configuration

    func configureAudioSession() {
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

    func handleEngineConfigurationChange() {
        guard !isUsingOpusPlayer, isPlaying else { return }
        appWarn("Audio engine configuration changed — restarting engine to resume playback", category: "audio")
        guard !engine.isRunning else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        startEngineIfNeeded()
        if !activeNode.isPlaying {
            activeNode.play()
        }
    }

    func handleAudioInterruption(_ notification: Notification) {
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

    func handleRouteChange(_ notification: Notification) {
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

    func configureEngine() {
        guard !isEngineConfigured else { return }
        engine.attach(primaryNode)
        engine.attach(secondaryNode)
        engine.attach(primaryBeatMatch)
        engine.attach(secondaryBeatMatch)
        engine.attach(crossfadeMixer)
        engine.attach(timePitch)
        engine.attach(equalizer)
        engine.attach(reverb)
        engine.attach(reverbMixer)
        engine.attach(reverbWetMixer)
        engine.attach(nightModeCompressor)
        engine.attach(limiter)
        engine.attach(environmentNode)
        engine.attach(spatialSourceMixer)
        configureLimiter()
        configureNightModeCompressor()
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
        engine.connect(equalizer, to: nightModeCompressor, format: nil)
        // Parallel reverb: compressor output fans out to the dry sum bus AND the reverb send.
        engine.connect(nightModeCompressor, to: [
            AVAudioConnectionPoint(node: reverbMixer, bus: 0),   // dry, full level
            AVAudioConnectionPoint(node: reverb, bus: 0)         // wet send
        ], fromBus: 0, format: nil)
        engine.connect(reverb, to: reverbWetMixer, format: nil)
        engine.connect(reverbWetMixer, to: reverbMixer, fromBus: 0, toBus: 1, format: nil)
        engine.connect(reverbMixer, to: limiter, format: nil)
        engine.connect(limiter, to: engine.mainMixerNode, format: nil)

        isEngineConfigured = true

        // If the karaoke unit finished its async instantiation before this
        // (re)configuration ran — e.g. on an engine-reset rebuild, where the
        // unit already exists from an earlier launch — re-attach it now.
        // Otherwise `configureKaraokeUnit`'s completion handler wires it in
        // itself once instantiation completes.
        if let karaokeUnit {
            wireKaraokeUnitIntoGraph(karaokeUnit)
        }
    }

    /// Registers and asynchronously instantiates `KaraokeAudioUnit`, a custom
    /// in-process Audio Unit performing real stereo center-channel
    /// cancellation. Async instantiation is unavoidable for a custom
    /// component (unlike `limiter`/`nightModeCompressor`, which wrap
    /// pre-registered Apple system components and can be built synchronously)
    /// — see `KaraokeAudioUnit`'s doc comment. Runs once, from `init()`.
    func configureKaraokeUnit() {
        AUAudioUnit.registerSubclass(
            KaraokeAudioUnit.self,
            as: .karaokeCancellation,
            name: "Lumisound Karaoke",
            version: 1
        )
        AVAudioUnit.instantiate(with: .karaokeCancellation, options: []) { [weak self] avAudioUnit, error in
            guard let self else { return }
            guard let avAudioUnit else {
                if let error {
                    appError("Failed to instantiate Karaoke audio unit: \(error.localizedDescription)", category: "audio")
                }
                return
            }
            Task { @MainActor in
                (avAudioUnit.auAudioUnit as? KaraokeAudioUnit)?.level = self.pendingKaraokeLevel
                avAudioUnit.auAudioUnit.shouldBypassEffect = !self.isKaraokeActive
                self.karaokeUnit = avAudioUnit
                self.wireKaraokeUnitIntoGraph(avAudioUnit)
            }
        }
    }

    /// Attaches (or re-attaches, after an `engine.reset()` rebuild) `unit`
    /// and splices it between `mainMixerNode` and `outputNode` — the single
    /// point every playback path (normal, spatial-audio-routed, mono-downmixed)
    /// converges on before reaching the hardware, matching what the old
    /// (broken) tap on `outputNode` was trying to reach. No-ops until
    /// `configureEngine()` has run at least once.
    ///
    /// Fully *stops* the engine around the graph mutation, not just
    /// `pause()` — attach/connect/disconnect are topology changes, and
    /// `pause()` leaves the render graph "live"/locked in a rendering-ready
    /// state rather than releasing it, unlike `stop()`. This can be invoked
    /// from the async instantiation callback, which may fire while playback
    /// is already running (e.g. autoplay-on-launch racing the async
    /// instantiate), so this has to handle that case correctly rather than
    /// assuming the engine is always stopped when it runs.
    func wireKaraokeUnitIntoGraph(_ unit: AVAudioUnit) {
        guard isEngineConfigured else { return }
        let wasRunning = engine.isRunning
        if wasRunning { engine.stop() }
        engine.attach(unit)
        engine.disconnectNodeOutput(engine.mainMixerNode)
        engine.connect(engine.mainMixerNode, to: unit, format: nil)
        engine.connect(unit, to: engine.outputNode, format: nil)
        if wasRunning { try? engine.start() }
    }

    /// Loads the default factory preset and zeroes the wet/dry mix — the real
    /// mix level/preset is then applied immediately by `applyAudioSettings()`,
    /// which runs as soon as the engine starts (or `audioSettings` is restored
    /// from disk) so reverb never plays at a stale level after a rebuild.
    func configureReverb() {
        reverb.loadFactoryPreset(.mediumRoom)
        // The reverb node is always 100% wet — it only ever produces the tail;
        // the blend with the dry signal happens at `reverbMixer`. The real
        // reverb amount lives on `reverbWetMixer.outputVolume`, set (along with
        // the dry bus at unity) by `applyAudioSettings()`.
        reverb.wetDryMix = 100
        reverbWetMixer.outputVolume = 0
        reverbMixer.outputVolume = 1
        loadedReverbPreset = .mediumRoom
    }

    /// Maps our Codable `ReverbRoomPreset` (Models layer, no AVFoundation
    /// dependency) onto the real `AVAudioUnitReverbPreset`.
    func avReverbPreset(for preset: ReverbRoomPreset) -> AVAudioUnitReverbPreset {
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
}
