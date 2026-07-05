import SwiftUI
import MediaPlayer

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

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: songColumns)
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
                player.setQueue(songs, startIndex: 0, autoplay: true)
            } label: {
                Label("Play", systemImage: "play.fill")
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(AppTheme.dynamicAccent, in: Capsule())
                    .foregroundStyle(.white)
            }
            Button {
                player.setQueue(songs.shuffled(), startIndex: 0, autoplay: true)
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

    var body: some View {
        VStack(spacing: 0) {
            if !songs.isEmpty {
                songsActionHeader
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
                                    if isSelecting {
                                        toggleSelection(song)
                                    } else {
                                        player.play(song: song, in: songs)
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
                                    ArtworkService.shared.prefetch(songs: Array(songs[lower..<upper]), pixelSize: 192)
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
        .onAppear {
            // Warm the first 30 songs' artwork at background priority so
            // rows/cells have images ready before the user scrolls to them.
            ArtworkService.shared.prefetch(songs: Array(songs.prefix(30)), pixelSize: prefetchPixelSize)
        }
        .onChange(of: songs.count) { _ in
            // Re-trigger prefetch when the song list grows (e.g. after a scan).
            ArtworkService.shared.prefetch(songs: Array(songs.prefix(30)), pixelSize: prefetchPixelSize)
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
