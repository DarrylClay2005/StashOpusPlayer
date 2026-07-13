import Accelerate
import AVFoundation
import CoreMedia
import Foundation

// MARK: - AudioFingerprintService
//
// On-device acoustic fingerprinting for the Duplicate Scanner (see
// DuplicateFinderService) — lets it confirm two same-duration tracks are
// actually the same recording instead of only trusting title/artist text
// matching, which misses a re-titled re-upload and can't tell a genuine
// same-titled-but-different-song apart from a real duplicate.
//
// This is the offline counterpart to AudioVisualizerService, the app's
// live-playback "audio listener/analyzer" (used by Auto EQ and Smart Auto
// Crossfade): same underlying technique — a vDSP FFT reduced to coarse
// log-spaced band energies — just applied here to samples decoded straight
// from a file at rest instead of a tap on whatever's currently playing,
// since comparing two arbitrary library tracks requires reading them
// without actually playing either one through the engine. Mirrors
// BPMAnalyzerService's decode/cache architecture (AVAssetReader -> mono PCM,
// disk cache keyed by path+mtime+size) for the same reason: both need to
// read files this app didn't originate straight off disk, cheaply and
// repeatably.
actor AudioFingerprintService {
    static let shared = AudioFingerprintService()

    /// Cosine similarity at/above this is treated as "the same recording".
    /// Empirically: different bitrate/container re-encodes or re-tags of the
    /// same source consistently land above 0.99 on this metric; genuinely
    /// different songs (even same genre/tempo/instrumentation) land well
    /// below 0.9. 0.975 leaves a safety margin on both sides.
    static let matchThreshold: Float = 0.975

    private var cache: [String: [Float]]
    private let cacheURL: URL
    private let fftSize = 2048
    private let log2n: vDSP_Length = 11 // 2^11 == 2048
    private let bandCount = 32
    private let sampleRate = 11025.0

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        cacheURL = caches.appendingPathComponent("audio_fingerprint_cache_v1.json")
        if let data = try? Data(contentsOf: cacheURL),
           let decoded = try? JSONDecoder().decode([String: [Float]].self, from: data) {
            cache = decoded
            appLog("AudioFingerprintService: loaded \(decoded.count) cached fingerprint(s)", category: "audio")
        } else {
            cache = [:]
        }
    }

    /// Returns a cached or freshly-computed normalized spectral-profile
    /// vector for `url`, or `nil` if the file can't be decoded (corrupt,
    /// unsupported format, too short). Unit-length normalized so
    /// `cosineSimilarity` compares spectral SHAPE only, not overall
    /// loudness — masters/normalization differ even for the identical
    /// recording, and raw energy would make those false negatives.
    func fingerprint(for url: URL) async -> [Float]? {
        let key = cacheKey(for: url)
        if let cached = cache[key] {
            appLog("AudioFingerprintService: cache hit for \(url.lastPathComponent)", category: "audio")
            return cached
        }
        appLog("AudioFingerprintService: analyzing \(url.lastPathComponent)", category: "audio")
        guard let samples = await Self.decodeMono(url: url, sampleRate: sampleRate, maxSeconds: 45, skipSeconds: 8) else {
            appWarn("AudioFingerprintService: could not decode \(url.lastPathComponent)", category: "audio")
            return nil
        }
        guard let vector = computeSpectralProfile(samples: samples) else {
            appWarn("AudioFingerprintService: too little audio to fingerprint \(url.lastPathComponent) (\(samples.count) samples)", category: "audio")
            return nil
        }
        cache[key] = vector
        persist()
        appLog("AudioFingerprintService: fingerprinted \(url.lastPathComponent) from \(samples.count) samples", category: "audio")
        return vector
    }

    /// Cosine similarity of two equal-length vectors, 0...1 for our
    /// non-negative log-magnitude vectors (1 == identical spectral shape).
    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0, magA: Float = 0, magB: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dot, vDSP_Length(a.count))
        vDSP_svesq(a, 1, &magA, vDSP_Length(a.count))
        vDSP_svesq(b, 1, &magB, vDSP_Length(b.count))
        guard magA > 0, magB > 0 else { return 0 }
        return dot / (sqrt(magA) * sqrt(magB))
    }

    private func cacheKey(for url: URL) -> String {
        let path = url.standardizedFileURL.path
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        let mtime = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let size = (attrs?[.size] as? Int) ?? 0
        return "\(path)|\(Int(mtime))|\(size)"
    }

    private func persist() {
        let snapshot = cache
        let destination = cacheURL
        Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: destination, options: .atomic)
        }
    }

    // MARK: - Spectral profile
    //
    // Same log-spaced-band, log-magnitude reduction AudioVisualizerService
    // applies per live buffer (see its `bars` computation) — run here once
    // per fixed-size window across the decoded excerpt and averaged into a
    // single long-term profile, since a duplicate check compares two whole
    // (well, sampled) tracks rather than reacting frame-by-frame.
    private func computeSpectralProfile(samples: [Int16]) -> [Float]? {
        guard samples.count >= fftSize else { return nil }
        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return nil }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        var accumulated = [Float](repeating: 0, count: bandCount)
        var windowCount = 0
        var offset = 0
        let halfSize = fftSize / 2

        while offset + fftSize <= samples.count {
            var real = [Float](repeating: 0, count: fftSize)
            var imag = [Float](repeating: 0, count: fftSize)
            for i in 0..<fftSize { real[i] = Float(samples[offset + i]) / 32768.0 }

            real.withUnsafeMutableBufferPointer { realPtr in
                imag.withUnsafeMutableBufferPointer { imagPtr in
                    guard let realBase = realPtr.baseAddress, let imagBase = imagPtr.baseAddress else { return }
                    var split = DSPSplitComplex(realp: realBase, imagp: imagBase)
                    vDSP_fft_zip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))

                    var magnitudes = [Float](repeating: 0, count: halfSize)
                    magnitudes.withUnsafeMutableBufferPointer { magPtr in
                        guard let magBase = magPtr.baseAddress else { return }
                        vDSP_zvmags(&split, 1, magBase, 1, vDSP_Length(halfSize))
                    }

                    for band in 0..<bandCount {
                        let lowFrac = pow(Double(band) / Double(bandCount), 2)
                        let highFrac = pow(Double(band + 1) / Double(bandCount), 2)
                        let lowBin = max(1, Int(lowFrac * Double(halfSize)))
                        let highBin = max(lowBin + 1, min(halfSize, Int(highFrac * Double(halfSize))))
                        guard lowBin < highBin else { continue }
                        let slice = magnitudes[lowBin..<highBin]
                        let avg = slice.reduce(0, +) / Float(slice.count)
                        accumulated[band] += log10(avg + 1)
                    }
                }
            }
            windowCount += 1
            offset += fftSize
        }
        guard windowCount > 0 else { return nil }
        for i in 0..<accumulated.count { accumulated[i] /= Float(windowCount) }

        var normSq: Float = 0
        vDSP_svesq(accumulated, 1, &normSq, vDSP_Length(accumulated.count))
        let norm = sqrt(normSq)
        guard norm > 0 else { return nil }
        return accumulated.map { $0 / norm }
    }

    // MARK: - Decode (same approach as BPMAnalyzerService.decodeMono, + a
    // configurable start offset so the excerpt skips a track's intro/lead-in
    // silence, which carries little identifying spectral content).

    private static func decodeMono(url: URL, sampleRate: Double, maxSeconds: Double, skipSeconds: Double) async -> [Int16]? {
        let asset = AVURLAsset(url: url)
        guard let tracks = try? await asset.loadTracks(withMediaType: .audio),
              let track = tracks.first,
              let reader = try? AVAssetReader(asset: asset)
        else { return nil }

        var start = 0.0
        if let duration = try? await asset.load(.duration) {
            let totalSeconds = CMTimeGetSeconds(duration)
            if totalSeconds.isFinite, totalSeconds > skipSeconds + 5 {
                start = skipSeconds
            }
            if totalSeconds.isFinite, totalSeconds > 0 {
                let remaining = max(1.0, totalSeconds - start)
                reader.timeRange = CMTimeRange(
                    start: CMTime(seconds: start, preferredTimescale: 600),
                    duration: CMTime(seconds: min(remaining, maxSeconds), preferredTimescale: 600)
                )
            }
        }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else { return nil }
        defer { reader.cancelReading() }

        let maxSamples = Int(sampleRate * maxSeconds)
        var samples: [Int16] = []
        samples.reserveCapacity(maxSamples)

        while let sampleBuffer = output.copyNextSampleBuffer() {
            if let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) {
                let length = CMBlockBufferGetDataLength(blockBuffer)
                var chunk = [Int16](repeating: 0, count: length / MemoryLayout<Int16>.size)
                CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: &chunk)
                samples.append(contentsOf: chunk)
            }
            if samples.count >= maxSamples {
                break
            }
        }
        if samples.count > maxSamples {
            samples.removeSubrange(maxSamples...)
        }
        return samples.isEmpty ? nil : samples
    }
}
