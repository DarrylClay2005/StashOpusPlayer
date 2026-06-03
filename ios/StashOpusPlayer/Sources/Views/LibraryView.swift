import SwiftUI

// MARK: - Tab enum

private enum LibraryTab: String, CaseIterable {
    case songs     = "Songs"
    case artists   = "Artists"
    case albums    = "Albums"
    case genres    = "Genres"
    case playlists = "Playlists"
    case favorites = "Favorites"
}

// MARK: - LibraryView

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryManager
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var folderService: MusicFolderService

    @State private var selectedTab: LibraryTab = .songs
    @State private var searchText: String = ""
    @State private var debouncedSearch: String = ""
    @State private var showAddMusic = false

    // MARK: Filtered songs for Songs tab (uses debounced search)

    private var filteredSongs: [Song] {
        let query = debouncedSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return library.allSongs }
        return library.allSongs.filter { song in
            song.displayName.localizedCaseInsensitiveContains(query)
                || song.artistName.localizedCaseInsensitiveContains(query)
                || song.albumName.localizedCaseInsensitiveContains(query)
        }
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Custom scrollable tab bar
                LibraryTabBar(selectedTab: $selectedTab)
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                // Error banner
                if let error = library.errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(AppTheme.warning)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(AppTheme.warning)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(AppTheme.surface.opacity(0.5))
                }

                // Tab content
                tabContent
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.large)
            .toolbar { toolbarItems }
            .safeAreaInset(edge: .bottom) { MiniPlayerBar() }
            .sheet(isPresented: $showAddMusic) {
                AddMusicView()
                    .environmentObject(library)
                    .environmentObject(folderService)
            }
            .onAppear {
                // Always rescan the local Documents folder (picks up files added via Files app/Finder)
                library.scanLocalDocuments()
                // Rescan any user-selected watched folders
                library.scanWatchedFolders(using: folderService)
                // Request Apple Music library access if we have no songs yet
                if library.allSongs.isEmpty && !library.isScanning {
                    library.requestAccessAndScan()
                }
            }
            // Debounce search: wait 0.3 s after the user stops typing
            .onChange(of: searchText) { newValue in
                Task {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    if searchText == newValue {
                        debouncedSearch = newValue
                    }
                }
            }
        }
    }

    // MARK: Tab content switcher

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .songs:
            SongsTab(songs: filteredSongs, searchText: $searchText, showAddMusic: $showAddMusic)
        case .artists:
            ArtistsTab()
        case .albums:
            AlbumsTab()
        case .genres:
            GenresTab()
        case .playlists:
            PlaylistsView()
        case .favorites:
            FavoritesView()
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            if library.isScanning {
                ProgressView()
                    .tint(AppTheme.accent)
            } else {
                Button {
                    library.scanAll(folderService: folderService)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .tint(AppTheme.accent)
            }

            Button {
                showAddMusic = true
            } label: {
                Image(systemName: "plus")
            }
            .tint(AppTheme.accent)
        }
    }
}

// MARK: - Custom Tab Bar

private struct LibraryTabBar: View {
    @Binding var selectedTab: LibraryTab

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(LibraryTab.allCases, id: \.self) { tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedTab = tab
                        }
                    } label: {
                        Text(tab.rawValue)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .foregroundStyle(
                                selectedTab == tab ? AppTheme.textPrimary : AppTheme.textSecondary
                            )
                            .background {
                                Capsule(style: .continuous)
                                    .fill(selectedTab == tab ? AppTheme.accent : AppTheme.surface)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }
}

// MARK: - Songs Tab

private struct SongsTab: View {
    let songs: [Song]
    @Binding var searchText: String
    @Binding var showAddMusic: Bool
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var library: LibraryManager

    var body: some View {
        List {
            if songs.isEmpty {
                EmptyLibraryView(
                    isScanning: library.isScanning,
                    onAddMusic: { showAddMusic = true },
                    onScan: { library.requestAccessAndScan() }
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(songs) { song in
                    Button {
                        player.play(song: song, in: songs)
                    } label: {
                        SongRow(song: song, isCurrent: player.currentSong?.id == song.id)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(AppTheme.surface.opacity(0.5))
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .searchable(text: $searchText, prompt: "Search songs, artists, albums")
    }
}

// MARK: - Artists Tab

private struct ArtistsTab: View {
    @EnvironmentObject private var library: LibraryManager

    var body: some View {
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
    }
}

private struct ArtistRow: View {
    let artist: String
    @EnvironmentObject private var library: LibraryManager

    private var songCount: Int {
        library.songs(byArtist: artist).count
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(AppTheme.elevatedSurface)
                Image(systemName: "person.fill")
                    .foregroundStyle(AppTheme.accent)
                    .font(.system(size: 18))
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(artist)
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                Text("\(songCount) \(songCount == 1 ? "song" : "songs")")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Albums Tab

private struct AlbumsTab: View {
    @EnvironmentObject private var library: LibraryManager

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

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
                .padding(.vertical, 12)
            }
        }
        .background(AppTheme.background.ignoresSafeArea())
    }
}

private struct AlbumGridCell: View {
    let album: String
    @EnvironmentObject private var library: LibraryManager

    private var representativeSong: Song? {
        library.songs(inAlbum: album).first
    }

    private var artistName: String {
        representativeSong?.artistName ?? "Unknown Artist"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if let song = representativeSong {
                    ArtworkThumbnail(song: song, size: 160)
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AppTheme.surface)
                        .overlay {
                            Image(systemName: "square.stack.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(AppTheme.accent)
                        }
                        .frame(width: 160, height: 160)
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

// MARK: - Genres Tab

private struct GenresTab: View {
    @EnvironmentObject private var library: LibraryManager
    @EnvironmentObject private var player: AudioPlayerManager

    var body: some View {
        List {
            if library.genres.isEmpty {
                EmptyStateView(icon: "music.note.list", title: "No genres", message: "Add music to see genres here.")
                    .listRowBackground(Color.clear)
            } else {
                ForEach(library.genres, id: \.self) { genre in
                    Button {
                        let songs = library.songs(inGenre: genre)
                        player.setQueue(songs, startIndex: 0, autoplay: true)
                    } label: {
                        GenreRow(genre: genre)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(AppTheme.surface.opacity(0.5))
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}

private struct GenreRow: View {
    let genre: String
    @EnvironmentObject private var library: LibraryManager

    private var songCount: Int {
        library.songs(inGenre: genre).count
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AppTheme.elevatedSurface)
                Image(systemName: "music.note.list")
                    .foregroundStyle(AppTheme.accent)
                    .font(.system(size: 16))
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(genre)
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                Text("\(songCount) \(songCount == 1 ? "song" : "songs")")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }

            Spacer()

            Image(systemName: "play.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(AppTheme.accent)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Empty Library State (Songs tab)

private struct EmptyLibraryView: View {
    let isScanning: Bool
    let onAddMusic: () -> Void
    let onScan: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: isScanning ? "waveform" : "music.note.list")
                .font(.system(size: 56, weight: .medium))
                .foregroundStyle(AppTheme.accent)

            Text(isScanning ? "Scanning…" : "No music yet")
                .font(.title2.weight(.bold))
                .foregroundStyle(AppTheme.textPrimary)

            if !isScanning {
                Text("Add music from your Files app, iTunes library, or connect via USB")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                VStack(spacing: 12) {
                    Button {
                        onAddMusic()
                    } label: {
                        Label("Add Music", systemImage: "plus.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accent)

                    Button {
                        onScan()
                    } label: {
                        Label("Scan Apple Music Library", systemImage: "arrow.clockwise")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(AppTheme.accent)
                }
                .padding(.horizontal, 32)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

// MARK: - Shared Empty State

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(AppTheme.accent)

            Text(title)
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 52)
        .padding(.horizontal, 24)
    }
}
