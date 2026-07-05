import Foundation
import MediaPlayer
import UIKit

extension LibraryManager {

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
}
