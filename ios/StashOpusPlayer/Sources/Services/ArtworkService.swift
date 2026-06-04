import AVFoundation
import Foundation
import MediaPlayer
import UIKit

final class ArtworkService {
    static let shared = ArtworkService()

    private let memoryCache = NSCache<NSString, UIImage>()
    private let diskCacheURL: URL

    /// Thread-safe cache for MPMediaLibrary lookups keyed by persistentID.
    ///
    /// `NSCache` is thread-safe and can be accessed from any thread or Task.
    /// Using it here (instead of a plain Swift dictionary) eliminates the data
    /// race that would otherwise exist when `fetchMediaLibraryArtwork` runs
    /// inside a `Task.detached` that can execute on any thread.
    ///
    /// "No artwork found" sentinel: a zero-size `UIImage()` is stored so that
    /// we don't re-query MPMediaLibrary for tracks that have no artwork.
    private let mediaQueryCache = NSCache<NSNumber, UIImage>()

    /// Sentinel image stored in `mediaQueryCache` to signal "already checked,
    /// no artwork exists for this ID".  Identified by zero pixel size.
    private let noArtworkSentinel = UIImage()

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        diskCacheURL = caches.appendingPathComponent("Artwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)

        memoryCache.countLimit = 300                          // max 300 images in memory
        memoryCache.totalCostLimit = 50 * 1024 * 1024        // 50 MB cap
    }

    func artwork(for song: Song) -> UIImage? {
        let key = cacheKey(for: song)
        if let cached = memoryCache.object(forKey: key as NSString) {
            return cached
        }
        if let onDisk = loadFromDisk(key: key) {
            setMemoryCache(onDisk, forKey: key)
            return onDisk
        }
        return nil
    }

    /// Stores `image` directly into the memory cache under an arbitrary `key`.
    /// Used by DocumentImportService to pre-cache video-file thumbnails extracted
    /// via AVAssetImageGenerator before the Song object is constructed.
    func cacheImage(_ image: UIImage, forKey key: String) {
        setMemoryCache(image, forKey: key)
    }

    /// Loads artwork asynchronously, checking memory cache → disk cache →
    /// remote thumbnail URL (for streaming tracks) → MPMediaLibrary → embedded asset metadata.
    func loadArtwork(for song: Song) async -> UIImage? {
        let key = cacheKey(for: song)

        if let cached = memoryCache.object(forKey: key as NSString) {
            return cached
        }

        if let onDisk = loadFromDisk(key: key) {
            setMemoryCache(onDisk, forKey: key)
            return onDisk
        }

        // For streaming tracks the artworkCacheKey is a remote thumbnail URL (YouTube/SoundCloud).
        if let cacheKeyStr = song.artworkCacheKey,
           cacheKeyStr.hasPrefix("http"),
           let thumbnailURL = URL(string: cacheKeyStr) {
            if let image = await fetchRemoteImage(url: thumbnailURL) {
                setMemoryCache(image, forKey: key)
                let resized = resizedImage(image, maxDimension: 600)
                saveToDisk(image: resized, key: key)
                return image
            }
        }

        if let persistentID = song.persistentID {
            let image = await fetchMediaLibraryArtwork(persistentID: persistentID)
            if let image {
                setMemoryCache(image, forKey: key)
            }
            return image
        }

        if let url = song.url {
            let image = await fetchAssetArtwork(url: url, key: key)
            if let image {
                setMemoryCache(image, forKey: key)
                let resized = resizedImage(image, maxDimension: 600)
                saveToDisk(image: resized, key: key)
            }
            return image
        }

        return nil
    }

    // MARK: - Private Helpers

    private func cacheKey(for song: Song) -> String {
        song.artworkCacheKey ?? song.id
    }

    /// Returns a sanitized filename-safe version of `key` by replacing characters
    /// that are illegal in file system paths on common platforms.
    private func sanitizedKey(_ key: String) -> String {
        let illegalCharacters = CharacterSet(charactersIn: "/:\\*?\"<>|")
        return key.components(separatedBy: illegalCharacters).joined(separator: "_")
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

    /// Saves `image` to the JPEG disk cache.
    ///
    /// Note: disk cache entries are never automatically invalidated when the
    /// source song file is deleted.  This wastes a small amount of disk space
    /// but is an acceptable trade-off: the cache is keyed by filename/ID and
    /// will be evicted if the user clears the app cache through iOS Settings.
    private func saveToDisk(image: UIImage, key: String) {
        let path = diskPath(key: key)
        if let data = image.jpegData(compressionQuality: 0.85) {
            try? data.write(to: path, options: .atomic)
        }
    }

    /// Store into NSCache with a cost proportional to the image's pixel footprint (4 bytes/pixel).
    private func setMemoryCache(_ image: UIImage, forKey key: String) {
        let cost = Int(image.size.width * image.size.height * 4)
        memoryCache.setObject(image, forKey: key as NSString, cost: cost)
    }

    /// Returns a new image scaled down so that neither dimension exceeds
    /// `maxDimension` points.  If the image is already within bounds it is
    /// returned unchanged (no copy).
    private func resizedImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        guard size.width > maxDimension || size.height > maxDimension else { return image }

        let scale = min(maxDimension / size.width, maxDimension / size.height)
        let newSize = CGSize(width: (size.width * scale).rounded(),
                             height: (size.height * scale).rounded())

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    /// Fetches artwork from MPMediaLibrary.
    ///
    /// `mediaQueryCache` (an `NSCache`) is thread-safe, so this method may
    /// freely be called from `Task.detached` blocks running on background threads
    /// without additional synchronisation.  The `noArtworkSentinel` (a zero-size
    /// `UIImage`) is stored in the cache when no artwork is found so that
    /// subsequent calls skip the MPMediaQuery entirely.
    private func fetchMediaLibraryArtwork(persistentID: UInt64) async -> UIImage? {
        let cacheKey = NSNumber(value: persistentID)

        if let cached = mediaQueryCache.object(forKey: cacheKey) {
            // Distinguish between "real image" and "already checked, nothing found"
            return cached.size == .zero ? nil : cached
        }

        let image = await Task.detached(priority: .utility) {
            let predicate = MPMediaPropertyPredicate(
                value: NSNumber(value: persistentID),
                forProperty: MPMediaItemPropertyPersistentID
            )
            let query = MPMediaQuery()
            query.addFilterPredicate(predicate)
            guard let item = query.items?.first else { return nil as UIImage? }
            let size = CGSize(width: 400, height: 400)
            return item.artwork?.image(at: size)
        }.value

        // Cache result — use sentinel to record "no artwork" without storing nil
        mediaQueryCache.setObject(image ?? self.noArtworkSentinel, forKey: cacheKey)
        return image
    }

    /// Downloads an image from a remote URL (used for streaming track thumbnails).
    private func fetchRemoteImage(url: URL) async -> UIImage? {
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return UIImage(data: data)
    }

    private func fetchAssetArtwork(url: URL, key: String) async -> UIImage? {
        return await Task.detached(priority: .utility) {
            let asset = AVURLAsset(url: url)
            // If the file no longer exists, `load(.commonMetadata)` throws and
            // `try?` returns nil — that is handled correctly below.
            guard let metadata = try? await asset.load(.commonMetadata) else { return nil }
            for item in metadata {
                if item.commonKey == .commonKeyArtwork {
                    if let data = try? await item.load(.dataValue),
                       let image = UIImage(data: data) {
                        return image
                    }
                    if let value = try? await item.load(.value) as? Data,
                       let image = UIImage(data: value) {
                        return image
                    }
                }
            }
            return nil
        }.value
    }
}
