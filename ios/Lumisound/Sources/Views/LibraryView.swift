import SwiftUI
import MediaPlayer

// MARK: - Tab enum

private enum LibraryTab: String, CaseIterable {
    case songs     = "Songs"
    case artists   = "Artists"
    case albums    = "Albums"
    case folders   = "Folders"
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
    @EnvironmentObject private var account: AccountService
    @EnvironmentObject private var streaming: StreamingService

    @AppStorage("autoCloudBackup") private var autoCloudBackup: Bool = false

    @State private var selectedTab: LibraryTab = .songs
    @State private var searchText: String = ""
    @State private var debouncedSearch: String = ""
    @State private var showAddMusic = false
    @State private var showOpenSharedPlaylist = false
    @State private var backupSyncTask: Task<Void, Never>?

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

                // Error banner — gains a real "Retry" button when the crash-loop
                // guard is active, since its message explicitly tells the user
                // to tap one (see LibraryManager.retryMediaLibraryScanAfterCrashGuard).
                if let error = library.errorMessage {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(AppTheme.warning)
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(AppTheme.warning)
                            Spacer()
                        }
                        if library.scanCrashGuardActive {
                            Button {
                                library.retryMediaLibraryScanAfterCrashGuard()
                            } label: {
                                Label("Retry", systemImage: "arrow.clockwise")
                                    .font(.caption.weight(.semibold))
                            }
                            .buttonStyle(.bordered)
                            .tint(AppTheme.warning)
                        }
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
            .sheet(isPresented: $showOpenSharedPlaylist) {
                CollaborativePlaylistView(playlist: nil)
                    .environmentObject(player)
                    .environmentObject(account)
                    .environmentObject(streaming)
                    .environmentObject(library)
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
                scheduleBackupSync()
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
            // Auto-Backup originally only fired on the "download from search" path,
            // so anything imported, scanned from Documents, or pulled from a watched
            // folder never made it to the cloud. Re-check whenever the library's
            // song count settles — scheduleBackupSync debounces so a multi-batch
            // scan triggers one sync, not dozens, and backUpLibraryIfNeeded itself
            // skips songs already present server-side.
            .onChange(of: library.allSongs.count) { _ in
                scheduleBackupSync()
            }
        }
    }

    /// Debounces auto-backup catch-up so rapid library changes (a scan landing in
    /// several batches, an import finishing) collapse into a single sync pass.
    private func scheduleBackupSync() {
        guard autoCloudBackup, account.isLoggedIn, let token = account.token else { return }
        backupSyncTask?.cancel()
        let songs = library.allSongs
        backupSyncTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            streaming.backUpLibraryIfNeeded(songs: songs, token: token)
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
        case .folders:
            FoldersTab()
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
            Button {
                showOpenSharedPlaylist = true
            } label: {
                Image(systemName: "link.badge.plus")
            }
            .tint(AppTheme.dynamicAccent)

            if library.isScanning {
                ProgressView()
                    .tint(AppTheme.dynamicAccent)
            } else {
                Button {
                    Task {
                        // Thorough re-scan: picks up new, deleted, AND changed-in-place
                        // files (not just new ones), re-scans watched folders + Apple
                        // Music, then pulls the latest favorites/playlists/settings from
                        // the server — all without restarting the app.
                        await library.refreshAll(folderService: folderService)
                        if account.isLoggedIn {
                            await account.pullSync(library: library, player: player)
                        }
                        if let result = library.lastScanResult {
                            ToastCenter.shared.show(result, category: .success, icon: "arrow.clockwise")
                        }
                    }
                } label: {
                    if library.isScanning {
                        ProgressView().tint(AppTheme.dynamicAccent)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .tint(AppTheme.dynamicAccent)
                .disabled(library.isScanning)
            }

            Button {
                showAddMusic = true
            } label: {
                Image(systemName: "plus")
            }
            .tint(AppTheme.dynamicAccent)
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
                                selectedTab == tab ? .white : AppTheme.textSecondary
                            )
                            .background {
                                if selectedTab == tab {
                                    Capsule(style: .continuous)
                                        .fill(
                                            LinearGradient(
                                                colors: [AppTheme.dynamicAccent, AppTheme.accentSoft],
                                                startPoint: .topLeading, endPoint: .bottomTrailing
                                            )
                                        )
                                        .shadow(color: AppTheme.dynamicAccent.opacity(0.4), radius: 6, x: 0, y: 3)
                                } else {
                                    Capsule(style: .continuous)
                                        .fill(AppTheme.surface.opacity(0.6))
                                        .overlay(Capsule().stroke(.white.opacity(0.06), lineWidth: 1))
                                }
                            }
                    }
                    .buttonStyle(PressableButtonStyle())
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
    /// Tracks whether the entrance animation has already fired for the current song list.
    @State private var didAnimateEntrance: Bool = false

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: songColumns)
    }

    var body: some View {
        VStack(spacing: 0) {
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
                                // Windowed artwork prefetch: the initial onAppear below
                                // only warms the first 30 — fine at the top of a 1,100-song
                                // library, useless once the user scrolls past row 200.
                                // `List` only calls onAppear for rows that actually become
                                // visible, so this stays cheap (and `prefetch` itself skips
                                // anything already cached) while keeping artwork ready a
                                // little ahead of and behind wherever the user is scrolling.
                                .onAppear {
                                    let lower = max(0, index - 8)
                                    let upper = min(songs.count, index + 24)
                                    guard lower < upper else { return }
                                    ArtworkService.shared.prefetch(songs: Array(songs[lower..<upper]))
                                }
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
        // Native search field — replaces a custom inline bar toggled from the
        // toolbar. That approach competed for space with 6 other trailing nav-bar
        // buttons (3 from LibraryView + 3 layout toggles here), and the search
        // icon — last in line — ended up clipped/unreachable on most screens,
        // which is why "library search" appeared broken: users could never
        // actually open the search field. `.searchable` integrates with the
        // large-title nav bar instead of competing for toolbar space, matching
        // the proven pattern already used in PlaylistDetailView/StreamSearchView.
        //
        // `displayMode: .always` pins the field below the nav bar so it stays
        // visible while scrolling — the default `.automatic` placement collapses
        // the bar into the title on scroll-down, which is exactly the "search
        // bar randomly disappears" report (it only reappeared on scroll-to-top).
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search songs, artists, albums…"
        )
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                // Layout toggles
                Button {
                    UserDefaults.standard.set(1, forKey: "library_songs_columns")
                } label: {
                    Image(systemName: "list.bullet")
                        .foregroundStyle(songColumns == 1 ? AppTheme.dynamicAccent : AppTheme.textSecondary)
                }
                .buttonStyle(.plain)

                Button {
                    UserDefaults.standard.set(2, forKey: "library_songs_columns")
                } label: {
                    Image(systemName: "square.grid.2x2")
                        .foregroundStyle(songColumns == 2 ? AppTheme.dynamicAccent : AppTheme.textSecondary)
                }
                .buttonStyle(.plain)

                Button {
                    UserDefaults.standard.set(3, forKey: "library_songs_columns")
                } label: {
                    Image(systemName: "square.grid.3x3")
                        .foregroundStyle(songColumns == 3 ? AppTheme.dynamicAccent : AppTheme.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Artists Tab

private struct ArtistsTab: View {
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
                        .padding(.vertical, 12)
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

// MARK: - Folders Tab
//
// Groups imported songs by the first subdirectory of "Imported Music" that
// contains them. Unlike the Albums tab, grouping is done by filesystem path —
// every song inside a folder shows up here regardless of its album metadata tag.

private struct FolderEntry: Identifiable {
    let id: String        // folder name (unique within Imported Music)
    let dirURL: URL
    let songs: [Song]
}

private struct FoldersTab: View {
    @EnvironmentObject private var library: LibraryManager
    @AppStorage("library_folders_columns") private var columns: Int = 2

    @State private var folders: [FolderEntry] = []

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: columns)
    }

    /// Groups allSongs by their top-level subdirectory under "Imported Music".
    /// Computed off the render path (see `.task(id:)` below) so large libraries
    /// don't re-run this O(n) grouping/sort on every body evaluation.
    private func computeFolders() -> [FolderEntry] {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return []
        }
        let importDir = docs.appendingPathComponent("Imported Music").standardizedFileURL
        let importPath = importDir.path

        var groups: [String: (url: URL, songs: [Song])] = [:]
        for song in library.allSongs {
            guard let url = song.url else { continue }
            let songPath = url.standardizedFileURL.path
            guard songPath.hasPrefix(importPath + "/") else { continue }
            // Path after "Imported Music/"
            let remainder = String(songPath.dropFirst(importPath.count + 1))
            let parts = remainder.split(separator: "/", maxSplits: 1)
            guard parts.count >= 2 else { continue }   // skip root-level files
            let name = String(parts[0])
            if groups[name] == nil {
                groups[name] = (importDir.appendingPathComponent(name), [])
            }
            groups[name]!.songs.append(song)
        }

        return groups
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            .map { FolderEntry(id: $0.key, dirURL: $0.value.url, songs: $0.value.songs) }
    }

    var body: some View {
        ScrollView {
            if folders.isEmpty {
                EmptyStateView(
                    icon: "folder",
                    title: "No folders",
                    message: "Create subfolders inside \"Imported Music\" in the Files app to organise your tracks."
                )
                .padding(.top, 60)
            } else {
                LazyVGrid(columns: gridColumns, spacing: 16) {
                    ForEach(folders) { folder in
                        NavigationLink {
                            LocalFolderDetailView(folderName: folder.id, folderURL: folder.dirURL)
                        } label: {
                            FolderGridCell(folder: folder)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .background(Color.clear.ignoresSafeArea())
        .task(id: library.allSongs.count) {
            folders = computeFolders()
        }
        .toolbar {
            // Mirrors SongsTab's column-toggle buttons (rather than a Menu) so
            // switching the Folders layout works the same, directly-tappable way.
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    columns = 1
                } label: {
                    Image(systemName: "rectangle.grid.1x2")
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

private struct FolderGridCell: View {
    let folder: FolderEntry

    private var representativeSong: Song? { folder.songs.first }
    private var trackCount: Int { folder.songs.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // GeometryReader sizes the artwork to the actual column width — like
            // SongGridCell, a hardcoded size here clips (3-column) or under-fills
            // (1-column) the cell depending on how many columns are selected.
            GeometryReader { geo in
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AppTheme.surface)

                    if let song = representativeSong {
                        ArtworkThumbnail(song: song, size: geo.size.width)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    } else {
                        Image(systemName: "folder.fill")
                            .font(.system(size: geo.size.width * 0.25))
                            .foregroundStyle(AppTheme.dynamicAccent)
                    }

                    // Folder badge overlay
                    VStack {
                        Spacer()
                        HStack {
                            Image(systemName: "folder.fill")
                                .font(.caption2)
                            Spacer()
                        }
                        .padding(6)
                        .adaptiveGlass(in: Rectangle())
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)

            VStack(alignment: .leading, spacing: 2) {
                Text(folder.id)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(2)

                Text("\(trackCount) \(trackCount == 1 ? "track" : "tracks")")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textSecondary)
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
                    .foregroundStyle(AppTheme.dynamicAccent)
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
                .foregroundStyle(AppTheme.dynamicAccent)
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
                .foregroundStyle(AppTheme.dynamicAccent)

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
                    .tint(AppTheme.dynamicAccent)

                    Button {
                        onScan()
                    } label: {
                        Label("Scan Apple Music Library", systemImage: "arrow.clockwise")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(AppTheme.dynamicAccent)
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
                .foregroundStyle(AppTheme.dynamicAccent)

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
