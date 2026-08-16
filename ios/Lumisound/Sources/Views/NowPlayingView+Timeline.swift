import SwiftUI
import UIKit

extension NowPlayingView {

    // MARK: - Timeline

    var timelineSection: some View {
        VStack(spacing: 10) {
            NowPlayingScrubber(seekerStyle: seekerStyle, seekHaptic: seekHaptic)
            NowPlayingPlaytimeCounter(style: playtimeCounterStyle)
            seekerStylePicker
            if seekerStyle == .custom {
                CustomScrubberSettingsPanel()
            }
            playtimeCounterStylePicker
        }
    }

    var playtimeCounterRow: some View {
        NowPlayingPlaytimeCounter(style: playtimeCounterStyle)
    }

    var playtimeCounterStylePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(PlaytimeCounterStyle.allCases) { style in
                    Button {
                        selectHaptic.selectionChanged()
                        playtimeCounterStyle = style
                        UserDefaults.standard.set(style.rawValue, forKey: "nowPlaying_playtimeCounterStyle")
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: style.iconName)
                                .font(.system(size: 11, weight: .medium))
                            Text(style.displayName)
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(playtimeCounterStyle == style ? .white : AppTheme.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            playtimeCounterStyle == style ? AppTheme.dynamicAccent : AppTheme.surface,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                    .animation(.easeInOut(duration: 0.18), value: playtimeCounterStyle)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    var seekerStylePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(SeekerStyle.allCases) { style in
                    Button {
                        selectHaptic.selectionChanged()
                        seekerStyle = style
                        UserDefaults.standard.set(style.rawValue, forKey: "nowPlaying_seekerStyle")
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: style.iconName)
                                .font(.system(size: 11, weight: .medium))
                            Text(style.displayName)
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(seekerStyle == style ? .white : AppTheme.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            seekerStyle == style ? AppTheme.dynamicAccent : AppTheme.surface,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                    .animation(.easeInOut(duration: 0.18), value: seekerStyle)
                }
            }
            .padding(.horizontal, 2)
        }
    }
}

// MARK: - Progress-isolated subviews
//
// These declare their own `@EnvironmentObject var progress: PlaybackProgress`
// instead of `NowPlayingView` doing so. `@EnvironmentObject`/`@ObservedObject`
// subscribes to `objectWillChange` for as long as it's *declared* on a type —
// regardless of whether that render's `body` actually reads it (see
// `PlaybackProgress`'s doc comment in AudioPlayerManager.swift) — so having
// it on `NowPlayingView` itself, one of the biggest view trees in the app
// (artwork, queue preview, lyrics, EQ, effects), forced all of that to
// re-evaluate on every ~0.25-0.5s position tick. Isolating the two pieces
// that actually need live position into their own small views keeps only
// these re-rendering that often.

private struct NowPlayingScrubber: View {
    @EnvironmentObject private var progress: PlaybackProgress
    @EnvironmentObject private var player: AudioPlayerManager
    let seekerStyle: SeekerStyle
    let seekHaptic: UIImpactFeedbackGenerator

    var body: some View {
        let onSeek: (TimeInterval) -> Void = { seekHaptic.impactOccurred(); player.seek(to: $0) }
        switch seekerStyle {
        case .waveform:
            if let url = player.currentSong?.url, url.isFileURL, progress.duration > 0 {
                WaveformScrubberView(
                    url: url,
                    position: progress.position,
                    duration: progress.duration,
                    isPlaying: player.isPlaying,
                    onSeek: onSeek
                )
            } else {
                ClassicScrubberView(
                    position: progress.position,
                    duration: progress.duration,
                    isPlaying: player.isPlaying,
                    onSeek: onSeek
                )
            }
        case .classic:
            ClassicScrubberView(
                position: progress.position,
                duration: progress.duration,
                isPlaying: player.isPlaying,
                onSeek: onSeek
            )
        case .ring:
            RingScrubberView(
                position: progress.position,
                duration: progress.duration,
                isPlaying: player.isPlaying,
                onSeek: onSeek
            )
        case .bars:
            BarsScrubberView(
                position: progress.position,
                duration: progress.duration,
                isPlaying: player.isPlaying,
                onSeek: onSeek
            )
        case .digital:
            DigitalScrubberView(
                position: progress.position,
                duration: progress.duration,
                isPlaying: player.isPlaying,
                onSeek: onSeek
            )
        case .pill:
            PillScrubberView(
                position: progress.position,
                duration: progress.duration,
                isPlaying: player.isPlaying,
                onSeek: onSeek
            )
        case .neonLine:
            NeonLineScrubberView(
                position: progress.position,
                duration: progress.duration,
                isPlaying: player.isPlaying,
                onSeek: onSeek
            )
        case .dotTrack:
            DotTrackScrubberView(
                position: progress.position,
                duration: progress.duration,
                isPlaying: player.isPlaying,
                onSeek: onSeek
            )
        case .segmented:
            SegmentedScrubberView(
                position: progress.position,
                duration: progress.duration,
                isPlaying: player.isPlaying,
                onSeek: onSeek
            )
        case .minimal:
            MinimalScrubberView(
                position: progress.position,
                duration: progress.duration,
                isPlaying: player.isPlaying,
                onSeek: onSeek
            )
        case .ruler:
            RulerScrubberView(
                position: progress.position,
                duration: progress.duration,
                isPlaying: player.isPlaying,
                onSeek: onSeek
            )
        case .custom:
            CustomScrubberView(
                position: progress.position,
                duration: progress.duration,
                isPlaying: player.isPlaying,
                onSeek: onSeek
            )
        }
    }
}

private struct NowPlayingPlaytimeCounter: View {
    @EnvironmentObject private var progress: PlaybackProgress
    let style: PlaytimeCounterStyle

    var body: some View {
        Text(style.text(position: progress.position, duration: progress.duration))
            .font(AppTheme.monoFont(size: 13))
            .foregroundStyle(AppTheme.textSecondary)
            .contentTransition(.numericText())
            .animation(.snappy, value: progress.position)
    }
}
