import Foundation

/// Persists `(mtime, fileSize) → Song` mappings on disk so repeated library scans
/// skip AVURLAsset metadata extraction for unchanged files.
/// Must be accessed on @MainActor (mirrors LibraryManager's actor isolation).
@MainActor
final class ScanCacheService {
    static let shared = ScanCacheService()

    struct CacheEntry: Codable {
        let mtime: TimeInterval
        let fileSize: Int64
        let song: Song
    }

    /// File `(mtime, size)` — the cheap, hashable identity used to detect changed files
    /// without re-running expensive `AVURLAsset` metadata extraction.
    struct FileStamp: Hashable {
        let mtime: TimeInterval
        let size: Int64
    }

    private var entries: [String: CacheEntry] = [:]
    private let cacheURL: URL

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheURL = caches.appendingPathComponent("library_scan_cache_v3.json")
        load()
    }

    /// Reads `(mtime, size)` for `url` directly from the filesystem.
    ///
    /// This performs a blocking `stat()` syscall — callers scanning many files
    /// MUST run this off the main actor (e.g. inside `Task.detached`) so a large
    /// library scan doesn't stall the UI with thousands of serial syscalls.
    nonisolated static func fileStamp(for url: URL) -> FileStamp? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64,
              let mdate = attrs[.modificationDate] as? Date
        else { return nil }
        return FileStamp(mtime: mdate.timeIntervalSince1970, size: size)
    }

    /// Returns the cached `Song` for `url` if `stamp` matches the stored entry.
    /// Pure in-memory dictionary lookup — no I/O, safe to call on the main actor.
    func cachedSong(for url: URL, stamp: FileStamp) -> Song? {
        guard let entry = entries[stableKey(for: url)],
              entry.mtime == stamp.mtime,
              entry.fileSize == stamp.size
        else { return nil }
        return entry.song
    }

    /// Stores a `Song` for `url` keyed on the given `(mtime, size)` stamp.
    /// Pure in-memory dictionary write — no I/O, safe to call on the main actor.
    func store(song: Song, for url: URL, stamp: FileStamp) {
        entries[stableKey(for: url)] = CacheEntry(mtime: stamp.mtime, fileSize: stamp.size, song: song)
    }

    /// Writes the in-memory cache to disk atomically. Call once after a bulk scan completes.
    /// Encoding/writing thousands of entries is offloaded to a background task so it
    /// never blocks the main thread.
    func persist() {
        let snapshot = entries
        let destination = cacheURL
        Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: destination, options: .atomic)
        }
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
