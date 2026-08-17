import Foundation

extension LibraryManager {
    /// Re-encodes a single already-vault-tagged imported song's file into
    /// the Lumisound-exclusive AAC container (see
    /// `LumisoundExclusiveExtensionService`), then re-keys every store that
    /// references the song by its old, path-derived ID
    /// (`DocumentImportService`'s `"local:\(relative path)"` scheme — the ID
    /// changes because the path/extension changes) so nothing silently
    /// disconnects from the conversion: favorites, playlists, play history,
    /// and the download ledger's filename record all get updated in the
    /// same pass. Skips:
    ///   - songs that aren't imported/local (no `url`), already converted,
    ///     or not vault-tagged yet (every on-disk track — downloaded or
    ///     plain local import — becomes eligible once
    ///     `LumisoundTrackVaultService.runBackfill` tags it)
    ///   - the currently-playing song, since replacing a file out from
    ///     under an open `AVAudioFile`/`AVPlayerItem` risks interrupting
    ///     playback; it's simply picked up on a later pass once it's no
    ///     longer playing.
    @discardableResult
    func convertToLumisoundExclusiveExtension(songID: String, currentlyPlayingID: String?) async -> Bool {
        // Split out of one big `guard` (temporarily, for field diagnosis —
        // see the session that added this comment) so a failure logs WHICH
        // condition tripped instead of the earlier silent `return false`
        // making "never converts anything" indistinguishable from "nothing
        // eligible yet" in the field.
        // `currentlyPlayingID` alone is a snapshot taken once before this
        // whole batch started — see `AudioPlayerManager.isInActiveQueue`'s
        // doc comment for why a fresh, whole-queue check is also needed
        // here, not just the single ID captured at batch-start.
        guard songID != currentlyPlayingID, AudioPlayerManager.shared?.isInActiveQueue(songID: songID) != true else {
            appWarn("convertToLumisoundExclusiveExtension: skipped \(songID) — currently playing or still in the active queue", category: "background")
            return false
        }
        guard let index = importedSongs.firstIndex(where: { $0.id == songID }) else {
            appWarn("convertToLumisoundExclusiveExtension: skipped \(songID) — not found in importedSongs", category: "background")
            return false
        }
        guard let oldURL = importedSongs[index].url, oldURL.isFileURL else {
            appWarn("convertToLumisoundExclusiveExtension: skipped \(songID) — no local file URL", category: "background")
            return false
        }
        guard !LumisoundExclusiveExtensionService.isConverted(oldURL) else {
            return false // already converted — not a failure, just nothing to do
        }
        guard let existingTag = LumisoundTrackTagger.readTag(fileURL: oldURL) else {
            appWarn("convertToLumisoundExclusiveExtension: skipped \(songID) at \(oldURL.lastPathComponent) — no readable vault tag at convert time", category: "background")
            return false
        }

        let oldSong = importedSongs[index]
        guard let newURL = await LumisoundExclusiveExtensionService.convert(fileURL: oldURL) else {
            appWarn("convertToLumisoundExclusiveExtension: re-encode failed for \(songID) at \(oldURL.lastPathComponent)", category: "background")
            return false
        }
        // Re-encoding writes a brand new inode (unlike the old rename-only
        // path), so the xattr vault tag doesn't carry over automatically —
        // re-apply it here using the tag we read off the original file
        // before it was replaced, otherwise every converted track would
        // silently lose the dedup fallback tag (see LibraryManager+
        // DuplicateDetection.swift / DuplicateFinderService.swift), which is
        // the exact class of bug fixed for sourceTrackID mixups elsewhere.
        LumisoundTrackTagger.tag(fileURL: newURL, trackID: existingTag.trackID, sourceURL: existingTag.sourceURL)

        let newID = ScanCacheService.documentsRelativePath(for: newURL).map { "local:\($0)" } ?? oldSong.id
        let newSong = Song(
            id: newID,
            title: oldSong.title,
            artist: oldSong.artist,
            album: oldSong.album,
            duration: oldSong.duration,
            url: newURL,
            persistentID: oldSong.persistentID,
            // Preserve the PRE-conversion cache key rather than resetting it
            // to the new (post-conversion) filename — every downloaded
            // track's artwork is already cached under its original filename
            // by `prefetchArtworkWithFallback` at download time (or, for a
            // streamed-origin Song, under its literal thumbnail URL). Since
            // this conversion happens to essentially every track eventually,
            // resetting the key here orphaned that already-successfully-
            // cached artwork on disk every single time, forcing a full
            // re-fetch through ArtworkService's fallback chain — which,
            // for a track whose embedded LUMISOUND_THUMBNAIL tag/artwork
            // also didn't survive re-encoding (see AudioEncoderService's
            // metadata-carry-over fix and the repair migration below), had
            // nothing left to fall back to and permanently showed no
            // artwork. Falls back to the new filename only when there was
            // no prior key at all (nothing to lose by keying fresh).
            artworkCacheKey: oldSong.artworkCacheKey ?? newURL.lastPathComponent,
            trackNumber: oldSong.trackNumber,
            year: oldSong.year,
            genre: oldSong.genre,
            bitrate: oldSong.bitrate,
            sampleRate: oldSong.sampleRate,
            sourceTrackID: oldSong.sourceTrackID,
            httpHeaders: oldSong.httpHeaders,
            bpm: oldSong.bpm,
            dateAdded: oldSong.dateAdded,
            queueSource: oldSong.queueSource
        )
        importedSongs[index] = newSong

        if newID != oldSong.id {
            if favoriteSongIDs.contains(oldSong.id) {
                favoriteSongIDs.remove(oldSong.id)
                favoriteSongIDs.insert(newID)
                persistence.saveFavorites(favoriteSongIDs)
            }
            var playlistsChanged = false
            for i in playlists.indices {
                guard let pos = playlists[i].songIDs.firstIndex(of: oldSong.id) else { continue }
                playlists[i].songIDs[pos] = newID
                playlistsChanged = true
            }
            if playlistsChanged { persistence.savePlaylists(playlists) }
            PlayHistoryStore.shared.rekey(from: oldSong.id, to: newID)
        }

        if let sourceTrackID = oldSong.sourceTrackID, !sourceTrackID.isEmpty {
            DownloadLedgerStore.shared.record(sourceTrackID: sourceTrackID, filename: newURL.lastPathComponent)
        }
        if let stamp = ScanCacheService.fileStamp(for: newURL) {
            ScanCacheService.shared.store(song: newSong, for: newURL, stamp: stamp)
            ScanCacheService.shared.persist()
        }

        rebuildAllSongs()
        return true
    }

    /// Repairs a single ALREADY-converted track whose embedded
    /// `LUMISOUND_ID`/title/artist/album went missing — the bug fixed in
    /// `AudioEncoderService`'s re-encode paths not carrying source metadata
    /// forward (they now do; this repairs files converted before that fix).
    /// Re-embeds title/artist/album plus a reconstructed `LUMISOUND_ID` (the
    /// trackID recovered from the vault xattr tag, which DID survive the
    /// original conversion) via a fast passthrough remux (`AudioTagWriter`,
    /// no audio re-decode), replacing the file IN PLACE at its existing URL
    /// — unlike `convertToLumisoundExclusiveExtension`, the filename/
    /// extension don't change here, so no re-keying of favorites/playlists/
    /// play history is needed. Returns `false` (not an error) when there's
    /// nothing to do: not converted, not local, no vault tag to recover a
    /// trackID from, or the currently-playing song.
    @discardableResult
    func repairEmbeddedMetadata(songID: String, currentlyPlayingID: String?) async -> Bool {
        guard songID != currentlyPlayingID, AudioPlayerManager.shared?.isInActiveQueue(songID: songID) != true else { return false }
        guard let index = importedSongs.firstIndex(where: { $0.id == songID }) else { return false }
        let song = importedSongs[index]
        guard let url = song.url, url.isFileURL, LumisoundExclusiveExtensionService.isConverted(url) else {
            return false
        }
        guard let tag = LumisoundTrackTagger.readTag(fileURL: url), !tag.trackID.isEmpty else {
            appWarn("repairEmbeddedMetadata: skipped \(songID) at \(url.lastPathComponent) — no readable vault tag to recover a trackID from", category: "background")
            return false
        }

        // Reconstructs the same deterministic YouTube thumbnail URL
        // ArtworkService's own runtime fallback uses (ArtworkService.
        // loadArtwork's `sourceTrackID.hasPrefix("youtube:")` branch) — an
        // embedded LUMISOUND_THUMBNAIL tag is a second, permanent path back
        // to it that doesn't depend on the disk artwork cache still holding
        // the right entry under the right key (see the artworkCacheKey fix
        // in convertToLumisoundExclusiveExtension above for the bug this
        // guards against).
        var thumbnailURL: String?
        if tag.trackID.hasPrefix("youtube:") {
            let videoID = String(tag.trackID.dropFirst("youtube:".count))
            if !videoID.isEmpty {
                thumbnailURL = "https://i.ytimg.com/vi/\(videoID)/hqdefault.jpg"
            }
        }

        // `url` is `.lms`-locked (guaranteed above), so its on-disk bytes
        // are XOR-masked — AVAssetExportSession can't read them directly.
        // AudioTagWriter verifies its own output is genuinely readable
        // before returning non-nil (see its doc comment) — a non-nil
        // `repairedURL` here is safe to treat as the new (plain, unlocked)
        // truth to re-lock back into place.
        let readableURL = LumisoundExclusiveExtensionService.playableURL(for: url)
        guard let repairedURL = await AudioTagWriter.tag(
            fileAt: readableURL, title: song.title, artist: song.artist, album: song.album,
            sourceTrackID: tag.trackID, thumbnailURL: thumbnailURL
        ) else {
            appWarn("repairEmbeddedMetadata: tag-write failed for \(songID) at \(url.lastPathComponent)", category: "background")
            return false
        }
        defer { try? FileManager.default.removeItem(at: repairedURL) }

        // Re-lock the freshly-tagged plain file back into `url`'s path —
        // writing `repairedURL`'s PLAIN bytes straight to the `.lms` path
        // would silently strip the file of its actual lock (no magic
        // header), which is exactly the "exclusive" guarantee this whole
        // pipeline exists for. Locked to a temp file first and only
        // swapped in via `replaceItemAt` once verified, matching
        // `LumisoundExclusiveExtensionService.relockLegacyFile`'s pattern.
        //
        // The lock/unlock/verify work itself is synchronous full-file I/O
        // with no `await` inside it -- run via `Task.detached` rather than
        // inline here, since `LibraryManager` is `@MainActor` and this
        // function is called from a plain main-actor loop
        // (`runMetadataRepairMigrationIfNeeded`'s repair phase). Same class
        // of bug as `LumisoundTrackVaultService.runLegacyRelockPass`
        // (confirmed root cause of reported multi-second playback stalls
        // and UI freezes) -- this path runs far less often (once per 24h,
        // only for tracks missing embedded metadata) but a large lossless
        // file hitting it would produce the identical symptom.
        let fm = FileManager.default
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
            appWarn("repairEmbeddedMetadata: re-lock or round-trip verification failed for \(songID) at \(url.lastPathComponent)", category: "background")
            return false
        }

        do {
            _ = try fm.replaceItemAt(url, withItemAt: lockedTempURL)
        } catch {
            appWarn("repairEmbeddedMetadata: replaceItemAt failed for \(songID): \(error.localizedDescription)", category: "background")
            return false
        }
        // replaceItemAt produces a new inode, so the xattr vault tag
        // doesn't carry over for free — re-apply it, same as
        // convertToLumisoundExclusiveExtension does.
        LumisoundTrackTagger.tag(fileURL: url, trackID: tag.trackID, sourceURL: tag.sourceURL)
        if let stamp = ScanCacheService.fileStamp(for: url) {
            ScanCacheService.shared.store(song: song, for: url, stamp: stamp)
            ScanCacheService.shared.persist()
        }
        return true
    }
}
