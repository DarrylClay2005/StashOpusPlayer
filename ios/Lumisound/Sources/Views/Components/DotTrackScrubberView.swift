import SwiftUI

/// A row of dots arranged in a gentle wave, sized by a traveling ripple while
/// playing. Filled dots (up to the playhead) glow with the accent color;
/// unfilled dots sit at the wave's baseline size. Dragging anywhere seeks
/// proportionally.
struct DotTrackScrubberView: View {
    let position: TimeInterval
    let duration: TimeInterval
    let isPlaying: Bool
    let onSeek: (TimeInterval) -> Void
    @Environment(\.scenePhase) private var scenePhase

    @State private var dragFraction: Double? = nil
    @State private var ripplePhase: Double = 0
    @State private var rippleTimer: Timer? = nil

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
                        let wave = 0.5 + 0.5 * sin(Double(i) * 0.6 - ripplePhase)
                        let baseSize: CGFloat = filled ? 6 : 4
                        let waveBoost: CGFloat = filled ? CGFloat(wave) * 4 : CGFloat(wave) * 1.5
                        let size = baseSize + waveBoost

                        Circle()
                            .fill(filled ? AppTheme.dynamicAccent : AppTheme.surface)
                            .frame(width: size, height: size)
                            .shadow(
                                color: AppTheme.dynamicAccent.opacity(filled ? 0.6 * wave : 0),
                                radius: filled ? 4 * wave : 0
                            )
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
        .onChange(of: isPlaying) { playing in
            if playing { startRipple() } else { stopRipple() }
        }
        .onChange(of: scenePhase) { phase in
            // Background audio keeps the run loop alive — pause/resume the
            // ripple timer instead of burning CPU with nothing on screen.
            if phase == .active {
                if isPlaying { startRipple() }
            } else {
                rippleTimer?.invalidate()
                rippleTimer = nil
            }
        }
        .onAppear {
            if isPlaying { startRipple() }
        }
        .onDisappear {
            stopRipple()
        }
    }

    private func startRipple() {
        rippleTimer?.invalidate()
        let t = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            withAnimation(.linear(duration: 0.05)) {
                ripplePhase += 0.12
            }
        }
        RunLoop.main.add(t, forMode: .common)
        rippleTimer = t
    }

    private func stopRipple() {
        rippleTimer?.invalidate()
        rippleTimer = nil
    }

    private func formatTime(_ t: TimeInterval) -> String {
        t.formattedAsMinutesSeconds
    }
}
