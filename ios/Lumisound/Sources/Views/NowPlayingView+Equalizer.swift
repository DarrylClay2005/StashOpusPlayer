import SwiftUI
import UIKit

extension NowPlayingView {

    // MARK: - Equalizer

    var equalizerSection: some View {
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

    func eqBandColumn(index: Int) -> some View {
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
}
