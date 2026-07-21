import Foundation
import MediaPlayer
import UIKit

extension LibraryManager {

    func isFavorite(songID: String) -> Bool {
        favoriteSongIDs.contains(songID)
    }

    func toggleFavorite(songID: String) {
        if favoriteSongIDs.contains(songID) {
            favoriteSongIDs.remove(songID)
            ToastCenter.shared.show("Removed from Favorites", category: .info, icon: "heart")
        } else {
            favoriteSongIDs.insert(songID)
            ToastCenter.shared.show("Added to Favorites", category: .success, icon: "heart.fill")
        }
        persistence.saveFavorites(favoriteSongIDs)
    }

    /// Adds multiple songs to Favorites in a single persistence write/toast —
    /// used by bulk "Favorite" actions (e.g. LocalFolderDetailView's
    /// multi-select bar) instead of looping `toggleFavorite(songID:)`, which
    /// would both toast per item AND flip an already-favorited song back off
    /// (this only ever adds, never removes). Songs already favorited are
    /// silently skipped rather than counted again.
    func addFavorites(ids songIDs: Set<String>) {
        let toAdd = songIDs.subtracting(favoriteSongIDs)
        guard !toAdd.isEmpty else {
            ToastCenter.shared.show("Already in Favorites", category: .info, icon: "heart")
            return
        }
        favoriteSongIDs.formUnion(toAdd)
        persistence.saveFavorites(favoriteSongIDs)
        appLog("addFavorites: \(toAdd.count) song(s) added", category: "library")
        ToastCenter.shared.show(
            "Added \(toAdd.count) song\(toAdd.count == 1 ? "" : "s") to Favorites",
            category: .success, icon: "heart.fill"
        )
    }

    func songs(for playlist: Playlist) -> [Song] {
        playlist.songIDs.compactMap { songsByID[$0] }
    }

    func songs(byArtist artist: String) -> [Song] {
        songsByArtist[artist] ?? []
    }

    func songs(inAlbum album: String) -> [Song] {
        songsByAlbum[album] ?? []
    }

    func songs(inGenre genre: String) -> [Song] {
        songsByGenre[genre] ?? []
    }
}
