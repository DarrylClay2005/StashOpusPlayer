import SwiftUI
import UIKit

extension NowPlayingView {

    // MARK: - Scroll content

    var scrollContent: some View {
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
                                    .fill(AppTheme.dynamicAccent)
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
