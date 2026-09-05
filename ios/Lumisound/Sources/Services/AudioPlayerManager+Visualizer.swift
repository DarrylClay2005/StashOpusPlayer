@preconcurrency import AVFoundation
import AudioToolbox
import Foundation
import MediaPlayer
import UIKit

extension AudioPlayerManager {

    // MARK: - Visualizer Tap
    //
    // Installed on `mainMixerNode` for analysis only — a read-only monitoring
    // tap, not an insert node, so it never affects what's actually played.

    func startVisualizerTap(handler: @escaping (AVAudioPCMBuffer) -> Void) {
        guard !visualizerTapInstalled else { return }
        visualizerTapInstalled = true
        // The spectrum uses a 2048-point FFT, but processing every 2048-frame
        // callback creates a main-actor update roughly 40 times per second.
        // A 4096-frame tap preserves the FFT resolution while halving callback,
        // allocation, and SwiftUI publication overhead.
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 4096, format: nil) { buffer, _ in
            handler(buffer)
        }
    }

    func stopVisualizerTap() {
        guard visualizerTapInstalled else { return }
        visualizerTapInstalled = false
        engine.mainMixerNode.removeTap(onBus: 0)
    }
}
