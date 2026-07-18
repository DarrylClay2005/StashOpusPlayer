import Foundation
import MediaPlayer
import UIKit

extension LibraryManager {

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
        RemoteLogger.log(category: "sync", event: "force_metadata_sync_started")
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
        // One summary event for the whole run, not one per track — `total`
        // can be the entire library, and the loop above already amortizes
        // its own network calls per-track; adding a remote-log call there
        // too would be the same tight-loop-of-blocking-calls pattern that's
        // previously caused main-thread hangs on large libraries.
        RemoteLogger.log(category: "sync", event: "force_metadata_sync_completed",
                          detail: ["updated": updatedCount, "total": total, "artworkFilled": artworkFilledCount])
        lastScanResult = "Force metadata sync: updated \(updatedCount) of \(total) song(s), artwork filled for \(artworkFilledCount)"
    }
}
