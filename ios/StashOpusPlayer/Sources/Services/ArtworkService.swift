import AVFoundation
import Foundation
import MediaPlayer
import UIKit

final class ArtworkService {
    static let shared = ArtworkService()

    private let memoryCache = NSCache<NSString, UIImage>()
    private let diskCacheURL: URL

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        diskCacheURL = caches.appendingPathComponent("Artwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)
    }

    func artwork(for song: Song) -> UIImage? {
        let key = cacheKey(for: song)
        if let cached = memoryCache.object(forKey: key as NSString) {
            return cached
        }
        if let onDisk = loadFromDisk(key: key) {
            memoryCache.setObject(onDisk, forKey: key as NSString)
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
            memoryCache.setObject(onDisk, forKey: key as NSString)
            return onDisk
        }

        if let persistentID = song.persistentID {
            let image = await fetchMediaLibraryArtwork(persistentID: persistentID)
            if let image {
                memoryCache.setObject(image, forKey: key as NSString)
            }
            return image
        }

        if let url = song.url {
            let image = await fetchAssetArtwork(url: url, key: key)
            if let image {
                memoryCache.setObject(image, forKey: key as NSString)
                saveToDisk(image: image, key: key)
            }
            return image
        }

        return nil
    }

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

    private func fetchMediaLibraryArtwork(persistentID: UInt64) async -> UIImage? {
        return await Task.detached(priority: .utility) {
            let predicate = MPMediaPropertyPredicate(
                value: NSNumber(value: persistentID),
                forProperty: MPMediaItemPropertyPersistentID
            )
            let query = MPMediaQuery()
            query.addFilterPredicate(predicate)
            guard let item = query.items?.first else { return nil }
            let size = CGSize(width: 400, height: 400)
            return item.artwork?.image(at: size)
        }.value
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
