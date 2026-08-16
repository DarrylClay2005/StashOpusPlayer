import SwiftUI

/// The plainest possible seeker — a hairline track, no thumb, no glow, no
/// timer-driven animation — for anyone who finds every other style too busy.
/// Same drag-to-seek gesture as every other scrubber, just visually silent
/// until touched (the track thickens slightly under an active drag so
/// there's still SOME feedback that a seek is in progress).
struct MinimalScrubberView: View {
    let position: TimeInterval
    let duration: TimeInterval
    let isPlaying: Bool
    let onSeek: (TimeInterval) -> Void

    @State private var dragFraction: Double? = nil

    private var progress: Double {
        guard duration > 0 else { return 0 }
        return min(1, dragFraction ?? (position / duration))
    }

    private var displayPosition: TimeInterval {
        dragFraction.map { $0 * duration } ?? position
    }

    private var isDragging: Bool { dragFraction != nil }

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AppTheme.textSecondary.opacity(0.2))
                        .frame(height: isDragging ? 3 : 1.5)
                    Capsule()
                        .fill(AppTheme.textPrimary.opacity(0.85))
                        .frame(width: geo.size.width * CGFloat(progress), height: isDragging ? 3 : 1.5)
                }
                .frame(height: 16)
                .contentShape(Rectangle().inset(by: -16))
                .animation(.easeOut(duration: 0.12), value: isDragging)
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
            .frame(height: 20)

            HStack {
                Text(formatTime(displayPosition))
                    .monospacedDigit()
                Spacer()
                Text("-" + formatTime(max(0, duration - displayPosition)))
                    .monospacedDigit()
            }
            .font(.caption2)
            .foregroundStyle(AppTheme.textSecondary.opacity(0.7))
        }
    }

    private func formatTime(_ t: TimeInterval) -> String {
        t.formattedAsMinutesSeconds
    }
}
