import SwiftUI
import UIKit

struct MiniPlayerBar: View {
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var library: LibraryManager
    @EnvironmentObject private var sleepTimer: SleepTimerService
    @State private var showingNowPlaying = false

    private let playHaptic  = UIImpactFeedbackGenerator(style: .light)
    private let skipHaptic  = UIImpactFeedbackGenerator(style: .medium)
    private let heartHaptic = UIImpactFeedbackGenerator(style: .soft)

    var body: some View {
        if player.currentSong != nil {
            barContent
                .sheet(isPresented: $showingNowPlaying) {
                    // isSheet: true tells NowPlayingView not to wrap itself in a
                    // NavigationStack — the sheet container provides one already,
                    // so wrapping again would produce a double navigation bar.
                    NavigationStack {
                        NowPlayingView(isSheet: true)
                            .environmentObject(player)
                            .environmentObject(player.progress)
                            .environmentObject(library)
                            .environmentObject(sleepTimer)
                    }
                }
        }
    }

    private var barContent: some View {
        ZStack(alignment: .top) {
            // Progress bar at the very top — its own view so the high-frequency
            // position ticks (every 0.25–0.5s) only re-render this sliver, not the
            // whole mini-player (which is mounted on most screens at once).
            MiniPlayerProgressBar()

            // Main content
            HStack(spacing: 12) {
                // Tap target for opening Now Playing — scoped to JUST the artwork
                // and text (not the whole bar). Attaching it to the full bar and
                // then trying to "absorb" taps on `controls` with empty
                // .simultaneousGesture/.onTapGesture handlers (the previous
                // approach) pits SwiftUI's gesture recognizers against the
                // Buttons below: taps on Play/Pause, Skip, and the heart could
                // intermittently fail to register OR also pop open the Now
                // Playing sheet — the "miniplayer freaks out" behavior reported.
                // Scoping the gesture to a non-interactive region sidesteps the
                // competition entirely; button taps now always go to the buttons.
                HStack(spacing: 12) {
                    artworkThumbnail
                    songInfo
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    showingNowPlaying = true
                }

                Spacer(minLength: 0)
                controls
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .padding(.bottom, 10)
            .frame(height: 80)
        }
        .adaptiveGlass(in: Rectangle())
    }

    private var artworkThumbnail: some View {
        Group {
            if let song = player.currentSong {
                ArtworkThumbnail(song: song, size: 46)
            }
        }
    }

    private var songInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let song = player.currentSong {
                MarqueeText(
                    text: song.displayName,
                    font: .subheadline.weight(.semibold),
                    color: AppTheme.textPrimary
                )
                .frame(height: 18)
                MarqueeText(
                    text: song.artistName,
                    font: .caption,
                    color: AppTheme.textSecondary
                )
                .frame(height: 14)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 16) {
            // Heart / Favorite button
            if let song = player.currentSong {
                Button {
                    heartHaptic.impactOccurred()
                    library.toggleFavorite(songID: song.id)
                } label: {
                    Image(systemName: library.isFavorite(songID: song.id) ? "heart.fill" : "heart")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(library.isFavorite(songID: song.id) ? AppTheme.dynamicAccent : AppTheme.textSecondary)
                }
                .buttonStyle(.plain)
                .animation(.spring(response: 0.3, dampingFraction: 0.55), value: library.isFavorite(songID: song.id))
            }

            // Play / Pause
            Button {
                playHaptic.impactOccurred()
                player.togglePlayPause()
            } label: {
                ZStack {
                    Circle()
                        .fill(AppTheme.dynamicAccent)
                        .frame(width: 36, height: 36)
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: player.isPlaying)

            // Skip Next
            Button {
                skipHaptic.impactOccurred()
                player.skipToNext()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(AppTheme.textPrimary)
            }
            .buttonStyle(.plain)
        }
        .onAppear {
            playHaptic.prepare()
            skipHaptic.prepare()
            heartHaptic.prepare()
        }
    }
}

// MARK: - MiniPlayerProgressBar

/// Renders the thin progress sliver atop the mini-player. Observes `PlaybackProgress`
/// directly (instead of reading `player.position`/`player.duration`) so its frequent
/// re-renders stay isolated to this small view rather than cascading through
/// `MiniPlayerBar`'s `objectWillChange` to every screen hosting it.
private struct MiniPlayerProgressBar: View {
    @EnvironmentObject private var progress: PlaybackProgress

    var body: some View {
        GeometryReader { geo in
            let fraction = progress.duration > 0 ? progress.position / progress.duration : 0
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(AppTheme.surface)
                    .frame(height: 2)
                Rectangle()
                    .fill(AppTheme.dynamicAccent)
                    .frame(width: geo.size.width * CGFloat(fraction), height: 2)
                    .animation(.linear(duration: 0.25), value: progress.position)
            }
        }
        .frame(height: 2)
    }
}
