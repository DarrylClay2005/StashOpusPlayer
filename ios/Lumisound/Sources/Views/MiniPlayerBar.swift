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
                            .environmentObject(library)
                            .environmentObject(sleepTimer)
                    }
                }
        }
    }

    private var barContent: some View {
        ZStack(alignment: .top) {
            // Progress bar at the very top
            progressBar

            // Main content
            HStack(spacing: 12) {
                artworkThumbnail
                songInfo
                Spacer(minLength: 0)
                controls
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .padding(.bottom, 10)
            .frame(height: 80)
        }
        .background(.ultraThinMaterial)
        .contentShape(Rectangle())
        .onTapGesture {
            showingNowPlaying = true
        }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            let progress = player.duration > 0 ? player.position / player.duration : 0
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(AppTheme.surface)
                    .frame(height: 2)
                Rectangle()
                    .fill(AppTheme.accent)
                    .frame(width: geo.size.width * CGFloat(progress), height: 2)
                    .animation(.linear(duration: 0.25), value: player.position)
            }
        }
        .frame(height: 2)
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
                Text(song.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                Text(song.artistName)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1)
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
                        .foregroundStyle(library.isFavorite(songID: song.id) ? AppTheme.accent : AppTheme.textSecondary)
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
                        .fill(AppTheme.accent)
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
        // Prevent taps on controls from bubbling up to the sheet trigger
        .simultaneousGesture(TapGesture().onEnded { })
        .onTapGesture { }
        .onAppear {
            playHaptic.prepare()
            skipHaptic.prepare()
            heartHaptic.prepare()
        }
    }
}
