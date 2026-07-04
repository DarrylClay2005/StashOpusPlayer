import Foundation

// MARK: - CacheManagerService

@MainActor
final class CacheManagerService: ObservableObject {

    // MARK: Published

    @Published private(set) var artworkCacheSize:  Int64 = 0
    @Published private(set) var artworkCacheCount: Int   = 0
    @Published private(set) var tempFilesSize:     Int64 = 0
    @Published private(set) var downloadedMusicSize: Int64 = 0
    @Published private(set) var artistImageCacheSize:  Int64 = 0
    @Published private(set) var artistImageCacheCount: Int   = 0
    @Published private(set) var transcodeCacheSize: Int64 = 0
    @Published private(set) var isScanning: Bool = false

    /// Files physically present in Imported Music that no current `Song` in
    /// the library references — leftovers from a deletion that didn't clean
    /// up its file, or files dropped in via the Files app that were never
    /// indexed. Populated by `scanOrphans(knownFilenames:)`, not the regular
    /// `scan()`, since it needs the live library's filenames to compare
    /// against and `CacheManagerService` otherwise has no `LibraryManager`
    /// dependency.
    @Published private(set) var orphanedFiles: [URL] = []
    @Published private(set) var orphanedFilesSize: Int64 = 0
    @Published private(set) var isScanningOrphans: Bool = false

    // MARK: Private

    private var lastScanDate: Date?

    /// URL of the ArtworkService disk cache folder.
    /// Mirrors the path computed in `ArtworkService.init`.
    private var artworkCacheURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Artwork", isDirectory: true)
    }

    /// Documents/Imported Music directory used by `DocumentImportService`.
    private var importedMusicURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Imported Music", isDirectory: true)
    }

    /// Mirrors the path computed in `ArtistImageService.init`.
    private var artistImageCacheURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("ArtistImages", isDirectory: true)
    }

    /// Mirrors the path computed in `AudioEncoderService.init`.
    private var transcodeCacheURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("lumisound_transcode", isDirectory: true)
    }

    // MARK: - Public API

    /// Triggers a fresh scan if no scan has been run in the last 5 minutes.
    func scanOnAppear() {
        if let last = lastScanDate, Date().timeIntervalSince(last) < 300 { return }
        Task { await scan() }
    }

    /// Scans all cache locations and refreshes published size properties.
    func scan() async {
        isScanning = true
        defer { isScanning = false }

        let (artCount, artSize) = await Task.detached(priority: .background) {
            Self.directoryStats(at: FileManager.default
                .urls(for: .cachesDirectory, in: .userDomainMask).first?
                .appendingPathComponent("Artwork", isDirectory: true))
        }.value

        let (_, tmpSize) = await Task.detached(priority: .background) {
            let tmpDir = FileManager.default.temporaryDirectory
            var totalSize: Int64 = 0
            let fm = FileManager.default
            guard let contents = try? fm.contentsOfDirectory(
                at: tmpDir,
                includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
                options: .skipsHiddenFiles
            ) else { return (0, Int64(0)) }
            var count = 0
            for url in contents where url.lastPathComponent.hasPrefix("dl_") {
                let (c, s) = Self.directoryStats(at: url)
                totalSize += s
                count += c
            }
            return (count, totalSize)
        }.value

        let (_, musicSize) = await Task.detached(priority: .background) {
            let musicDir = FileManager.default
                .urls(for: .documentDirectory, in: .userDomainMask).first?
                .appendingPathComponent("Imported Music", isDirectory: true)
            return Self.directoryStats(at: musicDir)
        }.value

        let (artistImgCount, artistImgSize) = await Task.detached(priority: .background) {
            Self.directoryStats(at: FileManager.default
                .urls(for: .cachesDirectory, in: .userDomainMask).first?
                .appendingPathComponent("ArtistImages", isDirectory: true))
        }.value

        let (_, transcodeSize) = await Task.detached(priority: .background) {
            Self.directoryStats(at: FileManager.default.temporaryDirectory
                .appendingPathComponent("lumisound_transcode", isDirectory: true))
        }.value

        artworkCacheCount    = artCount
        artworkCacheSize     = artSize
        tempFilesSize        = tmpSize
        downloadedMusicSize  = musicSize
        artistImageCacheCount = artistImgCount
        artistImageCacheSize  = artistImgSize
        transcodeCacheSize    = transcodeSize
        lastScanDate         = Date()
    }

    // MARK: - Clear Operations

    /// Clears the artwork memory cache and removes all files from the disk cache directory.
    func clearArtworkCache() {
        ArtworkService.shared.clearCache()
        if let url = artworkCacheURL {
            removeContents(of: url)
        }
        artworkCacheSize  = 0
        artworkCacheCount = 0
    }

    /// Clears the artwork cache and temp download files together. Does not
    /// touch imported music — that's the user's actual library.
    func clearAll() {
        clearArtworkCache()
        clearTempFiles()
        clearArtistImageCache()
        clearTranscodeCache()
    }

    /// Clears the artist-photo memory cache and removes all files from its disk cache directory.
    func clearArtistImageCache() {
        ArtistImageService.shared.clearCache()
        if let url = artistImageCacheURL {
            removeContents(of: url)
        }
        artistImageCacheSize  = 0
        artistImageCacheCount = 0
    }

    /// Deletes leftover audio-transcode work files. Safe any time playback
    /// isn't actively mid-transcode — a fresh file is written the next time
    /// one's needed.
    func clearTranscodeCache() {
        removeContents(of: transcodeCacheURL)
        transcodeCacheSize = 0
    }

    /// Compares files physically present in Imported Music against
    /// `knownFilenames` (the current library's referenced filenames) and
    /// records any that aren't referenced by anything — leftovers from a
    /// deletion that didn't clean up its file, or files dropped in via the
    /// Files app that were never indexed into the library.
    func scanOrphans(knownFilenames: Set<String>) async {
        isScanningOrphans = true
        defer { isScanningOrphans = false }
        let musicDir = importedMusicURL
        let (files, size) = await Task.detached(priority: .background) {
            guard let musicDir else { return ([URL](), Int64(0)) }
            let fm = FileManager.default
            guard let enumerator = fm.enumerator(
                at: musicDir,
                includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { return ([URL](), Int64(0)) }
            var orphans: [URL] = []
            var totalSize: Int64 = 0
            for case let fileURL as URL in enumerator {
                guard (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
                guard !knownFilenames.contains(fileURL.lastPathComponent) else { continue }
                orphans.append(fileURL)
                totalSize += (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { Int64($0) } ?? 0
            }
            return (orphans, totalSize)
        }.value
        orphanedFiles = files
        orphanedFilesSize = size
    }

    /// Deletes every file currently recorded in `orphanedFiles`.
    func deleteOrphanedFiles() {
        let fm = FileManager.default
        for url in orphanedFiles {
            try? fm.removeItem(at: url)
        }
        orphanedFiles = []
        orphanedFilesSize = 0
    }

    /// Deletes all `dl_*` temporary directories inside `FileManager.temporaryDirectory`.
    func clearTempFiles() {
        let tmpDir = FileManager.default.temporaryDirectory
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: tmpDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else { return }
        for url in contents where url.lastPathComponent.hasPrefix("dl_") {
            try? fm.removeItem(at: url)
        }
        tempFilesSize = 0
    }

    // MARK: - Private Helpers

    /// Returns (fileCount, totalByteSize) for a directory (recursive).
    /// Returns (0, 0) if the directory does not exist.
    nonisolated static func directoryStats(at url: URL?) -> (Int, Int64) {
        guard let url else { return (0, 0) }
        let fm = FileManager.default
        var count = 0
        var totalSize: Int64 = 0

        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return (0, 0) }

        for case let fileURL as URL in enumerator {
            guard (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { Int64($0) } ?? 0
            totalSize += size
            count += 1
        }
        return (count, totalSize)
    }

    /// Removes all contents inside `url` without removing the directory itself.
    nonisolated func removeContents(of url: URL) {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else { return }
        for item in contents {
            try? fm.removeItem(at: item)
        }
    }
}

// MARK: - Formatting Helpers

extension CacheManagerService {

    /// Human-readable byte string (e.g. "12.4 MB").
    static func formattedSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: bytes)
    }
}
