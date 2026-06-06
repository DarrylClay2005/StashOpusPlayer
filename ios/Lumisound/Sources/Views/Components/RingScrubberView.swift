import SwiftUI

struct RingScrubberView: View {
    let position: TimeInterval
    let duration: TimeInterval
    let isPlaying: Bool
    let onSeek: (TimeInterval) -> Void

    @State private var dragAngle: Double? = nil
    @State private var ringGlow = false
    @State private var outerRotation: Double = 0

    private var progress: Double {
        guard duration > 0 else { return 0 }
        if let angle = dragAngle {
            return min(max(angle / (2 * .pi), 0), 1)
        }
        return min(1, position / duration)
    }

    private var displayPosition: TimeInterval {
        dragAngle.map { min(max($0 / (2 * .pi), 0), 1) * duration } ?? position
    }

    var body: some View {
        VStack(spacing: 12) {
            GeometryReader { geo in
                let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                let radius = min(geo.size.width, geo.size.height) / 2 - 16

                ZStack {
                    // Outer decorative dashed ring — rotates while playing
                    Circle()
                        .strokeBorder(
                            AppTheme.dynamicAccent.opacity(ringGlow ? 0.22 : 0.08),
                            style: StrokeStyle(lineWidth: 1, dash: [4, 7])
                        )
                        .rotationEffect(.degrees(outerRotation))

                    // Track ring
                    Circle()
                        .stroke(AppTheme.surface, lineWidth: 10)

                    // Progress arc
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            LinearGradient(
                                colors: [AppTheme.accentSoft, AppTheme.dynamicAccent],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .shadow(
                            color: AppTheme.dynamicAccent.opacity(ringGlow ? 0.55 : 0.15),
                            radius: ringGlow ? 8 : 2
                        )
                        .animation(.easeInOut(duration: 0.12), value: progress)

                    // Thumb dot
                    Circle()
                        .fill(AppTheme.dynamicAccent)
                        .frame(width: 16, height: 16)
                        .shadow(
                            color: AppTheme.dynamicAccent.opacity(ringGlow ? 0.8 : 0.4),
                            radius: ringGlow ? 10 : 4
                        )
                        .scaleEffect(ringGlow ? 1.15 : 1.0)
                        .offset(y: -radius)
                        .rotationEffect(.degrees(progress * 360 - 90))
                        .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: ringGlow)

                    // Time display
                    VStack(spacing: 2) {
                        Text(formatTime(displayPosition))
                            .font(.system(size: 24, weight: .bold, design: .monospaced))
                            .foregroundStyle(AppTheme.textPrimary)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Text(formatTime(duration))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
                .contentShape(Circle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { val in
                            let dx = val.location.x - center.x
                            let dy = val.location.y - center.y
                            var angle = atan2(dy, dx) + .pi / 2
                            if angle < 0 { angle += 2 * .pi }
                            dragAngle = angle
                        }
                        .onEnded { val in
                            let dx = val.location.x - center.x
                            let dy = val.location.y - center.y
                            var angle = atan2(dy, dx) + .pi / 2
                            if angle < 0 { angle += 2 * .pi }
                            let frac = min(max(angle / (2 * .pi), 0), 1)
                            onSeek(frac * duration)
                            dragAngle = nil
                        }
                )
            }
            .frame(width: 200, height: 200)
            .frame(maxWidth: .infinity)
        }
        .onChange(of: isPlaying) { playing in
            updateAnimations(playing: playing)
        }
        .onAppear {
            updateAnimations(playing: isPlaying)
        }
    }

    private func updateAnimations(playing: Bool) {
        ringGlow = playing
        if playing {
            withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                outerRotation = 360
            }
        } else {
            withAnimation(.easeOut(duration: 0.5)) {
                outerRotation = 0
            }
        }
    }

    private func formatTime(_ t: TimeInterval) -> String {
        guard t.isFinite, t >= 0 else { return "0:00" }
        let total = Int(t.rounded())
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }
}
