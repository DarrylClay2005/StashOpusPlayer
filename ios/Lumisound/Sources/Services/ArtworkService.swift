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
    ///
    /// `loadArtwork` is a plain (non-actor-isolated) async function invoked
    /// concurrently from many `ArtworkThumbnail.task` instances while scrolling
    /// plus the background `prefetch` loop, so it can run on different threads of
    /// the cooperative pool at the same time. A bare `Set<String>` mutated from
    /// concurrent reads/inserts is a data race (unlike `memoryCache`/`mediaQueryCache`,
    /// which are `NSCache` and already thread-safe) — guard it with a lock.
    private var noArtworkKeys: Set<String> = []
    private let noArtworkLock = NSLock()

    private func isKnownNoArtwork(_ key: String) -> Bool {
        noArtworkLock.lock()
        defer { noArtworkLock.unlock() }
        return noArtworkKeys.contains(key)
    }

    private func markNoArtwork(_ key: String) {
        noArtworkLock.lock()
        defer { noArtworkLock.unlock() }
        noArtworkKeys.insert(key)
    }

    private func clearNoArtworkKeys() {
        noArtworkLock.lock()
        defer { noArtworkLock.unlock() }
        noArtworkKeys.removeAll()
    }

    /// Sentinel image stored in `mediaQueryCache` to signal "already checked, no artwork".
    private let noArtworkSentinel = UIImage()

    private static let videoExtensions: Set<String> = ["mp4", "m4v", "mov"]

    /// Cap for cached/persisted artwork dimensions. Was 600 — visibly blurry
    /// on @3x displays where the largest artwork view (NowPlaying, 300pt) needs
    /// ~900 physical px, even when the source file embeds UHD artwork. 1200
    /// covers that with headroom across @2x/@3x without ballooning disk usage.
    private static let artworkCacheDimension: CGFloat = 1200

    /// Bump whenever `artworkCacheDimension`/JPEG quality changes — triggers a
    /// one-time purge of disk-cached artwork written under the old settings, so
    /// upgrading users see the quality improvement without having to find and
    /// tap "Clear Artwork Cache" in Settings themselves.
    // v3: artwork is now letterbox-trimmed + square-cropped on cache write, so
    // purge older entries that were stored 16:9/letterboxed.
    private static let cacheFormatVersion = 3
    private static let cacheVersionFileName = ".cache_format_version"

    private init() {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            fatalError("Caches directory unavailable")
        }
        diskCacheURL = caches.appendingPathComponent("Artwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)
        purgeStaleArtworkCacheIfNeeded()

        // LRU eviction: cap at 200 images. NSCache evicts least-recently-used entries
        // automatically under memory pressure and when countLimit is exceeded.
        memoryCache.countLimit = 200
        memoryCache.totalCostLimit = 100 * 1024 * 1024   // 100 MB (was 50; video frames are large)
    }

    /// Wipes previously-cached artwork files once per `cacheFormatVersion` bump,
    /// so stale low-resolution/low-quality images don't linger on disk and keep
    /// being served instead of freshly (re)generated ones.
    ///
    /// Runs entirely off the main thread: `ArtworkService.shared` is first
    /// touched from `LibraryManager.init` during app launch, and synchronously
    /// deleting hundreds/thousands of cache files there would stall startup —
    /// exactly the kind of "update install freakout" users were already hitting
    /// from an unrelated full-library-rescan bug. The version-file write happens
    /// last so a process kill mid-purge re-triggers the purge next launch instead
    /// of leaving the cache in a mixed old/new state.
    private func purgeStaleArtworkCacheIfNeeded() {
        let versionFile = diskCacheURL.appendingPathComponent(Self.cacheVersionFileName)
        let storedVersion = (try? String(contentsOf: versionFile, encoding: .utf8))
            .flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        guard storedVersion != Self.cacheFormatVersion else { return }

        let cacheURL = diskCacheURL
        let newVersion = Self.cacheFormatVersion
        Task.detached(priority: .utility) {
            let fm = FileManager.default
            if let contents = try? fm.contentsOfDirectory(
                at: cacheURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
            ) {
                for url in contents { try? fm.removeItem(at: url) }
            }
            try? "\(newVersion)".write(to: versionFile, atomically: true, encoding: .utf8)
        }
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
        // Square-crop + downscale once, then use the SAME processed image for
        // both caches so the in-memory and on-disk copies match (previously the
        // raw, possibly non-square image went into memory while the squared one
        // went to disk — the artwork appeared to "re-crop" after a relaunch).
        let processed = resizedImage(image, maxDimension: Self.artworkCacheDimension)
        setMemoryCache(processed, forKey: key)
        saveToDisk(image: processed, key: key)
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
        if isKnownNoArtwork(key) { return nil }

        // Streaming tracks store their thumbnail URL as the artworkCacheKey.
        if let cacheKeyStr = song.artworkCacheKey,
           cacheKeyStr.hasPrefix("http"),
           let thumbnailURL = URL(string: cacheKeyStr) {
            appLog("Artwork: fetching remote thumbnail for \"\(song.displayName)\"", category: "artwork")
            if let image = await fetchRemoteImage(url: thumbnailURL, headers: song.httpHeaders) {
                // Cache and return the same downsized copy that lands on disk — caching the
                // full-resolution decode here (often far larger than artworkCacheDimension)
                // let just a few entries blow through totalCostLimit, forcing constant
                // evict/redecode churn while scrolling artwork-heavy views.
                let resized = resizedImage(image, maxDimension: Self.artworkCacheDimension)
                setMemoryCache(resized, forKey: key)
                saveToDisk(image: resized, key: key)
                return resized
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
                // Embedded tags are frequently full-resolution (3000×3000+) — downsize
                // before caching/returning so memory cost matches the disk copy.
                let resized = resizedImage(image, maxDimension: Self.artworkCacheDimension)
                setMemoryCache(resized, forKey: key)
                saveToDisk(image: resized, key: key)
                return resized
            }

            // Tracks downloaded via the bridge are tagged with the original
            // YouTube/SoundCloud thumbnail URL (LUMISOUND_THUMBNAIL) since
            // --embed-thumbnail isn't available. If the disk cache entry seeded
            // at download time was ever cleared, recover the same thumbnail here
            // instead of falling through to a guess-based iTunes Search lookup.
            if let thumbnailURL = await fetchEmbeddedThumbnailURL(url: url),
               let image = await fetchRemoteImage(url: thumbnailURL) {
                appLog("Artwork: recovered embedded LUMISOUND_THUMBNAIL for \"\(song.displayName)\"", category: "artwork")
                let resized = resizedImage(image, maxDimension: Self.artworkCacheDimension)
                setMemoryCache(resized, forKey: key)
                saveToDisk(image: resized, key: key)
                return resized
            }

            // For local video files, extract the first frame as artwork.
            if Self.videoExtensions.contains(url.pathExtension.lowercased()) {
                appLog("Artwork: extracting video frame for \"\(song.displayName)\"", category: "artwork")
                if let image = await extractVideoFrame(url: url) {
                    let resized = resizedImage(image, maxDimension: Self.artworkCacheDimension)
                    setMemoryCache(resized, forKey: key)
                    saveToDisk(image: resized, key: key)
                    return resized
                }
                appWarn("Artwork: video frame extraction failed for \"\(song.displayName)\"", category: "artwork")
            }
        }

        // Last resort: iTunes Search API using song title + artist.
        appLog("Artwork: querying iTunes for \"\(song.displayName)\" by \(song.artistName)", category: "artwork")
        if let image = await fetchITunesArtwork(title: song.title, artist: song.artist) {
            appLog("Artwork: iTunes match found for \"\(song.displayName)\"", category: "artwork")
            let resized = resizedImage(image, maxDimension: Self.artworkCacheDimension)
            setMemoryCache(resized, forKey: key)
            saveToDisk(image: resized, key: key)
            return resized
        }

        markNoArtwork(key)
        appWarn("Artwork: no source found for \"\(song.displayName)\"", category: "artwork")
        return nil
    }

    // MARK: - Cache Management

    /// Evicts all in-memory artwork entries immediately.
    /// The disk cache is left intact so artwork can be reloaded on next access.
    func clearCache() {
        memoryCache.removeAllObjects()
        mediaQueryCache.removeAllObjects()
        clearNoArtworkKeys()
    }

    /// Warms the memory cache for the given songs at background priority.
    /// Skips any song whose artwork is already cached; does not force-store entries
    /// when the cache is at capacity — NSCache will evict as needed.
    func prefetch(songs: [Song]) {
        Task(priority: .background) {
            for song in songs {
                guard artwork(for: song) == nil else { continue }
                _ = await loadArtwork(for: song)
            }
        }
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
        guard let data = image.jpegData(compressionQuality: 0.92) else {
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
        // 1) Trim solid letterbox/pillarbox bars (e.g. a 16:9 video frame padded
        //    into a 4:3 `hqdefault` YouTube thumbnail, which a plain square crop
        //    would otherwise keep — the "artwork still shows 16:9 with black
        //    bars" symptom). 2) center-crop the remaining content to a square so
        //    it fills the square frames used everywhere. Already-square art with
        //    no bars passes through both steps unchanged.
        let trimmed = trimmedLetterbox(image)
        let squared = squareCropped(trimmed)
        let size = squared.size
        guard size.width > maxDimension || size.height > maxDimension else { return squared }
        let scale = min(maxDimension / size.width, maxDimension / size.height)
        let newSize = CGSize(width: (size.width * scale).rounded(),
                             height: (size.height * scale).rounded())
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in squared.draw(in: CGRect(origin: .zero, size: newSize)) }
    }

    /// Returns the largest centered square crop of `image`. A no-op for images
    /// that are already square. Operates in the image's own pixel space and
    /// preserves orientation by rendering through `UIGraphicsImageRenderer`.
    private func squareCropped(_ image: UIImage) -> UIImage {
        let w = image.size.width
        let h = image.size.height
        guard w > 0, h > 0, abs(w - h) > 0.5 else { return image }
        let side = min(w, h)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        return renderer.image { _ in
            // Center the source so equal amounts are cropped from both edges of
            // the longer dimension.
            let origin = CGPoint(x: (side - w) / 2, y: (side - h) / 2)
            image.draw(in: CGRect(origin: origin, size: CGSize(width: w, height: h)))
        }
    }

    /// Detects and crops away near-uniform horizontal (letterbox) and vertical
    /// (pillarbox) bars around an image's real content — the matte/black bars
    /// baked into padded thumbnails (e.g. a 16:9 still inside a 4:3
    /// `hqdefault.jpg`). Scans a small downsampled copy for speed, maps the
    /// content rect back to the original, and crops. Returns the original
    /// unchanged when no significant bars are found.
    private func trimmedLetterbox(_ image: UIImage) -> UIImage {
        guard let cg = image.cgImage else { return image }
        let origW = cg.width, origH = cg.height
        guard origW > 8, origH > 8 else { return image }

        // Downsample to a small buffer (max 64px on the long edge) for a cheap scan.
        let maxScan = 64
        let scale = min(1.0, Double(maxScan) / Double(max(origW, origH)))
        let sw = max(2, Int(Double(origW) * scale))
        let sh = max(2, Int(Double(origH) * scale))
        let bytesPerRow = sw * 4
        var buf = [UInt8](repeating: 0, count: bytesPerRow * sh)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &buf, width: sw, height: sh, bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: sw, height: sh))

        // A row/column is a "bar" if every pixel is near-uniform AND close to the
        // corner color (the matte). Uniform: low spread from the line's first px.
        func brightness(_ i: Int) -> Int { Int(buf[i]) + Int(buf[i + 1]) + Int(buf[i + 2]) }
        let tol = 48  // per-channel-sum tolerance (~16/channel)

        func rowIsBar(_ y: Int) -> Bool {
            let base = y * bytesPerRow
            let ref = brightness(base)
            if ref > 170 * 3 { return false }  // bars are dark; skip bright rows
            for x in 0..<sw {
                if abs(brightness(base + x * 4) - ref) > tol { return false }
            }
            return true
        }
        func colIsBar(_ x: Int) -> Bool {
            let ref = brightness(x * 4)
            if ref > 170 * 3 { return false }
            for y in 0..<sh {
                if abs(brightness(y * bytesPerRow + x * 4) - ref) > tol { return false }
            }
            return true
        }

        var top = 0; while top < sh && rowIsBar(top) { top += 1 }
        var bottom = sh - 1; while bottom > top && rowIsBar(bottom) { bottom -= 1 }
        var left = 0; while left < sw && colIsBar(left) { left += 1 }
        var right = sw - 1; while right > left && colIsBar(right) { right -= 1 }

        let contentW = right - left + 1
        let contentH = bottom - top + 1
        // Ignore tiny trims (noise) — only act when a real bar (>4% of a side) exists.
        let trimmedX = (left + (sw - 1 - right))
        let trimmedY = (top + (sh - 1 - bottom))
        guard contentW > sw / 2, contentH > sh / 2,
              (trimmedY > sh / 25 || trimmedX > sw / 25) else { return image }

        // Map the content rect back to original pixel coordinates.
        let fx = Double(origW) / Double(sw)
        let fy = Double(origH) / Double(sh)
        let cropRect = CGRect(
            x: Double(left) * fx, y: Double(top) * fy,
            width: Double(contentW) * fx, height: Double(contentH) * fy
        ).integral
        guard let cropped = cg.cropping(to: cropRect) else { return image }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
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
            return item.artwork?.image(at: CGSize(width: Self.artworkCacheDimension, height: Self.artworkCacheDimension))
        }.value

        mediaQueryCache.setObject(image ?? noArtworkSentinel, forKey: cacheKey)
        return image
    }

    func fetchRemoteImage(url: URL, headers: [String: String]? = nil) async -> UIImage? {
        var req = URLRequest(url: url)
        headers?.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        guard let (data, response) = try? await URLSession.shared.data(for: req),
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

    /// Reads the `LUMISOUND_THUMBNAIL` metadata tag (embedded by the bridge at
    /// download time — see `_do_download_job`'s `tag_cmd`) and returns it as a URL.
    private func fetchEmbeddedThumbnailURL(url: URL) async -> URL? {
        return await Task.detached(priority: .utility) {
            let asset = AVURLAsset(url: url)
            guard let allMeta = try? await asset.load(.metadata) else { return nil as URL? }
            // Surfaces under different identifier forms depending on container —
            // check both the identifier and key, matching the LUMISOUND_ID lookup
            // in DocumentImportService.
            for item in allMeta {
                let idRaw = item.identifier?.rawValue.lowercased() ?? ""
                let keyRaw = (item.key as? String)?.lowercased() ?? ""
                guard idRaw.contains("lumisound_thumbnail") || keyRaw.contains("lumisound_thumbnail") else { continue }
                if let value = try? await item.load(.stringValue), let url = URL(string: value) {
                    return url
                }
            }
            return nil as URL?
        }.value
    }

    /// Extracts the first frame of a video file as a thumbnail.
    /// Uses the modern async `image(at:)` API on iOS 16+ with sync fallback.
    private func extractVideoFrame(url: URL) async -> UIImage? {
        return await Task.detached(priority: .utility) {
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: Self.artworkCacheDimension, height: Self.artworkCacheDimension)
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
