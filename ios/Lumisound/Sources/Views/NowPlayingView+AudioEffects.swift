import SwiftUI
import UIKit

extension NowPlayingView {

    // MARK: - Audio Effects

    var effectsSection: some View {
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
}
