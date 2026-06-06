import SwiftUI

struct RingScrubberView: View {
    let position: TimeInterval
    let duration: TimeInterval
    let onSeek: (TimeInterval) -> Void

    @State private var dragAngle: Double? = nil

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
                    Circle()
                        .stroke(AppTheme.surface, lineWidth: 10)

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
                        .animation(.easeInOut(duration: 0.1), value: progress)

                    Circle()
                        .fill(AppTheme.dynamicAccent)
                        .frame(width: 16, height: 16)
                        .shadow(color: AppTheme.dynamicAccent.opacity(0.6), radius: 6)
                        .offset(y: -radius)
                        .rotationEffect(.degrees(progress * 360 - 90))

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
    }

    private func formatTime(_ t: TimeInterval) -> String {
        guard t.isFinite, t >= 0 else { return "0:00" }
        let total = Int(t.rounded())
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }
}
