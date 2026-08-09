import SwiftUI
import MediaPlayer

// MARK: - Song sort order

/// Backs `SongsTab`'s sort-chip row — persisted via `@AppStorage` so the
/// chosen order survives relaunches, same as `library_songs_columns`.
private enum SongSortOrder: String {
    case title
    case artist
    case dateAdded
    case playCount
    case duration

    static let allCases: [SongSortOrder] = [.title, .artist, .dateAdded, .playCount, .duration]

    var label: String {
        switch self {
        case .title:     return "Title"
        case .artist:    return "Artist"
        case .dateAdded: return "Recently Added"
        case .playCount: return "Most Played"
        case .duration:  return "Duration"
        }
    }

    var icon: String {
        switch self {
        case .title:     return "textformat"
        case .artist:    return "person.fill"
        case .dateAdded: return "clock.fill"
        case .playCount: return "flame.fill"
        case .duration:  return "timer"
        }
    }
}

// MARK: - Songs Tab

struct SongsTab: View {
    let songs: [Song]
    @Binding var searchText: String
    @Binding var showAddMusic: Bool
    @Binding var isSelecting: Bool
    @Binding var selectedSongIDs: Set<String>
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var library: LibraryManager

    private func toggleSelection(_ song: Song) {
        if selectedSongIDs.contains(song.id) {
            selectedSongIDs.remove(song.id)
        } else {
            selectedSongIDs.insert(song.id)
        }
    }

    @AppStorage("library_songs_columns") private var songColumns: Int = 1
    /// Tracks whether the entrance animation has already fired for the current song list.
    @State private var didAnimateEntrance: Bool = false

    /// Persisted sort order — a horizontally-scrollable chip row (see
    /// `statsAndSortHeader`) rather than a hidden sort menu, matching the pattern
    /// Spotify's 2026 "Your Library" redesign moved to: sort/filter controls
    /// surfaced as chips directly above the list instead of buried behind a
    /// single button.
    @AppStorage("library_songs_sort") private var sortOrderRaw: String = SongSortOrder.title.rawValue
    private var sortOrder: SongSortOrder { SongSortOrder(rawValue: sortOrderRaw) ?? .title }

    /// Logic hook the active Lua theme preset can set (`hooks.pin_favorites_first`
    /// in the preset script — see `Theme/LuaThemeEngine.swift`): when on,
    /// favorited songs float to the top of whatever `sortOrder` is chosen,
    /// keeping that order stable within each of the two groups.
    @AppStorage("lua_pin_favorites_first") private var pinFavoritesFirst: Bool = false

    /// `songs`, sorted per `sortOrder` — every place `songs` used to be
    /// rendered/played/shuffled/prefetched now goes through this instead, so
    /// "Play" starts from the top of whatever order is currently showing.
    ///
    /// Backed by `sortedSongsCache` (recomputed only when a real dependency
    /// changes — see `recomputeSortedSongs`/the `.onChange` modifiers on
    /// `body`), not derived inline. This is referenced from ~8 separate
    /// places across this view's several computed subviews (the action
    /// header, both the list and grid bodies, prefetch bounds, entrance-
    /// animation triggers, …) — as a plain computed property recomputing a
    /// full O(n log n) sort (plus, with "Most Played" selected, two
    /// `PlayHistoryStore` lookups per comparison) EVERY time any of those
    /// read it, a single `body` evaluation for a several-thousand-song
    /// library was paying for the same sort many times over, on every
    /// render — including every keystroke while the search field above is
    /// focused. Caching cuts that to one recompute per actual change.
    ///
    /// `sortedSongsCache` is `nil` (not `[]`) until the first `.onAppear`
    /// populates it — falling straight back to a live compute in that gap
    /// (rather than showing an empty list) matters because the very first
    /// `body` evaluation renders the list/grid content synchronously, before
    /// any `.onAppear`/`.onChange` modifier has had a chance to run.
    private var sortedSongs: [Song] { sortedSongsCache ?? computeSortedSongs() }

    @State private var sortedSongsCache: [Song]? = nil

    private func recomputeSortedSongs() {
        sortedSongsCache = computeSortedSongs()
    }

    private func computeSortedSongs() -> [Song] {
        let base: [Song]
        switch sortOrder {
        case .title:
            base = songs.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        case .artist:
            base = songs.sorted { $0.artistName.localizedCaseInsensitiveCompare($1.artistName) == .orderedAscending }
        case .dateAdded:
            base = songs.sorted { ($0.dateAdded ?? .distantPast) > ($1.dateAdded ?? .distantPast) }
        case .playCount:
            base = songs.sorted { PlayHistoryStore.shared.playCount(for: $0.id) > PlayHistoryStore.shared.playCount(for: $1.id) }
        case .duration:
            base = songs.sorted { $0.duration > $1.duration }
        }
        guard pinFavoritesFirst else { return base }
        // `.sorted` on a Bool key is stable in practice here since we only
        // ever compare across the two favorite/non-favorite partitions —
        // done via an explicit stable filter+filter split (not `.sorted`)
        // so the relative order within each group from `base` above is
        // preserved exactly.
        let favorites = base.filter { library.isFavorite(songID: $0.id) }
        let rest = base.filter { !library.isFavorite(songID: $0.id) }
        return favorites + rest
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: songColumns)
    }

    /// "247 songs · 18h 32m" — a real library-stats line under the action
    /// buttons, common in Apple Music/Spotify library headers but previously
    /// absent here entirely.
    private var libraryStatsText: String {
        let totalSeconds = songs.reduce(0.0) { $0 + $1.duration }
        let hours = Int(totalSeconds) / 3600
        let minutes = (Int(totalSeconds) % 3600) / 60
        let durationText = hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
        return "\(songs.count) song\(songs.count == 1 ? "" : "s") · \(durationText)"
    }

    /// Physical pixel size to prefetch artwork thumbnails at for whichever
    /// layout (`List` rows vs. grid cells) is currently showing — must match
    /// what `ArtworkThumbnail` actually requests, or the prefetched bucket
    /// goes unread and scrolling still shows a placeholder flash.
    private var prefetchPixelSize: CGFloat {
        songColumns == 1 ? 192 : 768
    }

    /// Spotify/Apple-Music-style action bar above the song list.
    private var songsActionHeader: some View {
        HStack(spacing: 12) {
            Button {
                player.setQueue(sortedSongs, startIndex: 0, autoplay: true)
            } label: {
                Label("Play", systemImage: "play.fill")
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(AppTheme.dynamicAccent, in: Capsule())
                    .foregroundStyle(.white)
            }
            Button {
                player.setQueue(sortedSongs.shuffled(), startIndex: 0, autoplay: true)
            } label: {
                Label("Shuffle", systemImage: "shuffle")
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(AppTheme.surface, in: Capsule())
                    .foregroundStyle(AppTheme.textPrimary)
                    .overlay(Capsule().stroke(.white.opacity(0.08), lineWidth: 1))
            }
        }
        .buttonStyle(PressableButtonStyle())
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    /// Real library stats + a horizontally-scrollable sort-chip row.
    private var statsAndSortHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(libraryStatsText)
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(SongSortOrder.allCases, id: \.self) { order in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { sortOrderRaw = order.rawValue }
                        } label: {
                            Label(order.label, systemImage: order.icon)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(sortOrder == order ? .white : AppTheme.textPrimary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(
                                    sortOrder == order ? AppTheme.dynamicAccent : AppTheme.surface,
                                    in: Capsule()
                                )
                                .overlay(
                                    Capsule().stroke(.white.opacity(sortOrder == order ? 0 : 0.08), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.bottom, 10)
    }

    var body: some View {
        VStack(spacing: 0) {
            if !songs.isEmpty {
                songsActionHeader
                statsAndSortHeader
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
                            ForEach(Array(sortedSongs.enumerated()), id: \.element.id) { index, song in
                                Button {
                                    if isSelecting {
                                        toggleSelection(song)
                                    } else {
                                        player.play(song: song, in: sortedSongs)
                                    }
                                } label: {
                                    HStack(spacing: 12) {
                                        if isSelecting {
                                            Image(systemName: selectedSongIDs.contains(song.id) ? "checkmark.circle.fill" : "circle")
                                                .font(.system(size: 20))
                                                .foregroundStyle(
                                                    selectedSongIDs.contains(song.id)
                                                        ? AppTheme.dynamicAccent
                                                        : AppTheme.textSecondary
                                                )
                                                .transition(.scale.combined(with: .opacity))
                                                .animation(.spring(response: 0.25, dampingFraction: 0.6), value: selectedSongIDs)
                                        }
                                        SongRow(song: song, isCurrent: player.currentSong?.id == song.id)
                                    }
                                    .animation(.easeInOut(duration: 0.15), value: isSelecting)
                                }
                                .buttonStyle(.plain)
                                .listRowBackground(AppTheme.surface.opacity(0.5))
                                // Fast one-handed actions alongside the existing long-press
                                // context menu (SongContextMenuContent, via SongRow) — 2026's
                                // expected pattern per current gesture-UX research is swipe
                                // actions with distinct semantics/tint per edge, not everything
                                // buried behind a single long-press menu.
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    Button {
                                        library.toggleFavorite(songID: song.id)
                                    } label: {
                                        let isFav = library.isFavorite(songID: song.id)
                                        Label(isFav ? "Unfavorite" : "Favorite", systemImage: isFav ? "heart.slash.fill" : "heart.fill")
                                    }
                                    .tint(AppTheme.dynamicAccent)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button {
                                        player.insertNext(song: song)
                                    } label: {
                                        Label("Play Next", systemImage: "text.insert")
                                    }
                                    .tint(AppTheme.success)
                                }
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
                                    // Widened ahead/behind window when the active Lua
                                    // theme preset's `flags.aggressive_prefetch` is on
                                    // (see LuaFeatureFlags) — trades some extra network/
                                    // decode work for artwork being ready further in
                                    // advance of fast scrolling.
                                    let behind = LuaFeatureFlags.aggressivePrefetch ? 16 : 8
                                    let ahead = LuaFeatureFlags.aggressivePrefetch ? 48 : 24
                                    let lower = max(0, index - behind)
                                    let upper = min(sortedSongs.count, index + ahead)
                                    guard lower < upper else { return }
                                    ArtworkService.shared.prefetch(songs: Array(sortedSongs[lower..<upper]), pixelSize: 192)
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
                    .onChange(of: sortedSongs.first?.id) { _ in
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
                                ForEach(sortedSongs) { song in
                                    Button {
                                        player.play(song: song, in: sortedSongs)
                                    } label: {
                                        SongGridCell(song: song, isCurrent: player.currentSong?.id == song.id)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.top, 12)
                            // Extra clearance below the last row — a plain
                            // ScrollView's grid content was settling close
                            // enough to the MiniPlayerBar + tab bar that the
                            // last row could still peek through their
                            // translucent material while scrolling.
                            .padding(.bottom, 190)
                        }
                    }
                    .background(Color.clear.ignoresSafeArea())
                }
            }
        }
        // Keeps `sortedSongsCache` (see `sortedSongs`) current — every
        // modifier below that reads `sortedSongs` relies on one of these
        // having already run first, which holds true here since SwiftUI
        // fires same-event `.onAppear`/`.onChange` modifiers on one view in
        // the order they're attached.
        .onAppear { recomputeSortedSongs() }
        .onChange(of: songs) { _ in recomputeSortedSongs() }
        .onChange(of: sortOrderRaw) { _ in recomputeSortedSongs() }
        .onChange(of: pinFavoritesFirst) { _ in recomputeSortedSongs() }
        .onChange(of: library.favoriteSongIDs) { _ in recomputeSortedSongs() }
        .onAppear {
            // Warm the first 30 songs' artwork at background priority so
            // rows/cells have images ready before the user scrolls to them.
            ArtworkService.shared.prefetch(songs: Array(sortedSongs.prefix(30)), pixelSize: prefetchPixelSize)
        }
        .onChange(of: songs.count) { _ in
            // Re-trigger prefetch when the song list grows (e.g. after a scan).
            ArtworkService.shared.prefetch(songs: Array(sortedSongs.prefix(30)), pixelSize: prefetchPixelSize)
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
