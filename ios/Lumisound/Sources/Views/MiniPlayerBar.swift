import SwiftUI
import UIKit

struct MiniPlayerBar: View {
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var library: LibraryManager

    // Tapping the mini player switches to the Now Playing tab rather than
    // presenting a second, freshly-instantiated NowPlayingView in a sheet.
    // Previously each of the ~8 screens hosting MiniPlayerBar owned its own
    // sheet-presented NowPlayingView, so the view's timers/animations/lyrics
    // fetches could run twice (once in the Tab 2 instance, once in the sheet)
    // whenever a sheet was open. Reusing the same @AppStorage key as
    // ContentView's TabView selection means there is only ever one
    // NowPlayingView instance alive.
    @AppStorage("selected_tab") private var selectedTab = 0

    private let playHaptic  = UIImpactFeedbackGenerator(style: .light)
    private let skipHaptic  = UIImpactFeedbackGenerator(style: .medium)
    private let heartHaptic = UIImpactFeedbackGenerator(style: .soft)

    var body: some View {
        if player.currentSong != nil {
            barContent
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
                        .id(player.currentSong?.id)
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                    songInfo
                        .id(player.currentSong?.id)
                        .transition(.opacity)
                }
                .animation(.easeInOut(duration: 0.25), value: player.currentSong?.id)
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedTab = 1
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
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(.white.opacity(0.12), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.25), radius: 5, x: 0, y: 3)
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
                        .fill(
                            LinearGradient(
                                colors: [AppTheme.dynamicAccent, AppTheme.accentSoft],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 38, height: 38)
                        .shadow(color: AppTheme.dynamicAccent.opacity(0.4), radius: 6, x: 0, y: 3)
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .contentTransition(.opacity)
                }
            }
            .buttonStyle(PressableButtonStyle())
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
            .buttonStyle(PressableButtonStyle())
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
                Capsule()
                    .fill(AppTheme.surface)
                    .frame(height: 3)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.dynamicAccent, AppTheme.accentSoft],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(width: geo.size.width * CGFloat(fraction), height: 3)
                    .animation(.linear(duration: 0.25), value: progress.position)
            }
        }
        .frame(height: 3)
    }
}
