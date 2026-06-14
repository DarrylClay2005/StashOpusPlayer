import SwiftUI

/// A thin glowing line with a bright traveling "spark" at the playhead.
/// The line itself pulses subtly while playing.
struct NeonLineScrubberView: View {
    let position: TimeInterval
    let duration: TimeInterval
    let isPlaying: Bool
    let onSeek: (TimeInterval) -> Void

    @State private var dragFraction: Double? = nil
    @State private var glow = false

    private var progress: Double {
        guard duration > 0 else { return 0 }
        return min(1, dragFraction ?? (position / duration))
    }

    private var displayPosition: TimeInterval {
        dragFraction.map { $0 * duration } ?? position
    }

    var body: some View {
        VStack(spacing: 10) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AppTheme.surface)
                        .frame(height: 3)
                        .frame(maxHeight: .infinity, alignment: .center)

                    Capsule()
                        .fill(AppTheme.dynamicAccent)
                        .frame(width: geo.size.width * CGFloat(progress), height: 3)
                        .shadow(color: AppTheme.dynamicAccent.opacity(glow ? 0.9 : 0.4), radius: glow ? 8 : 3)
                        .frame(maxHeight: .infinity, alignment: .center)

                    Circle()
                        .fill(AppTheme.dynamicAccent)
                        .frame(width: 14, height: 14)
                        .shadow(color: AppTheme.dynamicAccent.opacity(glow ? 1 : 0.6), radius: glow ? 12 : 6)
                        .offset(x: geo.size.width * CGFloat(progress) - 7)
                        .frame(maxHeight: .infinity, alignment: .center)
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
            .animation(.easeOut(duration: 0.15), value: progress)

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
        .onChange(of: isPlaying) { playing in setGlow(playing) }
        .onAppear { setGlow(isPlaying) }
    }

    private func setGlow(_ playing: Bool) {
        if playing {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                glow = true
            }
        } else {
            withAnimation(.easeOut(duration: 0.4)) { glow = false }
        }
    }

    private func formatTime(_ t: TimeInterval) -> String {
        guard t.isFinite, t >= 0 else { return "0:00" }
        let total = Int(t.rounded())
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }
}
