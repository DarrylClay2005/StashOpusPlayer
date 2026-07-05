import Foundation
import MediaPlayer
import UIKit

extension LibraryManager {

    func createPlaylist(name: String) {
        let playlist = Playlist(id: UUID(), name: name, songIDs: [], createdAt: Date())
        playlists.append(playlist)
        persistence.savePlaylists(playlists)
        ToastCenter.shared.show("Created playlist \"\(name)\"", category: .success, icon: "music.note.list")
    }

    /// Merges a `LibraryBackup` into the current library — always additive,
    /// never overwrites/removes anything already here. Playlists are added
    /// as new playlists (fresh IDs, so re-importing the same backup twice
    /// just creates duplicates rather than silently merging song lists);
    /// any `songIDs`/favorite IDs the current library doesn't have (e.g. a
    /// song that only existed on the other device) are dropped rather than
    /// failing the whole import. Returns a summary for the caller to report.
    func importBackup(_ backup: LibraryBackup) -> (playlistsImported: Int, songsSkipped: Int) {
        let knownIDs = Set(allSongs.map(\.id))
        var songsSkipped = 0

        var importedPlaylists: [Playlist] = []
        for var playlist in backup.playlists {
            let originalCount = playlist.songIDs.count
            playlist.songIDs = playlist.songIDs.filter { knownIDs.contains($0) }
            songsSkipped += originalCount - playlist.songIDs.count
            playlist = Playlist(
                id: UUID(),
                name: playlist.name,
                songIDs: playlist.songIDs,
                createdAt: Date(),
                folder: playlist.folder,
                tags: playlist.tags,
                preferredArtworkStyle: playlist.preferredArtworkStyle
            )
            importedPlaylists.append(playlist)
        }
        playlists.append(contentsOf: importedPlaylists)
        persistence.savePlaylists(playlists)

        let matchedFavorites = backup.favoriteSongIDs.filter { knownIDs.contains($0) }
        songsSkipped += backup.favoriteSongIDs.count - matchedFavorites.count
        favoriteSongIDs.formUnion(matchedFavorites)
        persistence.saveFavorites(favoriteSongIDs)

        return (importedPlaylists.count, songsSkipped)
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

    /// Remembers the Now Playing artwork style last used while this playlist
    /// was the active playback context — see `Playlist.preferredArtworkStyle`.
    func setPreferredArtworkStyle(_ styleRawValue: String, forPlaylistID playlistID: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        guard playlists[index].preferredArtworkStyle != styleRawValue else { return }
        playlists[index].preferredArtworkStyle = styleRawValue
        persistence.savePlaylists(playlists)
    }

    /// All folder names currently in use, sorted, for grouping the playlists list.
    var playlistFolders: [String] {
        Array(Set(playlists.compactMap(\.folder))).sorted()
    }
}
