import SwiftUI

// MARK: - SpectrumWaveformArtworkView
//
// Album art in the center surrounded by 30 animated vertical bars that pulse
// to simulate an audio spectrum. Bar heights are driven by a Timer — no actual
// audio data is used. Bars are coloured with a gradient that cycles through
// AppTheme accent colors.

struct SpectrumWaveformArtworkView: View {
    let song: Song?
    let isPlaying: Bool

    @EnvironmentObject private var library: LibraryManager

    // Each bar's current height fraction in [0, 1]
    @State private var barHeights: [CGFloat]
    @State private var timer: Timer? = nil

    private let barCount      = 30
    private let artSize:     CGFloat = 180
    private let maxBarHeight: CGFloat = 80
    private let minBarHeight: CGFloat = 6
    private let barWidth:     CGFloat = 5
    private let barSpacing:   CGFloat = 4

    init(song: Song?, isPlaying: Bool) {
        self.song = song
        self.isPlaying = isPlaying
        // Initialise with a gentle resting pattern
        _barHeights = State(initialValue: (0..<30).map { i in
            0.15 + 0.35 * abs(sin(Double(i) * 0.4))
        })
    }

    var body: some View {
        ZStack {
            // Spectrum bars — drawn behind and around the art circle
            spectrumBars

            // Central album art
            centralArt
        }
        .frame(width: artSize + (maxBarHeight + 20) * 2,
               height: artSize + (maxBarHeight + 20) * 2)
        .onChange(of: isPlaying) { playing in
            if playing { startTimer() } else { stopTimer() }
        }
        .onAppear {
            if isPlaying { startTimer() }
        }
        .onDisappear {
            stopTimer()
        }
    }

    // MARK: Spectrum bars

    private var spectrumBars: some View {
        GeometryReader { geo in
            let cx = geo.size.width  / 2
            let cy = geo.size.height / 2
            let radius = artSize / 2 + 12   // gap between art edge and bar base

            ForEach(0..<barCount, id: \.self) { i in
                let angle = (Double(i) / Double(barCount)) * 2 * .pi - .pi / 2
                let barH = minBarHeight + (maxBarHeight - minBarHeight) * barHeights[i]
                let baseX = cx + CGFloat(cos(angle)) * radius
                let baseY = cy + CGFloat(sin(angle)) * radius

                // Each bar is a capsule pointing outward from the circle centre
                barCapsule(height: barH, index: i)
                    .rotationEffect(.degrees(Double(i) / Double(barCount) * 360 - 90))
                    .position(
                        x: baseX + CGFloat(cos(angle)) * barH / 2,
                        y: baseY + CGFloat(sin(angle)) * barH / 2
                    )
            }
        }
    }

    private func barCapsule(height: CGFloat, index: Int) -> some View {
        let fraction = Double(index) / Double(barCount)
        let startColor = AppTheme.accent.opacity(0.9)
        let midColor   = AppTheme.dynamicAccent
        let endColor   = AppTheme.accentSoft.opacity(0.7)
        let barColor: Color = fraction < 0.5
            ? interpolate(from: startColor, to: midColor, t: fraction * 2)
            : interpolate(from: midColor, to: endColor, t: (fraction - 0.5) * 2)

        return Capsule()
            .fill(barColor)
            .frame(width: barWidth, height: height)
    }

    // MARK: Central art

    private var centralArt: some View {
        Group {
            if let song {
                ArtworkThumbnail(song: song, size: artSize)
                    .environmentObject(library)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.surface, AppTheme.elevatedSurface],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: artSize, height: artSize)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 60, weight: .semibold))
                            .foregroundStyle(AppTheme.accent)
                    }
            }
        }
        .overlay(
            Circle()
                .strokeBorder(AppTheme.dynamicAccent.opacity(0.5), lineWidth: 2)
        )
        .shadow(color: AppTheme.dynamicAccent.opacity(0.4), radius: 16, x: 0, y: 0)
    }

    // MARK: Timer

    private func startTimer() {
        stopTimer()
        let t = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.08)) {
                for i in 0..<barCount {
                    // Combine a slow drift wave with random micro-jitter
                    let phase = Double(i) / Double(barCount) * 2 * .pi
                    let drift = 0.5 + 0.45 * sin(Date().timeIntervalSince1970 * 3.5 + phase)
                    let jitter = CGFloat.random(in: -0.12...0.12)
                    barHeights[i] = CGFloat(max(0.05, min(1.0, drift + Double(jitter))))
                }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        // Settle bars back to a gentle resting wave
        withAnimation(.easeOut(duration: 0.6)) {
            for i in 0..<barCount {
                barHeights[i] = 0.15 + 0.35 * abs(sin(Double(i) * 0.4))
            }
        }
    }

    // MARK: Color interpolation

    /// Simple linear interpolation between two SwiftUI Colors.
    /// Operates in sRGB color space.
    private func interpolate(from a: Color, to b: Color, t: Double) -> Color {
        let cA = UIColor(a).cgColor.components ?? [0, 0, 0, 1]
        let cB = UIColor(b).cgColor.components ?? [0, 0, 0, 1]
        func lerp(_ x: CGFloat, _ y: CGFloat) -> CGFloat { x + (y - x) * CGFloat(t) }
        let r = lerp(cA.count > 0 ? cA[0] : 0, cB.count > 0 ? cB[0] : 0)
        let g = lerp(cA.count > 1 ? cA[1] : 0, cB.count > 1 ? cB[1] : 0)
        let bl = lerp(cA.count > 2 ? cA[2] : 0, cB.count > 2 ? cB[2] : 0)
        let alpha = lerp(cA.count > 3 ? cA[3] : 1, cB.count > 3 ? cB[3] : 1)
        return Color(red: r, green: g, blue: bl, opacity: alpha)
    }
}
