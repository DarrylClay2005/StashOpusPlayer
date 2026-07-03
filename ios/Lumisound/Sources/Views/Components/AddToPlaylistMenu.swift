import SwiftUI

// MARK: - Reusable song context menu content

/// Drop-in context menu content for any song row.
/// Usage: attach `.contextMenu { SongContextMenuContent(song: song) }` to any view,
/// or use the `.songContextMenu(for:)` convenience modifier.
struct SongContextMenuContent: View {
    let song: Song

    @EnvironmentObject private var library: LibraryManager
    @EnvironmentObject private var player: AudioPlayerManager

    var body: some View {
        // MARK: Favorite / Unfavorite
        Button {
            library.toggleFavorite(songID: song.id)
        } label: {
            let isFav = library.isFavorite(songID: song.id)
            Label(
                isFav ? "Remove from Favorites" : "Add to Favorites",
                systemImage: isFav ? "heart.slash" : "heart"
            )
        }

        Divider()

        // MARK: Play Next
        Button {
            player.insertNext(song: song)
        } label: {
            Label("Play Next", systemImage: "text.insert")
        }

        // MARK: Add to End of Queue
        Button {
            player.appendToQueue(song: song)
        } label: {
            Label("Add to Queue", systemImage: "text.append")
        }

        // MARK: Identify Track (AcoustID) — only for imported/downloaded songs
        // with a local file (applyMetadataCorrection can't touch Apple Music
        // library tracks, and identification itself needs the local audio).
        if library.importedSongs.contains(where: { $0.id == song.id }), song.url?.isFileURL == true {
            Button {
                AcoustIDConfirmCenter.shared.identify(song: song)
            } label: {
                Label("Identify Track", systemImage: "waveform.badge.magnifyingglass")
            }
        }

        Divider()

        // MARK: Add to Playlist submenu
        if !library.playlists.isEmpty {
            Menu {
                ForEach(library.playlists) { playlist in
                    Button {
                        library.addSong(id: song.id, toPlaylistID: playlist.id)
                        ToastCenter.shared.show("Added to \"\(playlist.name)\"", category: .success, icon: "plus.rectangle.on.folder")
                    } label: {
                        Label(playlist.name, systemImage: "music.note.list")
                    }
                }
            } label: {
                Label("Add to Playlist", systemImage: "plus.rectangle.on.folder")
            }
        }

        // MARK: New Playlist with Song
        Button {
            let playlistName = song.displayName
            library.createPlaylist(name: playlistName)
            // Find by name rather than using .last, which is fragile if the array is sorted
            // or another concurrent mutation has appended to it.
            if let newPlaylist = library.playlists.last(where: { $0.name == playlistName }) {
                library.addSong(id: song.id, toPlaylistID: newPlaylist.id)
            }
            ToastCenter.shared.show("Created playlist \"\(playlistName)\"", category: .success, icon: "folder.badge.plus")
        } label: {
            Label("New Playlist with Song", systemImage: "folder.badge.plus")
        }

    }

}

// MARK: - ViewModifier

private struct SongContextMenuModifier: ViewModifier {
    let song: Song

    @EnvironmentObject private var library: LibraryManager
    @EnvironmentObject private var player: AudioPlayerManager

    func body(content: Content) -> some View {
        content.contextMenu {
            SongContextMenuContent(song: song)
                .environmentObject(library)
                .environmentObject(player)
        }
    }
}

// MARK: - View extension

extension View {
    /// Attaches the standard song context menu to any view.
    func songContextMenu(for song: Song) -> some View {
        modifier(SongContextMenuModifier(song: song))
    }
}
