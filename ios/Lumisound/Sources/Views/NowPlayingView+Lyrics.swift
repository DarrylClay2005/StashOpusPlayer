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

                if !lyricsLines.isEmpty, player.currentSong != nil {
                    Button {
                        showLyricsSyncEditor = true
                    } label: {
                        Label("Sync Editor", systemImage: "waveform.and.mic")
                            .font(.caption)
                            .foregroundStyle(AppTheme.dynamicAccent)
                    }
                    .padding(.top, 4)
                }

                // Karaoke Mode — one switch that pairs the synced lyrics above
                // with the center-channel vocal-cancellation audio effect, so
                // "sing along" is a single toggle instead of hunting in Effects.
                if player.currentSong != nil {
                    Toggle(isOn: Binding(
                        get: { player.audioSettings.activeEffectID == "karaoke" },
                        set: { on in player.applyEffect(on ? AudioEffectsService.karaoke : AudioEffectsService.none) }
                    )) {
                        Label("Karaoke Mode", systemImage: "music.mic")
                            .font(.caption)
                            .foregroundStyle(AppTheme.textPrimary)
                    }
                    .tint(AppTheme.dynamicAccent)
                    .padding(.top, 6)

                    if player.audioSettings.activeEffectID == "karaoke" {
                        Text("Reduces lead vocals (center-channel cancellation) so you can sing along to the lyrics above. Works best on standard stereo mixes.")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
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
        .sheet(isPresented: $showLyricsSyncEditor) {
            LyricsSyncEditorView(initialLines: lyricsLines)
                .environmentObject(player)
                .environmentObject(player.progress)
        }
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
