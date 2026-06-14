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
        appLog("Scanning local documents directory", category: "library")
        beginScan()
        Task {
            defer { endScan() }
            let fm = FileManager.default
            guard let docsDir = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return }

            var candidates: [URL] = []

            // Walk the full Documents tree recursively — covers root, Imported Music/,
            // and any nested folders the user may have created (e.g. by artist or album).
            let enumerator = fm.enumerator(
                at: docsDir,
                includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )
            while let url = enumerator?.nextObject() as? URL {
                // Skip directories themselves; only process regular files.
                guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
                if DocumentImportService.supportedExtensions.contains(url.pathExtension.lowercased()) {
                    candidates.append(url)
                }
            }

            guard !candidates.isEmpty else { return }

            // Evict songs whose backing files no longer exist (e.g. moved by the user
            // via Files app into an organised subfolder). Without this, the old path
            // stays in existingURLs and the new path is never picked up as "new".
            let fm2 = FileManager.default
            importedSongs = importedSongs.filter { song in
                guard let url = song.url else { return false }
                return fm2.fileExists(atPath: url.path)
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
    }

    /// Scans all user-selected folders tracked by `MusicFolderService` and adds
    /// any new audio files not already in the library.
    func scanWatchedFolders(using folderService: MusicFolderService) {
        appLog("scanWatchedFolders: starting", category: "library")
        beginScan()
        Task {
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
            } catch {
                appError("Import failed: \(error.localizedDescription)", category: "library")
                errorMessage = error.localizedDescription
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
        } else {
            favoriteSongIDs.insert(songID)
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
    }

    func deletePlaylist(_ playlist: Playlist) {
        playlists.removeAll { $0.id == playlist.id }
        persistence.savePlaylists(playlists)
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
        guard !playlists[index].songIDs.contains(songID) else { return }
        playlists[index].songIDs.append(songID)
        persistence.savePlaylists(playlists)
    }

    func removeSong(id songID: String, fromPlaylistID playlistID: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlists[index].songIDs.removeAll { $0 == songID }
        persistence.savePlaylists(playlists)
    }

    func reorderSongs(in playlistID: UUID, to newIDs: [Song.ID]) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlists[index].songIDs = newIDs
        persistence.savePlaylists(playlists)
    }

    func artwork(for song: Song) -> UIImage? {
        artwork.artwork(for: song)
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
            try? FileManager.default.removeItem(at: url)
        }
        importedSongs.removeAll { $0.id == songID }
        favoriteSongIDs.remove(songID)
        persistence.saveFavorites(favoriteSongIDs)
        for index in playlists.indices {
            playlists[index].songIDs.removeAll { $0 == songID }
        }
        persistence.savePlaylists(playlists)
        rebuildAllSongs()
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
