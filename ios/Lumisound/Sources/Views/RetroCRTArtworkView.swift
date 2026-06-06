import SwiftUI

struct RetroCRTArtworkView: View {
    let song: Song?
    let isPlaying: Bool

    @EnvironmentObject private var library: LibraryManager

    @State private var scanlineOffset: CGFloat = 0
    @State private var tickerOffset: CGFloat = 0
    @State private var screenOpacity: Double = 1.0
    @State private var bezelGlow = false
    @State private var flickerTimer: Timer? = nil

    private let screenSize:   CGFloat = 250
    private let bezelPad:     CGFloat = 20
    private let tickerHeight:  CGFloat = 22
    private let phosphorColor = Color(red: 0.0, green: 1.0, blue: 0.4).opacity(0.06)

    var body: some View {
        VStack(spacing: 0) {
            // CRT screen area
            ZStack {
                screenContent
                    .opacity(screenOpacity)

                scanlineOverlay

                phosphorColor
                    .allowsHitTesting(false)

                // Vignette — darkens corners like a real CRT
                RadialGradient(
                    colors: [.clear, .black.opacity(0.45)],
                    center: .center,
                    startRadius: 80,
                    endRadius: 160
                )
                .allowsHitTesting(false)
            }
            .frame(width: screenSize, height: screenSize)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .scaleEffect(x: 1.0, y: 0.96)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.8), lineWidth: 2)
            )
            .padding(bezelPad)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(white: 0.22), Color(white: 0.14)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    // Bezel glow when playing
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(
                            Color(red: 0.0, green: 1.0, blue: 0.4)
                                .opacity(bezelGlow ? 0.40 : 0.08),
                            lineWidth: 2
                        )
                        .animation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true), value: bezelGlow)

                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color(white: 0.35).opacity(0.6), lineWidth: 1)
                }
                .shadow(
                    color: Color(red: 0.0, green: 0.8, blue: 0.3)
                        .opacity(bezelGlow ? 0.35 : 0.05),
                    radius: bezelGlow ? 20 : 6, x: 0, y: 4
                )
                .animation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true), value: bezelGlow)
            )

            ledTicker
        }
        .onChange(of: isPlaying) { playing in
            updateAnimations(playing: playing)
        }
        .onAppear {
            startScanlineAnimation()
            updateAnimations(playing: isPlaying)
        }
        .onDisappear {
            flickerTimer?.invalidate()
            flickerTimer = nil
        }
    }

    // MARK: Screen content

    @ViewBuilder
    private var screenContent: some View {
        if let song {
            ArtworkThumbnail(song: song, size: screenSize)
                .environmentObject(library)
        } else {
            Color.black
                .overlay {
                    Image(systemName: "music.note.tv")
                        .font(.system(size: 60, weight: .semibold))
                        .foregroundStyle(Color(red: 0.0, green: 0.9, blue: 0.4).opacity(0.8))
                }
        }
    }

    // MARK: Scanline overlay

    private var scanlineOverlay: some View {
        GeometryReader { geo in
            let lineSpacing: CGFloat = 4
            let count = Int(geo.size.height / lineSpacing) + 2
            VStack(spacing: 0) {
                ForEach(0..<count, id: \.self) { _ in
                    Color.black.opacity(0.18)
                        .frame(height: 1)
                    Color.clear
                        .frame(height: lineSpacing - 1)
                }
            }
            .offset(y: scanlineOffset)
        }
        .allowsHitTesting(false)
    }

    private func startScanlineAnimation() {
        withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
            scanlineOffset = 4
        }
    }

    // MARK: LED ticker

    private var ledTicker: some View {
        let label = isPlaying
            ? "  ◀▶  NOW PLAYING: \(song?.displayName.uppercased() ?? "NOTHING")  —  \(song?.artistName.uppercased() ?? "")   "
            : "  ■  PAUSED  "

        return ZStack {
            Capsule()
                .fill(Color.black)
                .overlay(
                    Capsule()
                        .strokeBorder(Color(red: 0.0, green: 0.8, blue: 0.3).opacity(0.5), lineWidth: 1)
                )

            GeometryReader { geo in
                Text(label)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(red: 0.0, green: 1.0, blue: 0.4))
                    .fixedSize()
                    .offset(x: tickerOffset)
                    .onAppear { animateTicker(width: geo.size.width, label: label) }
                    .onChange(of: label) { newLabel in
                        animateTicker(width: geo.size.width, label: newLabel)
                    }
            }
            .clipped()
        }
        .frame(width: screenSize + bezelPad * 2, height: tickerHeight)
    }

    private func animateTicker(width: CGFloat, label: String) {
        let estimatedTextWidth = CGFloat(label.count) * 7.5
        tickerOffset = width
        withAnimation(.linear(duration: Double(label.count) * 0.12).repeatForever(autoreverses: false)) {
            tickerOffset = -estimatedTextWidth
        }
    }

    // MARK: Animations

    private func updateAnimations(playing: Bool) {
        bezelGlow = playing
        if playing {
            startFlicker()
        } else {
            flickerTimer?.invalidate()
            flickerTimer = nil
            withAnimation(.easeOut(duration: 0.3)) { screenOpacity = 1.0 }
        }
    }

    private func startFlicker() {
        flickerTimer?.invalidate()
        let t = Timer.scheduledTimer(withTimeInterval: Double.random(in: 3.0...7.0), repeats: false) { _ in
            guard isPlaying else { return }
            performFlicker()
        }
        RunLoop.main.add(t, forMode: .common)
        flickerTimer = t
    }

    private func performFlicker() {
        // Brief screen brightness drop — authentic CRT behaviour
        let steps = Int.random(in: 1...3)
        var delay = 0.0
        for _ in 0..<steps {
            let dropDelay = delay
            let dropDuration = Double.random(in: 0.04...0.10)
            DispatchQueue.main.asyncAfter(deadline: .now() + dropDelay) {
                withAnimation(.easeInOut(duration: dropDuration)) {
                    screenOpacity = Double.random(in: 0.55...0.80)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + dropDuration + 0.05) {
                    withAnimation(.easeIn(duration: 0.06)) { screenOpacity = 1.0 }
                }
            }
            delay += dropDuration + 0.12
        }
        // Schedule next flicker
        DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.1) {
            startFlicker()
        }
    }
}
