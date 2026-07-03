import Foundation
import AVFoundation

/// Computes and caches integrated-loudness gain for audio files that lack embedded
/// ReplayGain tags. Used as a fallback by AudioPlayerManager.scheduleCurrent.
actor NormalizationService {
    static let shared = NormalizationService()

    private let udKey = "normalization_gain_cache_v2"
    private var cache: [String: Float]

    private init() {
        cache = (UserDefaults.standard.dictionary(forKey: "normalization_gain_cache_v2") as? [String: Float]) ?? [:]
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
        Task.detached { [udKey] in
            UserDefaults.standard.set(snapshot, forKey: udKey)
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
    /// needed to reach -18 LUFS integrated loudness — the ReplayGain 2.0 reference
    /// level, chosen so untagged (analyzed) tracks land at the same perceived
    /// loudness as tracks with an embedded REPLAYGAIN_TRACK_GAIN tag — clamped to
    /// [-20, +12] dB. Uses the ITU-R BS.1770-4 K-weighted gated loudness algorithm
    /// (K-weighting filter + 400 ms/75%-overlap blocks + absolute -70 LUFS gate +
    /// relative -10 LU gate), the same measurement streaming services use.
    /// Returns 0 if the file cannot be decoded or has no gateable content.
    nonisolated private static func analyze(url: URL, targetLUFS: Double = -18.0) -> Float {
        guard let file = try? AVAudioFile(forReading: url) else { return 0 }
        let sr = file.processingFormat.sampleRate
        let ch = Int(file.processingFormat.channelCount)
        guard ch > 0, sr > 0 else { return 0 }

        let maxFrames = AVAudioFrameCount(min(file.length, AVAudioFramePosition(sr * 60)))
        file.framePosition = max(0, (file.length - Int64(maxFrames)) / 2)

        guard let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: maxFrames),
              (try? file.read(into: buf)) != nil,
              let channelData = buf.floatChannelData
        else { return 0 }

        let frames = Int(buf.frameLength)
        guard frames > 0 else { return 0 }

        // K-weight each channel (BS.1770 "head" pre-filter + RLB high-pass).
        var weighted = [[Double]](repeating: [Double](repeating: 0, count: frames), count: ch)
        for c in 0..<ch {
            var filter = KWeightingFilter(sampleRate: sr)
            let p = channelData[c]
            for i in 0..<frames {
                weighted[c][i] = filter.process(Double(p[i]))
            }
        }

        // Gated loudness per ITU-R BS.1770-4: 400 ms blocks, 75% overlap (100 ms step).
        let blockSize = Int(sr * 0.4)
        let step = max(1, Int(sr * 0.1))
        guard blockSize > 0, frames >= blockSize else { return 0 }

        var blocks: [(power: Double, loudness: Double)] = []
        var start = 0
        while start + blockSize <= frames {
            var sumSq = 0.0
            for c in 0..<ch {
                var channelSumSq = 0.0
                for i in start..<(start + blockSize) {
                    let s = weighted[c][i]
                    channelSumSq += s * s
                }
                sumSq += channelSumSq / Double(blockSize)
            }
            if sumSq > 0 {
                blocks.append((power: sumSq, loudness: -0.691 + 10 * log10(sumSq)))
            }
            start += step
        }
        guard !blocks.isEmpty else { return 0 }

        // Absolute gate: discard blocks quieter than -70 LUFS.
        let absGated = blocks.filter { $0.loudness > -70.0 }
        guard !absGated.isEmpty else { return 0 }

        // Relative gate: discard blocks more than 10 LU below the absolute-gated mean.
        let absMeanPower = absGated.reduce(0.0) { $0 + $1.power } / Double(absGated.count)
        let relativeThreshold = -0.691 + 10 * log10(absMeanPower) - 10.0
        let relGated = absGated.filter { $0.loudness > relativeThreshold }
        guard !relGated.isEmpty else { return 0 }

        let finalPower = relGated.reduce(0.0) { $0 + $1.power } / Double(relGated.count)
        guard finalPower > 0 else { return 0 }
        let integratedLUFS = -0.691 + 10 * log10(finalPower)

        let gainDB = targetLUFS - integratedLUFS
        return Float(min(max(gainDB, -20.0), 12.0))
    }
}

/// ITU-R BS.1770-4 K-weighting filter: a high-shelf "head" pre-filter cascaded
/// with an RLB high-pass, applied per channel before loudness summation.
private struct KWeightingFilter {
    private var stage1: Biquad
    private var stage2: Biquad

    init(sampleRate: Double) {
        stage1 = Biquad.headEffectShelf(sampleRate: sampleRate)
        stage2 = Biquad.rlbHighPass(sampleRate: sampleRate)
    }

    mutating func process(_ x: Double) -> Double {
        stage2.process(stage1.process(x))
    }
}

/// Direct-form II transposed biquad, coefficients pre-normalized (a0 == 1).
private struct Biquad {
    let b0, b1, b2, a1, a2: Double
    private var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0

    mutating func process(_ x: Double) -> Double {
        let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1; x1 = x
        y2 = y1; y1 = y
        return y
    }

    /// Stage 1 of K-weighting: models the acoustic effect of the human head as a
    /// ~+4 dB shelf above ~1.7 kHz. Standard BS.1770 constants, bilinear-transformed
    /// per sample rate.
    static func headEffectShelf(sampleRate: Double) -> Biquad {
        let f0 = 1681.9744509555319
        let G = 3.99984385397
        let Q = 0.7071752369554193
        let K = tan(Double.pi * f0 / sampleRate)
        let Vh = pow(10.0, G / 20.0)
        let Vb = pow(Vh, 0.4996667741545416)
        let a0 = 1.0 + K / Q + K * K
        return Biquad(
            b0: (Vh + Vb * K / Q + K * K) / a0,
            b1: 2.0 * (K * K - Vh) / a0,
            b2: (Vh - Vb * K / Q + K * K) / a0,
            a1: 2.0 * (K * K - 1.0) / a0,
            a2: (1.0 - K / Q + K * K) / a0
        )
    }

    /// Stage 2 of K-weighting: the RLB (Revised Low-frequency B) high-pass,
    /// standard BS.1770 constants, bilinear-transformed per sample rate.
    static func rlbHighPass(sampleRate: Double) -> Biquad {
        let f0 = 38.13547087602444
        let Q = 0.5003270373238773
        let K = tan(Double.pi * f0 / sampleRate)
        let a0 = 1.0 + K / Q + K * K
        return Biquad(
            b0: 1.0,
            b1: -2.0,
            b2: 1.0,
            a1: 2.0 * (K * K - 1.0) / a0,
            a2: (1.0 - K / Q + K * K) / a0
        )
    }
}
