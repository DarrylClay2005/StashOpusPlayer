import AVFoundation
import Foundation
import MediaPlayer
import UIKit

final class ArtworkService {
    static let shared = ArtworkService()

    private let memoryCache = NSCache<NSString, UIImage>()
    private let diskCacheURL: URL

    /// One-entry cache so repeated calls for the same persistentID skip re-querying MPMediaLibrary.
    private var mediaQueryCache: [UInt64: UIImage?] = [:]

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

    func loadArtwork(for song: Song) async -> UIImage? {
        let key = cacheKey(for: song)

        if let cached = memoryCache.object(forKey: key as NSString) {
            return cached
        }

        if let onDisk = loadFromDisk(key: key) {
            setMemoryCache(onDisk, forKey: key)
            return onDisk
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
                saveToDisk(image: image, key: key)
            }
            return image
        }

        return nil
    }

    // MARK: - Private Helpers

    private func cacheKey(for song: Song) -> String {
        song.artworkCacheKey ?? song.id
    }

    private func diskPath(key: String) -> URL {
        diskCacheURL.appendingPathComponent("\(key).jpg")
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

    /// Fetches artwork from MPMediaLibrary, using `mediaQueryCache` to avoid redundant queries.
    private func fetchMediaLibraryArtwork(persistentID: UInt64) async -> UIImage? {
        // Check the per-ID cache first (nil entry means we already tried and found nothing).
        if let cached = mediaQueryCache[persistentID] {
            return cached
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

        // Cache result (including nil so we don't re-query for missing artwork).
        mediaQueryCache[persistentID] = image
        return image
    }

    private func fetchAssetArtwork(url: URL, key: String) async -> UIImage? {
        return await Task.detached(priority: .utility) {
            let asset = AVURLAsset(url: url)
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
