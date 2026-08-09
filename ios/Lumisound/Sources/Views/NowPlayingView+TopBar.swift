import SwiftUI
import UIKit
import AVKit

extension NowPlayingView {

    // MARK: - Top bar
    //
    // A reinterpretation of the YouTube-Music-style reference's collapsed-
    // header row (expand chevron / headphones-video toggle / cast / overflow)
    // — this screen is a permanent tab rather than a dismissible sheet (see
    // `MiniPlayerBar`, owned by another workstream, for this app's actual
    // "collapsed player"), so there's no expand/dismiss chevron here. The
    // display-mode pill, AirPlay/cast button, and overflow menu all carry
    // over as genuinely useful affordances though.

    var topBar: some View {
        HStack(spacing: 10) {
            displayModePill
            Spacer()
            AirPlayRoutePicker(
                tint: UIColor(AppTheme.textSecondary),
                activeTint: UIColor(screenStyle.accentColor)
            )
            .frame(width: 26, height: 26)
            overflowMenu
        }
    }

    /// Reinterpretation of the reference design's headphones/video toggle:
    /// this app has no video track, so it instead switches the hero card
    /// between the artwork display and a full-size synced-lyrics view.
    var displayModePill: some View {
        HStack(spacing: 2) {
            ForEach(NowPlayingDisplayMode.allCases) { mode in
                Button {
                    selectHaptic.selectionChanged()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        displayMode = mode
                    }
                } label: {
                    Image(systemName: mode.iconName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(displayMode == mode ? .white : AppTheme.textSecondary)
                        .frame(width: 34, height: 28)
                        .background {
                            if displayMode == mode {
                                Capsule(style: .continuous).fill(screenStyle.accentColor)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(AppTheme.surface.opacity(0.6), in: Capsule(style: .continuous))
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: displayMode)
    }

    /// Overflow menu — sleep timer (previously only reachable once already
    /// running, via `sleepTimerPill`; this is the only way to *start* one
    /// from Now Playing), style manager, format info, and share.
    var overflowMenu: some View {
        Menu {
            Button {
                showSleepTimerSheet = true
            } label: {
                Label(sleepTimer.isActive ? "Edit Sleep Timer" : "Sleep Timer", systemImage: "moon.zzz.fill")
            }
            Button {
                showStyleManager = true
            } label: {
                Label("Manage Styles", systemImage: "paintpalette")
            }
            if player.currentSong?.formatTag != nil {
                Button {
                    showFormatInfoSheet = true
                } label: {
                    Label("Format Info", systemImage: "info.circle")
                }
            }
            if let url = player.currentSong?.url {
                ShareLink(item: url) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
            if account.isLoggedIn, player.currentSong != nil {
                Button {
                    showTransferPlaybackSheet = true
                } label: {
                    Label("Transfer Playback", systemImage: "arrow.triangle.swap")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle.fill")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 30, height: 30)
        }
    }

    // MARK: - "Playing from" row

    /// Context label + a pill jumping straight to the Queue panel —
    /// reinterprets the reference design's "Playing from X" row + queue/save
    /// affordance pairing.
    var playingFromRow: some View {
        HStack(spacing: 8) {
            Image(systemName: player.currentPlaylistID != nil ? "music.note.list" : "books.vertical.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.textSecondary)
            Text("Playing from \(playingFromLabel)")
                .font(.caption.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(1)

            Spacer(minLength: 8)

            Button {
                selectHaptic.selectionChanged()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    selectedPanel = .queue
                }
            } label: {
                HStack(spacing: 4) {
                    Text("Queue")
                        .font(.caption.weight(.semibold))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(screenStyle.accentColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(screenStyle.accentColor.opacity(0.14), in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Action pills row

    /// Like / AI-suggestion (Auto-Radio) / Save-to-playlist / Share pills —
    /// a reinterpretation of the reference design's action-pill row.
    /// Deliberately no "dislike" pill: this app has no recommendation/
    /// blacklist infrastructure for one to actually influence (see this
    /// workstream's final summary) — a pill that looks functional but isn't
    /// would be worse than not having it.
    var actionPillsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if let song = player.currentSong {
                    actionPill(
                        icon: library.isFavorite(songID: song.id) ? "heart.fill" : "heart",
                        label: "Like",
                        isActive: library.isFavorite(songID: song.id)
                    ) {
                        heartHaptic.impactOccurred()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            library.toggleFavorite(songID: song.id)
                        }
                    }
                }

                actionPill(icon: "sparkles", label: "Radio", isActive: player.autoRadioEnabled) {
                    selectHaptic.selectionChanged()
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        player.autoRadioEnabled.toggle()
                    }
                }

                if player.currentSong != nil, !library.playlists.isEmpty {
                    Menu {
                        ForEach(library.playlists) { playlist in
                            Button(playlist.name) {
                                if let song = player.currentSong {
                                    library.addSong(id: song.id, toPlaylistID: playlist.id)
                                }
                            }
                        }
                    } label: {
                        actionPillLabel(icon: "plus.circle", label: "Save", isActive: false)
                    }
                }

                if let url = player.currentSong?.url {
                    ShareLink(item: url) {
                        actionPillLabel(icon: "square.and.arrow.up", label: "Share", isActive: false)
                    }
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
    }

    func actionPill(icon: String, label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            actionPillLabel(icon: icon, label: label, isActive: isActive)
        }
        .buttonStyle(PressableButtonStyle())
    }

    func actionPillLabel(icon: String, label: String, isActive: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
            Text(label)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(isActive ? .white : AppTheme.textPrimary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            isActive ? screenStyle.accentColor : AppTheme.surface,
            in: RoundedRectangle(cornerRadius: screenStyle.elementCornerRadius, style: .continuous)
        )
        .animation(.easeInOut(duration: 0.18), value: isActive)
    }
}
