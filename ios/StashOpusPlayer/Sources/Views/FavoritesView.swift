import SwiftUI

// MARK: - Sort Order

private enum FavoritesSortOrder: String, CaseIterable {
    case title          = "Title"
    case artist         = "Artist"
    case recentlyAdded  = "Recently Added"
}

// MARK: - FavoritesView

struct FavoritesView: View {
    @EnvironmentObject private var library: LibraryManager
    @EnvironmentObject private var player: AudioPlayerManager

    @State private var sortOrder: FavoritesSortOrder = .title

    // MARK: Sorted favorites

    private var favorites: [Song] {
        let raw = library.favoriteSongs
        switch sortOrder {
        case .title:
            return raw.sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
        case .artist:
            return raw.sorted {
                let cmp = $0.artistName.localizedCaseInsensitiveCompare($1.artistName)
                if cmp != .orderedSame { return cmp == .orderedAscending }
                return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
        case .recentlyAdded:
            // favoriteSongs preserves insertion order from favoriteSongIDs (Set has no order),
            // so we reverse the alphabetical order as a proxy for "reverse / recently added" feel.
            return raw.sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedDescending
            }
        }
    }

    // MARK: Body

    var body: some View {
        List {
            if favorites.isEmpty {
                EmptyStateView(
                    icon: "heart.slash",
                    title: "No favorites",
                    message: "Long-press any song and choose \"Add to Favorites\"."
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

                    // Song count header
                    Text("\(favorites.count) \(favorites.count == 1 ? "song" : "songs")")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
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
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                library.toggleFavorite(songID: song.id)
                            } label: {
                                Label("Unfavorite", systemImage: "heart.slash")
                            }
                            .tint(AppTheme.error)
                        }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.clear.ignoresSafeArea())
        .navigationTitle("Favorites")
        .navigationBarTitleDisplayMode(.large)
        .safeAreaInset(edge: .bottom) { MiniPlayerBar() }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    ForEach(FavoritesSortOrder.allCases, id: \.self) { order in
                        Button {
                            sortOrder = order
                        } label: {
                            HStack {
                                Text(order.rawValue)
                                if sortOrder == order {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .tint(AppTheme.accent)
            }
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
