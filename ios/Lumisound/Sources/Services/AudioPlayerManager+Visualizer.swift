@preconcurrency import AVFoundation
import AudioToolbox
import Foundation
import MediaPlayer
import UIKit

extension AudioPlayerManager {

    // MARK: - Visualizer Tap
    //
    // Installed on `mainMixerNode` for analysis only — Karaoke is a real
    // insert node (`karaokeUnit`, wired between `mainMixerNode` and
    // `outputNode`), not a tap, so there's no shared-bus conflict to avoid
    // here anymore; this tap runs independently either way.

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
