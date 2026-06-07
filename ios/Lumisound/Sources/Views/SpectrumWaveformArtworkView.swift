import SwiftUI

struct SpectrumWaveformArtworkView: View {
    let song: Song?
    let isPlaying: Bool

    @EnvironmentObject private var library: LibraryManager

    @State private var barHeights: [CGFloat]
    @State private var timer: Timer? = nil
    @State private var artRotation: Double = 0
    @State private var pulseRadius: CGFloat = 0
    @State private var pulseOpacity: Double = 0
    @State private var glowPulse = false

    private let barCount      = 36
    private let artSize:     CGFloat = 180
    private let maxBarHeight: CGFloat = 80
    private let minBarHeight: CGFloat = 6
    private let barWidth:     CGFloat = 4
    private let barSpacing:   CGFloat = 3

    init(song: Song?, isPlaying: Bool) {
        self.song = song
        self.isPlaying = isPlaying
        _barHeights = State(initialValue: (0..<36).map { i in
            0.15 + 0.35 * abs(sin(Double(i) * 0.4))
        })
    }

    var body: some View {
        ZStack {
            // Beat pulse ring — expands outward from center
            Circle()
                .stroke(AppTheme.dynamicAccent.opacity(pulseOpacity), lineWidth: 2)
                .frame(width: artSize + pulseRadius, height: artSize + pulseRadius)
                .allowsHitTesting(false)

            // Spectrum bars radially arranged
            spectrumBars

            // Central album art — slowly rotates while playing
            centralArt
                .rotationEffect(.degrees(artRotation))
        }
        .frame(width: artSize + (maxBarHeight + 24) * 2,
               height: artSize + (maxBarHeight + 24) * 2)
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
            let radius = artSize / 2 + 14

            ForEach(0..<barCount, id: \.self) { i in
                let angle = (Double(i) / Double(barCount)) * 2 * .pi - .pi / 2
                let barH = minBarHeight + (maxBarHeight - minBarHeight) * barHeights[i]
                let baseX = cx + CGFloat(cos(angle)) * radius
                let baseY = cy + CGFloat(sin(angle)) * radius

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
        let startColor = AppTheme.dynamicAccent.opacity(0.9)
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
                            .foregroundStyle(AppTheme.dynamicAccent)
                    }
            }
        }
        .overlay(
            Circle()
                .strokeBorder(AppTheme.dynamicAccent.opacity(glowPulse ? 0.8 : 0.3), lineWidth: 2)
                .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: glowPulse)
        )
        .shadow(
            color: AppTheme.dynamicAccent.opacity(glowPulse ? 0.55 : 0.25),
            radius: glowPulse ? 20 : 10, x: 0, y: 0
        )
        .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: glowPulse)
    }

    // MARK: Timer

    private func startTimer() {
        stopTimer()
        glowPulse = true
        withAnimation(.linear(duration: 28).repeatForever(autoreverses: false)) {
            artRotation = 360
        }

        let t = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in
            let now = Date().timeIntervalSince1970
            var peak = 0.0
            withAnimation(.easeInOut(duration: 0.08)) {
                for i in 0..<barCount {
                    let phase = Double(i) / Double(barCount) * 2 * .pi
                    let drift = 0.5 + 0.45 * sin(now * 3.5 + phase)
                    let jitter = CGFloat.random(in: -0.12...0.12)
                    barHeights[i] = CGFloat(max(0.05, min(1.0, drift + Double(jitter))))
                    if Double(barHeights[i]) > peak { peak = Double(barHeights[i]) }
                }
            }
            // Trigger pulse ring on beat peak
            if peak > 0.88 && pulseOpacity < 0.05 {
                triggerBeatPulse()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        glowPulse = false
        withAnimation(.easeOut(duration: 0.8)) {
            artRotation = 0
        }
        withAnimation(.easeOut(duration: 0.6)) {
            for i in 0..<barCount {
                barHeights[i] = 0.15 + 0.35 * abs(sin(Double(i) * 0.4))
            }
        }
    }

    private func triggerBeatPulse() {
        pulseRadius = 0
        pulseOpacity = 0.6
        withAnimation(.easeOut(duration: 0.7)) {
            pulseRadius = 70
            pulseOpacity = 0
        }
    }

    // MARK: Color interpolation

    private func interpolate(from a: Color, to b: Color, t: Double) -> Color {
        let cA = UIColor(a).cgColor.components ?? [0, 0, 0, 1]
        let cB = UIColor(b).cgColor.components ?? [0, 0, 0, 1]
        func lerp(_ x: CGFloat, _ y: CGFloat) -> CGFloat { x + (y - x) * CGFloat(t) }
        let r  = lerp(cA.count > 0 ? cA[0] : 0, cB.count > 0 ? cB[0] : 0)
        let g  = lerp(cA.count > 1 ? cA[1] : 0, cB.count > 1 ? cB[1] : 0)
        let bl = lerp(cA.count > 2 ? cA[2] : 0, cB.count > 2 ? cB[2] : 0)
        let al = lerp(cA.count > 3 ? cA[3] : 1, cB.count > 3 ? cB[3] : 1)
        return Color(red: r, green: g, blue: bl, opacity: al)
    }
}
