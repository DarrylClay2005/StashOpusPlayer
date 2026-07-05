import SwiftUI
import MediaPlayer

// MARK: - Albums Tab

struct AlbumsTab: View {
    @EnvironmentObject private var library: LibraryManager

    @AppStorage("library_albums_columns") private var albumColumns: Int = 2

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: albumColumns)
    }

    var body: some View {
        ScrollView {
            if library.albums.isEmpty {
                EmptyStateView(icon: "square.stack", title: "No albums", message: "Add music to see albums here.")
                    .padding(.top, 60)
            } else {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(library.albums, id: \.self) { album in
                        NavigationLink {
                            AlbumDetailView(album: album)
                        } label: {
                            AlbumGridCell(album: album)
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
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        albumColumns = 1
                    } label: {
                        Label("1 Column", systemImage: "rectangle.grid.1x2")
                    }
                    Button {
                        albumColumns = 2
                    } label: {
                        Label("2 Columns", systemImage: "square.grid.2x2")
                    }
                    Button {
                        albumColumns = 3
                    } label: {
                        Label("3 Columns", systemImage: "square.grid.3x3")
                    }
                } label: {
                    Image(systemName: albumColumns == 1 ? "rectangle.grid.1x2" : albumColumns == 2 ? "square.grid.2x2" : "square.grid.3x3")
                        .tint(AppTheme.dynamicAccent)
                }
            }
        }
    }
}

private struct AlbumGridCell: View {
    let album: String
    @EnvironmentObject private var library: LibraryManager

    var body: some View {
        let representativeSong = library.songs(inAlbum: album).first
        let artistName = representativeSong?.artistName ?? "Unknown Artist"

        return VStack(alignment: .leading, spacing: 6) {
            // GeometryReader sizes the artwork to the actual column width — like
            // SongGridCell/FolderGridCell, a hardcoded size here clips (3-column)
            // or under-fills (1-column) the cell depending on the chosen layout.
            GeometryReader { geo in
                if let song = representativeSong {
                    ArtworkThumbnail(song: song, size: geo.size.width)
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AppTheme.surface)
                        .overlay {
                            Image(systemName: "square.stack.fill")
                                .font(.system(size: geo.size.width * 0.25))
                                .foregroundStyle(AppTheme.dynamicAccent)
                        }
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(album)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(2)

                Text(artistName)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 2)
        }
    }
}
