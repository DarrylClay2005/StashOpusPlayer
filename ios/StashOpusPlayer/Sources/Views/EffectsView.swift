import SwiftUI
import UIKit

// MARK: - EffectsView

struct EffectsView: View {
    @EnvironmentObject private var player: AudioPlayerManager

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)
    private let selectHaptic = UISelectionFeedbackGenerator()
    private let successHaptic = UINotificationFeedbackGenerator()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Active indicator row
            HStack(spacing: 6) {
                Text("Active:")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                let activeName = AudioEffectsService.effect(id: player.audioSettings.activeEffectID)?.name ?? "None"
                Text(activeName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Effect grid
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(AudioEffectsService.allEffects) { effect in
                    EffectCell(
                        effect: effect,
                        isActive: player.audioSettings.activeEffectID == effect.id
                    ) {
                        selectHaptic.selectionChanged()
                        player.applyEffect(effect)
                        successHaptic.notificationOccurred(.success)
                    }
                }
            }

            // 8D-specific speed controls shown when the 8D effect is active
            if player.audioSettings.activeEffectID == "8d" {
                EightDSpeedControl()
            }
        }
        .onAppear {
            selectHaptic.prepare()
            successHaptic.prepare()
        }
    }
}

// MARK: - 8D Speed Control

private struct EightDSpeedControl: View {
    @EnvironmentObject private var player: AudioPlayerManager

    // Preset speeds: label, hz value
    private let presets: [(label: String, hz: Double)] = [
        ("Slow", 0.08), ("Smooth", 0.15), ("Default", 0.18),
        ("Fast", 0.35), ("Wild", 0.70),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
                .overlay(AppTheme.elevatedSurface)

            HStack {
                Image(systemName: "rotate.3d")
                    .font(.caption)
                    .foregroundStyle(AppTheme.accent)
                Text("8D Rotation Speed")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                Text(String(format: "%.2f Hz", player.rotationHz))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(AppTheme.textSecondary)
            }

            // Speed presets
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(presets, id: \.hz) { preset in
                        Button {
                            player.set8DSpeed(hz: preset.hz)
                        } label: {
                            Text(preset.label)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(
                                    abs(player.rotationHz - preset.hz) < 0.01 ? .white : AppTheme.textSecondary
                                )
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    abs(player.rotationHz - preset.hz) < 0.01
                                        ? AnyShapeStyle(AppTheme.accent)
                                        : AnyShapeStyle(AppTheme.elevatedSurface),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                        .animation(.easeInOut(duration: 0.15), value: player.rotationHz)
                    }
                }
            }

            // Fine-tune slider
            Slider(
                value: Binding(
                    get: { player.rotationHz },
                    set: { player.set8DSpeed(hz: $0) }
                ),
                in: 0.02...2.0
            )
            .tint(AppTheme.accent)
        }
        .padding(.top, 4)
    }
}

// MARK: - EffectCell

private struct EffectCell: View {
    let effect: AudioEffect
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: effect.icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(isActive ? .white : AppTheme.textSecondary)
                    .frame(height: 22)

                Text(effect.name)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(isActive ? .white : AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity)
            .background(
                isActive
                    ? AnyShapeStyle(AppTheme.accent)
                    : AnyShapeStyle(AppTheme.elevatedSurface),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.18), value: isActive)
    }
}
