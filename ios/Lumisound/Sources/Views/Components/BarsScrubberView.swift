import SwiftUI

struct BarsScrubberView: View {
    let position: TimeInterval
    let duration: TimeInterval
    let isPlaying: Bool
    let onSeek: (TimeInterval) -> Void
    @Environment(\.scenePhase) private var scenePhase

    @State private var dragFraction: Double? = nil
    @State private var liveMultipliers: [CGFloat] = Array(repeating: 1.0, count: 36)
    @State private var animTimer: Timer? = nil

    private var progress: Double {
        guard duration > 0 else { return 0 }
        return min(1, dragFraction ?? (position / duration))
    }

    private var displayPosition: TimeInterval {
        dragFraction.map { $0 * duration } ?? position
    }

    private let barCount = 36

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(0..<barCount, id: \.self) { i in
                        let threshold = Double(i) / Double(barCount)
                        let isActive = threshold < progress
                        let h = barHeight(index: i, totalHeight: geo.size.height) * liveMultipliers[i]
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(
                                isActive
                                    ? AnyShapeStyle(LinearGradient(
                                        colors: [AppTheme.accentSoft, AppTheme.dynamicAccent],
                                        startPoint: .bottom,
                                        endPoint: .top
                                      ))
                                    : AnyShapeStyle(AppTheme.surface)
                            )
                            .frame(maxWidth: .infinity, maxHeight: h)
                            .animation(.easeInOut(duration: 0.12), value: h)
                            .animation(.easeInOut(duration: 0.06).delay(Double(i) * 0.002), value: isActive)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
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
            .frame(height: 52)

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
            if playing { startLiveAnimation() } else { stopLiveAnimation() }
        }
        .onChange(of: scenePhase) { phase in
            // Background audio keeps this 10Hz timer ticking with the scrubber
            // off-screen — pause/resume it instead of burning CPU for nothing.
            if phase == .active {
                if isPlaying { startLiveAnimation() }
            } else {
                animTimer?.invalidate()
                animTimer = nil
            }
        }
        .onAppear {
            if isPlaying { startLiveAnimation() }
        }
        .onDisappear {
            stopLiveAnimation()
        }
    }

    private func startLiveAnimation() {
        stopLiveAnimation()
        let t = Timer.scheduledTimer(withTimeInterval: 0.10, repeats: true) { _ in
            let now = Date().timeIntervalSince1970
            for i in 0..<barCount {
                let phase = Double(i) / Double(barCount) * 2 * .pi
                let wave = 0.9 + 0.12 * sin(now * 2.8 + phase)
                liveMultipliers[i] = CGFloat(wave)
            }
        }
        RunLoop.main.add(t, forMode: .common)
        animTimer = t
    }

    private func stopLiveAnimation() {
        animTimer?.invalidate()
        animTimer = nil
        withAnimation(.easeOut(duration: 0.4)) {
            liveMultipliers = Array(repeating: 1.0, count: barCount)
        }
    }

    private func barHeight(index: Int, totalHeight: CGFloat) -> CGFloat {
        let normalized = Double(index) / Double(barCount - 1)
        let wave = abs(sin(normalized * .pi * 2.5)) * 0.55 + 0.45
        return totalHeight * CGFloat(wave)
    }

    private func formatTime(_ t: TimeInterval) -> String {
        guard t.isFinite, t >= 0 else { return "0:00" }
        let total = Int(t.rounded())
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }
}
