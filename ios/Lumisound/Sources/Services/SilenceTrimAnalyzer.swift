import Foundation
import AVFoundation

/// On-device detection of dead air at the very start of a track — reuses
/// `BPMAnalyzerService.decodeMono`'s exact `AVAssetReader` decode path
/// (already shared with `PitchContourService` for the same reason: no need
/// for a third copy of that boilerplate), just measuring RMS energy over
/// the first several seconds instead of tempo. Same disk-cache-by-path+
/// mtime+size shape as `BPMAnalyzerService` too, so repeat lookups are free.
actor SilenceTrimAnalyzer {
    static let shared = SilenceTrimAnalyzer()

    /// Never trims more than this many seconds, even if the detected
    /// silence runs longer — a deliberately quiet intro that's part of the
    /// song (not dead air) shouldn't get skipped wholesale.
    private static let maxTrimSeconds = 10.0
    /// A window's RMS below this fraction of the analyzed snippet's peak
    /// RMS counts as "silence" for this purpose.
    private static let silenceThreshold = 0.02

    private var cache: [String: TimeInterval]
    private let cacheURL: URL

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        cacheURL = caches.appendingPathComponent("silence_trim_cache_v1.json")
        if let data = try? Data(contentsOf: cacheURL),
           let decoded = try? JSONDecoder().decode([String: TimeInterval].self, from: data) {
            cache = decoded
        } else {
            cache = [:]
        }
    }

    /// Returns how many leading seconds of `url` are near-silent (0 if
    /// none, or if the file can't be analyzed) — never more than
    /// `maxTrimSeconds`. `url` should be a local file URL; analyzing a
    /// remote stream would mean downloading it just to measure silence.
    func leadingSilence(for url: URL) async -> TimeInterval {
        let key = cacheKey(for: url)
        if let cached = cache[key] { return cached }

        let value = await Self.analyze(url: url)
        cache[key] = value
        persist()
        return value
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

    private static func analyze(url: URL) async -> TimeInterval {
        let sampleRate = 11025.0
        guard let samples = await BPMAnalyzerService.decodeMono(
            url: url, sampleRate: sampleRate, maxSeconds: maxTrimSeconds + 5
        ), !samples.isEmpty else { return 0 }

        let window = Int(sampleRate) / 50 // ~20ms windows
        guard window > 0 else { return 0 }

        var windowRMS: [Double] = []
        var i = 0
        while i + window <= samples.count {
            var sum = 0.0
            for sample in samples[i..<(i + window)] {
                let v = Double(sample) / Double(Int16.max)
                sum += v * v
            }
            windowRMS.append((sum / Double(window)).squareRoot())
            i += window
        }
        guard let peak = windowRMS.max(), peak > 0 else { return 0 }

        var silentWindows = 0
        for rms in windowRMS {
            if rms < peak * silenceThreshold {
                silentWindows += 1
            } else {
                break
            }
        }

        let seconds = Double(silentWindows * window) / sampleRate
        return min(seconds, maxTrimSeconds)
    }
}
