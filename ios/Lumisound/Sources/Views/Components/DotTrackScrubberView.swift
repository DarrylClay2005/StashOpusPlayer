import SwiftUI

/// A row of evenly-spaced dots that fill in (and grow slightly) as playback
/// progresses, like a step indicator. Dragging anywhere seeks proportionally.
struct DotTrackScrubberView: View {
    let position: TimeInterval
    let duration: TimeInterval
    let isPlaying: Bool
    let onSeek: (TimeInterval) -> Void

    @State private var dragFraction: Double? = nil

    private let dotCount = 30

    private var progress: Double {
        guard duration > 0 else { return 0 }
        return min(1, dragFraction ?? (position / duration))
    }

    private var displayPosition: TimeInterval {
        dragFraction.map { $0 * duration } ?? position
    }

    private var filledDots: Int {
        Int((progress * Double(dotCount)).rounded())
    }

    var body: some View {
        VStack(spacing: 10) {
            GeometryReader { geo in
                HStack(spacing: 0) {
                    ForEach(0..<dotCount, id: \.self) { i in
                        let filled = i < filledDots
                        Circle()
                            .fill(filled ? AppTheme.dynamicAccent : AppTheme.surface)
                            .frame(width: filled ? 7 : 5, height: filled ? 7 : 5)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
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
            .frame(height: 24)
            .animation(.easeOut(duration: 0.1), value: filledDots)

            HStack {
                Text(formatTime(displayPosition))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.textSecondary)
                Spacer()
                Text("-" + formatTime(max(0, duration - displayPosition)))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
    }

    private func formatTime(_ t: TimeInterval) -> String {
        guard t.isFinite, t >= 0 else { return "0:00" }
        let total = Int(t.rounded())
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }
}
