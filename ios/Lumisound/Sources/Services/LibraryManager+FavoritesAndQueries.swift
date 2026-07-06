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
