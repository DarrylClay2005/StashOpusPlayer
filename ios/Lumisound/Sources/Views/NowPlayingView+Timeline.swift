import SwiftUI
import UIKit

extension NowPlayingView {

    // MARK: - Timeline

    @ViewBuilder
    var timelineSection: some View {
        VStack(spacing: 10) {
            switch seekerStyle {
            case .waveform:
                if let url = player.currentSong?.url, url.isFileURL, progress.duration > 0 {
                    WaveformScrubberView(
                        url: url,
                        position: progress.position,
                        duration: progress.duration,
                        isPlaying: player.isPlaying,
                        onSeek: { seekHaptic.impactOccurred(); player.seek(to: $0) }
                    )
                } else {
                    ClassicScrubberView(
                        position: progress.position,
                        duration: progress.duration,
                        isPlaying: player.isPlaying,
                        onSeek: { seekHaptic.impactOccurred(); player.seek(to: $0) }
                    )
                }
            case .classic:
                ClassicScrubberView(
                    position: progress.position,
                    duration: progress.duration,
                    isPlaying: player.isPlaying,
                    onSeek: { seekHaptic.impactOccurred(); player.seek(to: $0) }
                )
            case .ring:
                RingScrubberView(
                    position: progress.position,
                    duration: progress.duration,
                    isPlaying: player.isPlaying,
                    onSeek: { seekHaptic.impactOccurred(); player.seek(to: $0) }
                )
            case .bars:
                BarsScrubberView(
                    position: progress.position,
                    duration: progress.duration,
                    isPlaying: player.isPlaying,
                    onSeek: { seekHaptic.impactOccurred(); player.seek(to: $0) }
                )
            case .digital:
                DigitalScrubberView(
                    position: progress.position,
                    duration: progress.duration,
                    isPlaying: player.isPlaying,
                    onSeek: { seekHaptic.impactOccurred(); player.seek(to: $0) }
                )
            case .pill:
                PillScrubberView(
                    position: progress.position,
                    duration: progress.duration,
                    isPlaying: player.isPlaying,
                    onSeek: { seekHaptic.impactOccurred(); player.seek(to: $0) }
                )
            case .neonLine:
                NeonLineScrubberView(
                    position: progress.position,
                    duration: progress.duration,
                    isPlaying: player.isPlaying,
                    onSeek: { seekHaptic.impactOccurred(); player.seek(to: $0) }
                )
            case .dotTrack:
                DotTrackScrubberView(
                    position: progress.position,
                    duration: progress.duration,
                    isPlaying: player.isPlaying,
                    onSeek: { seekHaptic.impactOccurred(); player.seek(to: $0) }
                )
            }

            playtimeCounterRow
            seekerStylePicker
            playtimeCounterStylePicker
        }
    }

    var playtimeCounterRow: some View {
        Text(playtimeCounterStyle.text(position: progress.position, duration: progress.duration))
            .font(AppTheme.monoFont(size: 13))
            .foregroundStyle(AppTheme.textSecondary)
            .contentTransition(.numericText())
            .animation(.snappy, value: progress.position)
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
