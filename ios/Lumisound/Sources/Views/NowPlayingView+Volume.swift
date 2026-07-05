import SwiftUI
import UIKit

extension NowPlayingView {

    // MARK: - Volume

    var volumeSection: some View {
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
}
