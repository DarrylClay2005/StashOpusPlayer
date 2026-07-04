import SwiftUI
import UIKit

// MARK: - Now Playing secondary-controls panel
//
// The advanced controls are grouped into switchable panels (segmented control)
// instead of one long vertical wall, so the core playback stays prominent and
// the extras are organized — the layout big music apps use.
private enum NowPlayingPanel: String, CaseIterable, Identifiable {
    case controls = "Controls"
    case sound    = "Sound"
    case queue    = "Queue"
    case lyrics   = "Lyrics"
    var id: String { rawValue }
}

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
            .tint(AppTheme.dynamicAccent)
        }
    }
}

// MARK: - NowPlayingView

struct NowPlayingView: View {
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var progress: PlaybackProgress
    @EnvironmentObject private var library: LibraryManager
    @EnvironmentObject private var sleepTimer: SleepTimerService

    // Seeking
    @State private var isSeeking = false
    @State private var draftPosition: TimeInterval = 0

    // Artwork pulse animation
    @State private var artworkScale: CGFloat = 1.0
    @State private var artworkOpacity: Double = 1.0

    // Artwork swipe-to-skip (horizontal drag on the artwork area)
    @State private var artworkDragOffset: CGFloat = 0
    @State private var artworkDragScale: CGFloat = 1.0

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

    // Artwork style. Falls back to the default below both for first-time
    // users AND for anyone whose saved rawValue predates the 2026-07 visual
    // overhaul (the old case names — including the even-older boolean
    // `nowPlaying_showVinylDisc` key this used to migrate from — no longer
    // exist in any form, so there's nothing left to migrate).
    @State private var artworkStyle: NowPlayingArtworkStyle = {
        if let raw = UserDefaults.standard.string(forKey: "nowPlaying_artworkStyle"),
           let style = NowPlayingArtworkStyle(rawValue: raw) {
            return style
        }
        return .kaleidoscopeBloom
    }()

    // Seeker style
    @State private var seekerStyle: SeekerStyle = {
        if let raw = UserDefaults.standard.string(forKey: "nowPlaying_seekerStyle"),
           let style = SeekerStyle(rawValue: raw) {
            return style
        }
        return .waveform
    }()

    // Playtime counter style
    @State private var playtimeCounterStyle: PlaytimeCounterStyle = {
        if let raw = UserDefaults.standard.string(forKey: "nowPlaying_playtimeCounterStyle"),
           let style = PlaytimeCounterStyle(rawValue: raw) {
            return style
        }
        return .elapsedRemaining
    }()

    // Queue preview panel
    @AppStorage("nowPlaying_showQueuePreview") private var showQueuePreview = true

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
    private let heartHaptic = UIImpactFeedbackGenerator(style: .soft)
    private let selectHaptic = UISelectionFeedbackGenerator()

    @State private var selectedPanel: NowPlayingPanel = .controls

    var body: some View {
        NavigationStack {
            scrollContent
                .appScreenBackground()
                .background(GalleryBackgroundView().ignoresSafeArea())
        }
        .toolbarBackground(.hidden, for: .navigationBar)
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
            heartHaptic.prepare()
            selectHaptic.prepare()
            loadLyrics()
        }
    }

    // MARK: - Scroll content

    private var scrollContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                // ── Core playback (always visible) ──
                artworkSection
                trackInfoSection
                timelineSection
                transportSection

                // ── Secondary controls, organized into switchable panels ──
                panelPicker
                selectedPanelContent
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.18), value: selectedPanel)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .navigationTitle("Now Playing")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var panelPicker: some View {
        Picker("Controls", selection: $selectedPanel) {
            ForEach(NowPlayingPanel.allCases) { panel in
                Text(panel.rawValue).tag(panel)
            }
        }
        .pickerStyle(.segmented)
        .padding(.top, 4)
    }

    @ViewBuilder
    private var selectedPanelContent: some View {
        switch selectedPanel {
        case .controls:
            VStack(spacing: 20) {
                volumeSection
                playbackControlsSection
                abRepeatSection
                sleepTimerPill
                autoRadioToggle
            }
        case .sound:
            VStack(spacing: 20) {
                effectsSection
                equalizerSection
                trackAudioSettingsSection
            }
        case .queue:
            queuePreviewSection
        case .lyrics:
            lyricsSection
        }
    }

    // MARK: - Artwork

    private var artworkSection: some View {
        VStack(spacing: 14) {
            // ── Artwork display ──────────────────────────────────────────
            ZStack {
                AmbientArtworkBackground(song: player.currentSong)
                    .environmentObject(library)

                artworkDisplay
                    .scaleEffect(artworkScale * artworkDragScale)
                    .opacity(artworkOpacity)
                    .offset(x: artworkDragOffset)
                    .animation(.spring(response: 0.4, dampingFraction: 0.65), value: artworkScale)
                    .animation(.easeInOut(duration: 0.2), value: artworkOpacity)
                    .id(artworkAnimationID)
                    .modifier(PulseModifier(isPlaying: player.isPlaying))
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(artworkSwipeGesture)

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
        case .kaleidoscopeBloom:
            KaleidoscopeBloomArtworkView(song: player.currentSong, isPlaying: player.isPlaying)
                .environmentObject(library)

        case .synthwaveHorizon:
            SynthwaveHorizonArtworkView(song: player.currentSong, isPlaying: player.isPlaying)
                .environmentObject(library)

        case .equalizerCutout:
            EqualizerCutoutArtworkView(song: player.currentSong, isPlaying: player.isPlaying)
                .environmentObject(library)

        case .liquidBlobFrame:
            LiquidBlobFrameArtworkView(song: player.currentSong, isPlaying: player.isPlaying)
                .environmentObject(library)

        case .origamiFoldReveal:
            OrigamiFoldRevealArtworkView(song: player.currentSong, isPlaying: player.isPlaying)
                .environmentObject(library)

        case .mosaicShatter:
            MosaicShatterArtworkView(song: player.currentSong, isPlaying: player.isPlaying)
                .environmentObject(library)

        case .circuitPulse:
            CircuitPulseArtworkView(song: player.currentSong, isPlaying: player.isPlaying)
                .environmentObject(library)

        case .radarSweep:
            RadarSweepArtworkView(song: player.currentSong, isPlaying: player.isPlaying)
                .environmentObject(library)

        case .discoMirrorBall:
            DiscoMirrorBallArtworkView(song: player.currentSong, isPlaying: player.isPlaying)
                .environmentObject(library)

        case .frostedIceCrystal:
            FrostedIceCrystalArtworkView(song: player.currentSong, isPlaying: player.isPlaying)
                .environmentObject(library)

        case .bioluminescentTide:
            BioluminescentTideArtworkView(song: player.currentSong, isPlaying: player.isPlaying)
                .environmentObject(library)

        case .cometOrbit:
            CometOrbitArtworkView(song: player.currentSong, isPlaying: player.isPlaying)
                .environmentObject(library)

        case .marquee:
            MarqueeArtworkView(song: player.currentSong, isPlaying: player.isPlaying)
                .environmentObject(library)

        case .holographic:
            HolographicArtworkView(song: player.currentSong, isPlaying: player.isPlaying)
                .environmentObject(library)

        case .ripple:
            RippleArtworkView(song: player.currentSong, isPlaying: player.isPlaying)
                .environmentObject(library)

        case .popArt:
            PopArtArtworkView(song: player.currentSong, isPlaying: player.isPlaying)
                .environmentObject(library)

        case .starfield:
            StarfieldArtworkView(song: player.currentSong, isPlaying: player.isPlaying)
                .environmentObject(library)

        case .stainedGlass:
            StainedGlassArtworkView(song: player.currentSong, isPlaying: player.isPlaying)
                .environmentObject(library)
        }
    }

    // MARK: - Artwork swipe-to-skip

    /// Swipe left/right on the artwork to skip to the next/previous track,
    /// mirroring the forward/backward transport buttons. Requires the drag to
    /// be clearly horizontal so it doesn't fight a sheet's swipe-to-dismiss.
    private var artworkSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onChanged { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) > abs(vertical) else { return }
                // Rubber-band: follow the finger but taper past ~120pt so a
                // long drag doesn't fling the artwork off-screen.
                artworkDragOffset = horizontal * (abs(horizontal) > 120 ? 0.15 : 0.4)
                artworkDragScale = 1.0 - min(abs(horizontal) / 800, 0.06)
            }
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                let isHorizontalSwipe = abs(horizontal) > abs(vertical) * 1.5 && abs(horizontal) > 60

                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    artworkDragOffset = 0
                    artworkDragScale = 1.0
                }

                guard isHorizontalSwipe else { return }
                skipHaptic.impactOccurred()
                if horizontal < 0 {
                    player.skipToNext()
                } else {
                    player.skipToPrevious()
                }
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

    // MARK: - Timeline

    @ViewBuilder
    private var timelineSection: some View {
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

    private var playtimeCounterRow: some View {
        Text(playtimeCounterStyle.text(position: progress.position, duration: progress.duration))
            .font(AppTheme.monoFont(size: 13))
            .foregroundStyle(AppTheme.textSecondary)
            .contentTransition(.numericText())
            .animation(.snappy, value: progress.position)
    }

    private var playtimeCounterStylePicker: some View {
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
            // Shuffle — active state shows a filled accent well.
            transportButton(
                systemName: "shuffle",
                font: .system(size: 18, weight: .semibold),
                isActive: player.shuffleEnabled
            ) {
                player.toggleShuffle()
            }

            Spacer()

            // Previous
            transportButton(
                systemName: "backward.fill",
                font: .system(size: 24, weight: .medium),
                isActive: false
            ) {
                skipHaptic.impactOccurred()
                player.skipToPrevious()
            }

            Spacer()

            // Play / Pause — centered, always 72pt circle with a soft gradient
            // and press-scale feedback for a more tactile, modern feel.
            Button {
                playHaptic.impactOccurred()
                player.togglePlayPause()
            } label: {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [AppTheme.dynamicAccent, AppTheme.accentSoft],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 72, height: 72)
                        .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1))
                        .shadow(color: AppTheme.dynamicAccent.opacity(0.5), radius: 16, x: 0, y: 8)
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                        .contentTransition(.opacity)
                }
            }
            .buttonStyle(PressableButtonStyle())
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: player.isPlaying)

            Spacer()

            // Next
            transportButton(
                systemName: "forward.fill",
                font: .system(size: 24, weight: .medium),
                isActive: false
            ) {
                skipHaptic.impactOccurred()
                player.skipToNext()
            }

            Spacer()

            // Repeat — active (all/one) shows a filled accent well.
            transportButton(
                systemName: repeatIcon,
                font: .system(size: 18, weight: .semibold),
                isActive: player.repeatMode != .off
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

    /// A secondary transport control rendered as an icon inside a subtle
    /// circular "well" — glass when active (accent-tinted), faint surface
    /// otherwise — with press-scale feedback.
    private func transportButton(
        systemName: String,
        font: Font,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(font)
                .foregroundStyle(isActive ? .white : AppTheme.textPrimary)
                .frame(width: 46, height: 46)
                .background(
                    Circle().fill(
                        isActive
                            ? AppTheme.dynamicAccent.opacity(0.9)
                            : AppTheme.elevatedSurface.opacity(0.5)
                    )
                )
                .overlay(
                    Circle().stroke(.white.opacity(isActive ? 0.25 : 0.08), lineWidth: 1)
                )
        }
        .buttonStyle(PressableButtonStyle())
        .animation(.easeInOut(duration: 0.2), value: isActive)
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
                .adaptiveGlass(tint: AppTheme.dynamicAccent, in: Capsule(), fallback: .regularMaterial)
                .overlay(
                    Capsule()
                        .strokeBorder(AppTheme.dynamicAccent.opacity(0.4), lineWidth: 1)
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
            .foregroundStyle(player.autoRadioEnabled ? AppTheme.dynamicAccent : AppTheme.textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .adaptiveGlass(
                tint: player.autoRadioEnabled ? AppTheme.dynamicAccent : AppTheme.surface,
                in: Capsule(),
                fallback: .regularMaterial
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        player.autoRadioEnabled ? AppTheme.dynamicAccent.opacity(0.4) : Color.clear,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: player.autoRadioEnabled)
    }

    // MARK: - Volume

    private var volumeSection: some View {
        VStack(spacing: 2) {
            HStack(spacing: 10) {
                Image(systemName: "speaker.fill")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                Slider(value: audioBinding(\.volume), in: 0...AudioSettings.maxVolume)
                    .tint(AppTheme.dynamicAccent)
                Image(systemName: "speaker.wave.3.fill")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                // AirPlay / output-route picker (AirPlay speakers, Bluetooth, etc.).
                AirPlayRoutePicker(
                    tint: UIColor(AppTheme.textSecondary),
                    activeTint: UIColor(AppTheme.dynamicAccent)
                )
                .frame(width: 30, height: 30)
            }
            // Above 100% the volume slider is boosting gain beyond the
            // device's normal output (via the EQ's global gain stage, in dB —
            // see AudioPlayerManager.applyOutputGain) — a limiter prevents
            // clipping, but it's worth flagging since it's an unusual range
            // for a slider.
            if player.audioSettings.volume > 1.0 {
                let boostDB = 20 * log10(player.audioSettings.volume)
                Text("Boost: +\(String(format: "%.1f", boostDB)) dB")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppTheme.dynamicAccent)
            }
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
        .tint(AppTheme.dynamicAccent)
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
                .tint(AppTheme.dynamicAccent)
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
                .tint(AppTheme.dynamicAccent)
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

    /// Mirrors `AudioPlayerManager.resolveNextIndex`'s semantics so "Up Next" only ever
    /// shows songs that will actually play next — previously this always wrapped the
    /// queue regardless of `repeatMode`, so e.g. with Repeat off and the queue near its
    /// end it listed earlier tracks that would never play (playback simply stops at the
    /// end), which is what showed up as "Next Up doesn't update properly at all".
    private var upNextSongs: [Song] {
        guard player.queue.count > 1 else { return [] }

        if player.repeatMode == .one {
            // The current song repeats — there's nothing else "up next".
            return []
        }

        // Shuffle reorders `queue` itself (see AudioPlayerManager.shuffleQueue), so the
        // same sequential walk below already reflects the shuffled play order.
        var result: [Song] = []
        var i = player.currentIndex + 1
        while result.count < 10 && i < player.queue.count {
            result.append(player.queue[i])
            i += 1
        }
        if player.repeatMode == .all {
            i = 0
            while result.count < 10 && i < player.currentIndex {
                result.append(player.queue[i])
                i += 1
            }
        }
        return result
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
                                                                .stroke(AppTheme.dynamicAccent, lineWidth: 2)
                                                          )
                                                        : AnyView(EmptyView())
                                                )
                                            Text(song.displayName)
                                                .font(.caption2)
                                                .foregroundStyle(idx == 0 ? AppTheme.dynamicAccent : AppTheme.textSecondary)
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
                            .background(AppTheme.dynamicAccent, in: Capsule())
                    }
                    if player.shuffleEnabled {
                        Image(systemName: "shuffle")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.dynamicAccent)
                    }
                    Spacer()
                    Text("\(player.queue.count) tracks")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
        )
        .tint(AppTheme.dynamicAccent)
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
                                .foregroundStyle(AppTheme.dynamicAccent)
                            Text("Looping \(formatTime(player.abRepeatStart ?? 0)) → \(formatTime(player.abRepeatEnd ?? 0))")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(AppTheme.dynamicAccent)
                            Spacer()
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 4)
                        .background(AppTheme.dynamicAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
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
                            .fill(AppTheme.dynamicAccent)
                            .frame(width: 7, height: 7)
                    }
                }
            }
        )
        .tint(AppTheme.dynamicAccent)
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
            .background(isSet ? AppTheme.dynamicAccent : AppTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                            .background(AppTheme.dynamicAccent, in: Capsule())
                    }
                }
            }
        )
        .tint(AppTheme.dynamicAccent)
        .panelStyle()
    }

    // MARK: - Per-Track Audio Settings

    /// Lets the user pin the current EQ/effects/volume/etc. (`player.audioSettings`)
    /// to this specific track, so they're recalled automatically every time it
    /// plays — independent of the global default settings used for other tracks.
    private var trackAudioSettingsSection: some View {
        Group {
            if player.currentSong != nil {
                HStack(spacing: 12) {
                    Image(systemName: player.isUsingTrackAudioSettings ? "pin.fill" : "pin")
                        .font(.system(size: 16))
                        .foregroundStyle(player.isUsingTrackAudioSettings ? AppTheme.dynamicAccent : AppTheme.textSecondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(player.isUsingTrackAudioSettings ? "Custom Sound for This Track" : "Using Default Sound Settings")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                        Text(player.isUsingTrackAudioSettings
                             ? "EQ, effects, and volume are saved just for this track."
                             : "Save the current EQ/effects/volume to use only for this track.")
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                    }

                    Spacer(minLength: 8)

                    Button {
                        selectHaptic.selectionChanged()
                        if player.isUsingTrackAudioSettings {
                            player.clearAudioSettingsForCurrentTrack()
                        } else {
                            player.saveAudioSettingsForCurrentTrack()
                        }
                    } label: {
                        Text(player.isUsingTrackAudioSettings ? "Remove" : "Save")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                player.isUsingTrackAudioSettings ? AppTheme.elevatedSurface : AppTheme.dynamicAccent,
                                in: Capsule()
                            )
                            .foregroundStyle(player.isUsingTrackAudioSettings ? AppTheme.textPrimary : .white)
                    }
                    .buttonStyle(.plain)
                }
                .panelStyle()
            }
        }
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
                    .tint(AppTheme.dynamicAccent)
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
                                                    ? AppTheme.dynamicAccent
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
                            .fill(AppTheme.dynamicAccent)
                            .frame(width: 7, height: 7)
                    }
                }
            }
        )
        .tint(AppTheme.dynamicAccent)
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
                            currentPosition: progress.position,
                            isPlaying: player.isPlaying
                        )
                        .frame(height: 260)
                        .clipped()
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
                .environmentObject(progress)
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
                .tint(AppTheme.dynamicAccent)
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
        time.formattedAsMinutesSeconds
    }

    private func triggerTrackChangeAnimation() {
        // Fade/shrink the *current* artwork out first — only swap the `.id()` (which
        // tears down and recreates the artwork view) once it's invisible. Updating the
        // ID immediately used to pop the new artwork in instantly before the fade-out
        // animation had a chance to play, producing a jarring flash on every transition
        // (and especially during crossfade, where the swap happens mid-playback).
        withAnimation(.easeOut(duration: 0.15)) {
            artworkOpacity = 0
            artworkScale = 0.92
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            artworkAnimationID = player.currentSong?.id ?? UUID().uuidString
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

        // 1. User-synced lyrics saved via the in-app Lyrics Sync Editor — these
        //    represent the user's own deliberate timing work, so they take
        //    priority over a generic sidecar file or a remote guess.
        if let content = try? String(contentsOf: syncedLyricsURL(for: song), encoding: .utf8) {
            lyricsLines = LrcParser.parse(content)
            return
        }

        // 2. Sidecar .lrc file next to the audio file
        if let url = song.url {
            let lrcURL = url.deletingPathExtension().appendingPathExtension("lrc")
            if let content = try? String(contentsOf: lrcURL, encoding: .utf8) {
                lyricsLines = LrcParser.parse(content)
                return
            }
        }

        // 3. LRCLIB — free, open lyrics database with synced LRC support
        //    Falls back to LyricsOVH if LRCLIB has no synced version.
        // Clear any lyrics left over from the previous track *before* kicking
        // off the remote fetch — otherwise the previous song's lyrics stay on
        // screen (and scroll/highlight against the new song's `progress`)
        // until the network call resolves, which looks like "wrong track"
        // lyrics for the new song.
        lyricsLines = []
        let songID = song.id
        Task {
            let title  = song.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let artist = song.artist.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return }

            // Skipping tracks fires loadLyrics() again before the previous
            // fetch resolves — an in-flight fetch for a now-stale song can
            // land after the new one and overwrite the correct lyrics with
            // the wrong song's. Bail if the user has moved on by the time
            // each remote call resolves. `currentSong` is main-actor isolated,
            // so every check has to hop over via MainActor.run.

            // LRCLIB: returns synced LRC if available
            if let lines = await fetchLRCLIB(title: title, artist: artist, duration: song.duration), !lines.isEmpty {
                await MainActor.run { if player.currentSong?.id == songID { lyricsLines = lines } }
                return
            }
            guard await MainActor.run(body: { player.currentSong?.id == songID }) else { return }

            // LyricsOVH: plain text fallback (no timestamps — shown as static block)
            if let lines = await fetchLyricsOVH(title: title, artist: artist), !lines.isEmpty {
                await MainActor.run { if player.currentSong?.id == songID { lyricsLines = lines } }
            }
        }
    }

    /// Path where `LyricsSyncEditorView` saves user-synced lyrics: `Documents/Lyrics/{songID}.lrc`.
    /// Filename sanitization must match `LyricsSyncEditorView.sanitizeFilename` exactly,
    /// or saved files silently become unreadable here.
    private func syncedLyricsURL(for song: Song) -> URL {
        let illegal  = CharacterSet(charactersIn: "/:\\*?\"<>|")
        let filename = song.id.components(separatedBy: illegal).joined(separator: "_") + ".lrc"
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lyrics", isDirectory: true)
            .appendingPathComponent(filename)
    }

    // MARK: - LRCLIB fetch (synced LRC)

    private func fetchLRCLIB(title: String, artist: String, duration: TimeInterval) async -> [LrcLine]? {
        let headers = ["User-Agent": "Lumisound/1.0 (https://github.com/HeavenlyXenusVR/Lumisound)"]

        // 1. /api/get — exact match by track/artist/duration. LRCLIB matches
        //    duration within a couple seconds, so this avoids returning lyrics
        //    for a same-titled track by a different artist or a different
        //    recording/edit with a different runtime.
        if duration > 0 {
            var getComponents = URLComponents(string: "https://lrclib.net/api/get")!
            getComponents.queryItems = [
                URLQueryItem(name: "track_name",  value: title),
                URLQueryItem(name: "artist_name", value: artist),
                URLQueryItem(name: "duration",    value: String(Int(duration.rounded()))),
            ]
            if let url = getComponents.url,
               let lines = await fetchLRCLIBResult(url: url, headers: headers, expectedDuration: duration) {
                return lines
            }
        }

        // 2. /api/search — fallback for tracks LRCLIB doesn't have an exact
        //    duration match for. Pick the result whose duration is closest to
        //    the local file's, instead of blindly trusting the first hit,
        //    which was often a different song/version entirely.
        var searchComponents = URLComponents(string: "https://lrclib.net/api/search")!
        searchComponents.queryItems = [
            URLQueryItem(name: "track_name",   value: title),
            URLQueryItem(name: "artist_name",  value: artist),
        ]
        guard let url = searchComponents.url else { return nil }
        var req = URLRequest(url: url)
        for (key, value) in headers { req.setValue(value, forHTTPHeaderField: key) }
        req.timeoutInterval = 8

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let results = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              !results.isEmpty
        else { return nil }

        let best: [String: Any]
        if duration > 0 {
            best = results.min {
                let d0 = ($0["duration"] as? Double) ?? .infinity
                let d1 = ($1["duration"] as? Double) ?? .infinity
                return abs(d0 - duration) < abs(d1 - duration)
            } ?? results[0]

            // If even the closest match is way off (different song entirely),
            // don't show misleading lyrics/timing at all.
            if let bestDuration = best["duration"] as? Double, abs(bestDuration - duration) > 10 {
                return nil
            }
        } else {
            best = results[0]
        }

        return linesFromResult(best)
    }

    private func fetchLRCLIBResult(url: URL, headers: [String: String], expectedDuration: TimeInterval) async -> [LrcLine]? {
        var req = URLRequest(url: url)
        for (key, value) in headers { req.setValue(value, forHTTPHeaderField: key) }
        req.timeoutInterval = 8

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        return linesFromResult(result)
    }

    private func linesFromResult(_ result: [String: Any]) -> [LrcLine]? {
        // Prefer synced lyrics; fall back to plain text with no timestamps
        if let syncedLrc = result["syncedLyrics"] as? String, !syncedLrc.isEmpty {
            let lines = LrcParser.parse(syncedLrc)
            if !lines.isEmpty { return lines }
        }
        if let plain = result["plainLyrics"] as? String, !plain.isEmpty {
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
