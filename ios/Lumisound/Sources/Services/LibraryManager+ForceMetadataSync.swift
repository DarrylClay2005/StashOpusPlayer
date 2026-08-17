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
    func forceMetadataSync(using folderService: MusicFolderService, currentlyPlayingID: String? = nil) async {
        guard !isForcingMetadataSync else { return }
        isForcingMetadataSync = true
        defer { isForcingMetadataSync = false }

        appLog("Force metadata sync: rescanning Documents + watched folders", category: "library")
        RemoteLogger.log(category: "sync", event: "force_metadata_sync_started")
        await scanLocalDocumentsAsync()
        await scanWatchedFoldersAsync(using: folderService)

        var updatedCount = 0
        var artworkFilledCount = 0
        var reEmbeddedCount = 0
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

                // Previously this whole function only updated the app's OWN
                // record of a track's metadata (ScanCacheService/EnrichmentCacheStore
                // below) — the corrected title/artist/album/genre/year never made
                // it back into the actual file. That meant: clear the scan cache,
                // reinstall, or open the file in any other app/backup, and the
                // "fix" was gone. Re-embed into the real file too, for tracks
                // vault-tagged (so we have a trackID to keep the LUMISOUND_ID atom
                // intact) and not currently playing (replacing a file out from
                // under an open AVAudioFile/AVPlayerItem risks interrupting
                // playback — same guard `convertToLumisoundExclusiveExtension`
                // and `repairEmbeddedMetadata` already use). Best-effort: any
                // failure here leaves the in-memory/cache update above intact,
                // it just doesn't persist to the file this pass — picked up again
                // on the next Force Metadata Sync.
                if current.id != currentlyPlayingID,
                   let tag = LumisoundTrackTagger.readTag(fileURL: url) {
                    if await reEmbedMetadata(current: current, url: url, trackID: tag.trackID, sourceURL: tag.sourceURL) {
                        reEmbeddedCount += 1
                    }
                }
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

        appLog("Force metadata sync: updated \(updatedCount) of \(total) song(s), filled artwork for \(artworkFilledCount), re-embedded into \(reEmbeddedCount) file(s)", category: "library")
        // One summary event for the whole run, not one per track — `total`
        // can be the entire library, and the loop above already amortizes
        // its own network calls per-track; adding a remote-log call there
        // too would be the same tight-loop-of-blocking-calls pattern that's
        // previously caused main-thread hangs on large libraries.
        RemoteLogger.log(category: "sync", event: "force_metadata_sync_completed",
                          detail: ["updated": updatedCount, "total": total, "artworkFilled": artworkFilledCount, "reEmbedded": reEmbeddedCount])
        lastScanResult = "Force metadata sync: updated \(updatedCount) of \(total) song(s), artwork filled for \(artworkFilledCount)"
    }

    /// Re-encodes `url` in place with `current`'s corrected title/artist/
    /// album/genre/year embedded via `AudioTagWriter`, replacing the
    /// original file only once the write is confirmed to produce a genuinely
    /// playable result. `replaceItemAt` (like `AudioTagWriter`'s export
    /// itself) produces a new inode, so the vault xattr tag doesn't carry
    /// over automatically — re-applied at the end, same as
    /// `repairEmbeddedMetadata`/`convertToLumisoundExclusiveExtension` do.
    private func reEmbedMetadata(current: Song, url: URL, trackID: String, sourceURL: String) async -> Bool {
        // `url`'s on-disk bytes are XOR-masked (and unreadable by
        // AVAssetExportSession, which AudioTagWriter uses internally) if
        // it's `.lms`-locked -- resolve before handing it off, same as every
        // other raw-file read in this pipeline.
        let readableURL = LumisoundExclusiveExtensionService.playableURL(for: url)
        guard let repairedURL = await AudioTagWriter.tag(
            fileAt: readableURL,
            title: current.title, artist: current.artist, album: current.album,
            sourceTrackID: trackID,
            genre: current.genre, year: current.year, trackNumber: current.trackNumber
        ) else {
            appWarn("forceMetadataSync: re-embed failed for \(url.lastPathComponent)", category: "library")
            return false
        }
        defer { try? FileManager.default.removeItem(at: repairedURL) }

        let fm = FileManager.default
        if LumisoundExclusiveExtensionService.isConverted(url) {
            // `repairedURL` is PLAIN (unlocked) output -- writing it straight
            // onto `url`'s `.lms` path would silently strip the file of its
            // lock (no magic header), AND worse, corrupt it on the next
            // playback attempt: `playableURL`/`LumisoundLockFormat.unlock`
            // would XOR-mask bytes that are already plain, since it has no
            // way to know the file stopped being genuinely locked. Re-lock
            // to a temp file first and verify round-trip before swapping in,
            // exactly like `LumisoundExclusiveExtensionService.relockLegacyFile`
            // and `repairEmbeddedMetadata` do.
            let lockedTempURL = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("lms")
            let verifyURL = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(repairedURL.pathExtension)
            defer {
                try? fm.removeItem(at: lockedTempURL)
                try? fm.removeItem(at: verifyURL)
            }
            let relockedOK = await Task.detached(priority: .utility) {
                guard LumisoundLockFormat.lock(plainURL: repairedURL, to: lockedTempURL) else { return false }
                guard LumisoundLockFormat.unlock(lockedURL: lockedTempURL, to: verifyURL),
                      CorruptFileFinderService.isValidAudioFile(at: verifyURL) else { return false }
                return true
            }.value
            guard relockedOK else {
                appWarn("forceMetadataSync: re-lock or round-trip verification failed for \(url.lastPathComponent)", category: "library")
                return false
            }
            do {
                _ = try fm.replaceItemAt(url, withItemAt: lockedTempURL)
            } catch {
                appWarn("forceMetadataSync: replaceItemAt failed for \(url.lastPathComponent): \(error.localizedDescription)", category: "library")
                return false
            }
        } else {
            do {
                _ = try fm.replaceItemAt(url, withItemAt: repairedURL)
            } catch {
                appWarn("forceMetadataSync: replaceItemAt failed for \(url.lastPathComponent): \(error.localizedDescription)", category: "library")
                return false
            }
        }
        LumisoundTrackTagger.tag(fileURL: url, trackID: trackID, sourceURL: sourceURL)
        return true
    }
}
