import Foundation
import MediaPlayer
import UIKit

extension LibraryManager {

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

    func performLocalDocumentsScan(force: Bool = false) async {
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

        // Evict songs whose backing files no longer exist (e.g. moved by the user
        // via Files app into an organised subfolder, or the last local file was
        // deleted outright). Runs even when `candidates` is empty — an early
        // return before this point used to skip eviction entirely whenever the
        // Documents tree had zero audio files left, leaving phantom entries for
        // deleted tracks stuck in the library forever.
        let fm2 = FileManager.default
        let countBeforeEviction = importedSongs.count
        importedSongs = importedSongs.filter { song in
            guard let url = song.url else { return false }
            return fm2.fileExists(atPath: url.path)
        }
        let evicted = countBeforeEviction != importedSongs.count

        guard !candidates.isEmpty else {
            if evicted { rebuildAllSongs() }
            return
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
}
