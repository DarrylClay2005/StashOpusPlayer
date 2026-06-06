import SwiftUI
import DSWaveformImage
import DSWaveformImageViews

// MARK: - WaveformScrubberView
//
// Renders the actual audio waveform of a local file using DSWaveformImage.
// Two waveform layers are stacked:
//   1. A dim background layer (full duration)
//   2. A tinted foreground layer clipped to the current playback progress
// Tap or drag anywhere on the waveform to seek.

struct WaveformScrubberView: View {
    let url: URL
    let position: TimeInterval
    let duration: TimeInterval
    let onSeek: (TimeInterval) -> Void

    @State private var dragFraction: Double? = nil

    private var progress: Double {
        guard duration > 0 else { return 0 }
        return min(1, dragFraction ?? (position / duration))
    }

    private var displayPosition: TimeInterval {
        dragFraction.map { $0 * duration } ?? position
    }

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Dim background — shows the full track waveform
                    WaveformView(
                        audioURL: url,
                        configuration: Waveform.Configuration(
                            style: .striped(.init(
                                color: UIColor(AppTheme.textSecondary).withAlphaComponent(0.28),
                                width: 2,
                                spacing: 1
                            )),
                            verticalScalingFactor: 0.85
                        )
                    )

                    // Tinted foreground — clipped to playhead position
                    WaveformView(
                        audioURL: url,
                        configuration: Waveform.Configuration(
                            style: .striped(.init(
                                color: UIColor(AppTheme.accent),
                                width: 2,
                                spacing: 1
                            )),
                            verticalScalingFactor: 0.85
                        )
                    )
                    .mask(alignment: .leading) {
                        Rectangle()
                            .frame(width: max(2, geo.size.width * progress))
                            .frame(maxHeight: .infinity)
                    }

                    // Playhead line
                    Rectangle()
                        .fill(Color.white.opacity(0.75))
                        .frame(width: 2)
                        .offset(x: max(0, geo.size.width * progress - 1))
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { val in
                            dragFraction = min(max(val.location.x / geo.size.width, 0), 1)
                        }
                        .onEnded { val in
                            let frac = min(max(val.location.x / geo.size.width, 0), 1)
                            onSeek(frac * duration)
                            dragFraction = nil
                        }
                )
            }
            .frame(height: 52)

            HStack {
                Text(formatTime(displayPosition))
                    .monospacedDigit()
                Spacer()
                Text("-" + formatTime(max(0, duration - displayPosition)))
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(AppTheme.textSecondary)
        }
    }

    private func formatTime(_ t: TimeInterval) -> String {
        guard t.isFinite, t >= 0 else { return "0:00" }
        let total = Int(t.rounded())
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }
}
