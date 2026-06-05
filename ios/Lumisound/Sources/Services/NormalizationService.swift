import Foundation
import AVFoundation

/// Computes and caches RMS-based loudness gain for audio files that lack embedded
/// ReplayGain tags. Used as a fallback by AudioPlayerManager.scheduleCurrent.
actor NormalizationService {
    static let shared = NormalizationService()

    private let udKey = "normalization_gain_cache_v1"
    private var cache: [String: Float]

    private init() {
        cache = (UserDefaults.standard.dictionary(forKey: "normalization_gain_cache_v1") as? [String: Float]) ?? [:]
    }

    /// Returns a dB gain offset for the file at `url`.
    /// Checks cache first; computes from audio samples on cache miss.
    /// Returns 0 if analysis is not possible (e.g. unsupported format like .opus).
    func gain(for url: URL) async -> Float {
        let key = stableKey(for: url)
        if let hit = cache[key] { return hit }

        let computed = await Task.detached(priority: .utility) {
            NormalizationService.analyze(url: url)
        }.value

        cache[key] = computed
        if cache.count > 2000 {
            cache = Dictionary(uniqueKeysWithValues: Array(cache.prefix(1500)))
        }
        let snapshot = cache
        Task.detached {
            UserDefaults.standard.set(snapshot, forKey: "normalization_gain_cache_v1")
        }
        return computed
    }

    private func stableKey(for url: URL) -> String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64,
              let mdate = attrs[.modificationDate] as? Date
        else { return url.lastPathComponent }
        return "\(url.lastPathComponent)_\(size)_\(Int64(mdate.timeIntervalSince1970 * 1000))"
    }

    /// Analyses up to 60 s of audio centred in the track and returns the gain (dB)
    /// needed to reach -18 dBFS RMS, clamped to [-20, +12] dB.
    /// Returns 0 if the file cannot be decoded (unsupported format).
    nonisolated private static func analyze(url: URL, targetRMSdB: Float = -18.0) -> Float {
        guard let file = try? AVAudioFile(forReading: url) else { return 0 }
        let sr = file.processingFormat.sampleRate
        let ch = Int(file.processingFormat.channelCount)
        guard ch > 0 else { return 0 }

        let maxFrames = AVAudioFrameCount(min(file.length, AVAudioFramePosition(sr * 60)))
        file.framePosition = max(0, (file.length - Int64(maxFrames)) / 2)

        guard let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: maxFrames),
              (try? file.read(into: buf)) != nil,
              let channelData = buf.floatChannelData
        else { return 0 }

        let frames = Int(buf.frameLength)
        guard frames > 0 else { return 0 }

        var sumSq: Double = 0
        for c in 0..<ch {
            let p = channelData[c]
            for i in 0..<frames {
                let s = Double(p[i])
                sumSq += s * s
            }
        }
        let rms = sqrt(sumSq / Double(frames * ch))
        guard rms > 1e-8 else { return 0 }

        let gainDB = targetRMSdB - Float(20.0 * log10(rms))
        return min(max(gainDB, -20.0), 12.0)
    }
}
