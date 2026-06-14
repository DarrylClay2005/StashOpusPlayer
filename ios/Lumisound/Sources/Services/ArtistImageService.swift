import Foundation
import UIKit

/// Fetches and caches real artist profile pictures, distinct from any track's
/// album artwork. Previously, artist rows/grid cells fell back to showing the
/// album art of whichever song happened to be first for that artist — which
/// looks like "random folder/track art" rather than an actual artist photo.
///
/// Source: Deezer's public search API (`api.deezer.com/search/artist`), which
/// requires no API key and returns `picture_xl` / `picture_medium` fields that
/// are genuine artist photos (not album covers). If Deezer has no match, no
/// image is returned and callers should fall back to a generic person icon —
/// never to a track's album art.
///
/// Caching mirrors `ArtworkService`'s memory + disk cache pattern: an
/// `NSCache` for fast in-memory hits, plus JPEG files under Caches/ArtistImages
/// keyed by a sanitized lowercase artist name so images persist across launches.
final class ArtistImageService {
    static let shared = ArtistImageService()

    private let memoryCache = NSCache<NSString, UIImage>()
    private let diskCacheURL: URL

    /// In-memory set of artist names known to have no Deezer match, so we don't
    /// repeatedly hit the network for artists with no photo available.
    private var noImageKeys: Set<String> = []
    private let noImageLock = NSLock()

    private init() {
        memoryCache.countLimit = 100
        memoryCache.totalCostLimit = 40 * 1024 * 1024 // 40 MB

        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        let dir = (caches ?? FileManager.default.temporaryDirectory).appendingPathComponent("ArtistImages", isDirectory: true)
        diskCacheURL = dir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    /// Returns a cached image (memory or disk) without making a network request.
    func cachedImage(for artist: String) -> UIImage? {
        let key = cacheKey(for: artist)
        if let cached = memoryCache.object(forKey: key as NSString) {
            return cached
        }
        if let onDisk = loadFromDisk(key: key) {
            setMemoryCache(onDisk, forKey: key)
            return onDisk
        }
        return nil
    }

    /// Loads the artist's profile picture, checking memory/disk caches first,
    /// then falling back to a Deezer artist search. Returns `nil` if no
    /// real artist photo could be found — callers should show a generic
    /// person icon in that case, never a track's album art.
    func loadImage(for artist: String) async -> UIImage? {
        let key = cacheKey(for: artist)

        if let cached = memoryCache.object(forKey: key as NSString) {
            return cached
        }
        if let onDisk = loadFromDisk(key: key) {
            setMemoryCache(onDisk, forKey: key)
            return onDisk
        }

        if isKnownNoImage(key) { return nil }

        guard let image = await fetchFromDeezer(artist: artist) else {
            markNoImage(key)
            return nil
        }

        setMemoryCache(image, forKey: key)
        saveToDisk(image: image, key: key)
        return image
    }

    /// Warms the cache for the given artist names at background priority.
    func prefetch(artists: [String]) {
        Task(priority: .background) {
            for artist in artists {
                guard cachedImage(for: artist) == nil else { continue }
                _ = await loadImage(for: artist)
            }
        }
    }

    // MARK: - Deezer

    private func fetchFromDeezer(artist: String) async -> UIImage? {
        let trimmed = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.localizedCaseInsensitiveCompare("Unknown Artist") != .orderedSame,
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.deezer.com/search/artist?q=\(encoded)&limit=1")
        else { return nil }

        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["data"] as? [[String: Any]],
              let first = results.first
        else { return nil }

        // Prefer the largest available photo; Deezer's "default" placeholder
        // images use a recognizable filename fragment we filter out.
        let candidates = [
            first["picture_xl"] as? String,
            first["picture_big"] as? String,
            first["picture_medium"] as? String
        ].compactMap { $0 }

        for candidateStr in candidates {
            guard !candidateStr.contains("artist//"), !candidateStr.isEmpty,
                  let imageURL = URL(string: candidateStr) else { continue }
            if let image = await fetchRemoteImage(url: imageURL) {
                return image
            }
        }
        return nil
    }

    private func fetchRemoteImage(url: URL) async -> UIImage? {
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return UIImage(data: data)
    }

    // MARK: - Cache helpers

    private func cacheKey(for artist: String) -> String {
        artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func sanitizedKey(_ key: String) -> String {
        let illegal = CharacterSet(charactersIn: "/:\\*?\"<>| ")
        return key.components(separatedBy: illegal).joined(separator: "_")
    }

    private func diskPath(key: String) -> URL {
        diskCacheURL.appendingPathComponent("\(sanitizedKey(key)).jpg")
    }

    private func loadFromDisk(key: String) -> UIImage? {
        let path = diskPath(key: key)
        guard FileManager.default.fileExists(atPath: path.path),
              let data = try? Data(contentsOf: path),
              let image = UIImage(data: data)
        else { return nil }
        return image
    }

    private func saveToDisk(image: UIImage, key: String) {
        guard let data = image.jpegData(compressionQuality: 0.9) else { return }
        try? data.write(to: diskPath(key: key), options: .atomic)
    }

    private func setMemoryCache(_ image: UIImage, forKey key: String) {
        let cost = Int(image.size.width * image.size.height * 4)
        memoryCache.setObject(image, forKey: key as NSString, cost: cost)
    }

    private func isKnownNoImage(_ key: String) -> Bool {
        noImageLock.lock()
        defer { noImageLock.unlock() }
        return noImageKeys.contains(key)
    }

    private func markNoImage(_ key: String) {
        noImageLock.lock()
        defer { noImageLock.unlock() }
        noImageKeys.insert(key)
    }
}
