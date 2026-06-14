import SwiftUI

/// LCD/digital-clock style time readout with a thin segmented progress strip
/// underneath. Tapping/dragging the strip seeks, same as the other scrubbers.
struct DigitalScrubberView: View {
    let position: TimeInterval
    let duration: TimeInterval
    let isPlaying: Bool
    let onSeek: (TimeInterval) -> Void

    @State private var dragFraction: Double? = nil
    @State private var colonBlink = false

    private let segmentCount = 40

    private var progress: Double {
        guard duration > 0 else { return 0 }
        return min(1, dragFraction ?? (position / duration))
    }

    private var displayPosition: TimeInterval {
        dragFraction.map { $0 * duration } ?? position
    }

    var body: some View {
        VStack(spacing: 10) {
            // Big digital readout
            HStack(spacing: 4) {
                Text(formatTime(displayPosition, blinkColon: colonBlink))
                    .font(.system(size: 34, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppTheme.dynamicAccent)
                    .shadow(color: AppTheme.dynamicAccent.opacity(isPlaying ? 0.6 : 0.0), radius: 8)
                    .contentTransition(.numericText())
                Text("/")
                    .font(.system(size: 22, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppTheme.textSecondary.opacity(0.5))
                Text(formatTime(duration, blinkColon: true))
                    .font(.system(size: 22, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .animation(.easeInOut(duration: 0.2), value: isPlaying)

            // Segmented LED-style progress strip
            GeometryReader { geo in
                let segWidth = (geo.size.width - CGFloat(segmentCount - 1) * 3) / CGFloat(segmentCount)
                HStack(spacing: 3) {
                    ForEach(0..<segmentCount, id: \.self) { i in
                        let threshold = Double(i) / Double(segmentCount)
                        let isActive = threshold < progress
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(isActive ? AppTheme.dynamicAccent : AppTheme.surface)
                            .frame(width: segWidth)
                            .shadow(color: isActive ? AppTheme.dynamicAccent.opacity(0.5) : .clear, radius: 3)
                    }
                }
                .frame(height: 14)
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
                .animation(.easeOut(duration: 0.1), value: progress)
            }
            .frame(height: 14)
        }
        .onChange(of: isPlaying) { playing in
            updateBlink(playing: playing)
        }
        .onAppear {
            updateBlink(playing: isPlaying)
        }
    }

    private func updateBlink(playing: Bool) {
        if playing {
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                colonBlink = true
            }
        } else {
            withAnimation(.easeInOut(duration: 0.2)) {
                colonBlink = false
            }
        }
    }

    private func formatTime(_ t: TimeInterval, blinkColon: Bool) -> String {
        guard t.isFinite, t >= 0 else { return "0:00" }
        let total = Int(t.rounded())
        let separator = blinkColon ? ":" : " "
        return "\(total / 60)\(separator)\(String(format: "%02d", total % 60))"
    }
}
