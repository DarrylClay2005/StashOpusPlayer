import SwiftUI

struct FavoritesView: View {
    @EnvironmentObject private var library: LibraryManager
    @EnvironmentObject private var player: AudioPlayerManager

    private var favorites: [Song] {
        library.favoriteSongs
    }

    var body: some View {
        NavigationStack {
            List {
                if favorites.isEmpty {
                    EmptyStateView(
                        icon: "heart.slash",
                        title: "No favorites",
                        message: "Tap the heart icon on any song to add it to your favorites."
                    )
                    .listRowBackground(Color.clear)
                } else {
                    // Play All / Shuffle buttons
                    Section {
                        HStack(spacing: 12) {
                            Button {
                                player.setQueue(favorites, startIndex: 0, autoplay: true)
                            } label: {
                                Label("Play All", systemImage: "play.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(AppTheme.accent)

                            Button {
                                let shuffled = favorites.shuffled()
                                player.setQueue(shuffled, startIndex: 0, autoplay: true)
                            } label: {
                                Label("Shuffle", systemImage: "shuffle")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(AppTheme.accent)
                        }
                        .listRowBackground(Color.clear)
                    }
                    .listSectionSeparator(.hidden)

                    // Favorites list
                    ForEach(favorites) { song in
                        FavoriteRow(song: song, isCurrent: player.currentSong?.id == song.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                player.play(song: song, in: favorites)
                            }
                            .listRowBackground(AppTheme.surface.opacity(0.5))
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("Favorites")
            .navigationBarTitleDisplayMode(.large)
            .safeAreaInset(edge: .bottom) { MiniPlayerBar() }
        }
    }
}

// MARK: - Favorite Row

private struct FavoriteRow: View {
    let song: Song
    let isCurrent: Bool

    @EnvironmentObject private var library: LibraryManager

    var body: some View {
        HStack(spacing: 0) {
            SongRow(song: song, isCurrent: isCurrent)

            Button {
                library.toggleFavorite(songID: song.id)
            } label: {
                Image(systemName: "heart.fill")
                    .foregroundStyle(AppTheme.accent)
                    .font(.system(size: 18))
                    .padding(.leading, 12)
            }
            .buttonStyle(.plain)
        }
    }
}
