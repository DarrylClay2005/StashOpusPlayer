import SwiftUI

struct BarsScrubberView: View {
    let position: TimeInterval
    let duration: TimeInterval
    let onSeek: (TimeInterval) -> Void

    @State private var dragFraction: Double? = nil

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
                            .frame(maxWidth: .infinity, maxHeight: barHeight(index: i, totalHeight: geo.size.height))
                            .animation(.easeInOut(duration: 0.06).delay(Double(i) * 0.003), value: isActive)
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
