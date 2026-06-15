import SwiftUI

/// A thin multi-color neon tube with a bright comet-like playhead — the
/// filled portion is a cyan-to-magenta gradient (rather than the app accent
/// color used elsewhere) and the playhead trails a soft fading glow behind
/// it, giving this preset a distinct "glowing tube" identity.
struct NeonLineScrubberView: View {
    let position: TimeInterval
    let duration: TimeInterval
    let isPlaying: Bool
    let onSeek: (TimeInterval) -> Void

    @State private var dragFraction: Double? = nil
    @State private var glow = false

    private let neonGradient = LinearGradient(
        colors: [
            Color(red: 0.25, green: 0.95, blue: 1.0),
            AppTheme.dynamicAccent,
            Color(red: 1.0, green: 0.35, blue: 0.95)
        ],
        startPoint: .leading,
        endPoint: .trailing
    )

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
                    // Unlit tube
                    Capsule()
                        .fill(AppTheme.surface)
                        .frame(height: 4)
                        .frame(maxHeight: .infinity, alignment: .center)

                    // Lit neon tube
                    Capsule()
                        .fill(neonGradient)
                        .frame(width: geo.size.width * CGFloat(progress), height: 4)
                        .shadow(color: Color(red: 0.25, green: 0.95, blue: 1.0).opacity(glow ? 0.8 : 0.35), radius: glow ? 10 : 4)
                        .shadow(color: Color(red: 1.0, green: 0.35, blue: 0.95).opacity(glow ? 0.8 : 0.35), radius: glow ? 10 : 4)
                        .frame(maxHeight: .infinity, alignment: .center)

                    // Comet trail — fading streak behind the playhead
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.clear, .white.opacity(glow ? 0.55 : 0.25)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: min(geo.size.width * CGFloat(progress), 46), height: 4)
                        .offset(x: max(0, geo.size.width * CGFloat(progress) - min(geo.size.width * CGFloat(progress), 46)))
                        .frame(maxHeight: .infinity, alignment: .center)
                        .blendMode(.plusLighter)

                    // Playhead spark
                    Circle()
                        .fill(.white)
                        .frame(width: 14, height: 14)
                        .shadow(color: Color(red: 0.25, green: 0.95, blue: 1.0).opacity(glow ? 1 : 0.6), radius: glow ? 14 : 7)
                        .shadow(color: Color(red: 1.0, green: 0.35, blue: 0.95).opacity(glow ? 0.8 : 0.4), radius: glow ? 10 : 5)
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
        t.formattedAsMinutesSeconds
    }
}
