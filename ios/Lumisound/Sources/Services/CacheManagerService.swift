import Foundation

// MARK: - CacheManagerService

@MainActor
final class CacheManagerService: ObservableObject {

    // MARK: Published

    @Published private(set) var artworkCacheSize:  Int64 = 0
    @Published private(set) var artworkCacheCount: Int   = 0
    @Published private(set) var tempFilesSize:     Int64 = 0
    @Published private(set) var downloadedMusicSize: Int64 = 0
    @Published private(set) var isScanning: Bool = false

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

        artworkCacheCount    = artCount
        artworkCacheSize     = artSize
        tempFilesSize        = tmpSize
        downloadedMusicSize  = musicSize
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
