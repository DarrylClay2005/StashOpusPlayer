import SwiftUI
import UIKit
import GroupActivities

extension NowPlayingView {

    // MARK: - Track Info + Favorite

    /// SharePlay "listen together" entry point. Calls the `GroupActivity`
    /// protocol's own `activate()` directly (a core, stable part of the
    /// GroupActivities framework since its introduction) rather than a
    /// higher-level SwiftUI convenience wrapper — the OS still owns the whole
    /// activation flow (FaceTime picker, permissions, etc.) once `activate()`
    /// is called; this app only needs to hand it the activity to propose.
    /// Actual cross-device sync is handled separately by `SharePlayCoordinator`
    /// once a session starts (see that type's doc comment for why sync is
    /// message-based rather than a shared `AVPlaybackCoordinator` timeline).
    /// Requires the Group Activities capability/entitlement — see integration
    /// notes wherever project.yml/entitlements changes are tracked.
    @ViewBuilder
    var sharePlayButton: some View {
        if let song = player.currentSong {
            Button {
                Task {
                    do {
                        _ = try await ListenTogetherActivity(songTitle: song.title, artistName: song.artist).activate()
                    } catch {
                        appWarn("SharePlay activate failed: \(error.localizedDescription)", category: "general")
                    }
                }
            } label: {
                Image(systemName: "shareplay")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
        }
    }

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

            sharePlayButton

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
