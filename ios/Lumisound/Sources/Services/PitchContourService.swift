import Foundation

// MARK: - PitchContourService
//
// On-device melody-contour extraction + matching for "Hum to Search" — find
// a song already in the local library by humming its tune instead of
// remembering its title. Reuses BPMAnalyzerService.decodeMono for PCM
// decoding (same proven AVAssetReader path, not duplicated here).
//
// This is intentionally NOT acoustic fingerprinting (see
// AudioFingerprintService, used for exact-recording duplicate detection) —
// a hum is monophonic, off-key, off-tempo, and missing lyrics/
// instrumentation entirely, so what's compared here is a coarse, key-
// independent RELATIVE pitch contour (semitone deltas from a track's own
// median F0 over time), not raw audio similarity. The search space is only
// the user's own downloaded library — there is no external melody database
// this queries or could query.
//
// Honest limitation, stated once here rather than scattered across
// comments: no vocal isolation is performed on library tracks (that's a
// much larger feature — see this session's stem-separation idea, which
// wasn't built). Autocorrelation pitch detection on a full produced mix
// (drums/bass/harmony alongside the melody) is inherently noisier than on
// a clean hum, so match quality depends a lot on how prominent a track's
// melodic line is in the mix. This is a best-effort v1, not a lab-grade
// query-by-humming system — matches are ranked and shown as candidates,
// never auto-selected.
actor PitchContourService {
    static let shared = PitchContourService()

    struct Match: Identifiable {
        let songID: String
        let score: Float
        var id: String { songID }
    }

    private var cache: [String: [Float]]
    private let cacheURL: URL

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        cacheURL = caches.appendingPathComponent("pitch_contour_cache_v1.json")
        if let data = try? Data(contentsOf: cacheURL),
           let decoded = try? JSONDecoder().decode([String: [Float]].self, from: data) {
            cache = decoded
        } else {
            cache = [:]
        }
    }

    /// Analyzes `humURL` (a short recorded hum) and ranks `songs` by
    /// melodic similarity, best first — only scores above `matchFloor` are
    /// returned, since this is inherently a fuzzy, best-effort match, not
    /// something that should ever claim high confidence.
    ///
    /// Caps how many NOT-YET-cached songs get analyzed in one call (analysis
    /// is real decode + windowed-autocorrelation work per song) so a huge,
    /// never-before-searched library can't turn one search into an
    /// unbounded scan — the cap just means a first search on a big library
    /// may miss some not-yet-analyzed tracks; every subsequent search
    /// (on this or any other query) covers more of the library as the
    /// cache fills in.
    func search(humURL: URL, songs: [(id: String, url: URL)], limit: Int = 10) async -> [Match] {
        guard let humContour = await Self.extractContour(url: humURL) else { return [] }

        var scored: [Match] = []
        var freshAnalysisBudget = Self.maxFreshAnalysesPerSearch
        for (id, url) in songs {
            let key = cacheKey(for: url)
            let candidateContour: [Float]?
            if let cached = cache[key] {
                candidateContour = cached
            } else if freshAnalysisBudget > 0 {
                freshAnalysisBudget -= 1
                candidateContour = await Self.extractContour(url: url)
                if let candidateContour {
                    cache[key] = candidateContour
                }
            } else {
                candidateContour = nil
            }
            guard let candidateContour else { continue }

            let score = Self.bestAlignmentScore(query: humContour, candidate: candidateContour)
            guard score >= Self.matchFloor else { continue }
            scored.append(Match(songID: id, score: score))
        }
        persist()
        return Array(scored.sorted { $0.score > $1.score }.prefix(limit))
    }

    private static let matchFloor: Float = 0.55
    private static let maxFreshAnalysesPerSearch = 150

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

    // MARK: - Pitch extraction

    private static let sampleRate = 8_000.0 // enough for the melodic F0 range (~80-1000Hz); keeps ACF cheap
    private static let windowSize = 1_024   // ~128ms at 8kHz
    private static let hopSize = 512        // 50% overlap
    private static let maxAnalysisSeconds = 30.0 // library tracks: a representative opening slice, not the whole file

    private static func extractContour(url: URL) async -> [Float]? {
        guard let samples = await BPMAnalyzerService.decodeMono(url: url, sampleRate: sampleRate, maxSeconds: maxAnalysisSeconds),
              samples.count >= windowSize
        else { return nil }

        var f0s: [Float] = []
        var i = 0
        while i + windowSize <= samples.count {
            if let f0 = autocorrelationPitch(samples: samples, start: i, count: windowSize, sampleRate: sampleRate) {
                f0s.append(f0)
            }
            i += hopSize
        }
        guard f0s.count >= 8 else { return nil }

        // Absolute Hz -> RELATIVE semitone contour (delta from the
        // sequence's own median F0) -- makes matching key-independent,
        // since a hum is essentially never in the recording's original key.
        let sorted = f0s.sorted()
        let median = sorted[sorted.count / 2]
        guard median > 0 else { return nil }
        return f0s.map { 12.0 * log2($0 / median) }
    }

    /// Basic autocorrelation pitch detector over one window — adequate for
    /// monophonic humming and for tracks with a clear, dominant melodic
    /// line; noisier on dense mixes (see the type doc's honest-limitation
    /// note). Returns `nil` for a window with no clear periodicity
    /// (silence, noise, or a mix too dense to read a dominant pitch from).
    private static func autocorrelationPitch(samples: [Int16], start: Int, count: Int, sampleRate: Double) -> Float? {
        let minHz = 80.0, maxHz = 1_000.0
        let minLag = Int(sampleRate / maxHz)
        let maxLag = Int(sampleRate / minHz)
        guard minLag >= 1, maxLag < count else { return nil }

        var window = [Double](repeating: 0, count: count)
        for k in 0..<count { window[k] = Double(samples[start + k]) }

        let mean = window.reduce(0, +) / Double(count)
        for k in 0..<count { window[k] -= mean }

        let energy = window.reduce(0) { $0 + $1 * $1 }
        guard energy > 1_000_000 else { return nil } // near-silence, not worth a pitch estimate

        var bestLag = 0
        var bestScore = 0.0
        for lag in minLag...maxLag {
            var sum = 0.0
            for k in 0..<(count - lag) {
                sum += window[k] * window[k + lag]
            }
            if sum > bestScore {
                bestScore = sum
                bestLag = lag
            }
        }
        guard bestLag > 0, bestScore / energy > 0.3 else { return nil } // weak periodicity -- not confident enough

        return Float(sampleRate / Double(bestLag))
    }

    // MARK: - Matching

    /// Slides `query` across `candidate` (the hum is a short snippet; the
    /// candidate track is much longer) and returns the best normalized
    /// cross-correlation found at any alignment offset — an approximation
    /// of full dynamic time warping that's cheap enough to run across a
    /// whole library on every search, at the cost of not tolerating tempo
    /// drift WITHIN the hummed snippet itself (only a fixed time offset,
    /// not a warped one).
    private static func bestAlignmentScore(query: [Float], candidate: [Float]) -> Float {
        guard query.count >= 4, candidate.count >= query.count else { return 0 }

        let queryMean = query.reduce(0, +) / Float(query.count)
        let queryNormalized = query.map { $0 - queryMean }
        let queryNorm = sqrt(queryNormalized.reduce(0) { $0 + $1 * $1 })
        guard queryNorm > 0 else { return 0 }

        var best: Float = 0
        var offset = 0
        while offset + query.count <= candidate.count {
            let slice = candidate[offset..<(offset + query.count)]
            let sliceMean = slice.reduce(0, +) / Float(slice.count)
            var dot: Float = 0
            var sliceSumSq: Float = 0
            for (q, c) in zip(queryNormalized, slice) {
                let cn = c - sliceMean
                dot += q * cn
                sliceSumSq += cn * cn
            }
            let sliceNorm = sqrt(sliceSumSq)
            if sliceNorm > 0 {
                let correlation = dot / (queryNorm * sliceNorm)
                if correlation > best { best = correlation }
            }
            offset += 4 // stride -- checking every single hop-frame offset is unnecessary for a coarse match
        }
        return max(0, best)
    }
}
