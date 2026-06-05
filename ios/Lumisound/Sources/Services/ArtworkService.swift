import AVFoundation
import Foundation
import MediaPlayer
import UIKit

final class ArtworkService {
    static let shared = ArtworkService()

    private let memoryCache = NSCache<NSString, UIImage>()
    private let diskCacheURL: URL

    /// Thread-safe cache for MPMediaLibrary lookups keyed by persistentID.
    private let mediaQueryCache = NSCache<NSNumber, UIImage>()

    /// In-memory set of cache keys for which all artwork sources failed. Prevents
    /// repeated lookups (including remote API calls) for tracks that have no artwork.
    /// Resets on app relaunch — that's fine; one miss per launch is acceptable.
    private var noArtworkKeys: Set<String> = []

    /// Sentinel image stored in `mediaQueryCache` to signal "already checked, no artwork".
    private let noArtworkSentinel = UIImage()

    private static let videoExtensions: Set<String> = ["mp4", "m4v", "mov"]

    private init() {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            fatalError("Caches directory unavailable")
        }
        diskCacheURL = caches.appendingPathComponent("Artwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)

        memoryCache.countLimit = 300
        memoryCache.totalCostLimit = 100 * 1024 * 1024   // 100 MB (was 50; video frames are large)
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

    /// Stores `image` in both memory and disk cache under `key`.
    /// Used by DocumentImportService to persist video-frame thumbnails so they
    /// survive app restarts and NSCache evictions.
    func cacheImage(_ image: UIImage, forKey key: String) {
        setMemoryCache(image, forKey: key)
        let resized = resizedImage(image, maxDimension: 600)
        saveToDisk(image: resized, key: key)
    }

    /// Fetches a remote image and writes it to both memory and disk cache under `key`.
    /// Call this before `scanLocalDocuments()` when you know the artwork URL in advance
    /// (e.g. after a YouTube/SoundCloud download to pre-seed the thumbnail).
    func prefetchRemoteImage(url: URL, forKey key: String) async {
        // Skip if already on disk.
        if loadFromDisk(key: key) != nil { return }
        guard let image = await fetchRemoteImage(url: url) else { return }
        cacheImage(image, forKey: key)
    }

    /// Full async artwork load: memory → disk → remote URL → media library →
    /// embedded asset metadata → video frame extraction → iTunes Search API.
    func loadArtwork(for song: Song) async -> UIImage? {
        let key = cacheKey(for: song)

        if let cached = memoryCache.object(forKey: key as NSString) {
            return cached
        }

        if let onDisk = loadFromDisk(key: key) {
            setMemoryCache(onDisk, forKey: key)
            return onDisk
        }

        // Negative cache: skip all network/API sources for keys we already know have no artwork.
        if noArtworkKeys.contains(key) { return nil }

        // Streaming tracks store their thumbnail URL as the artworkCacheKey.
        if let cacheKeyStr = song.artworkCacheKey,
           cacheKeyStr.hasPrefix("http"),
           let thumbnailURL = URL(string: cacheKeyStr) {
            appLog("Artwork: fetching remote thumbnail for \"\(song.displayName)\"", category: "artwork")
            if let image = await fetchRemoteImage(url: thumbnailURL) {
                setMemoryCache(image, forKey: key)
                let resized = resizedImage(image, maxDimension: 600)
                saveToDisk(image: resized, key: key)
                return image
            }
            appWarn("Artwork: remote fetch failed for \"\(song.displayName)\"", category: "artwork")
        }

        if let persistentID = song.persistentID {
            let image = await fetchMediaLibraryArtwork(persistentID: persistentID)
            if let image {
                appLog("Artwork: media library hit for \"\(song.displayName)\"", category: "artwork")
                setMemoryCache(image, forKey: key)
            } else {
                appLog("Artwork: media library miss for \"\(song.displayName)\"", category: "artwork")
            }
            return image
        }

        if let url = song.url {
            // Try embedded asset artwork (works for m4a, mp3, flac with embedded tags).
            if let image = await fetchAssetArtwork(url: url) {
                appLog("Artwork: embedded tag found for \"\(song.displayName)\"", category: "artwork")
                setMemoryCache(image, forKey: key)
                saveToDisk(image: resizedImage(image, maxDimension: 600), key: key)
                return image
            }

            // For local video files, extract the first frame as artwork.
            if Self.videoExtensions.contains(url.pathExtension.lowercased()) {
                appLog("Artwork: extracting video frame for \"\(song.displayName)\"", category: "artwork")
                if let image = await extractVideoFrame(url: url) {
                    setMemoryCache(image, forKey: key)
                    saveToDisk(image: resizedImage(image, maxDimension: 600), key: key)
                    return image
                }
                appWarn("Artwork: video frame extraction failed for \"\(song.displayName)\"", category: "artwork")
            }
        }

        // Last resort: iTunes Search API using song title + artist.
        appLog("Artwork: querying iTunes for \"\(song.displayName)\" by \(song.artistName)", category: "artwork")
        if let image = await fetchITunesArtwork(title: song.title, artist: song.artist) {
            appLog("Artwork: iTunes match found for \"\(song.displayName)\"", category: "artwork")
            setMemoryCache(image, forKey: key)
            saveToDisk(image: resizedImage(image, maxDimension: 600), key: key)
            return image
        }

        noArtworkKeys.insert(key)
        appWarn("Artwork: no source found for \"\(song.displayName)\"", category: "artwork")
        return nil
    }

    // MARK: - Private Helpers

    private func cacheKey(for song: Song) -> String {
        song.artworkCacheKey ?? song.id
    }

    private func sanitizedKey(_ key: String) -> String {
        let illegal = CharacterSet(charactersIn: "/:\\*?\"<>|")
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
        let path = diskPath(key: key)
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            appWarn("Artwork: saveToDisk encode failed for key \(key)", category: "artwork")
            return
        }
        do {
            try data.write(to: path, options: .atomic)
        } catch {
            appWarn("Artwork: saveToDisk write failed for key \(key): \(error)", category: "artwork")
        }
    }

    private func setMemoryCache(_ image: UIImage, forKey key: String) {
        let cost = Int(image.size.width * image.size.height * 4)
        memoryCache.setObject(image, forKey: key as NSString, cost: cost)
    }

    private func resizedImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        guard size.width > maxDimension || size.height > maxDimension else { return image }
        let scale = min(maxDimension / size.width, maxDimension / size.height)
        let newSize = CGSize(width: (size.width * scale).rounded(),
                             height: (size.height * scale).rounded())
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
    }

    // MARK: - Fetch methods

    private func fetchMediaLibraryArtwork(persistentID: UInt64) async -> UIImage? {
        let cacheKey = NSNumber(value: persistentID)
        if let cached = mediaQueryCache.object(forKey: cacheKey) {
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
            return item.artwork?.image(at: CGSize(width: 400, height: 400))
        }.value

        mediaQueryCache.setObject(image ?? noArtworkSentinel, forKey: cacheKey)
        return image
    }

    func fetchRemoteImage(url: URL) async -> UIImage? {
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return UIImage(data: data)
    }

    /// Reads embedded artwork from the file's metadata — checks both commonMetadata
    /// and all format-specific metadata items to maximise coverage across m4a, mp3, flac, etc.
    private func fetchAssetArtwork(url: URL) async -> UIImage? {
        return await Task.detached(priority: .utility) {
            let asset = AVURLAsset(url: url)

            // Pass 1: commonMetadata (works for most formats, fastest path)
            if let commonMetadata = try? await asset.load(.commonMetadata) {
                for item in commonMetadata where item.commonKey == .commonKeyArtwork {
                    if let data = try? await item.load(.dataValue),
                       let image = UIImage(data: data) { return image }
                    if let value = try? await item.load(.value) as? Data,
                       let image = UIImage(data: value) { return image }
                }
            }

            // Pass 2: all metadata items — catches artwork in format-specific tags
            // that AVFoundation doesn't surface via commonMetadata (e.g. some FLAC files).
            if let allMeta = try? await asset.load(.metadata) {
                for item in allMeta {
                    guard let identifierRaw = item.identifier?.rawValue else { continue }
                    let id = identifierRaw.lowercased()
                    guard id.contains("artwork") || id.contains("covr") ||
                          id.contains("apic") || id.contains("picture") else { continue }
                    if let data = try? await item.load(.dataValue),
                       data.count > 500,
                       let image = UIImage(data: data) { return image }
                    if let value = try? await item.load(.value) as? Data,
                       value.count > 500,
                       let image = UIImage(data: value) { return image }
                }
            }

            return nil as UIImage?
        }.value
    }

    /// Extracts the first frame of a video file as a thumbnail.
    /// Uses the modern async `image(at:)` API on iOS 16+ with sync fallback.
    private func extractVideoFrame(url: URL) async -> UIImage? {
        return await Task.detached(priority: .utility) {
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 600, height: 600)
            let time = CMTime(seconds: 1, preferredTimescale: 600)

            if #available(iOS 16, *) {
                if let result = try? await generator.image(at: time) {
                    return UIImage(cgImage: result.image)
                }
            } else {
                if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
                    return UIImage(cgImage: cgImage)
                }
            }
            return nil as UIImage?
        }.value
    }

    /// Queries the iTunes Search API for artwork matching `title` + `artist`.
    /// Used as a last resort for tracks that have no embedded art and are not video files.
    private func fetchITunesArtwork(title: String, artist: String) async -> UIImage? {
        let query = [title, artist]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !query.isEmpty,
              let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let apiURL = URL(string: "https://itunes.apple.com/search?term=\(encoded)&entity=song&limit=1&country=US")
        else { return nil }

        guard let (data, response) = try? await URLSession.shared.data(from: apiURL),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]],
              let first = results.first
        else { return nil }

        // Prefer 600×600 artwork; fall back to 100×100 upscaled.
        let artStr = (first["artworkUrl600"] as? String)
            ?? (first["artworkUrl100"] as? String ?? "").replacingOccurrences(of: "100x100bb", with: "600x600bb")
        guard let artURL = URL(string: artStr) else { return nil }
        return await fetchRemoteImage(url: artURL)
    }
}
