@preconcurrency import AVFoundation
import AudioToolbox
import Foundation
import MediaPlayer
import UIKit

extension AudioPlayerManager {

    // MARK: - Silence Trimming (leading only — see scheduleCurrent's call site)

    /// Scans up to `maxScanSeconds` of `file` (from its very start) for a
    /// silent lead-in and returns the frame offset where the signal first
    /// exceeds `thresholdLinear` in any channel — or 0 if no leading silence
    /// is found (including on any read failure, so this fails safe to "don't
    /// trim anything" rather than risk skipping real audio).
    ///
    /// Deliberately scoped to the LEADING edge only, not trailing silence —
    /// detecting trailing silence would need scanning from the end of the
    /// file (or monitoring live playback), which is meaningfully more
    /// complex and isn't implemented here.
    // maxScanSeconds trimmed from an earlier 4.0 — this scan (decode + linear
    // sample sweep) runs synchronously on the main thread in `scheduleCurrent`
    // for every fresh track start when silence trimming is on, and real
    // leading silence is virtually always under 2s; halving the window
    // roughly halves that per-track-start cost without missing realistic
    // cases. A full async rewrite of `scheduleCurrent` would remove the
    // main-thread cost entirely but touches the core scheduling path shared
    // by every playback/skip/gapless transition — too risky to change here
    // without the ability to compile/test it.
    func detectLeadingSilenceFrames(
        in file: AVAudioFile,
        thresholdLinear: Float = 0.02,
        maxScanSeconds: Double = 2.0
    ) -> AVAudioFramePosition {
        let format = file.processingFormat
        let sampleRate = format.sampleRate
        guard sampleRate > 0, file.length > 0 else { return 0 }

        let maxFrames = AVAudioFrameCount(min(Double(file.length), maxScanSeconds * sampleRate))
        guard maxFrames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: maxFrames) else {
            return 0
        }

        // Reading moves the file's own read cursor — restore it afterward so
        // this scan never disturbs the caller's own subsequent scheduling.
        let originalPosition = file.framePosition
        defer { file.framePosition = originalPosition }
        file.framePosition = 0

        do {
            try file.read(into: buffer, frameCount: maxFrames)
        } catch {
            return 0
        }

        guard let channelData = buffer.floatChannelData else { return 0 }
        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)

        for frame in 0..<frameLength {
            for channel in 0..<channelCount {
                if abs(channelData[channel][frame]) > thresholdLinear {
                    return AVAudioFramePosition(frame)
                }
            }
        }
        // The entire scanned prefix was silent (rare) — trim exactly that much,
        // not the whole file, so playback still starts promptly rather than
        // potentially skipping past real (very quiet) content beyond the scan window.
        return AVAudioFramePosition(frameLength)
    }
}
