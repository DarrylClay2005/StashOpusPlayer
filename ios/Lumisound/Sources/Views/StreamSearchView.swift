import SwiftUI
import UniformTypeIdentifiers

// MARK: - StreamSearchView

struct StreamSearchView: View {

    @EnvironmentObject private var streaming: StreamingService
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var library: LibraryManager
    @EnvironmentObject private var account: AccountService

    @State private var searchText        = ""
    @State private var selectedSource    = "youtube"
    @State private var loadingTrackID:   String? = nil
    @State private var downloadingTrackIDs: Set<String> = []
    @State private var downloadedTrackIDs: Set<String> = []
    @State private var failedTrackIDs: Set<String> = []
    @State private var healthOK: Bool? = nil
    @State private var showHealthToast   = false

    // Server library download tracking (separate from streaming downloads)
    @State private var downloadingServerTrackIDs: Set<String> = []
    @State private var downloadedServerTrackIDs: Set<String> = []

    @AppStorage("autoCloudBackup") private var autoCloudBackup: Bool = false

    // My Library upload
    @State private var showUploadPicker = false
    @State private var deletingUserTrackPath: String? = nil
    @State private var selectedInfoTrack: UserMusicTrack? = nil

    // Playlist batch download
    @State private var isDownloadingAll   = false
    @State private var downloadAllDone    = 0
    @State private var downloadAllTotal   = 0

    // Animation: tracks results version so we can stagger the fade-in
    @State private var resultsAnimationToken: UUID = UUID()

    // Trending searches & autocomplete suggestions
    @State private var trendingQueries: [SearchQueryCount] = []
    @State private var suggestions: [SearchQueryCount] = []

    private let sources = ["youtube", "soundcloud", "server", "my"]

    var body: some View {
        NavigationStack {
            Group {
                if streaming.isConfigured {
                    configuredBody
                } else {
                    notConfiguredView
                }
            }
            .navigationTitle("Cloud Services")
            .navigationBarTitleDisplayMode(.large)
            .background(GalleryBackgroundView().ignoresSafeArea())
            .toolbarBackground(.hidden, for: .navigationBar)
            // Consolidates the server-side features here (the "Cloud Services" hub)
            // so everything that talks to the bridge/account lives in one tab.
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        NavigationLink(destination: SubscriptionsView()) {
                            Label("Subscriptions & Tracked Playlists", systemImage: "person.crop.circle.badge.checkmark")
                        }
                        NavigationLink(destination: DiscoverView()) {
                            Label("Discover", systemImage: "sparkles")
                        }
                        NavigationLink(destination: DiscoverMixView()) {
                            Label("Discover Mix", systemImage: "wand.and.stars")
                        }
                        if account.isLoggedIn {
                            NavigationLink(destination: SharedPlaylistsView()) {
                                Label("Shared With Me", systemImage: "person.2.fill")
                            }
                        }
                    } label: {
                        Image(systemName: "square.grid.2x2")
                    }
                }
            }
            // Every other tab (Library, Queue, etc.) shows MiniPlayerBar so tapping a
            // track gives instant visual confirmation that playback started. This tab
            // was missing it — tapping ▶ on a search result appeared to do nothing
            // because the only feedback (the mini player appearing/updating) happened
            // off-screen on a different tab, making "play" feel like a no-op.
            .safeAreaInset(edge: .bottom) {
                MiniPlayerBar()
            }
        }
    }

    // MARK: — Not configured

    private var notConfiguredView: some View {
        VStack(spacing: 20) {
            Image(systemName: "server.rack")
                .font(.system(size: 56))
                .foregroundStyle(AppTheme.textSecondary)

            Text("Streaming Unavailable")
                .font(AppTheme.headlineFont(size: 18))
                .foregroundStyle(AppTheme.textPrimary)

            Text("Streaming search is currently unavailable. Please try again later.")
                .font(AppTheme.bodyFont(size: 14))
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            NavigationLink(destination: SettingsView()) {
                Label("Open Settings", systemImage: "gearshape")
                    .font(AppTheme.bodyFont(size: 15))
                    .foregroundStyle(AppTheme.background)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(AppTheme.dynamicAccent, in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: — Configured body

    private var configuredBody: some View {
        VStack(spacing: 0) {
            // Source picker
            Picker("Source", selection: $selectedSource) {
                ForEach(sources, id: \.self) { src in
                    Text(sourceLabel(src)).tag(src)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .onChange(of: selectedSource) { _ in
                if !searchText.isEmpty {
                    triggerSearch()
                }
            }

            // Error banner
            if let error = streaming.errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(AppTheme.warning)
                    Text(error)
                        .font(AppTheme.bodyFont(size: 13))
                        .foregroundStyle(AppTheme.warning)
                        .lineLimit(2)
                    Spacer()
                    if !searchText.isEmpty {
                        Button("Retry") {
                            triggerSearch()
                        }
                        .font(AppTheme.bodyFont(size: 13).weight(.semibold))
                        .foregroundStyle(AppTheme.dynamicAccent)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(AppTheme.warning.opacity(0.12))
            }

            // Results
            if selectedSource == "server" {
                serverResultsBody
            } else if selectedSource == "my" {
                userLibraryBody
            } else {
                streamResultsBody
            }
        }
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: selectedSource == "server" ? "Search server library…"
                : selectedSource == "my"    ? "Search your library…"
                : "Search or paste a YouTube playlist URL…"
        )
        .onSubmit(of: .search) {
            triggerSearch()
        }
        .onChange(of: searchText) { newValue in
            if newValue.isEmpty {
                streaming.searchResults = []
                streaming.serverTracks = []
                streaming.errorMessage = nil
                streaming.isPlaylistResult = false
                suggestions = []
                return
            }
            if selectedSource == "youtube" || selectedSource == "soundcloud" {
                Task {
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    if searchText == newValue {
                        suggestions = await streaming.searchSuggestions(query: newValue)
                    }
                }
            }
            // Debounced auto-search — mirrors LibraryView's 300ms pattern (the only
            // existing trigger here was `.onSubmit(of: .search)`, which fires solely
            // on the keyboard's Search/Return key). Most users type a query and expect
            // results to appear, never realizing they need to explicitly submit —
            // which is exactly what made this "search" look broken/unresponsive.
            // 400ms (vs Library's 300ms) gives the network round-trip to the bridge
            // a beat of slack so fast typists don't fire a search per keystroke.
            Task {
                try? await Task.sleep(nanoseconds: 400_000_000)
                if searchText == newValue {
                    triggerSearch()
                }
            }
        }
        .onChange(of: streaming.searchResults.count) { _ in
            resultsAnimationToken = UUID()
            refreshDownloadedStatus()
        }
        .onChange(of: streaming.serverTracks.count) { _ in
            refreshDownloadedStatus()
        }
        // `library.allSongs` only settles after the initial scan (and after any
        // subfolder/Force Metadata rescan) completes — re-check downloaded status
        // whenever it changes so subfolder-imported tracks correctly flip their
        // download icon to "already downloaded" instead of staying stuck on
        // "not downloaded" forever.
        .onChange(of: library.allSongs.count) { _ in
            refreshDownloadedStatus()
        }
        // When a playlist resolves, freshly scan the local library FIRST so
        // already-owned tracks (including ones in subfolders or restored from a
        // backup, which a stale `allSongs` would miss) are flagged as downloaded
        // immediately as the playlist appears — instead of showing as downloadable
        // until some later scan happens to settle.
        .onChange(of: streaming.isPlaylistResult) { isPlaylist in
            guard isPlaylist else { return }
            Task {
                await library.scanLocalDocumentsAsync()
                refreshDownloadedStatus()
            }
        }
        // Playback failures (expired CDN URL, YouTube bot-detection, network errors, etc.)
        // surface only on `player.errorMessage`, which previously had no visible home
        // outside Settings → Audio. Mirroring it into the banner here means tapping ▶
        // and having the stream fail to load shows *something* instead of looking like
        // the tap did nothing.
        .onChange(of: player.errorMessage) { newValue in
            if let message = newValue {
                streaming.errorMessage = message
            }
        }
        .onChange(of: selectedSource) { src in
            if src == "my" {
                guard let token = account.token else { return }
                Task { await streaming.fetchUserMusic(token: token) }
            } else if src == "server" {
                // Browse the whole server library on open (empty query) so the
                // Server tab actually shows content instead of an empty prompt.
                Task { await streaming.searchServerLibrary(query: searchText) }
            }
        }
        .onAppear {
            if selectedSource == "my", let token = account.token {
                Task { await streaming.fetchUserMusic(token: token) }
            }
            if selectedSource == "server" {
                Task { await streaming.searchServerLibrary(query: searchText) }
            }
            if trendingQueries.isEmpty {
                Task { trendingQueries = await streaming.searchTrending() }
            }
            refreshDownloadedStatus()
        }
        // fileImporter must be at this level (NavigationStack content root), NOT inside
        // a nested List or conditional branch — SwiftUI can't present the picker from deep hierarchy.
        .sheet(item: $selectedInfoTrack) { track in
            UserMusicInfoSheet(track: track)
        }
        .fileImporter(
            isPresented: $showUploadPicker,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: true
        ) { result in
            guard let token = account.token else { return }
            switch result {
            case .success(let urls):
                Task {
                    for url in urls {
                        let didAccess = url.startAccessingSecurityScopedResource()
                        do {
                            try await streaming.uploadToUserLibrary(fileURL: url, token: token)
                        } catch {
                            streaming.errorMessage = "Upload failed: \(error.localizedDescription)"
                        }
                        if didAccess { url.stopAccessingSecurityScopedResource() }
                    }
                    await streaming.fetchUserMusic(token: token)
                }
            case .failure(let error):
                streaming.errorMessage = "File picker error: \(error.localizedDescription)"
            }
        }
    }

    // MARK: — Streaming results (YouTube / SoundCloud)

    private var streamResultsBody: some View {
        Group {
            if streaming.isSearching || streaming.isResolvingPlaylist {
                Spacer()
                ProgressView(streaming.isResolvingPlaylist ? "Loading playlist…" : "Searching…")
                    .tint(AppTheme.dynamicAccent)
                    .foregroundStyle(AppTheme.textSecondary)
                Spacer()
            } else if searchText.isEmpty {
                trendingSearchesBody
            } else if streaming.searchResults.isEmpty {
                VStack(spacing: 0) {
                    if !suggestions.isEmpty {
                        suggestionsBody
                    }
                    Spacer()
                    Text("No results for \"\(searchText)\"")
                        .font(AppTheme.bodyFont(size: 15))
                        .foregroundStyle(AppTheme.textSecondary)
                    Spacer()
                }
            } else {
                VStack(spacing: 0) {
                    // Playlist banner — only shown after a successful playlist resolve
                    if streaming.isPlaylistResult && !streaming.searchResults.isEmpty {
                        VStack(spacing: 8) {
                            HStack(spacing: 10) {
                                Image(systemName: "music.note.list")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(AppTheme.dynamicAccent)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Playlist")
                                        .font(AppTheme.bodyFont(size: 11).weight(.semibold))
                                        .foregroundStyle(AppTheme.textSecondary)
                                        .kerning(0.6)
                                    Text("\(streaming.searchResults.count) tracks")
                                        .font(AppTheme.bodyFont(size: 15).weight(.semibold))
                                        .foregroundStyle(AppTheme.textPrimary)
                                }
                                Spacer()
                                if isDownloadingAll {
                                    HStack(spacing: 6) {
                                        ProgressView()
                                            .tint(AppTheme.dynamicAccent)
                                            .scaleEffect(0.8)
                                        Text("\(downloadAllDone)/\(downloadAllTotal)")
                                            .font(AppTheme.monoFont(size: 13))
                                            .foregroundStyle(AppTheme.textSecondary)
                                    }
                                } else if !failedTrackIDs.isEmpty {
                                    // Only the tracks that failed last time are retried — no
                                    // full search/resolve refresh, unlike the generic error
                                    // banner's "Retry" which re-resolves the whole playlist.
                                    Button {
                                        handleRetryFailedDownloads()
                                    } label: {
                                        Label("Retry \(failedTrackIDs.count)", systemImage: "arrow.clockwise")
                                            .font(AppTheme.bodyFont(size: 13).weight(.semibold))
                                            .foregroundStyle(AppTheme.warning)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 7)
                                            .adaptiveGlass(in: Capsule(), fallback: AppTheme.warning.opacity(0.15))
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    Button {
                                        handleDownloadAll()
                                    } label: {
                                        Label("Download All", systemImage: "arrow.down.circle.fill")
                                            .font(AppTheme.bodyFont(size: 13).weight(.semibold))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 7)
                                            .adaptiveGlass(tint: AppTheme.dynamicAccent, in: Capsule(), fallback: AppTheme.dynamicAccent)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }

                            // Determinate progress bar while a "Download All" run is active.
                            if isDownloadingAll && downloadAllTotal > 0 {
                                ProgressView(value: Double(downloadAllDone), total: Double(downloadAllTotal))
                                    .tint(AppTheme.dynamicAccent)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(AppTheme.surface)
                    }

                    List {
                        // Group results into per-source sections (YouTube / SoundCloud)
                        // so the user can clearly tell which platform each result came
                        // from. Most single-source searches will only populate one
                        // section, but playlist resolves can mix sources.
                        ForEach(groupedResults, id: \.source) { group in
                            Section {
                                ForEach(Array(group.tracks.enumerated()), id: \.element.id) { localIndex, track in
                                    let globalIndex = (streaming.searchResults.firstIndex(where: { $0.id == track.id }) ?? localIndex)
                                    StreamTrackRow(
                                        track: track,
                                        isLoading: loadingTrackID == track.id,
                                        isDownloading: downloadingTrackIDs.contains(track.id),
                                        isDownloaded: downloadedTrackIDs.contains(track.id),
                                        onPlay: { handlePlay(track: track) },
                                        onAddToQueue: { handleAddToQueue(track: track) },
                                        onDownload: { handleDownload(track: track) }
                                    )
                                    .listRowBackground(AppTheme.surface)
                                    .listRowSeparatorTint(AppTheme.background)
                                    // Staggered fade-in when results first appear
                                    .modifier(StaggeredFadeInModifier(index: globalIndex, token: resultsAnimationToken))
                                    .contextMenu {
                                        Button {
                                            handlePlayNext(track: track)
                                        } label: {
                                            Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
                                        }
                                        Button {
                                            handleAddToQueue(track: track)
                                        } label: {
                                            Label("Add to Queue", systemImage: "text.line.last.and.arrowtriangle.forward")
                                        }
                                        Button {
                                            handleDownload(track: track)
                                        } label: {
                                            Label("Download", systemImage: "arrow.down.circle")
                                        }
                                        if !track.youtubeURL.isEmpty, let linkURL = URL(string: track.youtubeURL) {
                                            Divider()
                                            Button {
                                                UIPasteboard.general.string = track.youtubeURL
                                            } label: {
                                                Label("Copy Link", systemImage: "link")
                                            }
                                            ShareLink(item: linkURL) {
                                                Label("Share", systemImage: "square.and.arrow.up")
                                            }
                                        }
                                    }
                                }
                            } header: {
                                Text(sourceLabel(group.source))
                                    .font(AppTheme.bodyFont(size: 12).weight(.semibold))
                                    .foregroundStyle(AppTheme.textSecondary)
                                    .kerning(0.8)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
        }
    }

    // MARK: — Trending searches & suggestions

    private var trendingSearchesBody: some View {
        Group {
            if trendingQueries.isEmpty {
                Spacer()
                Text("Search YouTube or SoundCloud, or paste a playlist URL.")
                    .font(AppTheme.bodyFont(size: 14))
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Spacer()
            } else {
                List(trendingQueries) { item in
                    Button {
                        searchText = item.query
                        triggerSearch()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.up.right")
                                .foregroundStyle(AppTheme.dynamicAccent)
                                .frame(width: 20)
                            Text(item.query)
                                .font(AppTheme.bodyFont(size: 14))
                                .foregroundStyle(AppTheme.textPrimary)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(AppTheme.surface)
                    .listRowSeparatorTint(AppTheme.background)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .safeAreaInset(edge: .top) {
                    Text("TRENDING SEARCHES")
                        .font(AppTheme.bodyFont(size: 11))
                        .foregroundStyle(AppTheme.textSecondary)
                        .kerning(0.8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .background(AppTheme.background)
                }
            }
        }
    }

    private var suggestionsBody: some View {
        VStack(spacing: 0) {
            ForEach(suggestions) { item in
                Button {
                    searchText = item.query
                    triggerSearch()
                } label: {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(AppTheme.textSecondary)
                            .frame(width: 20)
                        Text(item.query)
                            .font(AppTheme.bodyFont(size: 14))
                            .foregroundStyle(AppTheme.textPrimary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                Divider().background(AppTheme.background)
            }
        }
        .background(AppTheme.surface)
    }

    // MARK: — Server library results

    private var serverResultsBody: some View {
        Group {
            if streaming.isSearchingServer {
                Spacer()
                ProgressView("Searching server library…")
                    .tint(AppTheme.dynamicAccent)
                    .foregroundStyle(AppTheme.textSecondary)
                Spacer()
            } else if streaming.serverTracks.isEmpty && !searchText.isEmpty {
                Spacer()
                Text("No results for \"\(searchText)\"")
                    .font(AppTheme.bodyFont(size: 15))
                    .foregroundStyle(AppTheme.textSecondary)
                Spacer()
            } else if streaming.serverTracks.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: streaming.serverLibraryConfigured == false
                          ? "externaldrive.badge.xmark"
                          : "externaldrive.connected.to.line.below")
                        .font(.system(size: 44))
                        .foregroundStyle(AppTheme.textSecondary)
                    Text("Server Library")
                        .font(AppTheme.headlineFont(size: 16))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(streaming.serverLibraryConfigured == false
                         ? "No shared server library is configured. Ask the server admin to set SERVER_MUSIC_DIR to enable a shared, streamable music collection here."
                         : "Browse and stream the server's shared music collection, or search it above.")
                        .font(AppTheme.bodyFont(size: 14))
                        .foregroundStyle(AppTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                Spacer()
            } else {
                List(streaming.serverTracks) { track in
                    ServerTrackRow(
                        track: track,
                        artworkURL: streaming.serverArtworkURL(for: track),
                        isDownloading: downloadingServerTrackIDs.contains(track.id),
                        isDownloaded: downloadedServerTrackIDs.contains(track.id),
                        onPlay: { handleServerPlay(track: track) },
                        onDownload: { handleServerDownload(track: track) }
                    )
                    .listRowBackground(AppTheme.surface)
                    .listRowSeparatorTint(AppTheme.background)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    // MARK: — My Library body

    private var userLibraryBody: some View {
        Group {
            if !account.isLoggedIn {
                VStack {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.badge.questionmark")
                            .font(.system(size: 44))
                            .foregroundStyle(AppTheme.textSecondary)
                        Text("Log in to access your personal library")
                            .font(AppTheme.bodyFont(size: 15))
                            .foregroundStyle(AppTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    Spacer()
                }
            } else if streaming.isLoadingUserMusic {
                VStack {
                    Spacer()
                    ProgressView("Loading your library…")
                        .tint(AppTheme.dynamicAccent)
                        .foregroundStyle(AppTheme.textSecondary)
                    Spacer()
                }
            } else {
                List {
                    if !searchText.isEmpty && !matchingLocalSongs.isEmpty {
                        Section("On This Device") {
                            ForEach(matchingLocalSongs) { song in
                                SongRow(song: song, isCurrent: player.currentSong?.id == song.id)
                                    .listRowBackground(AppTheme.surface)
                                    .listRowSeparatorTint(AppTheme.background)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        player.play(song: song, in: matchingLocalSongs)
                                    }
                            }
                        }
                    }

                    if !searchText.isEmpty && !matchingDownloadHistory.isEmpty {
                        Section("Previously Downloaded") {
                            ForEach(matchingDownloadHistory) { item in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title)
                                            .font(AppTheme.bodyFont(size: 15))
                                            .foregroundStyle(AppTheme.textPrimary)
                                            .lineLimit(1)
                                        Text(item.artist)
                                            .font(.caption)
                                            .foregroundStyle(AppTheme.textSecondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    if downloadingTrackIDs.contains(item.id) {
                                        ProgressView().tint(AppTheme.dynamicAccent)
                                    } else if downloadedTrackIDs.contains(item.id) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                    } else {
                                        Button {
                                            handleDownload(track: item.asStreamTrack)
                                        } label: {
                                            Image(systemName: "arrow.down.circle")
                                                .foregroundStyle(AppTheme.dynamicAccent)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .listRowBackground(AppTheme.surface)
                                .listRowSeparatorTint(AppTheme.background)
                            }
                        }
                    }

                    // Upload button header
                    Section {
                        Button {
                            showUploadPicker = true
                        } label: {
                            HStack {
                                Label("Upload Music to Server", systemImage: "icloud.and.arrow.up")
                                    .foregroundStyle(AppTheme.dynamicAccent)
                                Spacer()
                                if streaming.isUploadingUserMusic {
                                    ProgressView()
                                        .tint(AppTheme.dynamicAccent)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(streaming.isUploadingUserMusic)
                    }
                    .listRowBackground(AppTheme.surface)

                    if streaming.userMusicTracks.isEmpty {
                        Section {
                            VStack(spacing: 12) {
                                Image(systemName: "folder.badge.plus")
                                    .font(.system(size: 40))
                                    .foregroundStyle(AppTheme.textSecondary)
                                Text("Your library is empty")
                                    .font(AppTheme.headlineFont(size: 16))
                                    .foregroundStyle(AppTheme.textPrimary)
                                Text("Upload music files to your personal server folder to play them anywhere.")
                                    .font(AppTheme.bodyFont(size: 14))
                                    .foregroundStyle(AppTheme.textSecondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 20)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 30)
                            .listRowBackground(Color.clear)
                        }
                    } else {
                        ForEach(streaming.userMusicTracks) { track in
                            UserMusicTrackRow(
                                track: track,
                                artworkURL: streaming.userMusicArtworkURL(for: track),
                                onPlay: { handleUserLibraryPlay(track: track) },
                                onInfo: { selectedInfoTrack = track },
                                onDelete: { handleUserLibraryDelete(track: track) }
                            )
                            .listRowBackground(AppTheme.surface)
                            .listRowSeparatorTint(AppTheme.background)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    // MARK: — Helpers

    /// Groups `streaming.searchResults` into per-source sections, preserving the
    /// order in which each source's first result appears (so a single-source
    /// search shows one section, and a mixed-source playlist resolve shows
    /// "YouTube" / "SoundCloud" sections in result order).
    private var groupedResults: [(source: String, tracks: [StreamTrack])] {
        var order: [String] = []
        var buckets: [String: [StreamTrack]] = [:]
        for track in streaming.searchResults {
            if buckets[track.source] == nil {
                buckets[track.source] = []
                order.append(track.source)
            }
            buckets[track.source]?.append(track)
        }
        return order.map { ($0, buckets[$0] ?? []) }
    }

    /// Songs already on this device whose title/artist/album match `searchText`
    /// — shown at the top of the "My Library" tab so on-device tracks actually
    /// surface in search instead of only the server-uploaded library.
    private var matchingLocalSongs: [Song] {
        guard !searchText.isEmpty else { return [] }
        let q = searchText.lowercased()
        return library.allSongs.filter {
            $0.title.lowercased().contains(q)
                || $0.artist.lowercased().contains(q)
                || $0.album.lowercased().contains(q)
        }
    }

    /// Server-recorded download history entries matching `searchText` that
    /// aren't already present on this device — surfaced as "Previously
    /// Downloaded" so the user can re-download tracks they've lost (reinstall,
    /// corruption cleanup, etc.) without re-searching from scratch.
    private var matchingDownloadHistory: [DownloadHistoryTrack] {
        guard !searchText.isEmpty else { return [] }
        let localIDs = Set(library.allSongs.compactMap { $0.sourceTrackID })
        return streaming.downloadHistory.filter { !localIDs.contains($0.sourceTrackID) }
    }

    private func sourceLabel(_ src: String) -> String {
        switch src {
        case "youtube":    return "YouTube"
        case "soundcloud": return "SoundCloud"
        case "server":     return "Server"
        case "my":         return "My Library"
        default:           return src.capitalized
        }
    }

    private func triggerSearch() {
        failedTrackIDs.removeAll()
        appBreadcrumb("Searched \"\(searchText)\" [source: \(selectedSource)]")
        if selectedSource == "server" {
            Task { await streaming.searchServerLibrary(query: searchText) }
        } else if selectedSource == "my" {
            guard let token = account.token else { return }
            Task { await streaming.fetchUserMusic(token: token, search: searchText) }
            Task { await streaming.fetchDownloadHistory(token: token, search: searchText) }
        } else if StreamingService.isPlaylistURL(searchText) {
            Task { await streaming.resolvePlaylist(url: searchText, existingSongs: library.allSongs) }
        } else {
            Task { await streaming.search(query: searchText, source: selectedSource) }
        }
    }

    // MARK: — Streaming Actions

    private func handlePlay(track: StreamTrack) {
        guard loadingTrackID == nil else { return }
        loadingTrackID = track.id
        appBreadcrumb("Tapped Play (preview) on \"\(track.title)\" [\(track.source)]")
        Task {
            defer { loadingTrackID = nil }
            do {
                let url = try await streaming.streamURL(for: track)
                let song = streaming.toSong(track: track, streamURL: url)
                player.play(song: song, in: [song])
            } catch {
                streaming.errorMessage = error.localizedDescription
            }
        }
    }

    private func handleAddToQueue(track: StreamTrack) {
        guard loadingTrackID == nil else { return }
        loadingTrackID = track.id
        Task {
            defer { loadingTrackID = nil }
            do {
                let url = try await streaming.streamURL(for: track)
                let song = streaming.toSong(track: track, streamURL: url)
                player.appendToQueue(song: song)
            } catch {
                streaming.errorMessage = error.localizedDescription
            }
        }
    }

    private func handlePlayNext(track: StreamTrack) {
        guard loadingTrackID == nil else { return }
        loadingTrackID = track.id
        Task {
            defer { loadingTrackID = nil }
            do {
                let url = try await streaming.streamURL(for: track)
                let song = streaming.toSong(track: track, streamURL: url)
                player.insertNext(song: song)
            } catch {
                streaming.errorMessage = error.localizedDescription
            }
        }
    }

    /// Re-derives `downloadedTrackIDs`/`downloadedServerTrackIDs` from the
    /// current `library.allSongs` (which includes everything found by recursive
    /// subfolder scans, not just top-level "Imported Music"). Previously these
    /// sets were ONLY mutated as a side effect of an in-session download, so
    /// tracks that were already on disk (in a subfolder, restored from backup,
    /// imported manually, etc.) permanently showed the "not downloaded" icon
    /// and could be re-downloaded as duplicates.
    private func refreshDownloadedStatus() {
        guard !library.allSongs.isEmpty else { return }
        let localSourceIDs = Set(library.allSongs.compactMap { $0.sourceTrackID })

        for track in streaming.searchResults {
            guard !downloadedTrackIDs.contains(track.id) else { continue }
            if localSourceIDs.contains(track.sourceTrackID)
                || library.isAlreadyImported(title: track.title, artist: track.artist, duration: track.duration) {
                downloadedTrackIDs.insert(track.id)
            }
        }

        for track in streaming.serverTracks {
            guard !downloadedServerTrackIDs.contains(track.id) else { continue }
            if library.isAlreadyImported(title: track.title, artist: track.artist, duration: track.duration) {
                downloadedServerTrackIDs.insert(track.id)
            }
        }
    }

    private func handleDownload(track: StreamTrack) {
        guard !downloadingTrackIDs.contains(track.id) else { return }
        downloadingTrackIDs.insert(track.id)
        appBreadcrumb("Tapped Download on \"\(track.title)\" [\(track.source)]")
        Task {
            do {
                // Rescan the full Documents tree (including subfolders the user has
                // created or moved files into) so `isAlreadyImported` reflects reality
                // before we decide whether to download — without this, a track sitting
                // in a subfolder of "Imported Music" would pass the sourceTrackID-only
                // check inside `downloadToLibrary` (which only looks at the top-level
                // download directory) and get re-downloaded as a duplicate.
                await library.scanLocalDocumentsAsync()
                if library.isAlreadyImported(title: track.title, artist: track.artist, duration: track.duration) {
                    downloadedTrackIDs.insert(track.id)
                    failedTrackIDs.remove(track.id)
                    downloadingTrackIDs.remove(track.id)
                    ToastCenter.shared.show("\"\(track.title)\" is already in your library", category: .info, icon: "checkmark.circle")
                    return
                }
                let localURL = try await streaming.downloadToLibrary(track: track, existingSongs: library.allSongs)
                library.scanLocalDocuments()
                downloadedTrackIDs.insert(track.id)
                failedTrackIDs.remove(track.id)
                appLog("Download succeeded: \"\(track.title)\"", category: "download",
                       extra: ["title": track.title, "artist": track.artist, "source": track.source, "trackId": track.id])
                ToastCenter.shared.show("Downloaded \"\(track.title)\"", category: .download, icon: "checkmark.circle.fill")
                NotificationService.shared.notify(
                    title: "Download Complete",
                    body: "\"\(track.title)\" is ready in your library.",
                    identifier: "download-\(track.id)"
                )
                if autoCloudBackup, account.isLoggedIn, let token = account.token {
                    Task {
                        try? await streaming.uploadTrack(
                            fileURL: localURL, token: token,
                            metadata: TrackMetadata(title: track.title, artist: track.artist, durationSeconds: track.duration)
                        )
                    }
                }
            } catch {
                streaming.errorMessage = "Download failed: \(error.localizedDescription)"
                failedTrackIDs.insert(track.id)
                appWarn("Download failed: \"\(track.title)\": \(error.localizedDescription)", category: "download",
                        extra: ["title": track.title, "artist": track.artist, "source": track.source, "trackId": track.id, "error": error.localizedDescription])
                ToastCenter.shared.show("Failed to download \"\(track.title)\"", category: .error)
            }
            downloadingTrackIDs.remove(track.id)
        }
    }

    private func handleDownloadAll() {
        guard !isDownloadingAll else { return }
        failedTrackIDs.removeAll()
        let url = searchText.trimmingCharacters(in: .whitespaces)
        let looksLikePlaylist = url.contains("list=") || url.contains("/playlist") || url.contains("/sets/")

        // For a playlist, re-run the resolver (the full per-item extractor) right
        // before downloading, so Download All always operates on EVERY item in
        // the current playlist — not a stale or partial result. The resolve also
        // sends the dedup manifest/inventory, so owned tracks are excluded.
        if streaming.isPlaylistResult, looksLikePlaylist {
            Task { @MainActor in
                await streaming.resolvePlaylist(url: url, existingSongs: library.allSongs)
                let tracks = streaming.searchResults
                guard !tracks.isEmpty else { return }
                runDownloadPipeline(tracks: tracks)
            }
            return
        }

        let tracks = streaming.searchResults
        guard !tracks.isEmpty else { return }
        runDownloadPipeline(tracks: tracks)
    }

    /// Re-runs the download pipeline for only the tracks that failed last
    /// time (`failedTrackIDs`) — no call to `triggerSearch()`/`resolvePlaylist`,
    /// so `streaming.searchResults` and the rest of the list stay untouched
    /// and the UI doesn't refresh wholesale.
    private func handleRetryFailedDownloads() {
        guard !isDownloadingAll else { return }
        let tracks = streaming.searchResults.filter { failedTrackIDs.contains($0.id) }
        guard !tracks.isEmpty else { return }
        failedTrackIDs.removeAll()
        runDownloadPipeline(tracks: tracks)
    }

    /// Bounded-concurrency download pipeline shared by "Download All" and
    /// "Retry Failed". Before downloading, refreshes the local library scan
    /// (recursively, including any subfolders) and skips any track that
    /// already matches a locally-imported song by title+artist — covering
    /// manually-imported files or ones from a different source that the
    /// `sourceTrackID`-based check inside `downloadToLibrary` wouldn't catch.
    private func runDownloadPipeline(tracks: [StreamTrack]) {
        isDownloadingAll = true
        downloadAllDone = 0
        downloadAllTotal = tracks.count

        // Matches the bridge's yt-dlp process semaphore (_YTDLP_SEMAPHORE = 4) so the
        // client keeps it saturated without piling up extra jobs that just sit
        // "pending" behind the semaphore (each holding its own /tmp/dl_* dir).
        let maxConcurrent = 4

        Task { @MainActor in
            // Make sure `library.allSongs` reflects every file on disk — including
            // subfolders the user created or moved files into — before deciding
            // what's already imported.
            await library.scanLocalDocumentsAsync()

            var toDownload: [StreamTrack] = []
            var skipped = 0
            for track in tracks {
                if library.hasLocalCopy(of: track) {
                    skipped += 1
                    downloadedTrackIDs.insert(track.id)
                    downloadAllDone += 1
                } else {
                    toDownload.append(track)
                }
            }

            var failed: [String] = []
            var nextIndex = 0

            await withTaskGroup(of: (track: StreamTrack, localURL: URL?, errorDescription: String?).self) { group in
                func launchNext() {
                    guard nextIndex < toDownload.count else { return }
                    let track = toDownload[nextIndex]
                    nextIndex += 1
                    group.addTask {
                        do {
                            let localURL = try await streaming.downloadToLibrary(track: track, existingSongs: library.allSongs)
                            appLog("Download All: succeeded for \"\(track.title)\"", category: "download",
                                   extra: ["title": track.title, "artist": track.artist, "source": track.source, "trackId": track.id])
                            return (track, localURL, nil)
                        } catch {
                            appWarn("Download All: failed for \"\(track.title)\": \(error.localizedDescription)", category: "download",
                                    extra: ["title": track.title, "artist": track.artist, "source": track.source, "trackId": track.id, "error": error.localizedDescription])
                            return (track, nil, error.localizedDescription)
                        }
                    }
                }

                for _ in 0..<min(maxConcurrent, toDownload.count) {
                    launchNext()
                }

                for await result in group {
                    if let localURL = result.localURL {
                        downloadedTrackIDs.insert(result.track.id)
                        failedTrackIDs.remove(result.track.id)
                        if autoCloudBackup, account.isLoggedIn, let token = account.token {
                            Task {
                                try? await streaming.uploadTrack(
                                    fileURL: localURL, token: token,
                                    metadata: TrackMetadata(title: result.track.title, artist: result.track.artist, durationSeconds: result.track.duration)
                                )
                            }
                        }
                    } else {
                        failed.append(result.track.title)
                        failedTrackIDs.insert(result.track.id)
                    }
                    downloadAllDone += 1
                    launchNext()
                }
            }

            library.scanLocalDocuments()
            isDownloadingAll = false
            let succeeded = toDownload.count - failed.count

            if failed.isEmpty {
                if skipped > 0 {
                    ToastCenter.shared.show("Downloaded \(succeeded), skipped \(skipped) already imported", category: .download)
                } else {
                    ToastCenter.shared.show("Downloaded \(succeeded) tracks", category: .download)
                }
            } else {
                streaming.errorMessage = "\(failed.count) track(s) failed to download."
                let skippedSuffix = skipped > 0 ? ", skipped \(skipped)" : ""
                ToastCenter.shared.show("Downloaded \(succeeded), \(failed.count) failed\(skippedSuffix)", category: .warning)
            }
        }
    }

    // MARK: — User Library Actions

    private func handleUserLibraryPlay(track: UserMusicTrack) {
        guard let token = account.token else { return }
        let song = streaming.toSong(userMusicTrack: track, token: token)
        player.play(song: song, in: streaming.userMusicTracks.map { streaming.toSong(userMusicTrack: $0, token: token) })
    }

    private func handleUserLibraryDelete(track: UserMusicTrack) {
        guard let token = account.token else { return }
        deletingUserTrackPath = track.serverPath
        Task {
            do {
                try await streaming.deleteUserMusic(path: track.serverPath, token: token)
                await streaming.fetchUserMusic(token: token)
                ToastCenter.shared.show("Deleted \"\(track.title)\" from cloud", category: .info, icon: "trash")
            } catch StreamingError.httpError(404) {
                // Already gone on the server — treat as a successful delete.
                await streaming.fetchUserMusic(token: token)
                ToastCenter.shared.show("Deleted \"\(track.title)\" from cloud", category: .info, icon: "trash")
            } catch {
                streaming.errorMessage = "Delete failed: \(error.localizedDescription)"
                ToastCenter.shared.show("Failed to delete \"\(track.title)\"", category: .error)
            }
            deletingUserTrackPath = nil
        }
    }

    // MARK: — Server Library Actions

    private func handleServerPlay(track: ServerTrack) {
        let song = streaming.toSong(serverTrack: track)
        player.play(song: song, in: [song])
    }

    private func handleServerDownload(track: ServerTrack) {
        guard !downloadingServerTrackIDs.contains(track.id),
              let streamURL = streaming.serverStreamURL(for: track) else { return }
        downloadingServerTrackIDs.insert(track.id)

        Task {
            // Same duplicate guard as `handleDownload`/`runDownloadPipeline`: rescan
            // first (picks up subfolder-imported files), then skip the download
            // entirely if a matching track is already in the library.
            await library.scanLocalDocumentsAsync()
            if library.isAlreadyImported(title: track.title, artist: track.artist, duration: track.duration) {
                downloadedServerTrackIDs.insert(track.id)
                downloadingServerTrackIDs.remove(track.id)
                ToastCenter.shared.show("\"\(track.title)\" is already in your library", category: .info, icon: "checkmark.circle")
                return
            }

            do {
                let importDir = streaming.downloadDirectory
                try? FileManager.default.createDirectory(at: importDir, withIntermediateDirectories: true)

                let safeName = String(
                    track.title
                        .replacingOccurrences(of: "/", with: "-")
                        .replacingOccurrences(of: ":", with: "-")
                        .prefix(100)
                )
                let ext = track.ext.isEmpty ? "m4a" : track.ext
                let destURL = importDir.appendingPathComponent("\(safeName).\(ext)")

                if FileManager.default.fileExists(atPath: destURL.path) {
                    downloadedServerTrackIDs.insert(track.id)
                    downloadingServerTrackIDs.remove(track.id)
                    return
                }

                var request = URLRequest(url: streamURL)
                request.httpMethod = "GET"
                if !streaming.apiKey.isEmpty {
                    request.setValue("Bearer \(streaming.apiKey)", forHTTPHeaderField: "Authorization")
                }
                request.timeoutInterval = 120

                // Retry a few times on incomplete/corrupt transfers, same as
                // StreamingService.downloadToLibrary, before giving up.
                let maxAttempts = 3
                var lastError: Error = StreamingError.corruptDownload

                for attempt in 1...maxAttempts {
                    do {
                        let (tmpURL, response) = try await URLSession.shared.download(for: request)
                        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                            throw StreamingError.httpError(http.statusCode)
                        }

                        // Verify the download is complete before adopting it — a truncated
                        // file would otherwise sit in the library showing "0:00" forever.
                        let downloadedSize = (try? FileManager.default.attributesOfItem(atPath: tmpURL.path))?[.size] as? Int64 ?? 0
                        let expectedSize = (response as? HTTPURLResponse)?.expectedContentLength ?? -1
                        if downloadedSize <= 0 || (expectedSize > 0 && downloadedSize != expectedSize) {
                            try? FileManager.default.removeItem(at: tmpURL)
                            throw StreamingError.incompleteDownload
                        }

                        try? FileManager.default.removeItem(at: destURL)
                        try FileManager.default.moveItem(at: tmpURL, to: destURL)

                        guard CorruptFileFinderService.isValidAudioFile(at: destURL) else {
                            try? FileManager.default.removeItem(at: destURL)
                            throw StreamingError.corruptDownload
                        }

                        library.scanLocalDocuments()
                        downloadedServerTrackIDs.insert(track.id)
                        lastError = StreamingError.corruptDownload
                        break
                    } catch let error as StreamingError {
                        switch error {
                        case .incompleteDownload, .corruptDownload:
                            lastError = error
                            if attempt == maxAttempts { throw error }
                            continue
                        default:
                            throw error
                        }
                    }
                }
            } catch {
                streaming.errorMessage = "Download failed: \(error.localizedDescription)"
            }
            downloadingServerTrackIDs.remove(track.id)
        }
    }
}

// MARK: - StreamTrackRow

private struct StreamTrackRow: View {

    let track: StreamTrack
    let isLoading: Bool
    let isDownloading: Bool
    let isDownloaded: Bool
    let onPlay: () -> Void
    let onAddToQueue: () -> Void
    let onDownload: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail with a small source-icon badge in the corner — gives each
            // row an at-a-glance platform indicator even outside its grouped section.
            ZStack(alignment: .bottomTrailing) {
                AsyncImage(url: URL(string: track.thumbnailURL)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure, .empty:
                        Image(systemName: sourceIcon)
                            .font(.system(size: 22))
                            .foregroundStyle(AppTheme.textSecondary)
                    @unknown default:
                        Color.clear
                    }
                }
                .frame(width: 56, height: 56)
                .background(AppTheme.elevatedSurface)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .clipped()

                Image(systemName: sourceIcon)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(sourceTint, in: Circle())
                    .overlay(Circle().stroke(AppTheme.surface, lineWidth: 1.5))
                    .offset(x: 4, y: 4)
            }

            // Title + artist
            VStack(alignment: .leading, spacing: 3) {
                Text(track.title)
                    .font(AppTheme.bodyFont(size: 14).weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                Text(track.artist.isEmpty ? sourceLabelForTrack : track.artist)
                    .font(AppTheme.bodyFont(size: 12))
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            // Duration
            Text(track.durationText)
                .font(AppTheme.monoFont(size: 12))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(minWidth: 36, alignment: .trailing)

            // Play / spinner
            if isLoading {
                ProgressView()
                    .tint(AppTheme.dynamicAccent)
                    .frame(width: 32, height: 32)
            } else {
                Button(action: onPlay) {
                    Image(systemName: "play.circle.fill")
                        .font(.title2)
                        .foregroundStyle(AppTheme.dynamicAccent)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }

            // Download button
            Button(action: onDownload) {
                if isDownloading {
                    ProgressView()
                        .tint(AppTheme.dynamicAccent)
                        .frame(width: 32, height: 32)
                } else if isDownloaded {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(AppTheme.success)
                        .frame(width: 32, height: 32)
                } else {
                    Image(systemName: "arrow.down.circle")
                        .font(.title2)
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(width: 32, height: 32)
                }
            }
            .buttonStyle(.plain)
            .disabled(isDownloading || isDownloaded)

            // Queue button
            Button(action: onAddToQueue) {
                Image(systemName: "text.line.last.and.arrowtriangle.forward")
                    .font(.system(size: 14))
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture(perform: onPlay)
    }

    private var sourceIcon: String {
        track.source == "soundcloud" ? "cloud.fill" : "play.rectangle.fill"
    }

    private var sourceTint: Color {
        track.source == "soundcloud" ? Color.orange : Color.red
    }

    private var sourceLabelForTrack: String {
        track.source == "soundcloud" ? "SoundCloud" : "YouTube"
    }
}

// MARK: - ServerTrackRow

private struct ServerTrackRow: View {

    let track: ServerTrack
    let artworkURL: URL?
    let isDownloading: Bool
    let isDownloaded: Bool
    let onPlay: () -> Void
    let onDownload: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Artwork
            AsyncImage(url: artworkURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure, .empty:
                    Image(systemName: "externaldrive.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(AppTheme.textSecondary)
                @unknown default:
                    Color.clear
                }
            }
            .frame(width: 44, height: 44)
            .background(AppTheme.elevatedSurface)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            // Title + artist + album
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(AppTheme.bodyFont(size: 14))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                if !track.artist.isEmpty {
                    Text(track.artist)
                        .font(AppTheme.bodyFont(size: 12))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                }
                if !track.album.isEmpty {
                    Text(track.album)
                        .font(AppTheme.bodyFont(size: 11))
                        .foregroundStyle(AppTheme.textSecondary.opacity(0.7))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            // Duration
            Text(track.durationText)
                .font(AppTheme.monoFont(size: 12))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(minWidth: 36, alignment: .trailing)

            // Play button
            Button(action: onPlay) {
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(AppTheme.dynamicAccent)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)

            // Download button
            Button(action: onDownload) {
                if isDownloading {
                    ProgressView()
                        .tint(AppTheme.dynamicAccent)
                        .frame(width: 32, height: 32)
                } else if isDownloaded {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(AppTheme.success)
                        .frame(width: 32, height: 32)
                } else {
                    Image(systemName: "arrow.down.circle")
                        .font(.title2)
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(width: 32, height: 32)
                }
            }
            .buttonStyle(.plain)
            .disabled(isDownloading || isDownloaded)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture(perform: onPlay)
    }
}

// MARK: - UserMusicTrackRow

private struct UserMusicTrackRow: View {
    let track: UserMusicTrack
    let artworkURL: URL?
    let onPlay: () -> Void
    let onInfo: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: artworkURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .failure, .empty:
                    Image(systemName: "music.note")
                        .font(.system(size: 18))
                        .foregroundStyle(AppTheme.textSecondary)
                @unknown default:
                    Color.clear
                }
            }
            .frame(width: 44, height: 44)
            .background(AppTheme.elevatedSurface)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(AppTheme.bodyFont(size: 14))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                if !track.artist.isEmpty && track.artist != "Unknown Artist" {
                    Text(track.artist)
                        .font(AppTheme.bodyFont(size: 12))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                }
                if !track.album.isEmpty {
                    Text(track.album)
                        .font(AppTheme.bodyFont(size: 11))
                        .foregroundStyle(AppTheme.textSecondary.opacity(0.7))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            Text(track.durationText)
                .font(AppTheme.monoFont(size: 12))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(minWidth: 36, alignment: .trailing)

            Button(action: onInfo) {
                Image(systemName: "info.circle")
                    .font(.system(size: 16))
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)

            Button(action: onPlay) {
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(AppTheme.dynamicAccent)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 16))
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture(perform: onPlay)
    }
}

// MARK: - UserMusicInfoSheet

private struct UserMusicInfoSheet: View {
    let track: UserMusicTrack
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    infoRow(label: "Title", value: track.title)
                    infoRow(label: "Artist", value: track.artist.isEmpty ? "—" : track.artist)
                    infoRow(label: "Album", value: track.album.isEmpty ? "—" : track.album)
                    infoRow(label: "Duration", value: track.durationText)
                } header: {
                    Text("Metadata")
                }
                .listRowBackground(AppTheme.surface)

                Section {
                    infoRow(label: "File", value: track.filename)
                    infoRow(label: "Format", value: track.ext.uppercased())
                    infoRow(label: "Server Path", value: track.serverPath)
                } header: {
                    Text("File Info")
                }
                .listRowBackground(AppTheme.surface)
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("File Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.tint(AppTheme.dynamicAccent)
                }
            }
        }
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(AppTheme.bodyFont(size: 13))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 70, alignment: .leading)
            Text(value)
                .font(AppTheme.bodyFont(size: 13))
                .foregroundStyle(AppTheme.textPrimary)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - StaggeredFadeInModifier

/// Fades each result row in with a small per-index delay whenever `token` changes.
private struct StaggeredFadeInModifier: ViewModifier {
    let index: Int
    let token: UUID
    @State private var visible: Bool = false

    private var delay: Double { Double(min(index, 19)) * 0.04 }

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .animation(
                .easeOut(duration: 0.25).delay(delay),
                value: visible
            )
            .onAppear { visible = true }
            .onChange(of: token) { _ in
                visible = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                    visible = true
                }
            }
    }
}
