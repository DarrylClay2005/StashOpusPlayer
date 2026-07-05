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
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 2048, format: nil) { buffer, _ in
            handler(buffer)
        }
    }

    func stopVisualizerTap() {
        guard visualizerTapInstalled else { return }
        visualizerTapInstalled = false
        engine.mainMixerNode.removeTap(onBus: 0)
    }
}
