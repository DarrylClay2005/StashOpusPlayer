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
//
// Each track's excerpt is split into `segmentCount` time segments, each
// reduced to its own band-energy vector, rather than blended into one
// long-term average. A single averaged vector only captures overall
// spectral BALANCE, which two different songs can easily share (same
// genre/mastering/EQ curve) even though their actual moment-to-moment
// content is nothing alike — that coincidence is exactly what let unrelated
// same-duration tracks get flagged as "sounds identical." Comparing segment
// sequences (see `sequenceSimilarity`) requires two tracks to track closely
// *throughout* the excerpt, not just on average, which a real re-encode of
// the same source does and an unrelated same-length track usually doesn't.
actor AudioFingerprintService {
    static let shared = AudioFingerprintService()

    /// Mean cosine similarity across all segments at/above this — combined
    /// with `segmentMatchThreshold`/`minMatchingSegmentFraction` below — is
    /// treated as "the same recording". Raised slightly from the old
    /// single-vector threshold (0.975) since segment-level matching is a
    /// stricter, more discriminating signal on its own; this mean bar mostly
    /// guards against a track passing the per-segment fraction check while
    /// still trending weak overall.
    static let matchThreshold: Float = 0.98

    /// Cosine similarity an individual segment must clear to count as
    /// "matching" for the `minMatchingSegmentFraction` check.
    static let segmentMatchThreshold: Float = 0.97

    /// Fraction of segments that must individually clear
    /// `segmentMatchThreshold` for two tracks to be considered the same
    /// recording (with `segmentCount = 6`, this requires 5 of 6). A single
    /// divergent segment — the moment two otherwise-similar-sounding but
    /// genuinely different songs actually differ — is enough to reject a
    /// match, which a single blended average could never catch.
    static let minMatchingSegmentFraction: Float = 0.8

    private var cache: [String: [[Float]]]
    private let cacheURL: URL
    private let fftSize = 2048
    private let log2n: vDSP_Length = 11 // 2^11 == 2048
    private let bandCount = 32
    private let sampleRate = 11025.0
    /// Number of equal time segments each excerpt is split into before
    /// fingerprinting — see the file-header comment for why segments beat a
    /// single blended average.
    private let segmentCount = 6

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        // v2: cache values changed shape from a single [Float] vector to
        // [[Float]] (one vector per segment) — a new filename keeps an old
        // v1 cache from being misread as the new format.
        cacheURL = caches.appendingPathComponent("audio_fingerprint_cache_v2.json")
        if let data = try? Data(contentsOf: cacheURL),
           let decoded = try? JSONDecoder().decode([String: [[Float]]].self, from: data) {
            cache = decoded
            appLog("AudioFingerprintService: loaded \(decoded.count) cached fingerprint(s)", category: "audio")
        } else {
            cache = [:]
        }
    }

    /// Returns a cached or freshly-computed sequence of `segmentCount`
    /// unit-length normalized spectral-profile vectors for `url` (one per
    /// time segment of the excerpt), or `nil` if the file can't be decoded
    /// (corrupt, unsupported format, too short). Unit-length normalized so
    /// `cosineSimilarity` compares spectral SHAPE only, not overall
    /// loudness — masters/normalization differ even for the identical
    /// recording, and raw energy would make those false negatives.
    func fingerprint(for url: URL) async -> [[Float]]? {
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
        guard let vectors = computeSpectralProfile(samples: samples) else {
            appWarn("AudioFingerprintService: too little audio to fingerprint \(url.lastPathComponent) (\(samples.count) samples)", category: "audio")
            return nil
        }
        cache[key] = vectors
        persist()
        appLog("AudioFingerprintService: fingerprinted \(url.lastPathComponent) from \(samples.count) samples into \(vectors.count) segment(s)", category: "audio")
        return vectors
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

    /// Combines two tracks' per-segment fingerprint sequences into a single
    /// match score: requires at least `minMatchingSegmentFraction` of the
    /// segments to individually clear `segmentMatchThreshold` (aligned by
    /// segment index — both sequences come from the same excerpt window/skip
    /// parameters, so segment N of one lines up with segment N of the
    /// other), then returns the mean similarity across all segments for the
    /// caller to compare against `matchThreshold`. Returns 0 (never a match)
    /// if the per-segment requirement isn't met, the segment-count fraction
    /// check being what actually catches unrelated same-duration tracks that
    /// merely share overall spectral balance — a case where the mean alone
    /// could still look deceptively high.
    static func sequenceSimilarity(_ a: [[Float]], _ b: [[Float]]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var total: Float = 0
        var matchingSegments = 0
        for i in 0..<a.count {
            let similarity = cosineSimilarity(a[i], b[i])
            total += similarity
            if similarity >= segmentMatchThreshold {
                matchingSegments += 1
            }
        }
        let mean = total / Float(a.count)
        let minMatchingSegments = Int((Float(a.count) * minMatchingSegmentFraction).rounded(.up))
        guard matchingSegments >= minMatchingSegments else { return 0 }
        return mean
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
    // per fixed-size window across the decoded excerpt, but averaged into
    // `segmentCount` separate per-segment profiles rather than one blended
    // long-term average (see the file-header comment for why).
    private func computeSpectralProfile(samples: [Int16]) -> [[Float]]? {
        guard samples.count >= fftSize else { return nil }
        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return nil }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        let halfSize = fftSize / 2
        let totalWindows = samples.count / fftSize
        // Fewer windows than segments would mean some segments never get a
        // single window to average — reject rather than return partially
        // empty/misleading segments (falls back to title+artist matching,
        // same as any other "too little audio" case).
        guard totalWindows >= segmentCount else { return nil }

        var accumulated = [[Float]](repeating: [Float](repeating: 0, count: bandCount), count: segmentCount)
        var windowCounts = [Int](repeating: 0, count: segmentCount)

        for windowIndex in 0..<totalWindows {
            let offset = windowIndex * fftSize
            var real = [Float](repeating: 0, count: fftSize)
            var imag = [Float](repeating: 0, count: fftSize)
            for i in 0..<fftSize { real[i] = Float(samples[offset + i]) / 32768.0 }

            // Proportionally bucket this window into one of `segmentCount`
            // equal time slices of the excerpt.
            let segment = min(segmentCount - 1, windowIndex * segmentCount / totalWindows)

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
                        accumulated[segment][band] += log10(avg + 1)
                    }
                }
            }
            windowCounts[segment] += 1
        }

        guard windowCounts.allSatisfy({ $0 > 0 }) else { return nil }

        var result: [[Float]] = []
        result.reserveCapacity(segmentCount)
        for segment in 0..<segmentCount {
            var vector = accumulated[segment]
            let count = Float(windowCounts[segment])
            for i in 0..<vector.count { vector[i] /= count }

            var normSq: Float = 0
            vDSP_svesq(vector, 1, &normSq, vDSP_Length(vector.count))
            let norm = sqrt(normSq)
            guard norm > 0 else { return nil }
            result.append(vector.map { $0 / norm })
        }
        return result
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
