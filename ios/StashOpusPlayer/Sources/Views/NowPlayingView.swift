import SwiftUI

struct NowPlayingView: View {
    @EnvironmentObject private var player: AudioPlayerManager
    @State private var isSeeking = false
    @State private var draftPosition: TimeInterval = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    artwork
                    trackInfo
                    timeline
                    transport
                    playbackControls
                    equalizerControls
                }
                .padding()
            }
            .navigationTitle("Now Playing")
            .appScreenBackground()
        }
    }

    private var artwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppTheme.surface)
                .aspectRatio(1, contentMode: .fit)
            Image(systemName: "music.note")
                .font(.system(size: 76, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
        }
        .frame(maxWidth: 320)
    }

    private var trackInfo: some View {
        VStack(spacing: 6) {
            Text(player.currentSong?.displayName ?? "Nothing Playing")
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
            Text(player.currentSong?.artistName ?? "Choose a song from Library")
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    private var timeline: some View {
        VStack(spacing: 6) {
            Slider(
                value: Binding(
                    get: { isSeeking ? draftPosition : player.position },
                    set: { draftPosition = $0 }
                ),
                in: 0...max(player.duration, 1),
                onEditingChanged: { editing in
                    isSeeking = editing
                    if !editing {
                        player.seek(to: draftPosition)
                    }
                }
            )
            .tint(AppTheme.accent)

            HStack {
                Text(formatTime(isSeeking ? draftPosition : player.position))
                Spacer()
                Text(formatTime(player.duration))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(AppTheme.textSecondary)
        }
    }

    private var transport: some View {
        HStack(spacing: 26) {
            Button {
                player.toggleShuffle()
            } label: {
                Image(systemName: "shuffle")
                    .foregroundStyle(player.shuffleEnabled ? AppTheme.accent : AppTheme.textPrimary)
            }

            Button {
                player.skipToPrevious()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.title2)
            }

            Button {
                player.togglePlayPause()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title)
                    .frame(width: 68, height: 68)
                    .background(AppTheme.accent, in: Circle())
            }

            Button {
                player.skipToNext()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.title2)
            }

            Button {
                player.cycleRepeatMode()
            } label: {
                Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat")
                    .foregroundStyle(player.repeatMode == .off ? AppTheme.textPrimary : AppTheme.accent)
            }
        }
        .buttonStyle(.plain)
    }

    private var playbackControls: some View {
        VStack(spacing: 14) {
            controlSlider(title: "Volume", value: binding(\.volume), range: 0...1, format: "%.0f%%", multiplier: 100)
            controlSlider(title: "Speed", value: binding(\.speed), range: 0.5...2.0, format: "%.2fx")
            controlSlider(title: "Pitch", value: binding(\.pitchSemitones), range: -12...12, format: "%.0f st")
        }
        .panelStyle()
    }

    private var equalizerControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("10-band EQ", isOn: Binding(
                get: { player.audioSettings.equalizerEnabled },
                set: { value in
                    var settings = player.audioSettings
                    settings.equalizerEnabled = value
                    player.audioSettings = settings
                }
            ))
            .tint(AppTheme.accent)

            ForEach(player.audioSettings.eqBands.indices, id: \.self) { index in
                HStack {
                    Text(eqLabel(for: index))
                        .font(.caption)
                        .frame(width: 54, alignment: .leading)
                        .foregroundStyle(AppTheme.textSecondary)
                    Slider(
                        value: Binding(
                            get: { player.audioSettings.eqBands[index] },
                            set: { value in
                                var settings = player.audioSettings
                                settings.eqBands[index] = value
                                player.audioSettings = settings
                            }
                        ),
                        in: -12...12
                    )
                    .tint(AppTheme.accent)
                }
            }
        }
        .panelStyle()
    }

    private func binding(_ keyPath: WritableKeyPath<AudioSettings, Float>) -> Binding<Float> {
        Binding {
            player.audioSettings[keyPath: keyPath]
        } set: { value in
            var settings = player.audioSettings
            settings[keyPath: keyPath] = value
            player.audioSettings = settings
        }
    }

    private func controlSlider(
        title: String,
        value: Binding<Float>,
        range: ClosedRange<Float>,
        format: String,
        multiplier: Float = 1
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: format, value.wrappedValue * multiplier))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(AppTheme.textSecondary)
            }
            Slider(value: value, in: range)
                .tint(AppTheme.accent)
        }
    }

    private func eqLabel(for index: Int) -> String {
        ["32", "64", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"][index]
    }

    private func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite, time > 0 else { return "0:00" }
        let total = Int(time.rounded())
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }
}
