import Foundation
import MediaPlayer
import UIKit

@MainActor
final class LibraryManager: ObservableObject {
    @Published private(set) var allSongs: [Song] = []
    @Published private(set) var artists: [String] = []
    @Published private(set) var albums: [String] = []
    @Published private(set) var genres: [String] = []
    @Published private(set) var playlists: [Playlist] = []
    @Published private(set) var favoriteSongIDs: Set<String> = []
    @Published private(set) var isScanning: Bool = false
    @Published var errorMessage: String?
    @Published var lastScanResult: String? = nil

    private let persistence: PersistenceService
    private let artwork: ArtworkService
    private let importer = DocumentImportService()

    private var mediaSongs: [Song] = []
    private var importedSongs: [Song] = []

    /// Pending debounced rebuild task. Cancelled and replaced on each rapid mutation.
    private var pendingRebuildTask: Task<Void, Never>?

    var favoriteSongs: [Song] {
        allSongs.filter { favoriteSongIDs.contains($0.id) }
    }

    init(persistence: PersistenceService = .shared, artwork: ArtworkService = .shared) {
        self.persistence = persistence
        self.artwork = artwork
        favoriteSongIDs = persistence.loadFavorites()
        playlists = persistence.loadPlaylists()
        // Immediately scan files already sitting in the app's Documents folder
        // (placed there via Finder/Files app or a previous import session).
        scanLocalDocuments()
    }

    /// Scans the app's Documents directory (root + Imported Music subfolder) for audio
    /// files and adds any that aren't already tracked. Called automatically on init and
    /// can be triggered manually after the user drops files via the Files app.
    /// Recursively scans the app's entire Documents directory for audio files and
    /// adds any not already tracked. Picks up files placed via Finder, Files app,
    /// iTunes file sharing, or any subdirectory the user created inside the app folder.
    func scanLocalDocuments() {
        appLog("Scanning local documents directory", category: "library")
        Task {
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

            // Only process files we haven't seen before.
            let existingURLs = Set(importedSongs.compactMap { $0.url?.standardizedFileURL })
            let newURLs = candidates.filter { !existingURLs.contains($0.standardizedFileURL) }
            guard !newURLs.isEmpty else { return }

            let newSongs: [Song] = await Task.detached(priority: .userInitiated) {
                await withTaskGroup(of: Song?.self) { group in
                    var results: [Song] = []
                    var pending = 0
                    let maxConcurrent = 8
                    var iterator = newURLs.makeIterator()

                    // Seed initial tasks
                    while pending < maxConcurrent, let url = iterator.next() {
                        let s = DocumentImportService()
                        group.addTask { await s.makeSong(for: url) }
                        pending += 1
                    }

                    // Process results and add more tasks
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

            appLog("Local scan complete: added \(newSongs.count) new song(s)", category: "library")
            importedSongs.append(contentsOf: newSongs)
            importedSongs = Array(Dictionary(grouping: importedSongs, by: { song in song.url.map { $0.standardizedFileURL.absoluteString } ?? song.id }).compactMap { $0.value.first })
            rebuildAllSongs()
        }
    }

    /// Scans all user-selected folders tracked by `MusicFolderService` and adds
    /// any new audio files not already in the library.
    func scanWatchedFolders(using folderService: MusicFolderService) {
        appLog("scanWatchedFolders: starting", category: "library")
        Task {
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

            let newSongs: [Song] = await Task.detached(priority: .userInitiated) {
                await withTaskGroup(of: Song?.self) { group in
                    var results: [Song] = []
                    var pending = 0
                    let maxConcurrent = 8
                    var iterator = newURLs.makeIterator()

                    // Seed initial tasks
                    while pending < maxConcurrent, let url = iterator.next() {
                        let s = DocumentImportService()
                        group.addTask { await s.makeSong(for: url) }
                        pending += 1
                    }

                    // Process results and add more tasks
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

            appLog("scanWatchedFolders: added \(newSongs.count) new song(s) from \(urls.count) folder(s)", category: "library")
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
        isScanning = true
        lastScanResult = nil
        Task {
            defer { isScanning = false }

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

            let newSongs: [Song] = await Task.detached(priority: .userInitiated) {
                await withTaskGroup(of: Song?.self) { group in
                    var results: [Song] = []
                    var pending = 0
                    let maxConcurrent = 8
                    var iterator = newURLs.makeIterator()

                    // Seed initial tasks
                    while pending < maxConcurrent, let fileURL = iterator.next() {
                        let s = DocumentImportService()
                        group.addTask { await s.makeSong(for: fileURL) }
                        pending += 1
                    }

                    // Process results and add more tasks
                    for await song in group {
                        if let song { results.append(song) }
                        pending -= 1
                        if let fileURL = iterator.next() {
                            let s = DocumentImportService()
                            group.addTask { await s.makeSong(for: fileURL) }
                            pending += 1
                        }
                    }
                    return results
                }
            }.value

            appLog("scanSpecificDirectory: added \(newSongs.count) new song(s) from \(url.lastPathComponent)", category: "library")
            importedSongs.append(contentsOf: newSongs)
            importedSongs = Array(Dictionary(grouping: importedSongs, by: { song in song.url.map { $0.standardizedFileURL.absoluteString } ?? song.id }).compactMap { $0.value.first })
            rebuildAllSongs()
            lastScanResult = "Found \(newSongs.count) song\(newSongs.count == 1 ? "" : "s") in \(url.lastPathComponent)"
        }
    }

    /// Convenience: scans both the local Documents folder and all user-selected watched folders.
    func scanAll(folderService: MusicFolderService) {
        scanLocalDocuments()
        scanWatchedFolders(using: folderService)
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

    func scanMediaLibrary() {
        guard MPMediaLibrary.authorizationStatus() == .authorized else {
            requestAccessAndScan()
            return
        }
        appLog("scanMediaLibrary: starting", category: "library")
        isScanning = true
        errorMessage = nil

        Task {
            let scanned: [Song] = await Task.detached(priority: .userInitiated) {
                let query = MPMediaQuery.songs()
                return (query.items ?? []).compactMap(Song.init(mediaItem:))
            }.value
            // Back on MainActor — Task inherits actor context from scanMediaLibrary().
            appLog("scanMediaLibrary: found \(scanned.count) song(s)", category: "library")
            self.mediaSongs = scanned
            self.rebuildAllSongs()
            self.isScanning = false
        }
    }

    func importFiles(urls: [URL]) {
        guard !urls.isEmpty else { return }
        appLog("Importing \(urls.count) file(s)", category: "library")
        isScanning = true
        errorMessage = nil

        Task {
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
            isScanning = false
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

    /// Debounced rebuild — cancels any pending task and schedules a new one after 0.1 s.
    /// This prevents runaway work when rapid successive mutations occur (e.g. bulk imports).
    private func rebuildAllSongs() {
        pendingRebuildTask?.cancel()
        pendingRebuildTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 s
            guard let self, !Task.isCancelled else { return }
            let combined = (self.mediaSongs + self.importedSongs).sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
            self.allSongs = combined
            self.artists = Array(Set(combined.map(\.artistName))).sorted()
            self.albums  = Array(Set(combined.map(\.albumName))).sorted()
            self.genres  = Array(Set(combined.compactMap { $0.genre.isEmpty ? nil : $0.genre })).sorted()
        }
    }
}
