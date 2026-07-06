import Foundation

/// One AI-assisted metadata pick remembered locally, keyed by filename — the
/// title/artist Aria Lumi picked, plus her `memory_id` (if any) so a later
/// manual correction can be reported back to her (see
/// `AccountService.reportMetadataCorrection`).
struct CachedResolution {
    let title: String
    let artist: String
    let memoryID: Int?
}

/// UserDefaults-backed cache of AI-assisted-suggestion results, keyed by
/// filename, so a file already resolved via
/// `AccountService.resolveMetadata(filename:candidates:)` isn't re-sent to the
/// bridge on every re-enrichment sweep, and so a later manual correction can
/// be traced back to the suggestion it's correcting. Modeled directly on
/// `EnrichmentCacheStore` (DocumentImportService.swift).
actor IntelligenceSuggestionCache {
    static let shared = IntelligenceSuggestionCache()

    private static let cacheKey = "intelligence_metadata_resolve_v1"

    /// filename -> {"title": ..., "artist": ..., "memory_id": "123"?}
    private var cache: [String: [String: String]]
    private var dirty = false

    private init() {
        cache = (UserDefaults.standard.dictionary(forKey: Self.cacheKey) as? [String: [String: String]]) ?? [:]
    }

    func lookup(_ filename: String) -> CachedResolution? {
        guard let entry = cache[filename], let title = entry["title"], let artist = entry["artist"] else {
            return nil
        }
        return CachedResolution(title: title, artist: artist, memoryID: entry["memory_id"].flatMap { Int($0) })
    }

    func store(_ filename: String, title: String, artist: String, memoryID: Int?) {
        var entry = ["title": title, "artist": artist]
        if let memoryID { entry["memory_id"] = String(memoryID) }
        cache[filename] = entry
        dirty = true
    }

    /// Flushes pending writes to `UserDefaults` in a single pass. Call once
    /// after a batch of re-enrichment resolves completes — not per song.
    func persist() {
        guard dirty else { return }
        UserDefaults.standard.set(cache, forKey: Self.cacheKey)
        dirty = false
    }
}
