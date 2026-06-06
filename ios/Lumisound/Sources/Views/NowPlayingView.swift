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

// MARK: - VinylDiscView

private struct VinylDiscView: View {
    let song: Song?
    let isPlaying: Bool
    @EnvironmentObject private var library: LibraryManager

    @State private var rotation: Double = 0
    @State private var animating = false

    var body: some View {
        ZStack {
            // Outer vinyl: dark circle with radial gradient texture
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(white: 0.08), Color(white: 0.12), Color(white: 0.06)],
                        center: .center,
                        startRadius: 50,
                        endRadius: 150
                    )
                )
                .overlay(vinylGrooves)

            // Center label: album artwork or accent color circle
            if let song {
                ArtworkThumbnail(song: song, size: 130)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color(white: 0.15), lineWidth: 2))
            } else {
                Circle()
                    .fill(AppTheme.accent.opacity(0.8))
                    .frame(width: 130, height: 130)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 40, weight: .semibold))
                            .foregroundStyle(.white)
                    )
            }

            // Center hole
            Circle()
                .fill(Color(white: 0.04))
                .frame(width: 18, height: 18)
        }
        .frame(width: 300, height: 300)
        .rotationEffect(.degrees(rotation))
        .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 10)
        .onChange(of: isPlaying) { playing in
            if playing { startSpinning() } else { pauseSpinning() }
        }
        .onAppear {
            if isPlaying { startSpinning() }
        }
    }

    private var vinylGrooves: some View {
        ZStack {
            // Concentric semi-transparent rings simulating grooves
            ForEach([0.78, 0.71, 0.64, 0.57, 0.50], id: \.self) { ratio in
                Circle()
                    .stroke(Color(white: 0.18).opacity(0.6), lineWidth: 1)
                    .frame(width: 300 * ratio, height: 300 * ratio)
            }
            // Highlight arc
            Circle()
                .trim(from: 0.1, to: 0.35)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.15), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    lineWidth: 40
                )
                .frame(width: 260, height: 260)
        }
    }

    private func startSpinning() {
        withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
            rotation = 360
        }
        animating = true
    }

    private func pauseSpinning() {
        withAnimation(.easeOut(duration: 0.5)) {
            // SwiftUI stops the repeating animation at the current value on next tick
        }
        animating = false
    }
}

// MARK: - NowPlayingView

struct NowPlayingView: View {
    /// Pass `true` when presenting as a sheet (e.g. from MiniPlayerBar) so the
    /// view does not wrap itself in a NavigationStack — the sheet already provides
    /// one, and nesting them produces a double navigation bar.
    var isSheet: Bool = false

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

    // Track info slide-up/fade-in animation
    @State private var trackInfoVisible: Bool = true

    // Collapsible panels
    @State private var showPlaybackControls = true
    @State private var showABRepeat = false
    @State private var showEffects = false
    @State private var showEQ = true
    @State private var showLyrics = false
    @State private var showLyricsSyncEditor = false

    // Artwork style — migrates old Bool key to the new enum key on first use
    @State private var artworkStyle: NowPlayingArtworkStyle = {
        // 1. New key takes priority
        if let raw = UserDefaults.standard.string(forKey: "nowPlaying_artworkStyle"),
           let style = NowPlayingArtworkStyle(rawValue: raw) {
            return style
        }
        // 2. Migrate old bool key: true → .vinylDisc, false → .albumArt
        if let oldBool = UserDefaults.standard.object(forKey: "nowPlaying_showVinylDisc") as? Bool {
            return oldBool ? .vinylDisc : .albumArt
        }
        // 3. Default
        return .vinylDisc
    }()

    // Seeker style
    @State private var seekerStyle: SeekerStyle = {
        if let raw = UserDefaults.standard.string(forKey: "nowPlaying_seekerStyle"),
           let style = SeekerStyle(rawValue: raw) {
            return style
        }
        return .waveform
    }()

    // Queue preview panel
    @State private var showQueuePreview = true

    // Sleep Timer sheet
    @State private var showSleepTimerSheet = false

    // Custom speed / pitch inline editing
    @State private var editingSpeed = false
    @State private var speedInput = ""
    @State private var editingPitch = false
    @State private var pitchInput = ""

    // Lyrics
    @State private var lyricsLines: [LrcLine] = []

    // Haptic generators — created once, prepared in onAppear
    private let seekHaptic = UIImpactFeedbackGenerator(style: .light)
    private let playHaptic = UIImpactFeedbackGenerator(style: .light)
    private let skipHaptic = UIImpactFeedbackGenerator(style: .medium)
    private let selectHaptic = UISelectionFeedbackGenerator()

    var body: some View {
        // When shown as a tab the view owns its NavigationStack.
        // When shown as a sheet MiniPlayerBar provides a NavigationStack already,
        // so we skip creating another one to avoid the double-navigation-bar bug.
        // Group lets the if/else return a single opaque type.
        Group {
            if isSheet {
                scrollContent
            } else {
                NavigationStack {
                    scrollContent
                        .appScreenBackground()
                        .background(GalleryBackgroundView().ignoresSafeArea())
                }
                .toolbarBackground(.hidden, for: .navigationBar)
            }
        }
        .sheet(isPresented: $showSleepTimerSheet) {
            SleepTimerSheet()
                .environmentObject(sleepTimer)
        }
        .onChange(of: player.currentSong?.id) { newID in
            guard newID != nil else { return }
            triggerTrackChangeAnimation()
            triggerTrackInfoAnimation()
            loadLyrics()
        }
        .onAppear {
            seekHaptic.prepare()
            playHaptic.prepare()
            skipHaptic.prepare()
            selectHaptic.prepare()
            loadLyrics()
        }
    }

    // MARK: - Scroll content (shared between tab and sheet presentations)

    private var scrollContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                artworkSection
                trackInfoSection
                timelineSection
                transportSection
                sleepTimerPill
                autoRadioToggle
                volumeSection
                playbackControlsSection
                queuePreviewSection
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
    }

    // MARK: - Artwork

    private var artworkSection: some View {
        VStack(spacing: 14) {
            // ── Artwork display ──────────────────────────────────────────
            artworkDisplay
                .scaleEffect(artworkScale)
                .opacity(artworkOpacity)
                .animation(.spring(response: 0.4, dampingFraction: 0.65), value: artworkScale)
                .animation(.easeInOut(duration: 0.2), value: artworkOpacity)
                .id(artworkAnimationID)
                .modifier(PulseModifier(isPlaying: player.isPlaying))

            // ── Style picker (horizontal scroll, 8 chips) ────────────────
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(NowPlayingArtworkStyle.allCases) { style in
                        Button {
                            artworkStyle = style
                            UserDefaults.standard.set(style.rawValue, forKey: "nowPlaying_artworkStyle")
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: style.iconName)
                                    .font(.system(size: 14, weight: .medium))
                                Text(style.displayName)
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundStyle(artworkStyle == style ? .white : AppTheme.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                artworkStyle == style
                                    ? AppTheme.dynamicAccent
                                    : AppTheme.surface,
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                        .animation(.easeInOut(duration: 0.18), value: artworkStyle)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    // MARK: - Artwork display (switches on style)

    @ViewBuilder
    private var artworkDisplay: some View {
        switch artworkStyle {
        case .vinylDisc:
            VinylDiscView(song: player.currentSong, isPlaying: player.isPlaying)

        case .albumArt:
            Group {
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

        case .polaroid:
            PolaroidArtworkView(song: player.currentSong, isPlaying: player.isPlaying)
                .environmentObject(library)

        case .floatingCards:
            FloatingCardsArtworkView(song: player.currentSong, isPlaying: player.isPlaying)
                .environmentObject(library)

        case .minimalist:
            MinimalistArtworkView(
                song: player.currentSong,
                isPlaying: player.isPlaying,
                progress: player.duration > 0 ? player.position / player.duration : 0
            )
            .environmentObject(library)

        case .glassmorphism:
            GlassmorphismArtworkView(song: player.currentSong, isPlaying: player.isPlaying)
                .environmentObject(library)

        case .retroCRT:
            RetroCRTArtworkView(song: player.currentSong, isPlaying: player.isPlaying)
                .environmentObject(library)

        case .spectrumWaveform:
            SpectrumWaveformArtworkView(song: player.currentSong, isPlaying: player.isPlaying)
                .environmentObject(library)

        case .cassetteTape:
            CassetteTapeArtworkView(song: player.currentSong, isPlaying: player.isPlaying)
                .environmentObject(library)

        case .neonGlow:
            NeonGlowArtworkView(song: player.currentSong, isPlaying: player.isPlaying)
                .environmentObject(library)
        }
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
        // Slide-up + fade-in on track change
        .opacity(trackInfoVisible ? 1 : 0)
        .offset(y: trackInfoVisible ? 0 : 14)
        .animation(.spring(response: 0.42, dampingFraction: 0.72), value: trackInfoVisible)
    }

    // MARK: - Timeline

    @ViewBuilder
    private var timelineSection: some View {
        VStack(spacing: 10) {
            switch seekerStyle {
            case .waveform:
                if let url = player.currentSong?.url, url.isFileURL, player.duration > 0 {
                    WaveformScrubberView(
                        url: url,
                        position: player.position,
                        duration: player.duration,
                        onSeek: { seekHaptic.impactOccurred(); player.seek(to: $0) }
                    )
                } else {
                    ClassicScrubberView(
                        position: player.position,
                        duration: player.duration,
                        onSeek: { seekHaptic.impactOccurred(); player.seek(to: $0) }
                    )
                }
            case .classic:
                ClassicScrubberView(
                    position: player.position,
                    duration: player.duration,
                    onSeek: { seekHaptic.impactOccurred(); player.seek(to: $0) }
                )
            case .ring:
                RingScrubberView(
                    position: player.position,
                    duration: player.duration,
                    onSeek: { seekHaptic.impactOccurred(); player.seek(to: $0) }
                )
            case .bars:
                BarsScrubberView(
                    position: player.position,
                    duration: player.duration,
                    onSeek: { seekHaptic.impactOccurred(); player.seek(to: $0) }
                )
            }

            seekerStylePicker
        }
    }

    private var seekerStylePicker: some View {
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
                skipHaptic.impactOccurred()
                player.skipToPrevious()
            }

            Spacer()

            // Play / Pause — centered, always 68pt circle
            Button {
                playHaptic.impactOccurred()
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
                skipHaptic.impactOccurred()
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

    // MARK: - Auto-Radio Toggle

    private var autoRadioToggle: some View {
        Button {
            player.autoRadioEnabled.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                Text("Auto-Radio")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Image(systemName: player.autoRadioEnabled ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
            }
            .foregroundStyle(player.autoRadioEnabled ? AppTheme.accent : AppTheme.textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(AppTheme.surface, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(
                        player.autoRadioEnabled ? AppTheme.accent.opacity(0.4) : Color.clear,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: player.autoRadioEnabled)
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
                    speedRow
                    pitchRow
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

    // MARK: - Speed Row

    private var speedRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Speed")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                if editingSpeed {
                    TextField("", text: $speedInput)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { applySpeedInput() }
                        .onAppear { speedInput = String(format: "%.2f", player.audioSettings.speed) }
                        .toolbar {
                            ToolbarItemGroup(placement: .keyboard) {
                                Spacer()
                                Button("Done") { applySpeedInput() }
                            }
                        }
                } else {
                    HStack(spacing: 4) {
                        Text(String(format: "%.2fx", player.audioSettings.speed))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(AppTheme.textSecondary)
                            .onTapGesture { editingSpeed = true }
                        Image(systemName: "pencil")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.textSecondary)
                            .onTapGesture { editingSpeed = true }
                    }
                }
            }
            Slider(value: audioBinding(\.speed), in: 0.5...2.0)
                .tint(AppTheme.accent)
        }
    }

    // MARK: - Pitch Row

    private var pitchRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Pitch")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                if editingPitch {
                    TextField("", text: $pitchInput)
                        .keyboardType(.numbersAndPunctuation)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { applyPitchInput() }
                        .onAppear { pitchInput = String(format: "%.1f", player.audioSettings.pitchSemitones) }
                        .toolbar {
                            ToolbarItemGroup(placement: .keyboard) {
                                Spacer()
                                Button("Done") { applyPitchInput() }
                            }
                        }
                } else {
                    HStack(spacing: 4) {
                        Text(String(format: "%.0f st", player.audioSettings.pitchSemitones))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(AppTheme.textSecondary)
                            .onTapGesture { editingPitch = true }
                        Image(systemName: "pencil")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.textSecondary)
                            .onTapGesture { editingPitch = true }
                    }
                }
            }
            Slider(value: audioBinding(\.pitchSemitones), in: -12...12)
                .tint(AppTheme.accent)
        }
    }

    // MARK: - Apply Helpers

    private func applySpeedInput() {
        if let parsed = Double(speedInput) {
            let clamped = Float(min(max(parsed, 0.1), 8.0))
            var settings = player.audioSettings
            settings.speed = clamped
            player.audioSettings = settings
        }
        editingSpeed = false
    }

    private func applyPitchInput() {
        if let parsed = Double(pitchInput) {
            let clamped = Float(min(max(parsed, -24.0), 24.0))
            var settings = player.audioSettings
            settings.pitchSemitones = clamped
            player.audioSettings = settings
        }
        editingPitch = false
    }

    // MARK: - Queue Preview

    private var upNextSongs: [Song] {
        guard !player.queue.isEmpty else { return [] }
        if player.shuffleEnabled {
            // When shuffle is on, show remaining songs (excluding current) in queue order.
            // Referencing player.shuffleEnabled ensures this recomputes on toggle.
            var pool = player.queue
            if let idx = pool.firstIndex(where: { $0.id == player.currentSong?.id }) {
                pool.remove(at: idx)
            }
            return Array(pool.prefix(10))
        } else {
            let start = (player.currentIndex + 1) % player.queue.count
            var result: [Song] = []
            var i = start
            while result.count < 10 && i != player.currentIndex {
                result.append(player.queue[i])
                i = (i + 1) % player.queue.count
            }
            return result
        }
    }

    private var queuePreviewSection: some View {
        DisclosureGroup(
            isExpanded: $showQueuePreview,
            content: {
                VStack(alignment: .leading, spacing: 10) {
                    if upNextSongs.isEmpty {
                        Text("Queue is empty")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 12)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(Array(upNextSongs.enumerated()), id: \.element.id) { idx, song in
                                    Button {
                                        if let queueIdx = player.queue.firstIndex(where: { $0.id == song.id }) {
                                            player.setQueue(player.queue, startIndex: queueIdx, autoplay: true)
                                        }
                                    } label: {
                                        VStack(spacing: 6) {
                                            ArtworkThumbnail(song: song, size: 60)
                                                .overlay(
                                                    idx == 0
                                                        ? AnyView(
                                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                                .stroke(AppTheme.accent, lineWidth: 2)
                                                          )
                                                        : AnyView(EmptyView())
                                                )
                                            Text(song.displayName)
                                                .font(.caption2)
                                                .foregroundStyle(idx == 0 ? AppTheme.accent : AppTheme.textSecondary)
                                                .lineLimit(1)
                                                .frame(width: 60)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 2)
                            .padding(.top, 10)
                        }
                    }
                }
            },
            label: {
                HStack(spacing: 6) {
                    Text("Up Next")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    if !upNextSongs.isEmpty {
                        Text("\(upNextSongs.count)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppTheme.accent, in: Capsule())
                    }
                    if player.shuffleEnabled {
                        Image(systemName: "shuffle")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.accent)
                    }
                    Spacer()
                    Text("\(player.queue.count) tracks")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
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
                                        selectHaptic.selectionChanged()
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

                if !lyricsLines.isEmpty, player.currentSong != nil {
                    Button {
                        showLyricsSyncEditor = true
                    } label: {
                        Label("Sync Editor", systemImage: "waveform.and.mic")
                            .font(.caption)
                            .foregroundStyle(AppTheme.accent)
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
        .tint(AppTheme.accent)
        .panelStyle()
        .sheet(isPresented: $showLyricsSyncEditor) {
            LyricsSyncEditorView(initialLines: lyricsLines)
                .environmentObject(player)
        }
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
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            withAnimation(.spring(response: 0.45, dampingFraction: 0.65)) {
                artworkOpacity = 1
                artworkScale = 1.0
            }
        }
    }

    private func triggerTrackInfoAnimation() {
        // Snap the info out (invisible, shifted down), then animate back in
        trackInfoVisible = false
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 80_000_000)
            trackInfoVisible = true
        }
    }

    private func loadLyrics() {
        guard let song = player.currentSong else { lyricsLines = []; return }

        // 1. Sidecar .lrc file next to the audio file (highest priority)
        if let url = song.url {
            let lrcURL = url.deletingPathExtension().appendingPathExtension("lrc")
            if let content = try? String(contentsOf: lrcURL, encoding: .utf8) {
                lyricsLines = LrcParser.parse(content)
                return
            }
        }

        // 2. LRCLIB — free, open lyrics database with synced LRC support
        //    Falls back to LyricsOVH if LRCLIB has no synced version.
        Task {
            let title  = song.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let artist = song.artist.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return }

            // LRCLIB: returns synced LRC if available
            if let lines = await fetchLRCLIB(title: title, artist: artist), !lines.isEmpty {
                await MainActor.run { lyricsLines = lines }
                return
            }

            // LyricsOVH: plain text fallback (no timestamps — shown as static block)
            if let lines = await fetchLyricsOVH(title: title, artist: artist), !lines.isEmpty {
                await MainActor.run { lyricsLines = lines }
            }
        }
    }

    // MARK: - LRCLIB fetch (synced LRC)

    private func fetchLRCLIB(title: String, artist: String) async -> [LrcLine]? {
        var components = URLComponents(string: "https://lrclib.net/api/search")!
        components.queryItems = [
            URLQueryItem(name: "track_name",   value: title),
            URLQueryItem(name: "artist_name",  value: artist),
        ]
        guard let url = components.url else { return nil }
        var req = URLRequest(url: url)
        req.setValue("Lumisound/1.0 (https://github.com/HeavenlyXenusVR/Lumisound)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 8

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let results = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let best = results.first
        else { return nil }

        // Prefer synced lyrics; fall back to plain text with no timestamps
        if let syncedLrc = best["syncedLyrics"] as? String, !syncedLrc.isEmpty {
            let lines = LrcParser.parse(syncedLrc)
            if !lines.isEmpty { return lines }
        }
        if let plain = best["plainLyrics"] as? String, !plain.isEmpty {
            // Wrap plain text lines as LrcLine with time=0 so they all display together
            return plain.components(separatedBy: "\n")
                .map { LrcLine(time: 0, text: $0) }
                .filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        }
        return nil
    }

    // MARK: - LyricsOVH fetch (plain text)

    private func fetchLyricsOVH(title: String, artist: String) async -> [LrcLine]? {
        guard !artist.isEmpty,
              let encArtist = artist.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let encTitle  = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.lyrics.ovh/v1/\(encArtist)/\(encTitle)")
        else { return nil }

        var req = URLRequest(url: url); req.timeoutInterval = 8
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let lyrics = json["lyrics"] as? String,
              !lyrics.isEmpty
        else { return nil }

        return lyrics.components(separatedBy: "\n")
            .map { LrcLine(time: 0, text: $0) }
            .filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
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
