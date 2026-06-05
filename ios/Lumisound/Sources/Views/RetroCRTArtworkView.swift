import SwiftUI

// MARK: - RetroCRTArtworkView
//
// Album art displayed inside a simulated CRT TV border.
// Features: rounded CRT bezel, scanline overlay, phosphor tint option,
// and an LED-style "NOW PLAYING" ticker that scrolls while playing.

struct RetroCRTArtworkView: View {
    let song: Song?
    let isPlaying: Bool

    @EnvironmentObject private var library: LibraryManager

    // Scanline animation
    @State private var scanlineOffset: CGFloat = 0
    // Ticker offset for the scrolling text
    @State private var tickerOffset: CGFloat = 0

    private let screenSize:  CGFloat = 250
    private let bezelPad:    CGFloat = 20
    private let tickerHeight: CGFloat = 22

    // The phosphor-tinted screen overlay uses a subtle green-tinted scanline
    private let phosphorColor = Color(red: 0.0, green: 1.0, blue: 0.4).opacity(0.06)

    var body: some View {
        VStack(spacing: 0) {
            // ── CRT screen area ──────────────────────────────────────────
            ZStack {
                // Album art (screen content)
                screenContent

                // Scanlines overlay
                scanlineOverlay

                // Phosphor tint
                phosphorColor
                    .allowsHitTesting(false)
            }
            .frame(width: screenSize, height: screenSize)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            // Slight CRT screen bulge simulation via scale on X
            .scaleEffect(x: 1.0, y: 0.96)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.8), lineWidth: 2)
            )

            // ── CRT Bezel ───────────────────────────────────────────────
            .padding(bezelPad)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(white: 0.22),
                                Color(white: 0.14)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(Color(white: 0.35).opacity(0.6), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.6), radius: 16, x: 0, y: 8)
            )

            // ── LED Ticker ───────────────────────────────────────────────
            ledTicker
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
        .onAppear { startScanlineAnimation() }
        .onChange(of: isPlaying) { _ in startScanlineAnimation() }
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
            // Ticker background
            Capsule()
                .fill(Color.black)
                .overlay(
                    Capsule()
                        .strokeBorder(Color(red: 0.0, green: 0.8, blue: 0.3).opacity(0.5), lineWidth: 1)
                )

            // Scrolling text
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
        // Estimate text width (monospaced: ~7.5 pts per char at size 11)
        let estimatedTextWidth = CGFloat(label.count) * 7.5
        tickerOffset = width
        withAnimation(.linear(duration: Double(label.count) * 0.12).repeatForever(autoreverses: false)) {
            tickerOffset = -estimatedTextWidth
        }
    }
}
