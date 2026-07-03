import Foundation
import MediaPlayer
import UIKit

/// Progress snapshot for an in-flight `scanMediaLibrary` run — lets the launch
/// screen show "Scanning 340 of 1,100 songs…" instead of a generic spinner for
/// users with big libraries, where the scan can take many seconds.
struct LibraryScanProgress: Equatable {
    let current: Int
    let total: Int
}

@MainActor
final class LibraryManager: ObservableObject {
    @Published private(set) var allSongs: [Song] = []
    @Published private(set) var artists: [String] = []
    @Published private(set) var albums: [String] = []
    @Published private(set) var genres: [String] = []
    @Published private(set) var playlists: [Playlist] = []
    @Published private(set) var favoriteSongIDs: Set<String> = []
    @Published private(set) var isScanning: Bool = false
    @Published private(set) var scanProgress: LibraryScanProgress? = nil
    /// Set when `scanMediaLibrary` has bailed out after repeated incomplete
    /// attempts (see the crash-loop guard in `scanMediaLibrary`). Lets the UI
    /// explain *why* the media library never loaded instead of just spinning.
    @Published private(set) var scanCrashGuardActive: Bool = false
    @Published var errorMessage: String?
    @Published var lastScanResult: String? = nil

    private let persistence: PersistenceService
    private let artwork: ArtworkService
    private let importer = DocumentImportService()

    /// Tracks how many scans (media library, local documents, watched folders,
    /// specific-directory) are currently in flight. `isScanning` reflects
    /// whether *any* of them are running, so the launch screen and library UI
    /// stay in "scanning" state for the full duration of a multi-scan launch
    /// instead of flipping to "done" as soon as the first scan finishes.
    private var activeScanCount: Int = 0

    private func beginScan() {
        activeScanCount += 1
        isScanning = true
    }

    private func endScan() {
        activeScanCount = max(0, activeScanCount - 1)
        if activeScanCount == 0 {
            isScanning = false
        }
    }

    private var mediaSongs: [Song] = []
    private var importedSongs: [Song] = []

    /// Pending debounced rebuild task. Cancelled and replaced on each rapid mutation.
    private var pendingRebuildTask: Task<Void, Never>?

    private var foregroundObserver: NSObjectProtocol?
    private var metadataReenrichTimer: Timer?
    private var isReenrichingMetadata = false
    private var metadataRefreshTimer: Timer?
    private var isRefreshingMetadata = false
    /// Set while `forceMetadataSync` is running, so the Settings button can
    /// show a spinner and avoid overlapping runs.
    @Published private(set) var isForcingMetadataSync = false
    /// Rotating cursor into `importedSongs` for `refreshNextMetadataBatch()` —
    /// advances by `metadataRefreshBatchSize` each tick so every track gets
    /// re-read eventually without ever doing a full-library pass in one go.
    private var metadataRefreshCursor = 0

    var favoriteSongs: [Song] {
        allSongs.filter { favoriteSongIDs.contains($0.id) }
    }

    init(persistence: PersistenceService = .shared, artwork: ArtworkService = .shared) {
        self.persistence = persistence
        self.artwork = artwork
        favoriteSongIDs = persistence.loadFavorites()
        playlists = persistence.loadPlaylists()
        // Show last session's library immediately — see `loadPersistedSnapshot`.
        // The real scans below always run afterward and overwrite this with
        // fresh data; this just removes the "empty list for several seconds"
        // window for users with big libraries (1000+ songs).
        loadPersistedSnapshot()
        // Re-scan local documents whenever the app returns to the foreground so
        // that files the user added via the Files app while Lumisound was
        // backgrounded are picked up without requiring a manual refresh.
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.scanLocalDocuments() }
        }
    }

    deinit {
        if let foregroundObserver {
            NotificationCenter.default.removeObserver(foregroundObserver)
        }
        metadataReenrichTimer?.invalidate()
        metadataRefreshTimer?.invalidate()
    }

    // MARK: - Periodic Metadata Re-Enrichment

    /// Call once on app launch. Re-checks imported songs with missing
    /// artist/album/genre/year every 10 minutes and tries to fill them in via
    /// `MetadataFetchService`.
    ///
    /// Covers the case where a user deletes and reinstalls the app, then
    /// copies their music back from a backup folder: the reinstall wipes
    /// `EnrichmentCacheStore`'s `UserDefaults` cache, but more importantly the
    /// very first scan after a mass file-copy can race with the filesystem
    /// (or simply hit a transient network failure during the iTunes/MusicBrainz/
    /// Deezer lookups in `DocumentImportService.makeSong`), leaving tracks
    /// permanently stuck with blank metadata since nothing ever re-checks them
    /// afterward. This sweep gives those tracks repeated chances to fill in.
    func startPeriodicMetadataReenrichment() {
        guard metadataReenrichTimer == nil else { return }

        Task { await reenrichSongsMissingMetadata() }

        let interval: TimeInterval = 10 * 60
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                // Skip the network-bound online metadata lookups while backgrounded —
                // pointless radio/CPU use when the user isn't viewing the library.
                guard UIApplication.shared.applicationState == .active else { return }
                await self?.reenrichSongsMissingMetadata()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        metadataReenrichTimer = timer
    }

    /// Finds locally-imported songs missing artist, album, genre, or year and
    /// tries to fill them in via the online metadata lookup chain. Updates
    /// `importedSongs`, the on-disk scan cache, and the enrichment cache so
    /// successful lookups persist across future scans/restarts.
    func reenrichSongsMissingMetadata() async {
        guard !isReenrichingMetadata else { return }
        let candidates = importedSongs.enumerated().filter { _, song in
            song.artist.isEmpty || song.album.isEmpty || song.genre.isEmpty || song.year.isEmpty
        }
        guard !candidates.isEmpty else { return }

        isReenrichingMetadata = true
        defer { isReenrichingMetadata = false }

        appLog("Periodic metadata re-enrichment: checking \(candidates.count) song(s)", category: "library")

        var updatedCount = 0
        for (index, song) in candidates {
            guard index < importedSongs.count, importedSongs[index].id == song.id else { continue }

            let enriched = await MetadataFetchService.shared.enrich(song: song)
            guard enriched.artist != song.artist || enriched.album != song.album
                || enriched.genre != song.genre || enriched.year != song.year
            else { continue }

            importedSongs[index] = enriched
            updatedCount += 1

            if let url = enriched.url, let stamp = ScanCacheService.fileStamp(for: url) {
                ScanCacheService.shared.store(song: enriched, for: url, stamp: stamp)
            }
            if let filename = enriched.url?.lastPathComponent {
                var entry: [String: String] = [:]
                if !enriched.artist.isEmpty { entry["artist"] = enriched.artist }
                if !enriched.album.isEmpty  { entry["album"]  = enriched.album  }
                if !enriched.genre.isEmpty  { entry["genre"]  = enriched.genre  }
                if !enriched.year.isEmpty   { entry["year"]   = enriched.year   }
                await EnrichmentCacheStore.shared.store(filename, entry: entry)
            }
        }

        guard updatedCount > 0 else { return }

        appLog("Periodic metadata re-enrichment: updated \(updatedCount) song(s)", category: "library")
        ScanCacheService.shared.persist()
        await EnrichmentCacheStore.shared.persist()
        rebuildAllSongs()
    }

    // MARK: - Force Metadata Sync

    /// Immediately rescans the whole local library (the Documents tree,
    /// including "Imported Music" and any subfolders, plus any watched
    /// folders) and then re-reads embedded tags and re-runs online
    /// enrichment for *every* imported track — not just a rotating batch or
    /// tracks with missing fields. For use from a "Force Metadata Sync"
    /// button in Settings; the periodic timers cover the lazy/background case.
    func forceMetadataSync(using folderService: MusicFolderService) async {
        guard !isForcingMetadataSync else { return }
        isForcingMetadataSync = true
        defer { isForcingMetadataSync = false }

        appLog("Force metadata sync: rescanning Documents + watched folders", category: "library")
        await scanLocalDocumentsAsync()
        await scanWatchedFoldersAsync(using: folderService)

        var updatedCount = 0
        var artworkFilledCount = 0
        let total = importedSongs.count

        for index in importedSongs.indices {
            let song = importedSongs[index]
            guard let url = song.url, FileManager.default.fileExists(atPath: url.path) else { continue }

            var current = song
            if let refreshed = await importer.refreshTags(for: url, current: current) {
                current = refreshed
            }
            if current.artist.isEmpty || current.album.isEmpty || current.genre.isEmpty || current.year.isEmpty {
                current = await MetadataFetchService.shared.enrich(song: current)
            }

            // refreshTags/enrich never touch artwork — fill in any tracks that
            // are still missing cached artwork (e.g. imported before
            // embedded-artwork extraction existed, or whose video frame
            // extraction previously failed transiently).
            if !ArtworkService.shared.hasCachedArtwork(for: current) {
                if await ArtworkService.shared.loadArtwork(for: current) != nil {
                    artworkFilledCount += 1
                }
            }

            guard index < importedSongs.count, importedSongs[index].id == song.id else { continue }
            if current != song {
                importedSongs[index] = current
                updatedCount += 1
            }

            if let stamp = ScanCacheService.fileStamp(for: url) {
                ScanCacheService.shared.store(song: current, for: url, stamp: stamp)
            }
            if let filename = current.url?.lastPathComponent {
                var entry: [String: String] = [:]
                if !current.artist.isEmpty { entry["artist"] = current.artist }
                if !current.album.isEmpty  { entry["album"]  = current.album  }
                if !current.genre.isEmpty  { entry["genre"]  = current.genre  }
                if !current.year.isEmpty   { entry["year"]   = current.year   }
                await EnrichmentCacheStore.shared.store(filename, entry: entry)
            }
        }

        ScanCacheService.shared.persist()
        await EnrichmentCacheStore.shared.persist()
        rebuildAllSongs()

        appLog("Force metadata sync: updated \(updatedCount) of \(total) song(s), filled artwork for \(artworkFilledCount)", category: "library")
        lastScanResult = "Force metadata sync: updated \(updatedCount) of \(total) song(s), artwork filled for \(artworkFilledCount)"
    }

    // MARK: - Tempo (BPM)

    /// Returns `song.bpm` if already known, otherwise analyzes the track via
    /// `BPMAnalyzerService` (on-device, ffmpeg-equivalent autocorrelation) and
    /// caches the result on the song for future lookups — used by the player
    /// to drive beat-aware crossfades and by any other tempo-aware feature.
    /// Returns `nil` if the song has no local URL or no tempo could be estimated.
    func bpm(for song: Song) async -> Double? {
        if let bpm = song.bpm { return bpm }
        guard let url = song.url else { return nil }

        guard let estimated = await BPMAnalyzerService.shared.bpm(for: url) else { return nil }
        storeBPM(estimated, for: song.id)
        return estimated
    }

    /// Writes a freshly-analyzed BPM back into `mediaSongs`/`importedSongs` so
    /// it's returned instantly next time and survives in the persisted
    /// library snapshot.
    private func storeBPM(_ bpm: Double, for songID: String) {
        if let index = mediaSongs.firstIndex(where: { $0.id == songID }) {
            mediaSongs[index].bpm = bpm
        } else if let index = importedSongs.firstIndex(where: { $0.id == songID }) {
            importedSongs[index].bpm = bpm
        } else {
            return
        }
        rebuildAllSongs()
    }

    // MARK: - Periodic Local Metadata Refresh

    /// Number of tracks re-read from disk per 3-minute tick. Small enough that
    /// a multi-thousand-track library only takes a few minutes per pass, but
    /// keeps each tick's work (a handful of `AVAsset` metadata loads) trivial.
    private static let metadataRefreshBatchSize = 5

    /// Call once on app launch. Every 3 minutes, re-reads the embedded tags of
    /// a small rotating batch of imported tracks directly from disk and updates
    /// the library if anything changed (e.g. the bridge re-tagged a file after
    /// a metadata re-check, or the user edited tags externally).
    ///
    /// Deliberately separate from `startPeriodicMetadataReenrichment`: that
    /// sweep only targets tracks with *missing* fields and hits online lookup
    /// services every 10 minutes. This sweep covers *all* imported tracks but
    /// only re-reads local file tags — no network calls, no artwork extraction —
    /// so it stays cheap even on a full pass.
    func startPeriodicMetadataRefresh() {
        guard metadataRefreshTimer == nil else { return }

        let interval: TimeInterval = 3 * 60
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                // Skip while backgrounded — re-reading file tags is wasted work
                // when the user can't see the library (e.g. background audio
                // playback keeps the process alive). Resumes on next foreground tick.
                guard UIApplication.shared.applicationState == .active else { return }
                await self?.refreshNextMetadataBatch()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        metadataRefreshTimer = timer
    }

    /// Re-reads embedded tags for the next rotating batch of imported tracks
    /// (starting at `metadataRefreshCursor`, wrapping around the array) and
    /// updates any that changed on disk since they were last scanned.
    func refreshNextMetadataBatch() async {
        guard !isRefreshingMetadata, !importedSongs.isEmpty else { return }

        isRefreshingMetadata = true
        defer { isRefreshingMetadata = false }

        let count = min(Self.metadataRefreshBatchSize, importedSongs.count)
        var updatedCount = 0

        for offset in 0..<count {
            let index = (metadataRefreshCursor + offset) % importedSongs.count
            let song = importedSongs[index]
            guard let url = song.url, FileManager.default.fileExists(atPath: url.path) else { continue }

            guard let refreshed = await importer.refreshTags(for: url, current: song) else { continue }
            guard index < importedSongs.count, importedSongs[index].id == song.id else { continue }

            importedSongs[index] = refreshed
            updatedCount += 1

            if let stamp = ScanCacheService.fileStamp(for: url) {
                ScanCacheService.shared.store(song: refreshed, for: url, stamp: stamp)
            }
        }

        metadataRefreshCursor = (metadataRefreshCursor + count) % importedSongs.count

        guard updatedCount > 0 else { return }

        appLog("Periodic metadata refresh: updated \(updatedCount) song(s)", category: "library")
        ScanCacheService.shared.persist()
        rebuildAllSongs()
    }

    // MARK: - Library Snapshot (instant-on-launch cache)

    private struct LibrarySnapshot: Codable {
        let songs: [Song]
        let artists: [String]
        let albums: [String]
        let genres: [String]
    }

    private static let snapshotURL: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return caches.appendingPathComponent("library_snapshot_v1.json")
    }()

    /// Reads the last-persisted library state synchronously so `allSongs` (and
    /// the derived facet lists) are populated the instant `LibraryManager` is
    /// constructed — before any scan has run. For a 1,100-song library the
    /// real scan can take many seconds; without this, the launch/library
    /// screens sit empty that whole time even though the user had a perfectly
    /// good library a moment ago. `scanMediaLibrary`/`scanLocalDocuments`/etc.
    /// always run after `init` and silently replace these values with fresh
    /// results once they complete (see `persistSnapshotIfSettled`).
    private func loadPersistedSnapshot() {
        guard let data = try? Data(contentsOf: Self.snapshotURL),
              let snapshot = try? JSONDecoder().decode(LibrarySnapshot.self, from: data),
              !snapshot.songs.isEmpty
        else { return }
        allSongs = snapshot.songs
        artists = snapshot.artists
        albums = snapshot.albums
        genres = snapshot.genres
        appLog("Loaded cached library snapshot: \(snapshot.songs.count) song(s)", category: "library")
    }

    /// Writes the current library state to disk so the next launch can show it
    /// instantly via `loadPersistedSnapshot`. Only called once a scan has
    /// fully settled (`!isScanning`) so we never persist a half-populated
    /// mid-scan state as if it were the real library. Encoding/writing
    /// thousands of `Song` structs is real work — offloaded to a background
    /// task exactly like `ScanCacheService.persist()`.
    private func persistSnapshotIfSettled() {
        guard !isScanning else { return }
        let snapshot = LibrarySnapshot(songs: allSongs, artists: artists, albums: albums, genres: genres)
        let destination = Self.snapshotURL
        Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: destination, options: .atomic)
        }
    }

    // MARK: - Scan Cache Helper

    /// Resolves a list of file URLs to Songs, using `ScanCacheService` for unchanged files
    /// and `DocumentImportService.makeSong` only for new or modified ones.
    private func resolveSongs(for urls: [URL]) async -> [Song] {
        // Stat every candidate file off the main actor first. `stat()` is a blocking
        // syscall — running it serially on the main thread for thousands of files
        // (as a naive cache check would) is the dominant cause of UI hitches/hangs
        // when scanning or importing a large library.
        let stamps: [(url: URL, stamp: ScanCacheService.FileStamp)] = await Task.detached(priority: .userInitiated) {
            urls.compactMap { url in
                ScanCacheService.fileStamp(for: url).map { (url, $0) }
            }
        }.value

        var cachedSongs: [Song] = []
        var uncached: [(url: URL, stamp: ScanCacheService.FileStamp)] = []

        // Pure in-memory dictionary lookups — cheap enough to stay on the main actor.
        for entry in stamps {
            if let cached = ScanCacheService.shared.cachedSong(for: entry.url, stamp: entry.stamp) {
                cachedSongs.append(cached)
            } else {
                uncached.append(entry)
            }
        }

        guard !uncached.isEmpty else { return cachedSongs }

        let stampByURL = Dictionary(
            uncached.map { ($0.url.standardizedFileURL, $0.stamp) },
            uniquingKeysWith: { first, _ in first }
        )

        // Process uncached files in checkpointed batches, storing+persisting the
        // scan cache after each one completes. Previously the cache was only
        // written once at the very end — so a scan interrupted by a crash, force
        // quit, or the OS killing a backgrounded app lost ALL of its metadata
        // extraction work and started completely from zero next launch (the
        // dominant cause of "it rescans my whole library again" reports for big
        // libraries). Now an interrupted scan resumes from the last completed
        // batch — at most ~100 files of repeated work instead of thousands.
        // Concurrency within each batch is unchanged (maxConcurrent = 8).
        let checkpointSize = 100
        var newSongs: [Song] = []
        newSongs.reserveCapacity(uncached.count)
        var batchStart = 0
        while batchStart < uncached.count {
            let batchEnd = min(batchStart + checkpointSize, uncached.count)
            let batchURLs = uncached[batchStart..<batchEnd].map(\.url)

            let batchSongs: [Song] = await Task.detached(priority: .userInitiated) {
                await withTaskGroup(of: Song?.self) { group in
                    var results: [Song] = []
                    var pending = 0
                    let maxConcurrent = 8
                    var iterator = batchURLs.makeIterator()

                    while pending < maxConcurrent, let url = iterator.next() {
                        let s = DocumentImportService()
                        group.addTask { await s.makeSong(for: url) }
                        pending += 1
                    }

                    for await song in group {
                        if let song { results.append(song) }
                        pending -= 1
                        if let url = iterator.next() {
                            let s = DocumentImportService()
                            group.addTask { await s.makeSong(for: url) }
                            pending += 1
                        }
                    }
                    return results
                }
            }.value

            for song in batchSongs {
                if let url = song.url, let stamp = stampByURL[url.standardizedFileURL] {
                    ScanCacheService.shared.store(song: song, for: url, stamp: stamp)
                }
            }
            ScanCacheService.shared.persist()

            newSongs.append(contentsOf: batchSongs)
            batchStart = batchEnd
        }

        await EnrichmentCacheStore.shared.persist()

        return cachedSongs + newSongs
    }

    // MARK: - Local Documents Scan

    /// Scans the app's Documents directory (root + Imported Music subfolder) for audio
    /// files and adds any that aren't already tracked. Called automatically on init and
    /// can be triggered manually after the user drops files via the Files app.
    /// Recursively scans the app's entire Documents directory for audio files and
    /// adds any not already tracked. Picks up files placed via Finder, Files app,
    /// iTunes file sharing, or any subdirectory the user created inside the app folder.
    func scanLocalDocuments() {
        beginScan()
        Task {
            defer { endScan() }
            await performLocalDocumentsScan()
        }
    }

    /// Thorough re-scan used by the Library "Refresh" button: re-reads files
    /// whose on-disk `(mtime, size)` changed since they were imported (e.g.
    /// tags edited in place via the Files app or a desktop tool), not just
    /// brand-new files — the periodic/automatic scan keeps its faster
    /// new-files-only path. Also re-scans watched folders and (if authorized)
    /// Apple Music, and publishes a `lastScanResult` summary the UI can toast.
    func refreshAll(folderService: MusicFolderService) async {
        beginScan()
        defer { endScan() }
        let before = importedSongs.count
        await performLocalDocumentsScan(force: true)
        await scanWatchedFoldersAsync(using: folderService)
        if MPMediaLibrary.authorizationStatus() == .authorized {
            scanMediaLibrary()
        }
        let after = allSongs.count
        let delta = after - before
        lastScanResult = delta > 0
            ? "Refreshed — \(after) songs (\(delta) new/updated)"
            : "Refreshed — \(after) songs, library is up to date"
    }

    /// Awaitable variant of `scanLocalDocuments()` — used by callers (e.g.
    /// "Download All") that need `allSongs` to reflect every locally-imported
    /// file, including any sitting in subfolders the user created or moved
    /// files into, *before* deciding what still needs to be downloaded.
    func scanLocalDocumentsAsync() async {
        beginScan()
        defer { endScan() }
        await performLocalDocumentsScan()
    }

    private func performLocalDocumentsScan(force: Bool = false) async {
        appLog("Scanning local documents directory (force: \(force))", category: "library")
        guard FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first != nil else { return }

        // Walk the full Documents tree OFF the main actor — LibraryManager is
        // @MainActor, so doing this enumeration inline blocked the UI every time
        // a screen scanned on appear (Subscriptions / tracked playlists / the
        // Cloud Services download flows), which is a big source of the "lag spike
        // when loading" reports on large libraries. Covers root, Imported Music/,
        // and any nested folders the user created.
        let candidates: [URL] = await Task.detached(priority: .utility) {
            let fm = FileManager.default
            guard let docsDir = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return [] }
            var result: [URL] = []
            let enumerator = fm.enumerator(
                at: docsDir,
                includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )
            while let url = enumerator?.nextObject() as? URL {
                guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
                if DocumentImportService.supportedExtensions.contains(url.pathExtension.lowercased()) {
                    result.append(url)
                }
            }
            return result
        }.value

        guard !candidates.isEmpty else { return }

        // Evict songs whose backing files no longer exist (e.g. moved by the user
        // via Files app into an organised subfolder). Without this, the old path
        // stays in existingURLs and the new path is never picked up as "new".
        let fm2 = FileManager.default
        importedSongs = importedSongs.filter { song in
            guard let url = song.url else { return false }
            return fm2.fileExists(atPath: url.path)
        }

        if force {
            // Refresh-button path: re-resolve EVERY candidate. `resolveSongs`
            // returns cached songs unchanged (cheap stat + dict hit) for files
            // whose (mtime, size) still matches, and re-extracts metadata only
            // for files that actually changed on disk — so in-place tag edits
            // are finally picked up, which the new-files-only path below misses.
            let resolved = await resolveSongs(for: candidates)
            importedSongs = Array(
                Dictionary(grouping: resolved, by: { song in song.url.map { $0.standardizedFileURL.absoluteString } ?? song.id })
                    .compactMap { $0.value.first }
            )
            appLog("Local scan (force) complete: \(importedSongs.count) song(s)", category: "library")
            rebuildAllSongs()
            return
        }

        // Only process files we haven't seen before.
        let existingURLs = Set(importedSongs.compactMap { $0.url?.standardizedFileURL })
        let newURLs = candidates.filter { !existingURLs.contains($0.standardizedFileURL) }
        guard !newURLs.isEmpty else { return }

        let newSongs = await resolveSongs(for: newURLs)

        appLog("Local scan complete: \(newSongs.count) song(s)", category: "library")
        importedSongs.append(contentsOf: newSongs)
        importedSongs = Array(Dictionary(grouping: importedSongs, by: { song in song.url.map { $0.standardizedFileURL.absoluteString } ?? song.id }).compactMap { $0.value.first })
        rebuildAllSongs()
    }

    /// Scans all user-selected folders tracked by `MusicFolderService` and adds
    /// any new audio files not already in the library.
    func scanWatchedFolders(using folderService: MusicFolderService) {
        Task { await scanWatchedFoldersAsync(using: folderService) }
    }

    /// Awaitable variant of `scanWatchedFolders(using:)` — used by callers
    /// (e.g. the duplicate finder) that need `allSongs` to reflect every
    /// watched-folder file before deciding what to do next.
    func scanWatchedFoldersAsync(using folderService: MusicFolderService) async {
        appLog("scanWatchedFolders: starting", category: "library")
        beginScan()
        defer { endScan() }
        let urls = folderService.resolveAll()
        guard !urls.isEmpty else {
            appLog("scanWatchedFolders: no accessible watched folders", category: "library")
            return
        }
        // Keep security-scoped access open until after makeSong reads the files.
        defer { for url in urls { url.stopAccessingSecurityScopedResource() } }

        var candidates: [URL] = []
        let fm = FileManager.default

        for baseURL in urls {
            let enumerator = fm.enumerator(
                at: baseURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )
            while let url = enumerator?.nextObject() as? URL {
                guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
                if DocumentImportService.supportedExtensions.contains(url.pathExtension.lowercased()) {
                    candidates.append(url)
                }
            }
        }

        guard !candidates.isEmpty else { return }

        let existingURLs = Set(importedSongs.compactMap { $0.url?.standardizedFileURL })
        let newURLs = candidates.filter { !existingURLs.contains($0.standardizedFileURL) }
        guard !newURLs.isEmpty else { return }

        let newSongs = await resolveSongs(for: newURLs)

        appLog("scanWatchedFolders: \(newSongs.count) song(s) from \(urls.count) folder(s)", category: "library")
        importedSongs.append(contentsOf: newSongs)
        importedSongs = Array(Dictionary(grouping: importedSongs, by: { song in song.url.map { $0.standardizedFileURL.absoluteString } ?? song.id }).compactMap { $0.value.first })
        rebuildAllSongs()

        // Push the updated folder structure (new tracks in watched folders)
        // to the server so it survives a reinstall — debounced, all
        // logged-in users, no opt-in toggle.
        if !newSongs.isEmpty {
            AccountService.shared?.scheduleFolderBackupPush(folderService: folderService, library: self)
        }
    }

    /// Scans a specific directory URL for audio files and adds any not already in the library.
    /// Designed for use with preset locations (Documents) that don't require a
    /// security-scoped bookmark — just a direct filesystem path the app can enumerate.
    func scanSpecificDirectory(_ url: URL) {
        appLog("scanSpecificDirectory: \(url.lastPathComponent)", category: "library")
        beginScan()
        lastScanResult = nil
        Task {
            defer { endScan() }

            let fm = FileManager.default
            var candidates: [URL] = []
            let enumerator = fm.enumerator(
                at: url,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )
            while let fileURL = enumerator?.nextObject() as? URL {
                guard (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
                else { continue }
                if DocumentImportService.supportedExtensions.contains(fileURL.pathExtension.lowercased()) {
                    candidates.append(fileURL)
                }
            }

            // No audio files at all — return silently (not an error).
            guard !candidates.isEmpty else { return }

            let existingURLs = Set(importedSongs.compactMap { $0.url?.standardizedFileURL })
            let newURLs = candidates.filter { !existingURLs.contains($0.standardizedFileURL) }

            // All files already in library — return silently.
            guard !newURLs.isEmpty else { return }

            let newSongs = await resolveSongs(for: newURLs)

            appLog("scanSpecificDirectory: \(newSongs.count) song(s) from \(url.lastPathComponent)", category: "library")
            importedSongs.append(contentsOf: newSongs)
            importedSongs = Array(Dictionary(grouping: importedSongs, by: { song in song.url.map { $0.standardizedFileURL.absoluteString } ?? song.id }).compactMap { $0.value.first })
            rebuildAllSongs()
            lastScanResult = "Found \(newSongs.count) song\(newSongs.count == 1 ? "" : "s") in \(url.lastPathComponent)"
        }
    }

    /// Convenience: re-scans every local source — the Documents folder, all
    /// user-selected watched folders, and (if previously granted) the Apple
    /// Music library — so the "Refresh" button picks up files added or
    /// changed outside the app since the last scan, not just on next launch.
    func scanAll(folderService: MusicFolderService) {
        scanLocalDocuments()
        scanWatchedFolders(using: folderService)
        // Only re-scan Apple Music if access was already granted — calling
        // `scanMediaLibrary()` without that check would trigger a permission
        // prompt for users who've never used the Apple Music Transfer feature.
        if MPMediaLibrary.authorizationStatus() == .authorized {
            scanMediaLibrary()
        }
    }

    func requestAccessAndScan() {
        appLog("requestAccessAndScan: requesting media library authorization", category: "library")
        Task {
            let existing = MPMediaLibrary.authorizationStatus()
            // Already denied/restricted — system won't re-prompt; send user to Settings.
            if existing == .denied || existing == .restricted {
                appWarn("requestAccessAndScan: access denied/restricted — opening Settings", category: "library")
                await UIApplication.shared.open(
                    URL(string: UIApplication.openSettingsURLString)!,
                    options: [:],
                    completionHandler: nil
                )
                errorMessage = "Open Settings → Privacy → Media & Apple Music to allow access."
                return
            }
            let status = await MPMediaLibrary.requestAuthorization()
            if status == .authorized {
                appLog("requestAccessAndScan: authorized, scanning", category: "library")
                errorMessage = nil
                scanMediaLibrary()
            } else if status == .denied || status == .restricted {
                appWarn("requestAccessAndScan: denied — opening Settings", category: "library")
                await UIApplication.shared.open(
                    URL(string: UIApplication.openSettingsURLString)!,
                    options: [:],
                    completionHandler: nil
                )
                errorMessage = "Open Settings → Privacy → Media & Apple Music to allow access."
            } else {
                appWarn("requestAccessAndScan: declined (status=\(status.rawValue))", category: "library")
                errorMessage = "Media library access was declined. Imported files still work."
            }
        }
    }

    /// Persists how many `scanMediaLibrary` runs in a row never reached completion.
    /// Survives process termination (unlike an in-memory flag), which is exactly
    /// what's needed to detect a crash loop: the counter is bumped *before* the
    /// scan starts and only cleared on success, so an app that crashes mid-scan
    /// comes back up, sees a non-zero count, and knows the previous attempt died.
    private static let scanAttemptCounterKey = "media_scan_incomplete_attempts"

    func scanMediaLibrary() {
        guard MPMediaLibrary.authorizationStatus() == .authorized else {
            requestAccessAndScan()
            return
        }

        // Crash-loop guard — `MPMediaQuery.songs().items` has been observed to
        // crash mid-read on some very large Apple Music libraries. Without this,
        // a crash here restarts the app straight back into the same scan: an
        // unrecoverable boot loop the user can only escape by deleting the app.
        // After 2 incomplete attempts in a row we stop trying automatically and
        // let the user fall back to imported/local files (still fully usable),
        // or switch scan sources from Settings.
        let defaults = UserDefaults.standard
        let priorAttempts = defaults.integer(forKey: Self.scanAttemptCounterKey)
        if priorAttempts >= 2 {
            appWarn("scanMediaLibrary: \(priorAttempts) consecutive incomplete attempts — refusing to retry automatically", category: "library")
            scanCrashGuardActive = true
            errorMessage = "The media library scan has been crashing repeatedly. Imported/local files still work — switch \"Default Scan Source\" to App Storage in Settings, or tap Retry to try again."
            return
        }
        defaults.set(priorAttempts + 1, forKey: Self.scanAttemptCounterKey)

        appLog("scanMediaLibrary: starting (attempt \(priorAttempts + 1))", category: "library")
        appBreadcrumb("Started media library scan (attempt \(priorAttempts + 1))")
        beginScan()
        errorMessage = nil
        scanCrashGuardActive = false
        scanProgress = nil

        Task {
            defer { endScan() }
            // The query itself is the slow, blocking part — keep it off the main actor.
            let items: [MPMediaItem] = await Task.detached(priority: .userInitiated) {
                MPMediaQuery.songs().items ?? []
            }.value
            appLog("scanMediaLibrary: found \(items.count) item(s), converting", category: "library")

            // Convert in small chunks with a yield in between. `Song.init(mediaItem:)`
            // is cheap per item (just reads cached MPMediaItem properties), but doing
            // all 1,000+ at once back-to-back is enough synchronous main-actor work to
            // visibly stall scrolling/animation — the "freakout" users see on big
            // libraries. Yielding between chunks lets the UI (and artwork prefetch)
            // get scheduling slices throughout, and doubles as the source for the
            // live "Scanning N of M" progress shown on the launch screen.
            var scanned: [Song] = []
            scanned.reserveCapacity(items.count)
            let chunkSize = 200
            var index = 0
            while index < items.count {
                guard !Task.isCancelled else { return }
                let end = min(index + chunkSize, items.count)
                scanned.append(contentsOf: items[index..<end].compactMap(Song.init(mediaItem:)))
                index = end
                scanProgress = LibraryScanProgress(current: index, total: items.count)
                await Task.yield()
            }

            appLog("scanMediaLibrary: found \(scanned.count) song(s)", category: "library")
            self.mediaSongs = scanned
            self.rebuildAllSongs()
            self.scanProgress = nil
            // Completed cleanly — reset the crash-loop counter so future launches
            // get the normal 2-attempt grace again rather than accumulating forever.
            defaults.set(0, forKey: Self.scanAttemptCounterKey)
            appBreadcrumb("Media library scan completed: \(scanned.count) song(s)")

            // `Song.init(mediaItem:)` returns nil for items with no `assetURL` —
            // i.e. Apple Music catalog tracks that are in the library but not
            // downloaded to this device (cloud-only). Without this message the
            // "Apple Music Transfer" felt completely broken for anyone whose
            // library is mostly cloud-streamed: the scan would "complete" having
            // imported nothing, with no indication why.
            let skipped = items.count - scanned.count
            if skipped > 0 {
                let songWord = skipped == 1 ? "song" : "songs"
                if scanned.isEmpty {
                    self.errorMessage = "Found \(skipped) \(songWord) in your Apple Music library, but none are downloaded to this device. Open the Music app, download the songs you want (tap ⋯ → Download), then scan again."
                } else {
                    self.errorMessage = "Imported \(scanned.count) song(s). \(skipped) \(songWord) in your Apple Music library aren't downloaded to this device and were skipped — download them in the Music app, then scan again to add them."
                }
            }
        }
    }

    /// User-initiated escape hatch from the crash-loop guard above. The guard's
    /// banner tells the user to "tap Retry" — this is that action. Deliberately
    /// NOT wired into any automatic path (onAppear, app launch, etc.): resetting
    /// the counter there would silently recreate the exact boot loop the guard
    /// exists to break. Only reachable by an explicit tap, so a genuinely broken
    /// library can't trap the user in endless automatic retries, while a
    /// transient run of bad luck is just one button away from a fresh attempt.
    func retryMediaLibraryScanAfterCrashGuard() {
        guard scanCrashGuardActive else { return }
        appLog("retryMediaLibraryScanAfterCrashGuard: user-initiated retry — resetting attempt counter", category: "library")
        appBreadcrumb("User retried media library scan after crash-loop guard")
        UserDefaults.standard.set(0, forKey: Self.scanAttemptCounterKey)
        scanCrashGuardActive = false
        errorMessage = nil
        scanMediaLibrary()
    }

    func importFiles(urls: [URL]) {
        guard !urls.isEmpty else { return }
        appLog("Importing \(urls.count) file(s)", category: "library")
        beginScan()
        errorMessage = nil

        Task {
            defer { endScan() }
            do {
                let imported = try await importer.importFiles(from: urls)
                appLog("Import complete: \(imported.count) file(s) added", category: "library")
                importedSongs.append(contentsOf: imported)
                importedSongs = Array(
                    Dictionary(grouping: importedSongs, by: { song in song.url.map { $0.standardizedFileURL.absoluteString } ?? song.id })
                        .compactMap { $0.value.first }
                )
                let songWord = imported.count == 1 ? "song" : "songs"
                ToastCenter.shared.show("Imported \(imported.count) \(songWord)", category: .success, icon: "tray.and.arrow.down.fill")
            } catch {
                appError("Import failed: \(error.localizedDescription)", category: "library")
                errorMessage = error.localizedDescription
                ToastCenter.shared.show("Import failed: \(error.localizedDescription)", category: .error)
            }
            rebuildAllSongs()
        }
    }

    func isFavorite(songID: String) -> Bool {
        favoriteSongIDs.contains(songID)
    }

    func toggleFavorite(songID: String) {
        if favoriteSongIDs.contains(songID) {
            favoriteSongIDs.remove(songID)
            ToastCenter.shared.show("Removed from Favorites", category: .info, icon: "heart")
        } else {
            favoriteSongIDs.insert(songID)
            ToastCenter.shared.show("Added to Favorites", category: .success, icon: "heart.fill")
        }
        persistence.saveFavorites(favoriteSongIDs)
    }

    func songs(for playlist: Playlist) -> [Song] {
        let lookup = Dictionary(uniqueKeysWithValues: allSongs.map { ($0.id, $0) })
        return playlist.songIDs.compactMap { lookup[$0] }
    }

    func songs(byArtist artist: String) -> [Song] {
        allSongs.filter { $0.artistName == artist }
    }

    func songs(inAlbum album: String) -> [Song] {
        allSongs.filter { $0.albumName == album }
    }

    func songs(inGenre genre: String) -> [Song] {
        allSongs.filter { $0.genre == genre }
    }

    func createPlaylist(name: String) {
        let playlist = Playlist(id: UUID(), name: name, songIDs: [], createdAt: Date())
        playlists.append(playlist)
        persistence.savePlaylists(playlists)
        ToastCenter.shared.show("Created playlist \"\(name)\"", category: .success, icon: "music.note.list")
    }

    func deletePlaylist(_ playlist: Playlist) {
        playlists.removeAll { $0.id == playlist.id }
        persistence.savePlaylists(playlists)
        ToastCenter.shared.show("Deleted playlist \"\(playlist.name)\"", category: .info, icon: "trash")
    }

    func renamePlaylist(_ playlist: Playlist, to newName: String) {
        guard let index = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        playlists[index].name = newName
        persistence.savePlaylists(playlists)
    }

    func setFolder(_ folder: String?, forPlaylistID playlistID: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        let trimmed = folder?.trimmingCharacters(in: .whitespacesAndNewlines)
        playlists[index].folder = (trimmed?.isEmpty ?? true) ? nil : trimmed
        persistence.savePlaylists(playlists)
    }

    func setTags(_ tags: [String], forPlaylistID playlistID: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlists[index].tags = tags
        persistence.savePlaylists(playlists)
    }

    /// All folder names currently in use, sorted, for grouping the playlists list.
    var playlistFolders: [String] {
        Array(Set(playlists.compactMap(\.folder))).sorted()
    }

    func addSong(id songID: String, toPlaylistID playlistID: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        guard !playlists[index].songIDs.contains(songID) else {
            ToastCenter.shared.show("Already in \"\(playlists[index].name)\"", category: .info, icon: "music.note.list")
            return
        }
        playlists[index].songIDs.append(songID)
        persistence.savePlaylists(playlists)
        ToastCenter.shared.show("Added to \"\(playlists[index].name)\"", category: .success, icon: "text.badge.plus")
    }

    /// Adds multiple songs to a playlist in a single persistence write/toast —
    /// used by Library's multi-select "Add to Playlist" bulk action instead of
    /// looping `addSong(id:toPlaylistID:)` (which would save+toast per item).
    /// Songs already in the playlist are skipped.
    func addSongs(ids songIDs: Set<String>, toPlaylistID playlistID: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        let toAdd = songIDs.subtracting(playlists[index].songIDs)
        guard !toAdd.isEmpty else {
            ToastCenter.shared.show("Already in \"\(playlists[index].name)\"", category: .info, icon: "music.note.list")
            return
        }
        playlists[index].songIDs.append(contentsOf: toAdd)
        persistence.savePlaylists(playlists)
        ToastCenter.shared.show(
            "Added \(toAdd.count) song\(toAdd.count == 1 ? "" : "s") to \"\(playlists[index].name)\"",
            category: .success, icon: "text.badge.plus"
        )
    }

    func removeSong(id songID: String, fromPlaylistID playlistID: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlists[index].songIDs.removeAll { $0 == songID }
        persistence.savePlaylists(playlists)
        ToastCenter.shared.show("Removed from \"\(playlists[index].name)\"", category: .info, icon: "text.badge.minus")
    }

    func reorderSongs(in playlistID: UUID, to newIDs: [Song.ID]) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlists[index].songIDs = newIDs
        persistence.savePlaylists(playlists)
    }

    /// True if `allSongs` already contains a song matching `title`/`artist`
    /// (normalized — case/diacritic/punctuation-insensitive, same rules as
    /// `DuplicateFinderService`), and within `DuplicateFinderService
    /// .durationTolerance` of `duration` when one is provided. Used by
    /// "Download All" to skip tracks that already exist locally under any
    /// filename or source — including manually-imported files or ones that
    /// predate the `LUMISOUND_ID`/`sourceTrackID` tagging — so re-downloads
    /// aren't queued just because the track lacks a matching source ID.
    func isAlreadyImported(title: String, artist: String, duration: TimeInterval? = nil) -> Bool {
        let key = DuplicateFinderService.normalize(title) + "|" + DuplicateFinderService.normalize(artist)
        guard key != "|" else { return false }
        return allSongs.contains { song in
            let songKey = DuplicateFinderService.normalize(song.title) + "|" + DuplicateFinderService.normalize(song.artist)
            guard songKey == key else { return false }
            guard let duration, duration > 0 else { return true }
            return abs(song.duration - duration) <= DuplicateFinderService.durationTolerance
        }
    }

    /// A precomputed index of the library's imported tracks for O(1) duplicate
    /// checks. `isAlreadyImported` is O(library) per call (it re-normalizes every
    /// song), so calling it in a loop over a big playlist (up to 1000 results)
    /// was an O(results × library) string-crunch on the main thread — long enough
    /// to trip the iOS watchdog (which presents as a crash). Build this index
    /// ONCE, then query it per candidate in O(1).
    struct ImportedIdentityIndex {
        fileprivate let byKey: [String: [TimeInterval]]
        func contains(title: String, artist: String, duration: TimeInterval?) -> Bool {
            let key = DuplicateFinderService.normalize(title) + "|" + DuplicateFinderService.normalize(artist)
            guard key != "|", let durations = byKey[key] else { return false }
            guard let duration, duration > 0 else { return true }
            return durations.contains { abs($0 - duration) <= DuplicateFinderService.durationTolerance }
        }
    }

    func importedIdentityIndex() -> ImportedIdentityIndex {
        var byKey: [String: [TimeInterval]] = [:]
        for song in allSongs {
            let key = DuplicateFinderService.normalize(song.title) + "|" + DuplicateFinderService.normalize(song.artist)
            guard key != "|" else { continue }
            byKey[key, default: []].append(song.duration)
        }
        return ImportedIdentityIndex(byKey: byKey)
    }

    /// True if a local copy of `track` already exists on the device, by EITHER:
    ///   1. an exact source-ID match (`Song.sourceTrackID` == "<source>:<id>",
    ///      i.e. the `LUMISOUND_ID` embedded at download time) whose backing file
    ///      still exists, OR
    ///   2. a normalized title+artist (+duration) match via `isAlreadyImported`,
    ///      which catches manual imports, re-encodes, and pre-tagging downloads.
    ///
    /// This is the pre-download gate for the tracked-playlist feature. Callers
    /// MUST `await scanLocalDocumentsAsync()` first so `allSongs` reflects every
    /// file in the Imported Music directory *and its subfolders* — otherwise a
    /// track that lives in a subfolder the scan hasn't seen yet would slip
    /// through and be downloaded twice (the bug this replaces: the old flow
    /// checked a stale library before yt-dlp ever ran).
    func hasLocalCopy(of track: StreamTrack) -> Bool {
        let sourceID = "\(track.source):\(track.id)"
        let fm = FileManager.default
        if allSongs.contains(where: { song in
            guard song.sourceTrackID == sourceID else { return false }
            guard let url = song.url else { return false }
            return fm.fileExists(atPath: url.path)
        }) {
            return true
        }
        // Download-ledger check: covers tracks whose embedded LUMISOUND_ID didn't
        // round-trip (m4a dropped the tag), so the file is in the library but no
        // Song carries `sourceID`. The ledger maps sourceID → filename; if that
        // filename is still present in the library, we have it.
        if let fn = DownloadLedgerStore.shared.filename(for: sourceID),
           allSongs.contains(where: { $0.url?.lastPathComponent == fn }) {
            return true
        }
        let dur: TimeInterval? = track.durationSeconds > 0 ? TimeInterval(track.durationSeconds) : nil
        return isAlreadyImported(title: track.title, artist: track.artist, duration: dur)
    }

    /// Permanently removes a locally-imported/downloaded song: deletes its
    /// backing file, drops it from `importedSongs`/`allSongs`, and removes any
    /// references to it from playlists and favorites. Used by the duplicate
    /// finder to delete redundant copies. Only works for imported songs (those
    /// with a file `url` and no `persistentID`) — songs from the Apple Music
    /// library can't be deleted from within the app sandbox, so callers should
    /// filter those out before offering deletion.
    func removeImportedSong(id songID: String) {
        guard let song = importedSongs.first(where: { $0.id == songID }) else { return }
        if let url = song.url {
            // Songs from user-watched folders (MusicFolderService) live outside the
            // app sandbox and are only reachable via a security-scoped bookmark —
            // without this, `removeItem` silently fails (the `try?` swallows an
            // error), the song disappears from the library list, but the file
            // stays on disk. This call is a harmless no-op for files already
            // inside the app's own Documents directory (e.g. "Imported Music"
            // and its subfolders).
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                appWarn("removeImportedSong: failed to delete file at \(url.path): \(error.localizedDescription)", category: "library")
                ToastCenter.shared.show("Couldn't delete \"\(song.displayName)\" from disk", category: .error)
                return
            }
        }
        importedSongs.removeAll { $0.id == songID }
        favoriteSongIDs.remove(songID)
        persistence.saveFavorites(favoriteSongIDs)
        for index in playlists.indices {
            playlists[index].songIDs.removeAll { $0 == songID }
        }
        persistence.savePlaylists(playlists)
        rebuildAllSongs()
        ToastCenter.shared.show("Deleted \"\(song.displayName)\"", category: .info, icon: "trash")
    }

    /// Bulk version of `removeImportedSong` for Library's multi-select "Delete"
    /// action — one rebuild/toast instead of one per song. IDs that aren't in
    /// `importedSongs` (e.g. Apple Music library tracks, which this can't
    /// delete) are silently skipped rather than failing the whole batch.
    func removeImportedSongs(ids songIDs: Set<String>) {
        let toDelete = importedSongs.filter { songIDs.contains($0.id) }
        guard !toDelete.isEmpty else { return }

        for song in toDelete {
            guard let url = song.url else { continue }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                appWarn("removeImportedSongs: failed to delete file at \(url.path): \(error.localizedDescription)", category: "library")
            }
        }

        let deletedIDs = Set(toDelete.map(\.id))
        importedSongs.removeAll { deletedIDs.contains($0.id) }
        favoriteSongIDs.subtract(deletedIDs)
        persistence.saveFavorites(favoriteSongIDs)
        for index in playlists.indices {
            playlists[index].songIDs.removeAll { deletedIDs.contains($0) }
        }
        persistence.savePlaylists(playlists)
        rebuildAllSongs()
        ToastCenter.shared.show(
            "Deleted \(deletedIDs.count) song\(deletedIDs.count == 1 ? "" : "s")",
            category: .info, icon: "trash"
        )
    }

    /// Applies a user-confirmed metadata correction (e.g. from AcoustIDService
    /// identification) to a single imported song. Unlike the periodic
    /// re-enrichment in `reenrichSongsMissingMetadata` — which only fills
    /// *empty* fields — this overwrites existing title/artist/album, since
    /// the user has explicitly reviewed and confirmed the match. Only affects
    /// the app's own record for the file (`ScanCacheService`'s cached Song),
    /// not the file's embedded tags.
    func applyMetadataCorrection(songID: String, title: String?, artist: String?, album: String?) {
        guard let index = importedSongs.firstIndex(where: { $0.id == songID }) else { return }
        var song = importedSongs[index]
        if let title, !title.isEmpty { song.title = title }
        if let artist, !artist.isEmpty { song.artist = artist }
        if let album, !album.isEmpty { song.album = album }
        importedSongs[index] = song

        if let url = song.url, let stamp = ScanCacheService.fileStamp(for: url) {
            ScanCacheService.shared.store(song: song, for: url, stamp: stamp)
            ScanCacheService.shared.persist()
        }
        rebuildAllSongs()
        ToastCenter.shared.show("Updated \"\(song.displayName)\"", category: .success, icon: "checkmark.circle")
    }

    /// Debounced rebuild — cancels any pending task and schedules a new one after 0.1 s.
    /// This prevents runaway work when rapid successive mutations occur (e.g. bulk imports).
    ///
    /// The locale-aware sort plus the three set/sort passes for filter facets are
    /// O(n log n) over the *entire* library on every mutation. For large libraries
    /// (thousands of tracks) that's enough synchronous work to visibly stall the UI
    /// if run on the main actor, so it's computed off-actor and only the final
    /// `@Published` assignment happens on the main actor.
    private func rebuildAllSongs() {
        pendingRebuildTask?.cancel()
        pendingRebuildTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 s
            guard let self, !Task.isCancelled else { return }
            let media = self.mediaSongs
            let imported = self.importedSongs

            let (combined, artists, albums, genres) = await Task.detached(priority: .userInitiated) {
                let combined = (media + imported).sorted {
                    $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                }
                let artists = Array(Set(combined.map(\.artistName))).sorted()
                let albums  = Array(Set(combined.map(\.albumName))).sorted()
                let genres  = Array(Set(combined.compactMap { $0.genre.isEmpty ? nil : $0.genre })).sorted()
                return (combined, artists, albums, genres)
            }.value

            guard !Task.isCancelled else { return }
            self.allSongs = combined
            self.artists = artists
            self.albums  = albums
            self.genres  = genres
            self.persistSnapshotIfSettled()
        }
    }
}
