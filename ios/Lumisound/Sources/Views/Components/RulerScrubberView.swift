import SwiftUI

/// A tape-measure-style ruler: evenly spaced tick marks (taller every 5th
/// tick) with a single accent-colored playhead line marking the current
/// position, rather than a filled bar. Reads more like a precise timeline
/// than a "progress fill," which is the point — distinct from every other
/// style here being some variation on "portion filled so far."
struct RulerScrubberView: View {
    let position: TimeInterval
    let duration: TimeInterval
    let isPlaying: Bool
    let onSeek: (TimeInterval) -> Void

    @State private var dragFraction: Double? = nil

    private let tickCount = 60

    private var progress: Double {
        guard duration > 0 else { return 0 }
        return min(1, dragFraction ?? (position / duration))
    }

    private var displayPosition: TimeInterval {
        dragFraction.map { $0 * duration } ?? position
    }

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    HStack(spacing: 0) {
                        ForEach(0..<tickCount, id: \.self) { i in
                            let isMajor = i % 5 == 0
                            Capsule()
                                .fill(AppTheme.textSecondary.opacity(isMajor ? 0.5 : 0.25))
                                .frame(width: isMajor ? 2 : 1, height: isMajor ? 16 : 9)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .center)

                    // Playhead line + a small accent dot riding on top of it.
                    Capsule()
                        .fill(AppTheme.dynamicAccent)
                        .frame(width: 2.5, height: 22)
                        .shadow(color: AppTheme.dynamicAccent.opacity(0.6), radius: 4)
                        .offset(x: max(0, min(geo.size.width - 2.5, geo.size.width * CGFloat(progress) - 1.25)))
                        .animation(.easeOut(duration: 0.15), value: progress)
                }
                .frame(height: 24)
                .contentShape(Rectangle().inset(by: -12))
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
            .frame(height: 30)

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
