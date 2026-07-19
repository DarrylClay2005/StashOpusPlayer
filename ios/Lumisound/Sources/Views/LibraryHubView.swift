import SwiftUI
import UIKit

// MARK: - Library Hub
//
// The Library tab's new landing screen — a dashboard ("hub") of shortcuts to
// the user's real playlists/folders/favorites, plus a few auto-generated
// groupings, sitting above the traditional Songs/Artists/Albums/Folders/...
// browsing tabs (still fully reachable via `LibraryTabBar` — see
// `LibraryTab.hub`, which sits alongside them rather than replacing them).
//
// Loosely inspired by a YouTube-Music-style home screen (a "speed dial" grid
// of shortcut tiles + horizontal carousels of curated content), but
// reinterpreted around Lumisound's own data model rather than cloned:
//   - Speed dial tiles = real `Playlist`s, `MusicFolderService` local
//     folders, and Favorites (if non-empty) — never placeholder content.
//   - Carousels = `SmartPlaylistStore`'s auto-generated mixes (the app's own
//     "auto-generated grouping" concept — Recently Added / Most Played /
//     Forgotten Favorites / Quick Listens, plus anything the user made
//     themselves), a Recently Added shelf, an On Repeat (most played) shelf,
//     a Forgotten Favorites shelf, and a Moods shelf if `MoodPlaylistService`
//     has classified anything yet.
struct LibraryHubView: View {
    @EnvironmentObject private var library: LibraryManager
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var folderService: MusicFolderService
    @EnvironmentObject private var moodService: MoodPlaylistService
    @EnvironmentObject private var streaming: StreamingService
    @EnvironmentObject private var account: AccountService
    @ObservedObject private var smartPlaylistStore = SmartPlaylistStore.shared
    /// Shared app-wide instance (see `LumisoundApp`) — the dedicated
    /// Friends tab reads/mutates this same friends list, so this hub's
    /// Friends Activity card needs to reflect that shared state rather than
    /// a private copy that could show stale data right after visiting Friends.
    @EnvironmentObject private var social: SocialService

    /// Lets a carousel's "See All" chip (or a Moods tile) jump straight to
    /// the matching traditional browsing tab instead of the hub needing its
    /// own duplicate destination screen for content already browsable there.
    @Binding var selectedTab: LibraryTab

    @State private var shortcuts: [HubShortcut] = []
    @State private var recentlyAdded: [Song] = []
    @State private var mostPlayed: [Song] = []
    @State private var forgottenFavorites: [Song] = []
    @State private var hasLoadedOnce = false

    // Server-backed extras — independent of the on-device reload() above,
    // since these come from the network rather than LibraryManager.
    @State private var weeklyMixSongs: [Song] = []
    @State private var similarListenerSearchQuery: String? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                if !hasLoadedOnce {
                    HubSkeleton()
                        .transition(.opacity)
                } else if library.allSongs.isEmpty {
                    HubEmptyState()
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                } else {
                    hubContent
                        .transition(.opacity)
                }
            }
            .padding(.top, 12)
            // Extra clearance below the last row — see SongsTab's identical
            // fix (clears MiniPlayerBar + tab bar).
            .padding(.bottom, 190)
            .animation(.easeInOut(duration: 0.35), value: hasLoadedOnce)
        }
        .background(Color.clear.ignoresSafeArea())
        .task(id: library.allSongs.count) {
            reload()
        }
        .task {
            await loadServerExtras()
        }
        .sheet(item: Binding(
            get: { similarListenerSearchQuery.map { IdentifiableQuery(text: $0) } },
            set: { similarListenerSearchQuery = $0?.text }
        )) { query in
            StreamSearchView(initialSearchText: query.text)
        }
    }

    private struct IdentifiableQuery: Identifiable { let text: String; var id: String { text } }

    @ViewBuilder
    private var hubContent: some View {
        HubQuickActionsRow(hasLibrary: !library.allSongs.isEmpty, onShuffleAll: shuffleAll)

        if !shortcuts.isEmpty {
            HubSpeedDialSection(shortcuts: shortcuts)
                .transition(.move(edge: .top).combined(with: .opacity))
        }

        if !weeklyMixSongs.isEmpty {
            HubSongCarousel(
                title: "Weekly Mix", icon: "sparkles.tv",
                songs: weeklyMixSongs, seeAllTab: nil, selectedTab: $selectedTab
            )
        }

        if !smartPlaylistStore.playlists.isEmpty {
            mixesCarousel
        }

        if !recentlyAdded.isEmpty {
            HubSongCarousel(
                title: "Recently Added", icon: "clock.badge.checkmark",
                songs: recentlyAdded, seeAllTab: .songs, selectedTab: $selectedTab
            )
        }

        if !mostPlayed.isEmpty {
            HubSongCarousel(
                title: "On Repeat", icon: "flame.fill",
                songs: mostPlayed, seeAllTab: .songs, selectedTab: $selectedTab
            )
        }

        if !forgottenFavorites.isEmpty {
            HubSongCarousel(
                title: "Forgotten Favorites", icon: "heart.slash",
                songs: forgottenFavorites, seeAllTab: .favorites, selectedTab: $selectedTab
            )
        }

        if !moodBucketsWithSongs.isEmpty {
            moodsCarousel
        }

        if !social.friendsActivity.isEmpty {
            HubFriendsActivityCarousel(entries: social.friendsActivity)
        }

        if !account.similarListenerTracks.isEmpty {
            HubSimilarListenersCarousel(
                tracks: account.similarListenerTracks,
                listenerCount: account.similarListenerCount,
                onSelect: { track in
                    similarListenerSearchQuery = [track.title, track.artist].compactMap { $0 }.joined(separator: " ")
                }
            )
        }
    }

    /// Plays a random song from the whole on-device library with shuffle
    /// enabled — `setQueue` (called by `play(song:in:)`) shuffles the queue
    /// itself whenever `shuffleEnabled` is already true by the time it runs,
    /// so setting it first is all this needs.
    private func shuffleAll() {
        guard let random = library.allSongs.randomElement() else { return }
        player.shuffleEnabled = true
        player.play(song: random, in: library.allSongs)
    }

    /// Fetches the three network-backed hub extras once — independent of
    /// `reload()`'s on-device `library.allSongs.count` trigger, since these
    /// don't change just because the local library was rescanned.
    private func loadServerExtras() async {
        async let weeklyMix: Void = {
            guard let token = account.token else { return }
            await streaming.fetchWeeklyMix(token: token)
            weeklyMixSongs = streaming.weeklyMix.map { streaming.toSong(weeklyMixTrack: $0, token: token) }
        }()
        async let similarListeners: Void = account.fetchSimilarListeners()
        async let friendsActivity: Void = social.fetchFriendsActivity()
        _ = await (weeklyMix, similarListeners, friendsActivity)
    }

    // MARK: Mixes carousel

    private var mixesCarousel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HubSectionHeader(title: "Mixes For You", icon: "wand.and.stars")
                .padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(smartPlaylistStore.playlists) { mix in
                        HubParallaxCard {
                            NavigationLink {
                                SmartPlaylistDetailView(playlistID: mix.id)
                            } label: {
                                HubMixCard(mix: mix)
                                    .environmentObject(library)
                            }
                            .buttonStyle(PressableButtonStyle())
                        }
                        .frame(width: 168, height: 168)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: Moods carousel
    //
    // `MoodPlaylistService` doesn't expose a standalone per-bucket detail
    // view (it's owned by another workstream), so a mood tile jumps to the
    // existing `.moods` browsing tab rather than inventing a new push
    // destination into a screen this workstream doesn't own.

    private var moodBucketsWithSongs: [(bucket: MoodBucket, songs: [Song])] {
        [
            (MoodBucket.energetic, moodService.energeticSongs),
            (MoodBucket.chill, moodService.chillSongs),
            (MoodBucket.focus, moodService.focusSongs),
            (MoodBucket.sleep, moodService.sleepSongs),
        ].filter { !$0.1.isEmpty }
    }

    private var moodsCarousel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HubSectionHeader(title: "Moods", icon: "theatermasks.fill", seeAllTab: .moods, selectedTab: $selectedTab)
                .padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(Array(moodBucketsWithSongs.enumerated()), id: \.offset) { _, entry in
                        HubParallaxCard {
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                    selectedTab = .moods
                                }
                            } label: {
                                HubMoodCard(bucket: entry.bucket, count: entry.songs.count, representative: entry.songs.first)
                            }
                            .buttonStyle(PressableButtonStyle())
                        }
                        .frame(width: 140, height: 140)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: Data loading
    //
    // Snapshots everything into local `@State` off the render path (rather
    // than recomputing in `body` on every unrelated re-render — e.g. a
    // `player` publish from a track change), mirroring `FoldersTab`'s
    // `.task(id:)` pattern. Re-runs whenever `allSongs.count` changes.
    private func reload() {
        shortcuts = Self.buildShortcuts(library: library)
        recentlyAdded = library.recentlyAddedSongs(limit: 20)
        mostPlayed = library.mostPlayedSongs(limit: 20)
        forgottenFavorites = library.forgottenFavoriteSongs(limit: 20)
        if !hasLoadedOnce {
            withAnimation(.easeInOut(duration: 0.35)) { hasLoadedOnce = true }
        }
    }

    private static func buildShortcuts(library: LibraryManager) -> [HubShortcut] {
        var result: [HubShortcut] = []

        if !library.favoriteSongs.isEmpty {
            result.append(HubShortcut(
                id: "favorites", kind: .favorites, title: "Favorites",
                songs: library.favoriteSongs, icon: "heart.fill"
            ))
        }

        // Most recently created first — matches "what did I just make" intuition,
        // and keeps a fresh playlist visible on the first speed-dial page even
        // once a user has accumulated many.
        for playlist in library.playlists.sorted(by: { $0.createdAt > $1.createdAt }) {
            result.append(HubShortcut(
                id: "playlist-\(playlist.id.uuidString)", kind: .playlist(playlist), title: playlist.name,
                songs: library.songs(for: playlist), icon: "music.note.list"
            ))
        }

        for folder in MusicFolderService.localFolderGroups(from: library.allSongs) {
            result.append(HubShortcut(
                id: "folder-\(folder.id)", kind: .folder(folder), title: folder.id,
                songs: folder.songs, icon: "folder.fill"
            ))
        }

        return result
    }
}

// MARK: - HubShortcut

/// One speed-dial tile's worth of data — always backed by something real in
/// the user's own library, never placeholder/sample content.
struct HubShortcut: Identifiable {
    enum Kind {
        case favorites
        case playlist(Playlist)
        case folder(MusicFolderService.LocalFolderGroup)
    }
    let id: String
    let kind: Kind
    let title: String
    let songs: [Song]
    let icon: String
}

// MARK: - Speed Dial Section

/// A swipeable, paged 2×2 grid of shortcut tiles with page dots below —
/// reinterprets the reference design's "speed dial" as a compact way to
/// surface every playlist/folder/favorites shortcut without an unbounded
/// scroll, since (unlike the carousels below) tiles here are meant to feel
/// like a fixed "home screen" rather than an endless shelf.
private struct HubSpeedDialSection: View {
    let shortcuts: [HubShortcut]
    @State private var page = 0

    private let perPage = 4
    private let spacing: CGFloat = 12
    private let horizontalPadding: CGFloat = 16

    private var pages: [[HubShortcut]] {
        stride(from: 0, to: shortcuts.count, by: perPage).map {
            Array(shortcuts[$0..<min($0 + perPage, shortcuts.count)])
        }
    }

    /// Deliberately not measured via `GeometryReader` around the whole
    /// section — a paged `TabView` needs an explicit height up front (it
    /// doesn't self-size like a `VStack` would), and `UIScreen.main.bounds`
    /// gives a perfectly good estimate for a phone-only layout like the
    /// rest of this screen already assumes (see `AlbumHeaderView`'s fixed
    /// 256pt artwork for the same reasoning).
    private var tileWidth: CGFloat {
        (UIScreen.main.bounds.width - horizontalPadding * 2 - spacing) / 2
    }

    private var tileHeight: CGFloat { tileWidth + 46 }
    private var pageHeight: CGFloat { tileHeight * 2 + spacing }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HubSectionHeader(title: "Quick Access", icon: "square.grid.2x2.fill")
                .padding(.horizontal, horizontalPadding)

            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, pageShortcuts in
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: spacing), GridItem(.flexible(), spacing: spacing)],
                        spacing: spacing
                    ) {
                        ForEach(pageShortcuts) { shortcut in
                            HubSpeedDialTile(shortcut: shortcut, tileWidth: tileWidth)
                        }
                    }
                    .padding(.horizontal, horizontalPadding)
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: pageHeight)

            if pages.count > 1 {
                HStack(spacing: 6) {
                    ForEach(pages.indices, id: \.self) { i in
                        Capsule()
                            .fill(i == page ? AppTheme.dynamicAccent : AppTheme.textSecondary.opacity(0.3))
                            .frame(width: i == page ? 16 : 6, height: 6)
                    }
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.75), value: page)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct HubSpeedDialTile: View {
    let shortcut: HubShortcut
    let tileWidth: CGFloat

    @EnvironmentObject private var library: LibraryManager

    // Snapshotted once (see `.task(id:)` below) rather than recomputed every
    // body evaluation: both `listenedFraction` and `collageSongs` scan the
    // shortcut's full song list (and, for the former, do a PlayHistoryStore
    // lookup per song), and this tile previously also held an unused
    // `@EnvironmentObject var player: AudioPlayerManager` — since SwiftUI
    // invalidates every view holding a reference to an ObservableObject on
    // ANY of its `@Published` changes (not just ones the view actually
    // reads), that meant every visible speed-dial tile redid both scans on
    // every play/pause/track-change/queue-mutation even though this view
    // never used `player` for anything. Dropping the dependency and caching
    // the results fixes both the unnecessary re-renders and the repeated
    // O(n) work.
    @State private var listenedFraction: Double? = nil
    @State private var collage: [Song] = []

    var body: some View {
        NavigationLink {
            destination
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HubArtworkCollage(
                    songs: collage,
                    size: tileWidth,
                    placeholderIcon: shortcut.icon
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(shortcut.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)
                    // A thin "how much of this have you listened to" bar when
                    // it's meaningful (more than one song); otherwise just a
                    // plain track count — see `LibraryManager.listenedFraction`.
                    if let fraction = listenedFraction, shortcut.songs.count > 1 {
                        ProgressView(value: fraction)
                            .tint(AppTheme.dynamicAccent)
                            .frame(height: 3)
                    } else {
                        Text("\(shortcut.songs.count) \(shortcut.songs.count == 1 ? "song" : "songs")")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
            }
            .frame(width: tileWidth, alignment: .leading)
        }
        .buttonStyle(PressableButtonStyle())
        .task(id: shortcut.id) {
            listenedFraction = library.listenedFraction(of: shortcut.songs)
            collage = library.collageSongs(from: shortcut.songs)
        }
    }

    @ViewBuilder
    private var destination: some View {
        switch shortcut.kind {
        case .favorites:
            FavoritesView()
        case .playlist(let playlist):
            PlaylistDetailView(playlist: playlist)
        case .folder(let folder):
            LocalFolderDetailView(folderName: folder.id, folderURL: folder.dirURL)
        }
    }
}

// MARK: - Artwork Collage

/// A single big thumbnail for 0-1 songs, or a 2×2 mosaic of up to 4 for a
/// richer "this is a real collection" look — always built from the
/// shortcut's actual songs (see `LibraryManager.collageSongs(from:)`), never
/// a placeholder image.
private struct HubArtworkCollage: View {
    let songs: [Song]
    let size: CGFloat
    let placeholderIcon: String

    var body: some View {
        Group {
            if songs.isEmpty {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppTheme.surface)
                    .overlay {
                        Image(systemName: placeholderIcon)
                            .font(.system(size: size * 0.28))
                            .foregroundStyle(AppTheme.dynamicAccent)
                    }
            } else if songs.count == 1 {
                ArtworkThumbnail(song: songs[0], size: size)
            } else {
                let half = (size / 2).rounded(.down)
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        ArtworkThumbnail(song: songs[0], size: half)
                        quadrant(index: 1, size: half)
                    }
                    HStack(spacing: 0) {
                        quadrant(index: 2, size: half)
                        quadrant(index: 3, size: half)
                    }
                }
                .frame(width: half * 2, height: half * 2)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func quadrant(index: Int, size: CGFloat) -> some View {
        if songs.indices.contains(index) {
            ArtworkThumbnail(song: songs[index], size: size)
        } else {
            Rectangle().fill(AppTheme.surface).frame(width: size, height: size)
        }
    }
}

// MARK: - Section header (with optional "See All" chip)

private struct HubSectionHeader: View {
    let title: String
    let icon: String
    var seeAllTab: LibraryTab? = nil
    var selectedTab: Binding<LibraryTab>? = nil

    var body: some View {
        HStack {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)
            Spacer()
            if let seeAllTab, let selectedTab {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        selectedTab.wrappedValue = seeAllTab
                    }
                } label: {
                    HStack(spacing: 2) {
                        Text("See All")
                        Image(systemName: "chevron.right")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.dynamicAccent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(AppTheme.dynamicAccent.opacity(0.12)))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Generic song carousel (Recently Added / On Repeat / Forgotten Favorites)

private struct HubSongCarousel: View {
    let title: String
    let icon: String
    let songs: [Song]
    var seeAllTab: LibraryTab? = nil
    @Binding var selectedTab: LibraryTab

    @EnvironmentObject private var player: AudioPlayerManager

    private let cardWidth: CGFloat = 132

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HubSectionHeader(title: title, icon: icon, seeAllTab: seeAllTab, selectedTab: $selectedTab)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(songs) { song in
                        HubParallaxCard {
                            Button {
                                player.play(song: song, in: songs)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    ArtworkThumbnail(song: song, size: cardWidth)
                                        .overlay(alignment: .bottomTrailing) { nowPlayingBadge(for: song) }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(song.displayName)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(AppTheme.textPrimary)
                                            .lineLimit(1)
                                        Text(song.artistName)
                                            .font(.caption2)
                                            .foregroundStyle(AppTheme.textSecondary)
                                            .lineLimit(1)
                                    }
                                }
                                .frame(width: cardWidth, alignment: .leading)
                            }
                            .buttonStyle(PressableButtonStyle())
                        }
                        .frame(width: cardWidth, height: cardWidth + 46)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private func nowPlayingBadge(for song: Song) -> some View {
        if player.currentSong?.id == song.id {
            Image(systemName: "waveform")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .padding(5)
                .background(AppTheme.dynamicAccent, in: Circle())
                .padding(6)
        }
    }
}

// MARK: - Quick Actions row

/// One-tap shortcuts pinned to the very top of the hub, above even the speed
/// dial — the hub is a "what do I want to do right now" landing screen, and
/// "just start playing something" is the single most common answer to that,
/// so it shouldn't need a scroll + a tap-into-a-tile to get there.
private struct HubQuickActionsRow: View {
    let hasLibrary: Bool
    let onShuffleAll: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                actionChip(title: "Shuffle All", icon: "shuffle", action: onShuffleAll)
                    .disabled(!hasLibrary)
                    .opacity(hasLibrary ? 1 : 0.4)
            }
            .padding(.horizontal, 16)
        }
    }

    private func actionChip(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppTheme.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .adaptiveGlass(
                tint: AppTheme.dynamicAccent.opacity(0.16),
                in: Capsule(),
                fallback: AppTheme.surface
            )
        }
        .buttonStyle(PressableButtonStyle())
    }
}

// MARK: - Friends Activity carousel

/// "What friends are playing" — surfaces the Social Ecosystem's friends-only
/// activity feed (recent plays/favorites, already gated server-side by each
/// friend's own `share_now_playing` privacy toggle) right on the hub instead
/// of it only living inside the Friends screen, so the two big features this
/// app shipped in the same window — the library hub and the social system —
/// actually feel like one app rather than two bolted together.
private struct HubFriendsActivityCarousel: View {
    let entries: [SocialActivityEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HubSectionHeader(title: "Friends Activity", icon: "person.2.wave.2.fill")
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(entries.prefix(20)) { entry in
                        HubParallaxCard {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    SocialAvatarView(userId: entry.userId, size: 28)
                                    Text(entry.displayName ?? entry.username)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(AppTheme.textPrimary)
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                    Image(systemName: entry.isPlayed ? "play.fill" : "heart.fill")
                                        .font(.caption2)
                                        .foregroundStyle(AppTheme.dynamicAccent)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.title ?? "Unknown Title")
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.textPrimary)
                                        .lineLimit(1)
                                    if let artist = entry.artist, !artist.isEmpty {
                                        Text(artist)
                                            .font(.caption2)
                                            .foregroundStyle(AppTheme.textSecondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(10)
                            .frame(width: 168, height: 100, alignment: .topLeading)
                            .adaptiveGlass(
                                tint: AppTheme.dynamicAccent.opacity(0.1),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous),
                                fallback: AppTheme.surface
                            )
                        }
                        .frame(width: 168, height: 100)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
        }
    }
}

// MARK: - Similar Listeners carousel

/// "Because listeners like you also play..." — real collaborative-filtering
/// recommendations from `/social/similar-listeners` (other opted-in users
/// whose top artists overlap with the caller's own). These are plain
/// title/artist suggestions, not something already in this user's library or
/// server storage, so tapping one opens the Cloud Services search pre-filled
/// with that title/artist rather than trying to play it directly.
private struct HubSimilarListenersCarousel: View {
    let tracks: [TrendingTrack]
    let listenerCount: Int
    let onSelect: (TrendingTrack) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HubSectionHeader(title: "Similar Listeners", icon: "person.3.sequence.fill")
                .padding(.horizontal, 16)
            Text("Based on \(listenerCount) listener\(listenerCount == 1 ? "" : "s") with taste like yours")
                .font(.caption2)
                .foregroundStyle(AppTheme.textSecondary)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(tracks.prefix(20)) { track in
                        HubParallaxCard {
                            Button { onSelect(track) } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(AppTheme.dynamicAccent.opacity(0.16))
                                        Image(systemName: "waveform.badge.magnifyingglass")
                                            .font(.title3)
                                            .foregroundStyle(AppTheme.dynamicAccent)
                                    }
                                    .frame(width: 132, height: 132)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(track.title)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(AppTheme.textPrimary)
                                            .lineLimit(1)
                                        if let artist = track.artist, !artist.isEmpty {
                                            Text(artist)
                                                .font(.caption2)
                                                .foregroundStyle(AppTheme.textSecondary)
                                                .lineLimit(1)
                                        }
                                    }
                                }
                                .frame(width: 132, alignment: .leading)
                            }
                            .buttonStyle(PressableButtonStyle())
                        }
                        .frame(width: 132, height: 178)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
        }
    }
}

// MARK: - Mix card (SmartPlaylist — Recently Added / Most Played / Forgotten
// Favorites / Quick Listens / anything the user built themselves)

private struct HubMixCard: View {
    let mix: SmartPlaylist
    @EnvironmentObject private var library: LibraryManager

    // Snapshotted once per mix rather than re-evaluated (a full rule scan
    // over the library) on every body re-render — same reasoning as
    // `HubSpeedDialTile`'s `listenedFraction`/`collage` caching above.
    @State private var songs: [Song] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                AppTheme.dynamicAccentGradient
                if let song = songs.first {
                    ArtworkThumbnail(song: song, size: 168)
                        .opacity(0.85)
                }
                VStack {
                    Spacer()
                    HStack {
                        Image(systemName: mix.icon)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                            .shadow(radius: 3)
                        Spacer()
                    }
                    .padding(10)
                }
            }
            .frame(width: 168, height: 110)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(mix.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                Text("\(songs.count) \(songs.count == 1 ? "song" : "songs")")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .frame(width: 168, alignment: .leading)
        .task(id: mix.id) {
            songs = mix.evaluate(over: library.allSongs, favorites: library.favoriteSongIDs)
        }
    }
}

// MARK: - Mood card

private struct HubMoodCard: View {
    let bucket: MoodBucket
    let count: Int
    let representative: Song?

    private var icon: String {
        switch bucket {
        case .energetic: return "bolt.fill"
        case .chill:     return "leaf.fill"
        case .focus:     return "target"
        case .sleep:     return "moon.stars.fill"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AppTheme.surface)
                if let representative {
                    ArtworkThumbnail(song: representative, size: 140)
                        .opacity(0.55)
                }
                VStack {
                    Spacer()
                    HStack {
                        Image(systemName: icon)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                            .shadow(radius: 3)
                        Spacer()
                    }
                    .padding(10)
                }
            }
            .frame(width: 140, height: 100)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(bucket.rawValue)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Text("\(count) \(count == 1 ? "song" : "songs")")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .frame(width: 140, alignment: .leading)
    }
}

// MARK: - Carousel scroll parallax
//
// A light "physics" touch for horizontal carousels: cards nearer the screen's
// horizontal center render at full scale/opacity, cards further out shrink
// and fade slightly — cheap (`GeometryReader` + `.global` frame comparison,
// no scroll-offset preference-key plumbing) and works back to iOS 16 (the
// project's deployment target — `.scrollTransition` is iOS 17+ only, so this
// hand-rolled version is used instead of it everywhere in the hub).
private struct HubParallaxCard<Content: View>: View {
    private let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        GeometryReader { geo in
            let midX = geo.frame(in: .global).midX
            let screenMidX = UIScreen.main.bounds.width / 2
            let distance = abs(midX - screenMidX)
            let maxDistance = UIScreen.main.bounds.width / 2 + 100
            let normalized = min(distance / maxDistance, 1)
            content
                .scaleEffect(1 - normalized * 0.08)
                .opacity(1 - normalized * 0.25)
        }
    }
}

// MARK: - Loading skeleton

private struct HubSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            VStack(alignment: .leading, spacing: 10) {
                skeletonBar(width: 130, height: 18).padding(.horizontal, 16)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(0..<4, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: 6) {
                            skeletonBlock(cornerRadius: 12).aspectRatio(1, contentMode: .fit)
                            skeletonBar(width: 90, height: 12)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }

            ForEach(0..<2, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 10) {
                    skeletonBar(width: 120, height: 16).padding(.horizontal, 16)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(0..<4, id: \.self) { _ in
                                VStack(alignment: .leading, spacing: 6) {
                                    skeletonBlock(cornerRadius: 10).frame(width: 132, height: 132)
                                    skeletonBar(width: 100, height: 10)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
        }
    }

    private func skeletonBlock(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(AppTheme.surface)
            .overlay(ShimmerOverlay().clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)))
    }

    private func skeletonBar(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
            .fill(AppTheme.surface)
            .frame(width: width, height: height)
            .overlay(ShimmerOverlay().clipShape(RoundedRectangle(cornerRadius: height / 2, style: .continuous)))
    }
}

// MARK: - Animated empty state

private struct HubEmptyState: View {
    @State private var animateIn = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 52, weight: .semibold))
                .foregroundStyle(AppTheme.dynamicAccentGradient)
                .scaleEffect(animateIn ? 1 : 0.7)
            Text("Your hub is empty")
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)
            Text("Add music to see your playlists, folders, and favorites collected here.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
        .opacity(animateIn ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.65).delay(0.05)) {
                animateIn = true
            }
        }
    }
}
