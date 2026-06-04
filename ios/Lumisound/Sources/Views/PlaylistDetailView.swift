import SwiftUI

struct PlaylistDetailView: View {
    let playlist: Playlist

    @EnvironmentObject private var library: LibraryManager
    @EnvironmentObject private var player: AudioPlayerManager

    @State private var isEditing = false
    @State private var showingAddSongs = false

    // Always look up the live playlist so mutations (add/remove/reorder) are reflected immediately.
    private var currentPlaylist: Playlist {
        library.playlists.first(where: { $0.id == playlist.id }) ?? playlist
    }

    private var songs: [Song] {
        library.songs(for: currentPlaylist)
    }

    var body: some View {
        List {
            if songs.isEmpty {
                EmptyStateView(
                    icon: "music.note.list",
                    title: "No songs",
                    message: "Tap the + button to add songs to this playlist."
                )
                .listRowBackground(Color.clear)
            } else {
                // Play All button
                Section {
                    Button {
                        player.setQueue(songs, startIndex: 0, autoplay: true)
                    } label: {
                        Label("Play All", systemImage: "play.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(AppTheme.accent)
                    .listRowBackground(Color.clear)
                }
                .listSectionSeparator(.hidden)

                // Song list
                ForEach(songs) { song in
                    Button {
                        if !isEditing {
                            player.play(song: song, in: songs)
                        }
                    } label: {
                        SongRow(song: song, isCurrent: player.currentSong?.id == song.id)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(AppTheme.surface.opacity(0.5))
                    .contextMenu {
                        Button(role: .destructive) {
                            library.removeSong(id: song.id, fromPlaylistID: playlist.id)
                        } label: {
                            Label("Remove from Playlist", systemImage: "minus.circle")
                        }
                    }
                }
                .onMove { source, destination in
                    // Derive the reordered list from the displayed songs array
                    var reordered = songs.map(\.id)
                    reordered.move(fromOffsets: source, toOffset: destination)
                    reorder(newIDs: reordered)
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        let song = songs[index]
                        library.removeSong(id: song.id, fromPlaylistID: playlist.id)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.clear.ignoresSafeArea())
        .environment(\.editMode, .constant(isEditing ? .active : .inactive))
        .navigationTitle(playlist.name)
        .navigationBarTitleDisplayMode(.large)
        .safeAreaInset(edge: .bottom) { MiniPlayerBar() }
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    showingAddSongs = true
                } label: {
                    Image(systemName: "plus")
                }
                .tint(AppTheme.accent)

                Button {
                    withAnimation { isEditing.toggle() }
                } label: {
                    Text(isEditing ? "Done" : "Edit")
                        .fontWeight(isEditing ? .semibold : .regular)
                }
                .tint(AppTheme.accent)
            }
        }
        .sheet(isPresented: $showingAddSongs) {
            AddSongsSheet(playlist: playlist)
                .environmentObject(library)
                .environmentObject(player) // SongRow context menu (SongContextMenuContent) needs it
        }
    }

    private func reorder(newIDs: [Song.ID]) {
        library.reorderSongs(in: playlist.id, to: newIDs)
    }
}

// MARK: - Add Songs Sheet

private struct AddSongsSheet: View {
    let playlist: Playlist

    @EnvironmentObject private var library: LibraryManager
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""

    private var filteredSongs: [Song] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return library.allSongs }
        return library.allSongs.filter { song in
            song.displayName.localizedCaseInsensitiveContains(query)
                || song.artistName.localizedCaseInsensitiveContains(query)
        }
    }

    private func isInPlaylist(_ song: Song) -> Bool {
        (library.playlists.first(where: { $0.id == playlist.id }) ?? playlist).songIDs.contains(song.id)
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredSongs) { song in
                    Button {
                        if isInPlaylist(song) {
                            library.removeSong(id: song.id, fromPlaylistID: playlist.id)
                        } else {
                            library.addSong(id: song.id, toPlaylistID: playlist.id)
                        }
                    } label: {
                        HStack {
                            SongRow(
                                song: song,
                                isCurrent: false,
                                showArtwork: true,
                                subtitle: song.artistName
                            )
                            Spacer(minLength: 8)
                            Image(systemName: isInPlaylist(song) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(isInPlaylist(song) ? AppTheme.accent : AppTheme.textSecondary)
                                .font(.system(size: 22))
                                .animation(.easeInOut(duration: 0.15), value: isInPlaylist(song))
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(AppTheme.surface.opacity(0.5))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.clear.ignoresSafeArea())
            .searchable(text: $searchText, prompt: "Search songs")
            .navigationTitle("Add Songs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .tint(AppTheme.accent)
                }
            }
        }
    }
}
