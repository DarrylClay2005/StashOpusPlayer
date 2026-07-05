@preconcurrency import AVFoundation
import AudioToolbox
import Foundation
import MediaPlayer
import UIKit

extension AudioPlayerManager {

    // MARK: - Spatial Audio routing

    /// Wires (or unwires) `AVAudioEnvironmentNode` into the signal path.
    /// When disabled — the default, and the only state existing users ever
    /// see unless they opt in — `limiter` connects straight to
    /// `mainMixerNode`, identical to the graph before this feature existed.
    /// When enabled, the final mix is routed through `spatialSourceMixer` (the
    /// HRTF-positionable source) and `environmentNode` (the binaural
    /// renderer + listener), anchored as a single source in front of the
    /// listener and head-tracked when compatible headphones are connected.
    func setSpatialAudioRouting(_ enabled: Bool) {
        guard isEngineConfigured, enabled != isSpatialAudioRouted else { return }
        isSpatialAudioRouted = enabled

        engine.disconnectNodeOutput(limiter)
        engine.disconnectNodeOutput(spatialSourceMixer)
        engine.disconnectNodeOutput(environmentNode)

        if enabled {
            engine.connect(limiter, to: spatialSourceMixer, format: nil)
            // Force MONO on this specific connection so AVAudioEngine downmixes
            // the stereo bed at the boundary and the environment node treats it
            // as a single point source — genuinely HRTF-spatialized. Leaving
            // this connection stereo (format: nil) would instead pass it
            // through as an unspatialized ambient bed, i.e. do nothing audible.
            let monoFormat = AVAudioFormat(
                standardFormatWithSampleRate: spatialSourceMixer.outputFormat(forBus: 0).sampleRate,
                channels: 1
            )
            engine.connect(spatialSourceMixer, to: environmentNode, format: monoFormat)
            engine.connect(environmentNode, to: engine.mainMixerNode, format: nil)

            environmentNode.renderingAlgorithm = .HRTFHQ
            environmentNode.listenerPosition = AVAudio3DPoint(x: 0, y: 0, z: 0)
            environmentNode.listenerAngularOrientation = AVAudio3DAngularOrientation(yaw: 0, pitch: 0, roll: 0)
            // Anchor the whole mix directly in front of the listener — HRTF
            // rendering externalizes it ("outside your head") even without
            // head tracking; tracking (when available) then keeps it anchored
            // in place as the listener turns.
            spatialSourceMixer.destination(forMixer: environmentNode, bus: 0)?.position = AVAudio3DPoint(x: 0, y: 0, z: -1)

            if SpatialAudioService.shared.isHeadTrackingAvailable {
                SpatialAudioService.shared.onOrientationUpdate = { [weak self] orientation in
                    self?.environmentNode.listenerAngularOrientation = orientation
                }
                SpatialAudioService.shared.startTracking()
            }
        } else {
            SpatialAudioService.shared.stopTracking()
            SpatialAudioService.shared.onOrientationUpdate = nil
            engine.connect(limiter, to: engine.mainMixerNode, format: nil)
        }
    }

    /// Configures `limiter` as a fast brick-wall peak limiter: threshold just
    /// under 0 dBFS with a very high ratio, near-instant attack, and a short
    /// release. With this in place, raising `crossfadeMixer.outputVolume`
    /// above 1.0 (via `audioSettings.volume`, up to `AudioSettings.maxVolume`)
    /// makes playback louder without the output signal hard-clipping.
    func configureLimiter() {
        let unit = limiter.audioUnit
        AudioUnitSetParameter(unit, kDynamicsProcessorParam_Threshold, kAudioUnitScope_Global, 0, -1.0, 0)    // dB — start limiting just below full scale
        AudioUnitSetParameter(unit, kDynamicsProcessorParam_HeadRoom, kAudioUnitScope_Global, 0, 1.0, 0)      // dB of headroom above the threshold
        AudioUnitSetParameter(unit, kDynamicsProcessorParam_AttackTime, kAudioUnitScope_Global, 0, 0.001, 0)  // seconds — fast enough to catch transients
        AudioUnitSetParameter(unit, kDynamicsProcessorParam_ReleaseTime, kAudioUnitScope_Global, 0, 0.05, 0)  // seconds — short so it doesn't pump audibly
        AudioUnitSetParameter(unit, kDynamicsProcessorParam_OverallGain, kAudioUnitScope_Global, 0, 0, 0)
        limiter.bypass = false
    }

    func configureEqualizer() {
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

    func startEngineIfNeeded() {
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
            // engine.reset() wipes all connections, including any spatial-audio
            // routing — clear the tracking flag too so configureEngine()'s
            // default (unrouted) connection isn't skipped by a stale "already
            // routed" guard once applyAudioSettings() re-runs below.
            isSpatialAudioRouted = false
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
}
