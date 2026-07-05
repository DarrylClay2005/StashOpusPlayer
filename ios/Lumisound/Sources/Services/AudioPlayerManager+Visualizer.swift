@preconcurrency import AVFoundation
import AudioToolbox
import Foundation
import MediaPlayer
import UIKit

extension AudioPlayerManager {

    // MARK: - Visualizer Tap
    //
    // Deliberately installed on `mainMixerNode`, NOT `outputNode` — Karaoke's
    // tap already owns `outputNode` bus 0, and a node only supports one tap
    // per bus at a time (installing a second silently replaces the first).
    // Using a different node entirely means this can run independently of
    // Karaoke Mode with no conflict.

    var visualizerTapInstalled = false

    func startVisualizerTap(handler: @escaping (AVAudioPCMBuffer) -> Void) {
        guard !visualizerTapInstalled else { return }
        visualizerTapInstalled = true
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 2048, format: nil) { buffer, _ in
            handler(buffer)
        }
    }

    func stopVisualizerTap() {
        guard visualizerTapInstalled else { return }
        visualizerTapInstalled = false
        engine.mainMixerNode.removeTap(onBus: 0)
    }

    /// Applies stereo center-channel cancellation in-place to a PCM buffer.
    /// For each stereo pair: out_L = (L − R) × 0.5 × level; out_R = (R − L) × 0.5 × level.
    func applyCenterCancellation(to buffer: AVAudioPCMBuffer, level: Float) {
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
}
