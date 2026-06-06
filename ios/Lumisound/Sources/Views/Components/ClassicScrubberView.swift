import SwiftUI

struct ClassicScrubberView: View {
    let position: TimeInterval
    let duration: TimeInterval
    let isPlaying: Bool
    let onSeek: (TimeInterval) -> Void

    @State private var dragFraction: Double? = nil
    @State private var thumbPulse = false

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
                    Capsule()
                        .fill(AppTheme.surface)
                        .frame(height: 4)

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [AppTheme.accentSoft, AppTheme.dynamicAccent],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * CGFloat(progress), height: 4)
                        .animation(.easeOut(duration: 0.15), value: progress)

                    // Glowing thumb
                    Circle()
                        .fill(AppTheme.dynamicAccent)
                        .frame(width: 16, height: 16)
                        .shadow(
                            color: AppTheme.dynamicAccent.opacity(thumbPulse ? 0.85 : 0.4),
                            radius: thumbPulse ? 12 : 5
                        )
                        .scaleEffect(thumbPulse ? 1.18 : 1.0)
                        .offset(x: max(0, geo.size.width * CGFloat(progress) - 8))
                        .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: thumbPulse)
                }
                .frame(height: 16)
                .contentShape(Rectangle().inset(by: -16))
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
            .frame(height: 40)

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
        .onChange(of: isPlaying) { playing in
            thumbPulse = playing
        }
        .onAppear {
            thumbPulse = isPlaying
        }
    }

    private func formatTime(_ t: TimeInterval) -> String {
        guard t.isFinite, t >= 0 else { return "0:00" }
        let total = Int(t.rounded())
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }
}
