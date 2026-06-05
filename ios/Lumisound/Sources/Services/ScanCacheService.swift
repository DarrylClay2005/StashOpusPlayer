import Foundation

/// Persists `(mtime, fileSize) → Song` mappings on disk so repeated library scans
/// skip AVURLAsset metadata extraction for unchanged files.
/// Must be accessed on @MainActor (mirrors LibraryManager's actor isolation).
@MainActor
final class ScanCacheService {
    static let shared = ScanCacheService()

    private struct CacheEntry: Codable {
        let mtime: TimeInterval
        let fileSize: Int64
        let song: Song
    }

    private var entries: [String: CacheEntry] = [:]
    private let cacheURL: URL

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheURL = caches.appendingPathComponent("library_scan_cache_v3.json")
        load()
    }

    /// Returns the cached `Song` for `url` if file attributes match the stored entry.
    func cachedSong(for url: URL) -> Song? {
        guard let entry = entries[stableKey(for: url)] else { return nil }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64,
              let mdate = attrs[.modificationDate] as? Date,
              entry.mtime == mdate.timeIntervalSince1970,
              entry.fileSize == size
        else { return nil }
        return entry.song
    }

    /// Stores a `Song` for `url` keyed on the current file `(mtime, size)`.
    func store(song: Song, for url: URL) {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64,
              let mdate = attrs[.modificationDate] as? Date
        else { return }
        entries[stableKey(for: url)] = CacheEntry(
            mtime: mdate.timeIntervalSince1970,
            fileSize: size,
            song: song
        )
    }

    /// Writes the in-memory cache to disk atomically. Call once after a bulk scan completes.
    func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }

    /// Removes cache entries for paths that no longer exist on disk.
    func evictMissing() {
        entries = entries.filter { FileManager.default.fileExists(atPath: $0.key) }
    }

    private func stableKey(for url: URL) -> String {
        url.standardizedFileURL.path
    }

    private func load() {
        guard let data = try? Data(contentsOf: cacheURL),
              let decoded = try? JSONDecoder().decode([String: CacheEntry].self, from: data)
        else { return }
        entries = decoded
    }
}
