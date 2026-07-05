import SwiftUI
import UIKit

extension NowPlayingView {

    // MARK: - Playback Controls Panel

    var playbackControlsSection: some View {
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
}
