import SwiftUI
import UIKit

extension NowPlayingView {

    // MARK: - Scroll content

    var scrollContent: some View {
        ScrollView {
            VStack(spacing: screenStyle.sectionSpacing) {
                // ── Top bar: hero display-mode pill, AirPlay, overflow menu ──
                topBar

                // ── Hero card: artwork or full lyrics, depending on displayMode ──
                // `.scrollTransition` (the scroll-linked parallax below) needs
                // iOS 17 — this app's deployment target is iOS 16 — so it's
                // only applied on 17+; iOS 16 falls back to just the
                // transition/animation with no parallax rather than failing
                // to build entirely.
                if #available(iOS 17.0, *) {
                    heroSection
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        .animation(.easeInOut(duration: 0.25), value: displayMode)
                        // Subtle scroll-linked parallax — the hero card eases down
                        // in scale/opacity as it scrolls toward the top edge,
                        // rather than just hard-clipping, for a touch more
                        // premium "liveliness" while scrolling to the panels below.
                        .scrollTransition(.animated) { content, phase in
                            content
                                .scaleEffect(phase.isIdentity ? 1.0 : 0.94)
                                .opacity(phase.isIdentity ? 1.0 : 0.85)
                        }
                } else {
                    heroSection
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        .animation(.easeInOut(duration: 0.25), value: displayMode)
                }

                trackInfoSection
                aiDJCaption
                ListenTogetherReactionBar()
                timelineSection
                transportSection

                // A small decorative drag-handle accent below transport,
                // echoing the reference design's sheet-drag affordance —
                // purely cosmetic here since this screen is a fixed tab
                // rather than a dismissible sheet.
                Capsule()
                    .fill(AppTheme.textSecondary.opacity(0.25))
                    .frame(width: 36, height: 4)
                    .frame(maxWidth: .infinity)

                // ── "Playing from" context row + like/radio/save/share pills ──
                playingFromRow
                actionPillsRow

                // ── Secondary controls, organized into switchable, swipeable panels ──
                panelPicker
                panelPageDots
                selectedPanelContent
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.18), value: selectedPanel)
                    .gesture(panelSwipeGesture)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            // `CustomTabBar` is composited above every tab's own content via
            // `.safeAreaInset` on ContentView's outer Group (see its own doc
            // comment) — that inset only reserves space automatically for
            // screens that explicitly add a matching bottom inset/padding
            // themselves (MiniPlayerBar already does, see its doc comment).
            // NowPlayingView never did, so its own bottom controls/action
            // pills rendered flush to the true safe area, directly under
            // where the pill-shaped tab bar sits on top and intercepts
            // touches meant for this screen. Reserving the same
            // `CustomTabBar.totalHeight` here keeps this screen's content
            // clear of it, consistent with every other tab.
            .padding(.bottom, 32 + CustomTabBar.totalHeight)
        }
        .navigationTitle("Now Playing")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The hero card — artwork display (default) or a full-size synced
    /// lyrics view, toggled by the top bar's display-mode pill. See
    /// `NowPlayingDisplayMode`'s doc comment for why this replaces the
    /// reference design's headphones/video toggle.
    @ViewBuilder
    var heroSection: some View {
        switch displayMode {
        case .artwork:
            artworkSection
        case .lyrics:
            NowPlayingFullLyricsHero(
                lines: lyricsLines,
                onOpenSyncEditor: { showLyricsSyncEditor = true }
            )
        }
    }

    /// A custom sliding-pill segmented control — the accent capsule glides
    /// between labels via a shared `matchedGeometryEffect` instead of the
    /// native segmented control's instant cross-fade.
    var panelPicker: some View {
        HStack(spacing: 4) {
            ForEach(NowPlayingPanel.allCases) { panel in
                Button {
                    selectHaptic.selectionChanged()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        selectedPanel = panel
                    }
                } label: {
                    Text(panel.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selectedPanel == panel ? .white : AppTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background {
                            if selectedPanel == panel {
                                Capsule(style: .continuous)
                                    .fill(screenStyle.accentColor)
                                    .matchedGeometryEffect(id: "panelPickerPill", in: panelPickerNamespace)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(AppTheme.surface.opacity(0.6), in: Capsule(style: .continuous))
        .padding(.top, 4)
    }

    /// A YouTube-Music-style paging dot indicator beneath the panel picker —
    /// echoes the reference design's swipeable-cards paging cue. Paired with
    /// `panelSwipeGesture` (attached to `selectedPanelContent` below) so the
    /// panels are both tappable (via `panelPicker`) and swipeable.
    var panelPageDots: some View {
        HStack(spacing: 6) {
            ForEach(NowPlayingPanel.allCases) { panel in
                Circle()
                    .fill(panel == selectedPanel ? screenStyle.accentColor : AppTheme.textSecondary.opacity(0.3))
                    .frame(width: 5, height: 5)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: selectedPanel)
        .padding(.top, 2)
    }

    /// Horizontal swipe on the panel content advances/retreats through
    /// `NowPlayingPanel.allCases`, mirroring `panelPicker`'s taps. Requires a
    /// clearly-horizontal drag so it doesn't fight the ScrollView's vertical
    /// scrolling.
    var panelSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) > abs(vertical) * 1.5, abs(horizontal) > 40 else { return }
                let cases = NowPlayingPanel.allCases
                guard let idx = cases.firstIndex(of: selectedPanel) else { return }
                let nextIdx = horizontal < 0 ? idx + 1 : idx - 1
                guard cases.indices.contains(nextIdx) else { return }
                selectHaptic.selectionChanged()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    selectedPanel = cases[nextIdx]
                }
            }
    }

    @ViewBuilder
    var selectedPanelContent: some View {
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
                workoutModeSection
                trackAudioSettingsSection
            }
        case .queue:
            queuePreviewSection
        case .lyrics:
            lyricsSection
        case .bookmarks:
            bookmarksSection
        }
    }
}

// MARK: - Full lyrics hero (progress-isolated, mirrors NowPlayingView+Lyrics.swift)

private struct NowPlayingFullLyricsHero: View {
    @EnvironmentObject private var progress: PlaybackProgress
    @EnvironmentObject private var player: AudioPlayerManager
    let lines: [LrcLine]
    var onOpenSyncEditor: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            if lines.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "quote.bubble")
                        .font(.system(size: 32))
                        .foregroundStyle(AppTheme.textSecondary.opacity(0.5))
                    Text("Lyrics not available")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, minHeight: 320)
            } else {
                LyricsView(lines: lines, currentPosition: progress.position, isPlaying: player.isPlaying)
                    .frame(minHeight: 320, maxHeight: 420)
                    .clipped()

                Button(action: onOpenSyncEditor) {
                    Label("Sync Editor", systemImage: "waveform.and.mic")
                        .font(.caption)
                        .foregroundStyle(AppTheme.dynamicAccent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 8)
    }
}
