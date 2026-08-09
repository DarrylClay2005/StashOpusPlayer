import Foundation
import AVFoundation
import CoreMedia

// MARK: - BPMAnalyzerService
//
// On-device tempo estimation for any track the player can open — local
// imports, watched-folder files, and Apple Music items alike. This is a
// Swift port of the bridge's `_estimate_bpm` (ios-bridge/main.py): decode the
// first 60s to mono 11025Hz PCM, build a coarse energy-onset envelope
// (~50 frames/sec), and autocorrelate it to find the dominant beat period in
// the 60-200 BPM range. Results are cached on disk by file path + mtime +
// size so repeat lookups (e.g. re-arming the "Up Next" track on every
// crossfade) are free.

actor BPMAnalyzerService {
    static let shared = BPMAnalyzerService()

    private var cache: [String: Double]
    private let cacheURL: URL

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        cacheURL = caches.appendingPathComponent("bpm_cache_v1.json")
        if let data = try? Data(contentsOf: cacheURL),
           let decoded = try? JSONDecoder().decode([String: Double].self, from: data) {
            cache = decoded
        } else {
            cache = [:]
        }
    }

    /// Returns a best-effort BPM for `url`, using the on-disk cache when the
    /// file hasn't changed since it was last analyzed. Returns `nil` if the
    /// file can't be decoded or no confident tempo could be estimated.
    func bpm(for url: URL) async -> Double? {
        let key = cacheKey(for: url)
        if let cached = cache[key] { return cached }

        guard let value = await Self.estimate(url: url) else { return nil }
        cache[key] = value
        persist()
        return value
    }

    /// Cache-only lookup — doesn't trigger analysis. Useful for callers (like
    /// the crossfade scheduler) that only want a value if it's already known.
    func cachedBPM(for url: URL) -> Double? {
        cache[cacheKey(for: url)]
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

    // MARK: - Analysis

    private static func estimate(url: URL) async -> Double? {
        let sampleRate = 11025.0
        guard let samples = await decodeMono(url: url, sampleRate: sampleRate, maxSeconds: 60),
              samples.count >= Int(sampleRate) * 4
        else { return nil }

        let window = Int(sampleRate) / 50 // ~20ms windows -> ~50 frames/sec
        guard window > 0 else { return nil }

        var energies: [Double] = []
        var i = 0
        while i + window <= samples.count {
            var sum = 0.0
            for sample in samples[i..<(i + window)] {
                let v = Double(sample)
                sum += v * v
            }
            energies.append(sum / Double(window))
            i += window
        }
        guard energies.count >= 20 else { return nil }

        // Onset envelope: positive jumps in energy between consecutive windows.
        var onsets: [Double] = []
        onsets.reserveCapacity(energies.count - 1)
        for idx in 1..<energies.count {
            onsets.append(max(0.0, energies[idx] - energies[idx - 1]))
        }

        let frameRate = sampleRate / Double(window) // frames per second
        let minBPM = 60.0, maxBPM = 200.0
        let minLag = max(1, Int(frameRate * 60.0 / maxBPM))
        let maxLag = min(Int(frameRate * 60.0 / minBPM), onsets.count - 1)
        guard minLag < maxLag else { return nil }

        var bestLag = 0
        var bestScore = -1.0
        for lag in minLag...maxLag {
            var score = 0.0
            for idx in lag..<onsets.count {
                score += onsets[idx] * onsets[idx - lag]
            }
            if score > bestScore {
                bestScore = score
                bestLag = lag
            }
        }
        guard bestLag > 0 else { return nil }

        return (60.0 * frameRate / Double(bestLag) * 10).rounded() / 10
    }

    /// Decodes the first `maxSeconds` of `url`'s audio track to mono 16-bit PCM
    /// at `sampleRate`. Returns `nil` if the file has no audio track or can't
    /// be opened by `AVAssetReader`. Internal (not `private`) since
    /// `PitchContourService` (hum-to-search) reuses this exact decode path
    /// rather than duplicating its own `AVAssetReader` boilerplate.
    static func decodeMono(url: URL, sampleRate: Double, maxSeconds: Double) async -> [Int16]? {
        let asset = AVURLAsset(url: url)
        guard let tracks = try? await asset.loadTracks(withMediaType: .audio),
              let track = tracks.first,
              let reader = try? AVAssetReader(asset: asset)
        else { return nil }

        if let duration = try? await asset.load(.duration) {
            let seconds = CMTimeGetSeconds(duration)
            if seconds.isFinite, seconds > 0 {
                reader.timeRange = CMTimeRange(
                    start: .zero,
                    duration: CMTime(seconds: min(seconds, maxSeconds), preferredTimescale: 600)
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
