import SwiftUI
import UIKit

extension NowPlayingView {

    // MARK: - Lyrics

    var lyricsSection: some View {
        DisclosureGroup(
            isExpanded: $showLyrics,
            content: {
                Group {
                    if lyricsLines.isEmpty {
                        Text("Lyrics not available")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 20)
                    } else {
                        NowPlayingLyricsBody(lines: lyricsLines)
                    }
                }
                .padding(.top, 8)

                if player.currentSong != nil {
                    HStack(spacing: 16) {
                        if !lyricsLines.isEmpty {
                            Button {
                                showLyricsSyncEditor = true
                            } label: {
                                Label("Sync Editor", systemImage: "waveform.and.mic")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.dynamicAccent)
                            }
                        }
                        // Always available, even with no lyrics found yet —
                        // "Open up custom lyrics files injecting": a user's
                        // own .lrc (synced) or .txt (plain) file for this
                        // track, picked from the system document browser.
                        Button {
                            showLyricsFileImporter = true
                        } label: {
                            Label("Import File", systemImage: "square.and.arrow.down")
                                .font(.caption)
                                .foregroundStyle(AppTheme.dynamicAccent)
                        }
                        // The only lyrics source that works for a track no
                        // database has ever heard of (a personal/unreleased
                        // recording) and the only one that verifies wording
                        // against the actual audio — see
                        // `generateLyricsWithAria()`. Always available (not
                        // just when `lyricsLines` is empty), since it's also
                        // how an existing fetched/imported guess gets
                        // cross-checked and re-timed against the real track.
                        Button {
                            generateLyricsWithAria()
                        } label: {
                            if isGeneratingLyrics {
                                Label("Generating…", systemImage: "waveform")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.textSecondary)
                            } else {
                                Label("Generate with Aria", systemImage: "sparkles")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.dynamicAccent)
                            }
                        }
                        .disabled(isGeneratingLyrics)
                    }
                    .padding(.top, 4)
                }
            },
            label: {
                Text("Lyrics")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
            }
        )
        .tint(AppTheme.dynamicAccent)
        .panelStyle()
        // `.sheet(isPresented: $showLyricsSyncEditor)` lives on
        // `NowPlayingView.body` now, not here — the 2026-07 redesign's
        // full-lyrics hero mode (`NowPlayingDisplayMode.lyrics`) also opens
        // this same sync editor, and that hero can be showing while this
        // disclosure-group panel isn't even selected/mounted.
    }
}

// MARK: - Progress-isolated subview
//
// Declares its own `@EnvironmentObject var progress` rather than relying on
// `NowPlayingView`'s — see NowPlayingView+Timeline.swift's isolation comment
// for why. Lyrics sync highlighting genuinely needs live position updates
// (unlike the one-shot reads in NowPlayingView+Bookmarks.swift), so this
// stays a real `PlaybackProgress` subscriber, just scoped to this small view
// instead of the whole Now Playing screen.
private struct NowPlayingLyricsBody: View {
    @EnvironmentObject private var progress: PlaybackProgress
    @EnvironmentObject private var player: AudioPlayerManager
    let lines: [LrcLine]

    var body: some View {
        LyricsView(lines: lines, currentPosition: progress.position, isPlaying: player.isPlaying)
            .frame(height: 260)
            .clipped()
    }
}
