import SwiftUI
import MediaPlayer

// MARK: - Tab enum

private enum LibraryTab: String, CaseIterable {
    case songs     = "Songs"
    case artists   = "Artists"
    case albums    = "Albums"
    case genres    = "Genres"
    case playlists = "Playlists"
    case favorites = "Favorites"
    case moods     = "Moods"
}

// MARK: - LibraryView

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryManager
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var folderService: MusicFolderService
    @EnvironmentObject private var moodService: MoodPlaylistService

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
            .background(GalleryBackgroundView().ignoresSafeArea())
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar { toolbarItems }
            .safeAreaInset(edge: .bottom) { MiniPlayerBar() }
            .sheet(isPresented: $showAddMusic) {
                AddMusicView()
                    .environmentObject(library)
                    .environmentObject(folderService)
            }
            .onAppear {
                let scanSource = UserDefaults.standard.string(forKey: "default_scan_source") ?? "apple_music"
                library.scanWatchedFolders(using: folderService)
                switch scanSource {
                case "app_storage":
                    library.scanLocalDocuments()
                case "both":
                    library.scanLocalDocuments()
                    library.requestAccessAndScan()
                default: // "apple_music" — also scan Documents for transferred files
                    library.scanLocalDocuments()
                    if library.allSongs.isEmpty && !library.isScanning {
                        library.requestAccessAndScan()
                    }
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
        case .moods:
            MoodPlaylistsView()
                .environmentObject(moodService)
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

    @AppStorage("library_songs_columns") private var songColumns: Int = 1
    @State private var showSearch: Bool = false
    @FocusState private var searchFocused: Bool
    /// Tracks whether the entrance animation has already fired for the current song list.
    @State private var didAnimateEntrance: Bool = false

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: songColumns)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Inline search bar — shown when search icon is tapped
            if showSearch {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15))
                        .foregroundStyle(AppTheme.textSecondary)
                    TextField("Search songs, artists, albums…", text: $searchText)
                        .foregroundStyle(AppTheme.textPrimary)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($searchFocused)
                        .submitLabel(.search)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(AppTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onAppear { searchFocused = true }
            }

            // Content — list or grid
            Group {
                if songColumns == 1 {
                    List {
                        if songs.isEmpty {
                            EmptyLibraryView(
                                isScanning: library.isScanning,
                                onAddMusic: { showAddMusic = true },
                                onScan: { library.requestAccessAndScan() }
                            )
                            .listRowBackground(Color.clear)
                        } else {
                            ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                                Button {
                                    player.play(song: song, in: songs)
                                } label: {
                                    SongRow(song: song, isCurrent: player.currentSong?.id == song.id)
                                }
                                .buttonStyle(.plain)
                                .listRowBackground(AppTheme.surface.opacity(0.5))
                                // Staggered entrance: first 20 rows slide in from the left
                                .modifier(StaggeredSlideInModifier(
                                    index: index,
                                    maxIndex: 19,
                                    didAnimate: didAnimateEntrance
                                ))
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .onAppear {
                        guard !didAnimateEntrance else { return }
                        didAnimateEntrance = true
                    }
                    .onChange(of: songs.first?.id) { _ in
                        // Re-trigger entrance animation when the song list changes substantially
                        didAnimateEntrance = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            didAnimateEntrance = true
                        }
                    }
                } else {
                    ScrollView {
                        if songs.isEmpty {
                            EmptyLibraryView(
                                isScanning: library.isScanning,
                                onAddMusic: { showAddMusic = true },
                                onScan: { library.requestAccessAndScan() }
                            )
                            .padding(.top, 60)
                        } else {
                            LazyVGrid(columns: gridColumns, spacing: 12) {
                                ForEach(songs) { song in
                                    Button {
                                        player.play(song: song, in: songs)
                                    } label: {
                                        SongGridCell(song: song, isCurrent: player.currentSong?.id == song.id)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                        }
                    }
                    .background(Color.clear.ignoresSafeArea())
                }
            }
        }
        .onAppear {
            // Warm the first 30 songs' artwork at background priority so grid
            // cells have images ready before the user scrolls to them.
            ArtworkService.shared.prefetch(songs: Array(songs.prefix(30)))
        }
        .onChange(of: songs.count) { _ in
            // Re-trigger prefetch when the song list grows (e.g. after a scan).
            ArtworkService.shared.prefetch(songs: Array(songs.prefix(30)))
        }
        .animation(.easeInOut(duration: 0.2), value: showSearch)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                // Layout toggles
                Button {
                    UserDefaults.standard.set(1, forKey: "library_songs_columns")
                } label: {
                    Image(systemName: "list.bullet")
                        .foregroundStyle(songColumns == 1 ? AppTheme.accent : AppTheme.textSecondary)
                }
                .buttonStyle(.plain)

                Button {
                    UserDefaults.standard.set(2, forKey: "library_songs_columns")
                } label: {
                    Image(systemName: "square.grid.2x2")
                        .foregroundStyle(songColumns == 2 ? AppTheme.accent : AppTheme.textSecondary)
                }
                .buttonStyle(.plain)

                Button {
                    UserDefaults.standard.set(3, forKey: "library_songs_columns")
                } label: {
                    Image(systemName: "square.grid.3x3")
                        .foregroundStyle(songColumns == 3 ? AppTheme.accent : AppTheme.textSecondary)
                }
                .buttonStyle(.plain)

                // Search toggle
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showSearch.toggle()
                        if !showSearch { searchText = "" }
                    }
                } label: {
                    Image(systemName: showSearch ? "magnifyingglass.circle.fill" : "magnifyingglass")
                        .foregroundStyle(showSearch ? AppTheme.accent : AppTheme.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Song Grid Cell

private struct SongGridCell: View {
    let song: Song
    let isCurrent: Bool
    @EnvironmentObject private var library: LibraryManager

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // GeometryReader ensures the artwork fills the actual column width instead of
            // being locked to the hardcoded 120pt size, which caused clipping/spacing issues.
            GeometryReader { geo in
                ArtworkThumbnail(song: song, size: geo.size.width)
                    .overlay(alignment: .bottomTrailing) {
                        if isCurrent {
                            Image(systemName: "waveform")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(4)
                                .background(AppTheme.accent, in: Circle())
                                .padding(4)
                        }
                    }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(song.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isCurrent ? AppTheme.accent : AppTheme.textPrimary)
                    .lineLimit(2)
                Text(song.artistName)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 2)
        }
        .padding(6)
        .background(AppTheme.surface.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
                .padding(.vertical, 12)
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
                        .tint(AppTheme.accent)
                }
            }
        }
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

// MARK: - StaggeredSlideInModifier

/// Slides a view in from the left with a per-index delay, capped at `maxIndex`.
/// Once `didAnimate` flips to true the animation fires once and the view
/// settles in its final position.
private struct StaggeredSlideInModifier: ViewModifier {
    let index: Int
    let maxIndex: Int
    let didAnimate: Bool

    private var cappedIndex: Int { min(index, maxIndex) }
    private var delay: Double { Double(cappedIndex) * 0.03 }

    func body(content: Content) -> some View {
        content
            .opacity(didAnimate ? 1 : 0)
            .offset(x: didAnimate ? 0 : -30)
            .animation(
                didAnimate
                    ? .spring(response: 0.38, dampingFraction: 0.78).delay(delay)
                    : .none,
                value: didAnimate
            )
    }
}
