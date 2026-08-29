import Foundation

// MARK: - BeatGridAnalyzerService
//
// Full-track offline beat/onset detection for Music Haptics. Before this
// existed, MusicHapticsService only ever reacted to LIVE audio energy at a
// fixed 60Hz poll — a real-time rise-over-threshold heuristic that misses
// exactly the beats a listener actually notices (a kick under a sustained
// pad/bassline never registers as a "rise" since the energy floor is already
// high; a quiet or syncopated hit falls under the fixed threshold entirely).
// This mirrors what Apple Music's own Music Haptics does: analyze the WHOLE
// track once, up front, and drive haptics from the resulting beat grid
// during playback — not guess in real time. BPMAnalyzerService already does
// something similar for a single averaged tempo value from the first 60s;
// this instead keeps every individual onset TIMESTAMP across the full track
// (bounded by `maxAnalysisSeconds`), which is what a playback-synced
// scheduler actually needs.
actor BeatGridAnalyzerService {
    static let shared = BeatGridAnalyzerService()

    /// Longest stretch of a track analyzed for onsets. Bounded (rather than
    /// the whole file unconditionally) so an hour-long DJ mix or podcast
    /// accidentally routed through Music Haptics can't blow up decode time
    /// or cache size — 12 minutes covers effectively every song.
    private static let maxAnalysisSeconds = 12 * 60.0

    private var cache: [String: [Double]]
    private let cacheURL: URL
    /// Tracks in-flight analysis so two near-simultaneous callers (e.g. a
    /// fast track skip right after Music Haptics starts) share one decode
    /// instead of racing two full-track analyses.
    private var inFlight: [String: Task<[Double], Never>] = [:]

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        cacheURL = caches.appendingPathComponent("beat_grid_cache_v1.json")
        if let data = try? Data(contentsOf: cacheURL),
           let decoded = try? JSONDecoder().decode([String: [Double]].self, from: data) {
            cache = decoded
        } else {
            cache = [:]
        }
    }

    /// Returns every detected onset (in seconds from track start) for `url`,
    /// or `nil` if the file couldn't be decoded/analyzed — callers should
    /// fall back to live energy-reactive haptics in that case, never block
    /// on this. Cached on disk by path+mtime+size, same convention as
    /// BPMAnalyzerService/AudioFingerprintService.
    func beatGrid(for url: URL) async -> [Double]? {
        let key = cacheKey(for: url)
        if let cached = cache[key] { return cached.isEmpty ? nil : cached }

        if let existing = inFlight[key] {
            let result = await existing.value
            return result.isEmpty ? nil : result
        }

        let task = Task<[Double], Never> {
            await Self.analyze(url: url)
        }
        inFlight[key] = task
        let onsets = await task.value
        inFlight[key] = nil

        cache[key] = onsets
        persist()
        return onsets.isEmpty ? nil : onsets
    }

    /// Cache-only lookup — doesn't trigger analysis. Lets MusicHapticsService
    /// start with live-reactive haptics immediately (never blocking playback
    /// start on a full-track decode) while `beatGrid(for:)` runs in the
    /// background for next time / a slightly-delayed handoff to the precise
    /// beat grid on this same play-through once it's ready.
    func cachedBeatGrid(for url: URL) -> [Double]? {
        guard let cached = cache[cacheKey(for: url)], !cached.isEmpty else { return nil }
        return cached
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
    //
    // Spectral-flux onset detection: same coarse-band-energy reduction
    // AudioFingerprintService/AudioVisualizerService use, but tracking each
    // band's frame-to-frame POSITIVE energy change (the "flux") summed
    // across bands, rather than either a single wideband envelope
    // (BPMAnalyzerService's autocorrelation input, good for a global tempo
    // estimate but not for picking out individual hits) or one blended
    // spectral shape. A local adaptive threshold (median of a sliding
    // window, not one fixed global cutoff) is what actually catches a quiet
    // verse's hits and a loud chorus's hits alike, which a single fixed
    // threshold — the exact class of heuristic the live 60Hz path already
    // used and was reported to miss beats with — cannot do at once.

    private static func analyze(url: URL) async -> [Double] {
        let sampleRate = 11025.0
        guard let samples = await BPMAnalyzerService.decodeMono(url: url, sampleRate: sampleRate, maxSeconds: maxAnalysisSeconds),
              samples.count >= Int(sampleRate) * 2
        else { return [] }

        // ~100 frames/sec: fine enough to resolve individual hits close
        // together (fast hi-hats/snares) without the frame count for a
        // 12-minute track becoming unreasonable to hold in memory.
        let hopSize = max(1, Int(sampleRate) / 100)
        let bandCount = 8
        let windowSize = hopSize * 2

        var frames: [[Double]] = []
        frames.reserveCapacity(samples.count / hopSize)

        var offset = 0
        while offset + windowSize <= samples.count {
            var bandEnergies = [Double](repeating: 0, count: bandCount)
            let bandWidth = windowSize / bandCount
            if bandWidth > 0 {
                for band in 0..<bandCount {
                    let start = offset + band * bandWidth
                    let end = min(offset + windowSize, start + bandWidth)
                    guard start < end else { continue }
                    var sum = 0.0
                    for i in start..<end {
                        let v = Double(samples[i])
                        sum += v * v
                    }
                    bandEnergies[band] = sum / Double(end - start)
                }
            }
            frames.append(bandEnergies)
            offset += hopSize
        }
        guard frames.count > 20 else { return [] }

        // Spectral flux per frame: sum of positive per-band energy increases
        // vs. the previous frame. A real onset (any instrument's attack)
        // shows up as a broadband positive jump; steady sustained energy
        // (a held pad/bass note) contributes ~0 flux even though its
        // ABSOLUTE energy is high — this is exactly what a plain rise-over-
        // previous-sample check (the old live heuristic) got wrong on
        // sustained material.
        var flux = [Double](repeating: 0, count: frames.count)
        for i in 1..<frames.count {
            var sum = 0.0
            for band in 0..<bandCount {
                let diff = frames[i][band] - frames[i - 1][band]
                if diff > 0 { sum += diff }
            }
            flux[i] = sum
        }

        // Local adaptive threshold: median of a ~1s window centered on each
        // frame, scaled up — catches onsets in both quiet and loud
        // passages of the same track, unlike one fixed global cutoff.
        let halfWindow = 50
        let minIntervalFrames = 6 // ~60ms floor between onsets — avoids double-firing one transient across 2-3 frames
        var onsets: [Double] = []
        var lastOnsetFrame = -minIntervalFrames
        let frameDuration = Double(hopSize) / sampleRate

        for i in 0..<flux.count {
            let lo = max(0, i - halfWindow)
            let hi = min(flux.count, i + halfWindow)
            guard hi > lo else { continue }
            let localMedian = flux[lo..<hi].sorted(by: <)[(hi - lo) / 2]
            let threshold = localMedian * 1.8 + 0.0001

            guard flux[i] > threshold, i - lastOnsetFrame >= minIntervalFrames else { continue }
            // Local peak check: only fire on the frame that's the actual max
            // within its immediate neighborhood, not every frame that
            // happens to clear the threshold while flux is still rising.
            let peakLo = max(0, i - 2)
            let peakHi = min(flux.count, i + 3)
            guard flux[i] == flux[peakLo..<peakHi].max() else { continue }

            onsets.append(Double(i) * frameDuration)
            lastOnsetFrame = i
        }

        return onsets
    }
}
