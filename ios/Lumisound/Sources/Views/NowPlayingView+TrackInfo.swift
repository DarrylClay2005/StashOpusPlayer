import SwiftUI
import UIKit

extension NowPlayingView {

    // MARK: - Track Info + Favorite

    var trackInfoSection: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(player.currentSong?.displayName ?? "Nothing Playing")
                    .font(.title2.bold())
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
                HStack(spacing: 6) {
                    MarqueeText(
                        text: player.currentSong?.artistName ?? "Choose a song from the Library",
                        font: .body,
                        color: AppTheme.textSecondary
                    )
                    .frame(height: 20)
                    .contentTransition(.opacity)

                    if let bpm = player.currentSong?.bpm {
                        Text("\(Int(bpm.rounded())) BPM")
                            .font(AppTheme.monoFont(size: 11))
                            .foregroundStyle(AppTheme.textSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppTheme.elevatedSurface, in: Capsule())
                            .fixedSize()
                    }

                    if let song = player.currentSong, let formatTag = song.formatTag {
                        Button {
                            selectHaptic.selectionChanged()
                            showFormatInfoSheet = true
                        } label: {
                            HStack(spacing: 4) {
                                if player.isUsingOpusPlayer {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 9))
                                        .foregroundStyle(AppTheme.warning)
                                }
                                Text(formatTag)
                                    .font(AppTheme.monoFont(size: 11))
                            }
                            .foregroundStyle(AppTheme.textSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppTheme.elevatedSurface, in: Capsule())
                            .fixedSize()
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.25), value: player.currentSong?.id)
            Spacer(minLength: 8)

            if let song = player.currentSong {
                Button {
                    heartHaptic.impactOccurred()
                    library.toggleFavorite(songID: song.id)
                } label: {
                    Image(systemName: library.isFavorite(songID: song.id) ? "heart.fill" : "heart")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(library.isFavorite(songID: song.id) ? AppTheme.dynamicAccent : AppTheme.textSecondary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: library.isFavorite(songID: song.id))
            }
        }
        // Slide-up + fade-in on track change
        .opacity(trackInfoVisible ? 1 : 0)
        .offset(y: trackInfoVisible ? 0 : 14)
        .animation(.spring(response: 0.42, dampingFraction: 0.72), value: trackInfoVisible)
    }
}
