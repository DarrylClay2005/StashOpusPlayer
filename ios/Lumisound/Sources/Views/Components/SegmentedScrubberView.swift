import SwiftUI

/// A row of small, discrete rounded-rect segments (Spotify-style) instead of
/// one continuous bar — filled segments (up to the playhead) glow with the
/// accent color. Purely geometry-driven (segment count × progress), no
/// timer/animation loop running while idle, same cheap-render precedent as
/// `ClassicScrubberView`.
struct SegmentedScrubberView: View {
    let position: TimeInterval
    let duration: TimeInterval
    let isPlaying: Bool
    let onSeek: (TimeInterval) -> Void

    @State private var dragFraction: Double? = nil

    private let segmentCount = 40
    private let segmentSpacing: CGFloat = 3

    private var progress: Double {
        guard duration > 0 else { return 0 }
        return min(1, dragFraction ?? (position / duration))
    }

    private var displayPosition: TimeInterval {
        dragFraction.map { $0 * duration } ?? position
    }

    private var filledSegments: Int {
        Int((progress * Double(segmentCount)).rounded())
    }

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                HStack(spacing: segmentSpacing) {
                    ForEach(0..<segmentCount, id: \.self) { i in
                        let filled = i < filledSegments
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(filled ? AppTheme.dynamicAccent : AppTheme.surface)
                            .shadow(color: AppTheme.dynamicAccent.opacity(filled ? 0.35 : 0), radius: 3)
                    }
                }
                .frame(maxWidth: .infinity)
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
            .frame(height: 22)
            .animation(.easeOut(duration: 0.1), value: filledSegments)

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
        t.formattedAsMinutesSeconds
    }
}
