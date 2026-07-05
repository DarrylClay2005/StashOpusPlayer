import SwiftUI
import MediaPlayer

// MARK: - Artists Tab

struct ArtistsTab: View {
    @EnvironmentObject private var library: LibraryManager

    // Mirrors AlbumsTab's per-layout column count so the Artists grid can show
    // 1 (list), 2, or 3 columns just like Albums/Folders.
    @AppStorage("library_artists_columns") private var columns: Int = 1

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: columns)
    }

    var body: some View {
        Group {
            if columns == 1 {
                List {
                    if library.artists.isEmpty {
                        EmptyStateView(icon: "person.crop.circle", title: "No artists", message: "Add music to see artists here.")
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(library.artists, id: \.self) { artist in
                            NavigationLink {
                                ArtistDetailView(artist: artist)
                            } label: {
                                ArtistRow(artist: artist)
                            }
                            .listRowBackground(AppTheme.surface.opacity(0.5))
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            } else {
                ScrollView {
                    if library.artists.isEmpty {
                        EmptyStateView(icon: "person.crop.circle", title: "No artists", message: "Add music to see artists here.")
                            .padding(.top, 60)
                    } else {
                        LazyVGrid(columns: gridColumns, spacing: 16) {
                            ForEach(library.artists, id: \.self) { artist in
                                NavigationLink {
                                    ArtistDetailView(artist: artist)
                                } label: {
                                    ArtistGridCell(artist: artist)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        // Extra clearance below the last row — see SongsTab's
                        // identical fix.
                        .padding(.bottom, 190)
                    }
                }
                .background(Color.clear.ignoresSafeArea())
            }
        }
        .onAppear {
            ArtistImageService.shared.prefetch(artists: library.artists)
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    columns = 1
                } label: {
                    Image(systemName: "list.bullet")
                        .foregroundStyle(columns == 1 ? AppTheme.dynamicAccent : AppTheme.textSecondary)
                }
                .buttonStyle(.plain)

                Button {
                    columns = 2
                } label: {
                    Image(systemName: "square.grid.2x2")
                        .foregroundStyle(columns == 2 ? AppTheme.dynamicAccent : AppTheme.textSecondary)
                }
                .buttonStyle(.plain)

                Button {
                    columns = 3
                } label: {
                    Image(systemName: "square.grid.3x3")
                        .foregroundStyle(columns == 3 ? AppTheme.dynamicAccent : AppTheme.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct ArtistRow: View {
    let artist: String
    @EnvironmentObject private var library: LibraryManager

    var body: some View {
        let artistSongs = library.songs(byArtist: artist)
        let songCount = artistSongs.count
        let albumCount = Set(artistSongs.map { $0.albumName }).count

        return HStack(spacing: 12) {
            ArtistAvatar(artist: artist, size: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(artist)
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                Text("\(albumCount) \(albumCount == 1 ? "album" : "albums") · \(songCount) \(songCount == 1 ? "song" : "songs")")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Artist Grid Cell (2/3-column layout)

private struct ArtistGridCell: View {
    let artist: String
    @EnvironmentObject private var library: LibraryManager

    var body: some View {
        let artistSongs = library.songs(byArtist: artist)
        let songCount = artistSongs.count
        let albumCount = Set(artistSongs.map { $0.albumName }).count

        return VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                ArtistAvatar(artist: artist, size: geo.size.width, cornerRadius: 8)
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)

            VStack(alignment: .leading, spacing: 2) {
                Text(artist)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(2)

                Text("\(albumCount) \(albumCount == 1 ? "album" : "albums") · \(songCount) \(songCount == 1 ? "song" : "songs")")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 2)
        }
    }
}
