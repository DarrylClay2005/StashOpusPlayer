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
        guard songID != currentlyPlayingID,
              let index = importedSongs.firstIndex(where: { $0.id == songID }),
              let oldURL = importedSongs[index].url,
              oldURL.isFileURL,
              !LumisoundExclusiveExtensionService.isConverted(oldURL),
              LumisoundTrackTagger.isTagged(fileURL: oldURL)
        else { return false }

        let oldSong = importedSongs[index]
        guard let newURL = LumisoundExclusiveExtensionService.convert(fileURL: oldURL) else { return false }

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
