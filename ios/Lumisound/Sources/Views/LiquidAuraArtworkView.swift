import SwiftUI

// MARK: - LiquidAuraArtworkView — "Lava Lamp"
//
// The cover over slow, drifting blobs of palette colour — a lava-lamp glow.
struct LiquidAuraArtworkView: View {
    let song: Song?
    let isPlaying: Bool

    @EnvironmentObject private var library: LibraryManager
    @State private var palette: ArtworkPalette?
    @State private var drift = false

    private var c1: Color { palette?.primary ?? AppTheme.dynamicAccent }
    private var c2: Color { palette?.secondary ?? AppTheme.accentSoft }

    // (size, color, restPos, driftPos)
    private var blobs: [(CGFloat, Color, CGSize, CGSize)] {
        [
            (170, c1, CGSize(width: -70, height: -60), CGSize(width: -40, height: 40)),
            (150, c2, CGSize(width: 80, height: -40),  CGSize(width: 50, height: 70)),
            (130, c1, CGSize(width: 50, height: 90),   CGSize(width: -60, height: 30)),
            (120, c2, CGSize(width: -80, height: 70),  CGSize(width: -30, height: -60)),
        ]
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Color.black)

            ForEach(Array(blobs.enumerated()), id: \.offset) { _, b in
                Circle()
                    .fill(b.1)
                    .frame(width: b.0, height: b.0)
                    .blur(radius: 42)
                    .opacity(isPlaying ? 0.6 : 0.4)
                    .offset(drift ? b.3 : b.2)
            }

            StyleCover(song: song, size: 240, cornerRadius: 20)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.16), lineWidth: 1))
                .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
        }
        .frame(width: 320, height: 320)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .modifier(FloatModifier(isPlaying: isPlaying, amount: 5, speed: 3.2))
        .onAppear {
            withAnimation(.easeInOut(duration: 7).repeatForever(autoreverses: true)) { drift = true }
        }
        .task(id: song?.id) { palette = await ArtworkPaletteLoader.palette(for: song, library: library) }
        .animation(.easeInOut(duration: 1.0), value: palette)
    }
}
