import SwiftUI

/// A large filling capsule with the elapsed/remaining time printed directly on
/// top of it — the fill clips to reveal a light-on-dark label as progress advances.
struct PillScrubberView: View {
    let position: TimeInterval
    let duration: TimeInterval
    let isPlaying: Bool
    let onSeek: (TimeInterval) -> Void

    @State private var dragFraction: Double? = nil
    @State private var pulse = false

    private var progress: Double {
        guard duration > 0 else { return 0 }
        return min(1, dragFraction ?? (position / duration))
    }

    private var displayPosition: TimeInterval {
        dragFraction.map { $0 * duration } ?? position
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Track
                Capsule()
                    .fill(AppTheme.surface)

                // Fill
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.dynamicAccent, AppTheme.accentSoft],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(geo.size.height, geo.size.width * CGFloat(progress)))
                    .shadow(color: AppTheme.dynamicAccent.opacity(pulse ? 0.5 : 0.2), radius: pulse ? 10 : 4)
                    .animation(.easeOut(duration: 0.15), value: progress)
                    .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: pulse)

                // Labels — same two Text views drawn twice (once light, once dark)
                // and clipped against the fill so each half reads against its
                // own background, like a "liquid" progress label.
                timeLabels
                    .foregroundStyle(AppTheme.textPrimary)

                timeLabels
                    .foregroundStyle(Color.black.opacity(0.75))
                    .mask(
                        Capsule()
                            .frame(width: max(geo.size.height, geo.size.width * CGFloat(progress)))
                            .animation(.easeOut(duration: 0.15), value: progress)
                    )
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
        .frame(height: 44)
        .onChange(of: isPlaying) { playing in
            pulse = playing
        }
        .onAppear {
            pulse = isPlaying
        }
    }

    private var timeLabels: some View {
        HStack {
            Text(formatTime(displayPosition))
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .monospacedDigit()
            Spacer()
            Text("-" + formatTime(max(0, duration - displayPosition)))
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .padding(.horizontal, 18)
    }

    private func formatTime(_ t: TimeInterval) -> String {
        t.formattedAsMinutesSeconds
    }
}
