import Foundation

extension LibraryManager {
    /// Converts a single already-vault-tagged imported song's file to carry
    /// the Lumisound-exclusive extension (see `LumisoundExclusiveExtensionService`),
    /// then re-keys every store that references the song by its old,
    /// path-derived ID (`DocumentImportService`'s `"local:\(relative path)"`
    /// scheme — the ID changes because the path changes) so nothing silently
    /// disconnects from the rename: favorites, playlists, play history, and
    /// the download ledger's filename record all get updated in the same
    /// pass. Skips:
    ///   - songs that aren't imported/local (no `url`), already converted,
    ///     or not vault-tagged (only confirmed Lumisound-sourced downloads
    ///     are eligible — see `LumisoundTrackVaultService`)
    ///   - the currently-playing song, since renaming a file out from under
    ///     an open `AVAudioFile`/`AVPlayerItem` risks interrupting playback;
    ///     it's simply picked up on a later pass once it's no longer playing.
    @discardableResult
    func convertToLumisoundExclusiveExtension(songID: String, currentlyPlayingID: String?) -> Bool {
        // Split out of one big `guard` (temporarily, for field diagnosis —
        // see the session that added this comment) so a failure logs WHICH
        // condition tripped instead of the earlier silent `return false`
        // making "never converts anything" indistinguishable from "nothing
        // eligible yet" in the field.
        guard songID != currentlyPlayingID else {
            appWarn("convertToLumisoundExclusiveExtension: skipped \(songID) — currently playing", category: "background")
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
        guard LumisoundTrackTagger.isTagged(fileURL: oldURL) else {
            appWarn("convertToLumisoundExclusiveExtension: skipped \(songID) at \(oldURL.lastPathComponent) — isTagged() false at convert time", category: "background")
            return false
        }

        let oldSong = importedSongs[index]
        guard let newURL = LumisoundExclusiveExtensionService.convert(fileURL: oldURL) else {
            appWarn("convertToLumisoundExclusiveExtension: rename failed for \(songID) at \(oldURL.lastPathComponent)", category: "background")
            return false
        }

        let newID = ScanCacheService.documentsRelativePath(for: newURL).map { "local:\($0)" } ?? oldSong.id
        let newSong = Song(
            id: newID,
            title: oldSong.title,
            artist: oldSong.artist,
            album: oldSong.album,
            duration: oldSong.duration,
            url: newURL,
            persistentID: oldSong.persistentID,
            artworkCacheKey: newURL.lastPathComponent,
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
}
