import SwiftUI
import UIKit

// MARK: - Vertical Slider

/// A vertical slider built by rotating a standard SwiftUI Slider -90 degrees.
private struct VerticalSlider: View {
    @Binding var value: Float
    let range: ClosedRange<Float>

    var body: some View {
        GeometryReader { geo in
            Slider(
                value: $value,
                in: range
            )
            .rotationEffect(.degrees(-90))
            .frame(width: geo.size.height, height: geo.size.width)
            .offset(
                x: (geo.size.width - geo.size.height) / 2,
                y: (geo.size.height - geo.size.width) / 2
            )
            .tint(AppTheme.accent)
        }
    }
}

// MARK: - NowPlayingView

struct NowPlayingView: View {
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var library: LibraryManager
    @EnvironmentObject private var sleepTimer: SleepTimerService

    @Environment(\.dismiss) private var dismiss

    // Seeking
    @State private var isSeeking = false
    @State private var draftPosition: TimeInterval = 0

    // Artwork pulse animation
    @State private var artworkScale: CGFloat = 1.0
    @State private var artworkOpacity: Double = 1.0

    // Track-change animation ID
    @State private var artworkAnimationID: String = ""

    // Collapsible panels
    @State private var showPlaybackControls = true
    @State private var showABRepeat = false
    @State private var showEffects = false
    @State private var showEQ = true
    @State private var showLyrics = false

    // Sleep Timer sheet
    @State private var showSleepTimerSheet = false

    // Lyrics
    @State private var lyricsLines: [LrcLine] = []

    // Haptic generator for seek start
    private let seekHaptic = UIImpactFeedbackGenerator(style: .light)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    artworkSection
                    trackInfoSection
                    timelineSection
                    transportSection
                    sleepTimerPill
                    volumeSection
                    playbackControlsSection
                    abRepeatSection
                    effectsSection
                    equalizerSection
                    lyricsSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            // Swipe down to dismiss when presented as a sheet
            .gesture(
                DragGesture()
                    .onEnded { value in
                        if value.translation.height > 60 {
                            dismiss()
                        }
                    }
            )
            .navigationTitle("Now Playing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .appScreenBackground()
        }
        .sheet(isPresented: $showSleepTimerSheet) {
            SleepTimerSheet()
                .environmentObject(sleepTimer)
        }
        .onChange(of: player.currentSong?.id) { newID in
            guard newID != nil else { return }
            triggerTrackChangeAnimation()
            loadLyrics()
        }
        .onAppear {
            seekHaptic.prepare()
            loadLyrics()
        }
    }

    // MARK: - Artwork

    private var artworkSection: some View {
        ZStack {
            if let song = player.currentSong {
                ArtworkThumbnail(song: song, size: 300)
                    .shadow(color: AppTheme.accent.opacity(0.3), radius: 24, x: 0, y: 12)
            } else {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.surface, AppTheme.elevatedSurface],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 300, height: 300)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 80, weight: .semibold))
                            .foregroundStyle(AppTheme.accent)
                    }
                    .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 10)
            }
        }
        .scaleEffect(artworkScale)
        .opacity(artworkOpacity)
        .animation(.spring(response: 0.4, dampingFraction: 0.65), value: artworkScale)
        .animation(.easeInOut(duration: 0.2), value: artworkOpacity)
        .id(artworkAnimationID)
        // Subtle pulse when playing
        .modifier(PulseModifier(isPlaying: player.isPlaying))
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    // MARK: - Track Info + Favorite

    private var trackInfoSection: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(player.currentSong?.displayName ?? "Nothing Playing")
                    .font(.title2.bold())
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(player.currentSong?.artistName ?? "Choose a song from the Library")
                    .font(.body)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)

            if let song = player.currentSong {
                Button {
                    library.toggleFavorite(songID: song.id)
                } label: {
                    Image(systemName: library.isFavorite(songID: song.id) ? "heart.fill" : "heart")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(library.isFavorite(songID: song.id) ? AppTheme.accent : AppTheme.textSecondary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: library.isFavorite(songID: song.id))
            }
        }
    }

    // MARK: - Timeline

    private var timelineSection: some View {
        VStack(spacing: 6) {
            Slider(
                value: Binding(
                    get: { isSeeking ? draftPosition : player.position },
                    set: { draftPosition = $0 }
                ),
                in: 0...max(player.duration, 1),
                onEditingChanged: { editing in
                    isSeeking = editing
                    if editing {
                        seekHaptic.impactOccurred()
                    } else {
                        player.seek(to: draftPosition)
                    }
                }
            )
            .tint(AppTheme.accent)

            HStack {
                Text(formatTime(isSeeking ? draftPosition : player.position))
                    .monospacedDigit()
                Spacer()
                Text("-" + formatTime(max(0, player.duration - (isSeeking ? draftPosition : player.position))))
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(AppTheme.textSecondary)
        }
    }

    // MARK: - Transport Controls

    private var transportSection: some View {
        HStack(spacing: 0) {
            // Shuffle
            transportButton(
                systemName: "shuffle",
                tint: player.shuffleEnabled ? AppTheme.accent : AppTheme.textPrimary,
                font: .system(size: 18, weight: .medium)
            ) {
                player.toggleShuffle()
            }

            Spacer()

            // Previous
            transportButton(
                systemName: "backward.fill",
                tint: AppTheme.textPrimary,
                font: .system(size: 24, weight: .medium)
            ) {
                player.skipToPrevious()
            }

            Spacer()

            // Play / Pause — centered, always 68pt circle
            Button {
                player.togglePlayPause()
            } label: {
                ZStack {
                    Circle()
                        .fill(AppTheme.accent)
                        .frame(width: 68, height: 68)
                        .shadow(color: AppTheme.accent.opacity(0.45), radius: 12, x: 0, y: 6)
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: player.isPlaying)

            Spacer()

            // Next
            transportButton(
                systemName: "forward.fill",
                tint: AppTheme.textPrimary,
                font: .system(size: 24, weight: .medium)
            ) {
                player.skipToNext()
            }

            Spacer()

            // Repeat
            transportButton(
                systemName: repeatIcon,
                tint: player.repeatMode == .off ? AppTheme.textPrimary : AppTheme.accent,
                font: .system(size: 18, weight: .medium)
            ) {
                player.cycleRepeatMode()
            }
        }
        .padding(.vertical, 4)
    }

    private var repeatIcon: String {
        switch player.repeatMode {
        case .off:  return "repeat"
        case .all:  return "repeat"
        case .one:  return "repeat.1"
        }
    }

    private func transportButton(
        systemName: String,
        tint: Color,
        font: Font,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(font)
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Sleep Timer Pill

    @ViewBuilder
    private var sleepTimerPill: some View {
        if sleepTimer.isActive {
            Button {
                showSleepTimerSheet = true
            } label: {
                HStack(spacing: 6) {
                    Text("💤")
                        .font(.caption)
                    Text(sleepTimer.formattedRemaining)
                        .font(.system(.caption, design: .monospaced).weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.textPrimary)
                        .contentTransition(.numericText())
                        .animation(.linear(duration: 0.5), value: sleepTimer.remainingSeconds)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    AppTheme.surface,
                    in: Capsule()
                )
                .overlay(
                    Capsule()
                        .strokeBorder(AppTheme.accent.opacity(0.4), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .transition(.scale.combined(with: .opacity))
            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: sleepTimer.isActive)
        }
    }

    // MARK: - Volume

    private var volumeSection: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.fill")
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
            Slider(value: audioBinding(\.volume), in: 0...1)
                .tint(AppTheme.accent)
            Image(systemName: "speaker.wave.3.fill")
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Playback Controls Panel

    private var playbackControlsSection: some View {
        DisclosureGroup(
            isExpanded: $showPlaybackControls,
            content: {
                VStack(spacing: 14) {
                    labeledSlider(
                        label: "Speed",
                        valueText: String(format: "%.2fx", player.audioSettings.speed),
                        value: audioBinding(\.speed),
                        range: 0.5...2.0
                    )
                    labeledSlider(
                        label: "Pitch",
                        valueText: String(format: "%.0f st", player.audioSettings.pitchSemitones),
                        value: audioBinding(\.pitchSemitones),
                        range: -12...12
                    )
                }
                .padding(.top, 10)
            },
            label: {
                // When collapsed, show current speed value if not 1.0 for quick reference
                HStack(spacing: 6) {
                    Text("Playback Controls")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    if !showPlaybackControls && player.audioSettings.speed != 1.0 {
                        Text(String(format: "%.2f×", player.audioSettings.speed))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(AppTheme.textSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppTheme.elevatedSurface, in: Capsule())
                    }
                }
            }
        )
        .tint(AppTheme.accent)
        .panelStyle()
    }

    // MARK: - AB Repeat

    private var abRepeatSection: some View {
        DisclosureGroup(
            isExpanded: $showABRepeat,
            content: {
                VStack(spacing: 12) {
                    // Status row
                    if player.abRepeatEnabled {
                        HStack {
                            Image(systemName: "repeat")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(AppTheme.accent)
                            Text("Looping \(formatTime(player.abRepeatStart ?? 0)) → \(formatTime(player.abRepeatEnd ?? 0))")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(AppTheme.accent)
                            Spacer()
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 4)
                        .background(AppTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                    }

                    HStack(spacing: 10) {
                        // A button
                        abButton(
                            label: "A",
                            subtitle: player.abRepeatStart.map { formatTime($0) },
                            isSet: player.abRepeatStart != nil,
                            action: { player.setABStart() }
                        )

                        // Arrow
                        Image(systemName: "arrow.right")
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)

                        // B button
                        abButton(
                            label: "B",
                            subtitle: player.abRepeatEnd.map { formatTime($0) },
                            isSet: player.abRepeatEnd != nil,
                            action: { player.setABEnd() }
                        )

                        Spacer()

                        // Clear
                        if player.abRepeatStart != nil || player.abRepeatEnd != nil {
                            Button {
                                player.clearABRepeat()
                            } label: {
                                Label("Clear", systemImage: "xmark.circle.fill")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(AppTheme.textSecondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.top, 10)
            },
            label: {
                HStack {
                    Text("A–B Repeat")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    if player.abRepeatEnabled {
                        Circle()
                            .fill(AppTheme.accent)
                            .frame(width: 7, height: 7)
                    }
                }
            }
        )
        .tint(AppTheme.accent)
        .panelStyle()
    }

    private func abButton(label: String, subtitle: String?, isSet: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(label)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(isSet ? .white : AppTheme.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(isSet ? .white.opacity(0.85) : AppTheme.textSecondary)
                }
            }
            .frame(width: 52, height: 40)
            .background(isSet ? AppTheme.accent : AppTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isSet)
    }

    // MARK: - Audio Effects

    private var effectsSection: some View {
        DisclosureGroup(
            isExpanded: $showEffects,
            content: {
                EffectsView()
                    .padding(.top, 8)
            },
            label: {
                HStack {
                    Text("Audio Effects")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    if player.audioSettings.activeEffectID != "none" {
                        Text(AudioEffectsService.effect(id: player.audioSettings.activeEffectID)?.name ?? "")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(AppTheme.accent, in: Capsule())
                    }
                }
            }
        )
        .tint(AppTheme.accent)
        .panelStyle()
    }

    // MARK: - Equalizer

    private var equalizerSection: some View {
        DisclosureGroup(
            isExpanded: $showEQ,
            content: {
                VStack(spacing: 14) {
                    // EQ Enable Toggle
                    Toggle("10-Band EQ", isOn: Binding(
                        get: { player.audioSettings.equalizerEnabled },
                        set: { val in
                            var s = player.audioSettings
                            s.equalizerEnabled = val
                            player.audioSettings = s
                        }
                    ))
                    .tint(AppTheme.accent)
                    .font(.subheadline)

                    if player.audioSettings.equalizerEnabled {
                        // Preset chips
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(EQPreset.allCases) { preset in
                                    Button {
                                        player.applyEQPreset(preset)
                                    } label: {
                                        Text(preset.displayName)
                                            .font(.caption.weight(.medium))
                                            .foregroundStyle(
                                                player.audioSettings.eqPreset == preset
                                                    ? .white
                                                    : AppTheme.textSecondary
                                            )
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(
                                                player.audioSettings.eqPreset == preset
                                                    ? AppTheme.accent
                                                    : AppTheme.elevatedSurface,
                                                in: Capsule()
                                            )
                                    }
                                    .buttonStyle(.plain)
                                    .animation(.easeInOut(duration: 0.2), value: player.audioSettings.eqPreset)
                                }
                            }
                            .padding(.vertical, 2)
                        }

                        // Vertical EQ Bands
                        HStack(alignment: .bottom, spacing: 0) {
                            ForEach(player.audioSettings.eqBands.indices, id: \.self) { index in
                                eqBandColumn(index: index)
                            }
                        }
                        .frame(height: 160)
                        .padding(.top, 4)
                    } else {
                        // Placeholder when EQ is disabled
                        HStack(spacing: 10) {
                            Image(systemName: "slider.vertical.3")
                                .font(.system(size: 20))
                                .foregroundStyle(AppTheme.textSecondary.opacity(0.6))
                            Text("Enable to customize EQ bands")
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                    }
                }
                .padding(.top, 10)
            },
            label: {
                HStack {
                    Text("Equalizer")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    if player.audioSettings.equalizerEnabled {
                        Circle()
                            .fill(AppTheme.accent)
                            .frame(width: 7, height: 7)
                    }
                }
            }
        )
        .tint(AppTheme.accent)
        .panelStyle()
    }

    private func eqBandColumn(index: Int) -> some View {
        let labels = ["32", "64", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]

        return VStack(spacing: 4) {
            // Gain value
            Text(String(format: "%.0f", player.audioSettings.eqBands[index]))
                .font(.system(size: 9).monospacedDigit())
                .foregroundStyle(AppTheme.textSecondary)
                .frame(height: 12)

            // Vertical slider
            VerticalSlider(
                value: Binding(
                    get: { player.audioSettings.eqBands[index] },
                    set: { val in
                        var s = player.audioSettings
                        s.eqBands[index] = val
                        s.eqPreset = .custom
                        player.audioSettings = s
                    }
                ),
                range: -12...12
            )
            .frame(height: 110)

            // Band label
            Text(labels[index])
                .font(.system(size: 9))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(height: 14)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Lyrics

    private var lyricsSection: some View {
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
                        LyricsView(
                            lines: lyricsLines,
                            currentPosition: player.position
                        )
                        .frame(height: 260)
                    }
                }
                .padding(.top, 8)
            },
            label: {
                Text("Lyrics")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
            }
        )
        .tint(AppTheme.accent)
        .panelStyle()
    }

    // MARK: - Helpers

    private func labeledSlider(
        label: String,
        valueText: String,
        value: Binding<Float>,
        range: ClosedRange<Float>
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                Text(valueText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(AppTheme.textSecondary)
            }
            Slider(value: value, in: range)
                .tint(AppTheme.accent)
        }
    }

    private func audioBinding(_ keyPath: WritableKeyPath<AudioSettings, Float>) -> Binding<Float> {
        Binding {
            player.audioSettings[keyPath: keyPath]
        } set: { value in
            var settings = player.audioSettings
            settings[keyPath: keyPath] = value
            player.audioSettings = settings
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite, time >= 0 else { return "0:00" }
        let total = Int(time.rounded())
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }

    private func triggerTrackChangeAnimation() {
        artworkAnimationID = player.currentSong?.id ?? UUID().uuidString
        withAnimation(.easeOut(duration: 0.15)) {
            artworkOpacity = 0
            artworkScale = 0.92
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.65)) {
                artworkOpacity = 1
                artworkScale = 1.0
            }
        }
    }

    private func loadLyrics() {
        guard let url = player.currentSong?.url else {
            lyricsLines = []
            return
        }
        let lrcURL = url.deletingPathExtension().appendingPathExtension("lrc")
        if let content = try? String(contentsOf: lrcURL, encoding: .utf8) {
            lyricsLines = LrcParser.parse(content)
        } else {
            lyricsLines = []
        }
    }
}

// MARK: - Pulse Modifier

private struct PulseModifier: ViewModifier {
    let isPlaying: Bool
    @State private var pulsing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(pulsing ? 1.022 : 1.0)
            .onChange(of: isPlaying) { playing in
                if playing {
                    withAnimation(
                        .easeInOut(duration: 1.8)
                            .repeatForever(autoreverses: true)
                    ) {
                        pulsing = true
                    }
                } else {
                    withAnimation(.easeOut(duration: 0.4)) {
                        pulsing = false
                    }
                }
            }
            .onAppear {
                if isPlaying {
                    withAnimation(
                        .easeInOut(duration: 1.8)
                            .repeatForever(autoreverses: true)
                    ) {
                        pulsing = true
                    }
                }
            }
    }
}
